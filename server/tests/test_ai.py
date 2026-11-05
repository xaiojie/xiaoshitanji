import asyncio
import json
from dataclasses import replace

import httpx
import pytest
from sqlalchemy import func, select

from app.models import AIUsage


def body(image=False):
    parts = [{"type": "text", "text": "一小碗米饭"}]
    if image:
        parts.append({"type": "image_url", "image_url": {"url": "data:image/jpeg;base64,/9j/2Q=="}})
    return {"messages": [{"role": "system", "content": "分析食物，输出 JSON"},
                         {"role": "user", "content": parts}], "response_format": {"type": "json_object"}}


@pytest.fixture
async def ai(app):
    app.state.settings = replace(app.state.settings, ai_api_key="server-only-secret", ai_daily_limit=2,
                                 ai_global_daily_limit=3, ai_requests_per_minute=100)
    calls = []
    async def complete(request):
        calls.append(request)
        return httpx.Response(200, json={"model": "deepseek-flash", "choices": [
            {"finish_reason": "stop", "message": {"content": '{"foods":[]}'}}]})
    transport = httpx.MockTransport(complete)
    async with httpx.AsyncClient(transport=transport) as upstream:
        app.state.ai_client = upstream
        yield calls


@pytest.mark.parametrize("image", [False, True])
async def test_free_ai_uses_server_key_and_fixed_limits(client, app, ai, image):
    response = await client.post("/v1/ai/completions", json=body(image))
    assert response.status_code == 200
    assert len(ai) == 1
    upstream = ai[0]
    assert str(upstream.url) == "https://api.deepseek.com/chat/completions"
    assert upstream.headers["authorization"] == "Bearer server-only-secret"
    payload = json.loads(upstream.content)
    assert payload["model"] == "deepseek-flash"
    assert payload["max_tokens"] == 4096
    assert payload["stream"] is False
    assert payload["messages"] == body(image)["messages"]
    assert "server-only-secret" not in response.text
    assert response.headers["cache-control"] == "no-store"


async def test_unconfigured_ai_fails_without_upstream_call(client, app, ai):
    app.state.settings = replace(app.state.settings, ai_api_key="")
    assert (await client.post("/v1/ai/completions", json=body())).status_code == 503
    assert not ai


@pytest.mark.parametrize("change", [
    {"model": "expensive"}, {"max_tokens": 100000}, {"stream": True},
    {"response_format": {"type": "unsupported"}},
    {"messages": [{"role": "system", "content": "hi"}]},
    {"messages": [{"role": "system", "content": "hi"}, {"role": "user", "content": [
        {"type": "image_url", "image_url": {"url": "https://example.com/private"}}]}]},
    {"messages": [{"role": "system", "content": "hi"}, {"role": "user", "content": [
        {"type": "image_url", "image_url": {"url": "data:image/jpeg;base64,invalid"}}]}]},
])
async def test_invalid_or_unbounded_contract_never_reaches_provider(client, ai, change):
    payload = body() | change
    assert (await client.post("/v1/ai/completions", json=payload)).status_code == 422
    assert not ai


async def test_daily_quota_is_persistent_and_atomic(client, app, ai):
    responses = await asyncio.gather(*(client.post("/v1/ai/completions", json=body()) for _ in range(5)))
    assert sorted(r.status_code for r in responses) == [200, 200, 429, 429, 429]
    assert len(ai) == 2
    async with app.state.database.session_factory() as session:
        rows = list((await session.scalars(select(AIUsage))).all())
        assert sorted(row.requests for row in rows) == [2, 2]
    # A new in-memory limiter does not reset persisted quota.
    app.state.ai_recent.clear()
    response = await client.post("/v1/ai/completions", json=body())
    assert response.status_code == 429
    assert int(response.headers["retry-after"]) > 0


async def test_global_limit_and_spoofed_forwarding_headers(client, app, ai):
    app.state.settings = replace(app.state.settings, ai_daily_limit=10, ai_global_daily_limit=1)
    assert (await client.post("/v1/ai/completions", json=body())).status_code == 200
    response = await client.post("/v1/ai/completions", json=body(), headers={"X-Forwarded-For": "1.2.3.4"})
    assert response.status_code == 429
    assert len(ai) == 1


async def test_minute_limit(client, app, ai):
    app.state.settings = replace(app.state.settings, ai_requests_per_minute=1)
    assert (await client.post("/v1/ai/completions", json=body())).status_code == 200
    assert (await client.post("/v1/ai/completions", json=body())).status_code == 429
    assert len(ai) == 1


@pytest.mark.parametrize("status", [401, 402, 429, 500])
async def test_upstream_error_is_sanitized(client, app, ai, status):
    async def fail(request):
        return httpx.Response(status, text="server-only-secret upstream internal details")
    async with httpx.AsyncClient(transport=httpx.MockTransport(fail)) as upstream:
        app.state.ai_client = upstream
        response = await client.post("/v1/ai/completions", json=body())
    assert response.status_code in {429, 502, 503}
    assert "server-only-secret" not in response.text
    assert "upstream internal" not in response.text


async def test_chunked_oversize_body_is_rejected(client, ai):
    async def chunks():
        yield b" " * 4_000_000
        yield b" " * 4_000_000
    response = await client.post("/v1/ai/completions", content=chunks())
    assert response.status_code == 413
    assert not ai


async def test_busy_service_rejects_before_reserving_daily_quota(client, app, ai):
    semaphore = app.state.ai_semaphore
    for _ in range(app.state.settings.ai_max_concurrent):
        await semaphore.acquire()
    try:
        assert (await client.post("/v1/ai/completions", json=body())).status_code == 503
        assert not ai
        async with app.state.database.session_factory() as session:
            assert await session.scalar(select(func.count()).select_from(AIUsage)) == 0
    finally:
        for _ in range(app.state.settings.ai_max_concurrent):
            semaphore.release()


async def test_upstream_timeout_releases_concurrency_slot(client, app, ai):
    async def timeout(request):
        raise httpx.ReadTimeout("private upstream diagnostic", request=request)
    async with httpx.AsyncClient(transport=httpx.MockTransport(timeout)) as upstream:
        app.state.ai_client = upstream
        response = await client.post("/v1/ai/completions", json=body())
        assert response.status_code == 504
        assert "private upstream" not in response.text
        assert app.state.ai_semaphore._value == app.state.settings.ai_max_concurrent


def test_deployment_overwrites_untrusted_forwarding_header():
    from pathlib import Path
    template = (Path(__file__).parents[1] / "deploy/nginx-xiaoshitanji.conf").read_text()
    assert "proxy_set_header X-Forwarded-For $remote_addr;" in template
    assert "$proxy_add_x_forwarded_for" not in template


@pytest.mark.parametrize("content", [
    b"<html>gateway error</html>",
    b'{"choices": "not-a-list"}',
    b'{"model": "deepseek-flash"}',
    b"[]",
    b"",
])
async def test_upstream_200_without_completion_contract_is_a_bad_gateway(client, app, ai, content):
    async def broken(request):
        return httpx.Response(200, content=content)
    async with httpx.AsyncClient(transport=httpx.MockTransport(broken)) as upstream:
        app.state.ai_client = upstream
        response = await client.post("/v1/ai/completions", json=body())
    assert response.status_code == 502
    assert "分析结果" in response.json()["detail"]


async def test_oversized_upstream_body_is_a_bad_gateway(client, app, ai):
    oversized = b'{"choices": [], "pad": "' + b"x" * 300_000 + b'"}'

    async def huge(request):
        return httpx.Response(200, content=oversized)
    async with httpx.AsyncClient(transport=httpx.MockTransport(huge)) as upstream:
        app.state.ai_client = upstream
        response = await client.post("/v1/ai/completions", json=body())
    assert response.status_code == 502
    assert "过长" in response.json()["detail"]
