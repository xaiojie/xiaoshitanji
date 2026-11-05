"""Managed AI gateway. Provider credentials and billing controls stay on the server."""

import asyncio
import base64
import binascii
import hashlib
import hmac
import json
import time
from datetime import timedelta

import httpx
from fastapi import APIRouter, HTTPException, Request
from fastapi.responses import JSONResponse
from sqlalchemy import delete, update
from sqlalchemy.dialects.postgresql import insert as pg_insert
from sqlalchemy.dialects.sqlite import insert as sqlite_insert

from .models import AIUsage, utcnow

router = APIRouter()
MAX_BODY = 7_000_000
MAX_RESPONSE = 256_000


def validated_body(raw: bytes) -> dict:
    try:
        body = json.loads(raw)
        if not isinstance(body, dict) or set(body) != {"messages", "response_format"}:
            raise ValueError()
        if body["response_format"] not in ({"type": "json_object"}, {"type": "text"}):
            raise ValueError()
        messages = body["messages"]
        if not isinstance(messages, list) or len(messages) != 2:
            raise ValueError()
        system, user = messages
        if set(system) != {"role", "content"} or system["role"] != "system":
            raise ValueError()
        if not isinstance(system["content"], str) or not 1 <= len(system["content"]) <= 18_000:
            raise ValueError()
        if set(user) != {"role", "content"} or user["role"] != "user":
            raise ValueError()
        parts = user["content"]
        if not isinstance(parts, list) or not 1 <= len(parts) <= 2:
            raise ValueError()
        images = 0
        for part in parts:
            if part.get("type") == "text":
                if set(part) != {"type", "text"} or not isinstance(part["text"], str):
                    raise ValueError()
                if not 1 <= len(part["text"]) <= 250_000:
                    raise ValueError()
            elif part.get("type") == "image_url":
                images += 1
                image = part["image_url"]
                if set(part) != {"type", "image_url"} or not isinstance(image, dict):
                    raise ValueError()
                if set(image) - {"url", "detail"} or image.get("detail", "auto") not in {"auto", "low", "high"}:
                    raise ValueError()
                url = image["url"]
                prefix = "data:image/jpeg;base64,"
                if not isinstance(url, str) or not url.startswith(prefix):
                    raise ValueError()
                decoded = base64.b64decode(url[len(prefix):], validate=True)
                if not 4 <= len(decoded) <= 5_000_000 or not decoded.startswith(b"\xff\xd8"):
                    raise ValueError()
            else:
                raise ValueError()
        if images > 1:
            raise ValueError()
        return body
    except (ValueError, TypeError, KeyError, AttributeError, binascii.Error):
        raise HTTPException(status_code=422, detail="分析内容格式无效，请更新 App 或更换输入后重试。") from None


def check_minute_limit(request: Request, subject: str, limit: int) -> None:
    now = time.monotonic()
    recent = request.app.state.ai_recent
    # Expire inactive subjects and cap map size before accepting another network.
    for key in list(recent):
        if recent[key][-1] < now - 60:
            del recent[key]
    if subject not in recent and len(recent) >= 10_000:
        raise HTTPException(status_code=503, detail="AI 服务繁忙，请稍后重试。")
    hits = [hit for hit in recent.get(subject, []) if hit >= now - 60]
    if len(hits) >= limit:
        raise HTTPException(status_code=429, detail="分析次数较多，请一分钟后再试。", headers={"Retry-After": "60"})
    recent[subject] = hits + [now]


async def reserve_daily_quota(request: Request, subject: str) -> None:
    config = request.app.state.settings
    now = utcnow()
    day = now.date().isoformat()
    reset = (now + timedelta(days=1)).replace(hour=0, minute=0, second=0, microsecond=0)
    async with request.app.state.database.session_factory() as session, session.begin():
        insert = sqlite_insert if session.bind.dialect.name == "sqlite" else pg_insert
        for owner, limit in (("global", config.ai_global_daily_limit), (subject, config.ai_daily_limit)):
            await session.execute(insert(AIUsage).values(day=day, subject=owner, requests=0)
                                  .on_conflict_do_nothing(index_elements=["day", "subject"]))
            count = await session.scalar(update(AIUsage)
                .where(AIUsage.day == day, AIUsage.subject == owner, AIUsage.requests < limit)
                .values(requests=AIUsage.requests + 1).returning(AIUsage.requests))
            if count is None:
                detail = "今日免费分析额度已用完，请明天再试。" if owner != "global" else "今日 AI 服务额度已用完，请明天再试。"
                raise HTTPException(status_code=429, detail=detail,
                                    headers={"Retry-After": str(max(1, int((reset - now).total_seconds())))})
        await session.execute(delete(AIUsage).where(AIUsage.day < (now - timedelta(days=2)).date().isoformat()))


@router.post("/v1/ai/completions")
async def complete(request: Request) -> JSONResponse:
    config = request.app.state.settings
    if not config.ai_api_key:
        raise HTTPException(status_code=503, detail="AI 服务正在准备，请稍后重试。")
    raw = bytearray()
    async for chunk in request.stream():
        raw.extend(chunk)
        if len(raw) > MAX_BODY:
            raise HTTPException(status_code=413, detail="照片或分析数据过大，请缩小照片或选择较短时间范围。")
    body = validated_body(bytes(raw))
    # Nginx overwrites X-Forwarded-For. Uvicorn supplies the trusted peer here.
    # Arbitrary forwarding headers sent directly to the API are never read.
    host = request.client.host if request.client else "unknown"
    day = utcnow().date().isoformat()
    subject = hmac.new(config.ai_api_key.encode(), f"{day}|{host}".encode(), hashlib.sha256).hexdigest()
    check_minute_limit(request, subject, config.ai_requests_per_minute)
    semaphore = request.app.state.ai_semaphore
    try:
        await asyncio.wait_for(semaphore.acquire(), timeout=0.05)
    except TimeoutError:
        raise HTTPException(status_code=503, detail="AI 正在处理其他分析，请稍后重试。", headers={"Retry-After": "10"}) from None
    try:
        await reserve_daily_quota(request, subject)
        payload = body | {"model": config.ai_model, "thinking": {"type": "disabled"},
                          "temperature": 0.2, "max_tokens": 4096, "stream": False}
        async with request.app.state.ai_client.stream(
            "POST", "https://api.deepseek.com/chat/completions", json=payload,
            headers={"Authorization": f"Bearer {config.ai_api_key}"},
        ) as upstream:
            if upstream.status_code == 429:
                raise HTTPException(status_code=429, detail="AI 服务请求较多，请稍后重试。", headers={"Retry-After": "60"})
            if upstream.status_code != 200:
                raise HTTPException(status_code=503, detail="AI 服务暂时不可用，请稍后重试。")
            data = bytearray()
            async for chunk in upstream.aiter_bytes():
                data.extend(chunk)
                if len(data) > MAX_RESPONSE:
                    raise HTTPException(status_code=502, detail="分析结果过长，请简化输入后重试。")
        try:
            result = json.loads(data)
            if not isinstance(result, dict) or not isinstance(result.get("choices"), list):
                raise ValueError()
        except (ValueError, TypeError):
            raise HTTPException(status_code=502, detail="分析结果未完整返回，请重试。") from None
        # Forward only the completion contract needed by the app, never arbitrary upstream metadata.
        return JSONResponse({"model": config.ai_model, "choices": result["choices"]},
                            headers={"Cache-Control": "no-store"})
    except httpx.TimeoutException:
        raise HTTPException(status_code=504, detail="分析超时，输入已保留，请稍后重试。") from None
    except httpx.RequestError:
        raise HTTPException(status_code=502, detail="AI 服务连接失败，请稍后重试。") from None
    finally:
        semaphore.release()
