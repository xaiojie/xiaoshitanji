"""认证：Argon2id 口令、会话 token、简单限流。"""

import hashlib
import hmac
import re
import secrets
import time
from collections import defaultdict, deque
from datetime import datetime, timedelta, timezone

from argon2 import PasswordHasher
from argon2.exceptions import VerifyMismatchError, VerificationError
from fastapi import Depends, HTTPException, Request
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from .db import get_session
from .models import Token, User, utcnow

USERNAME_PATTERN = re.compile(r"^[a-z0-9][a-z0-9_.-]{2,31}$")
PASSWORD_MIN = 8
PASSWORD_MAX = 128

_hasher = PasswordHasher(time_cost=3, memory_cost=65536, parallelism=2)


def normalize_username(raw: str) -> str:
    return raw.strip().lower()


def validate_credentials(username: str, password: str) -> str:
    """返回规范化用户名；不合法直接抛 422 语义的中文错误。"""
    name = normalize_username(username)
    if not USERNAME_PATTERN.fullmatch(name):
        raise HTTPException(status_code=422, detail="用户名需 3–32 位，只能包含小写字母、数字、下划线、点和短横线。")
    if not PASSWORD_MIN <= len(password) <= PASSWORD_MAX:
        raise HTTPException(status_code=422, detail=f"密码长度需在 {PASSWORD_MIN}–{PASSWORD_MAX} 位之间。")
    return name


def hash_password(password: str) -> str:
    return _hasher.hash(password)


def verify_password(password_hash: str, password: str) -> bool:
    try:
        return _hasher.verify(password_hash, password)
    except (VerifyMismatchError, VerificationError):
        return False


def needs_rehash(password_hash: str) -> bool:
    return _hasher.check_needs_rehash(password_hash)


def new_token() -> str:
    return secrets.token_urlsafe(32)


def token_digest(token: str) -> str:
    return hashlib.sha256(token.encode("utf-8")).hexdigest()


def token_expiry(days: int) -> datetime:
    return utcnow() + timedelta(days=days)


def constant_time_equals(left: str, right: str) -> bool:
    return hmac.compare_digest(left, right)


class AttemptLimiter:
    """按 key 的滑动窗口限流；单进程内存实现，够挡住脚本撞库。"""

    def __init__(self, limit: int, window_seconds: int = 60) -> None:
        self.limit = limit
        self.window = window_seconds
        self.hits: dict[str, deque[float]] = defaultdict(deque)

    def check(self, key: str) -> None:
        now = time.monotonic()
        bucket = self.hits[key]
        while bucket and now - bucket[0] > self.window:
            bucket.popleft()
        if len(bucket) >= self.limit:
            raise HTTPException(status_code=429, detail="尝试过于频繁，请稍后再试。")
        bucket.append(now)


def client_key(request: Request, username: str = "", *, trust_forwarded: bool = False) -> str:
    """限流分桶键。

    只有部署在反向代理后面（`trust_proxy_headers`）时才采信
    `X-Forwarded-For`，否则直连方可以伪造多个 IP 打散限流。
    """
    forwarded = request.headers.get("x-forwarded-for", "") if trust_forwarded else ""
    host = forwarded.split(",")[0].strip() if forwarded else (request.client.host if request.client else "unknown")
    return f"{host}|{username}"


async def current_token(
    request: Request, session: AsyncSession = Depends(get_session)
) -> tuple[Token, User]:
    header = request.headers.get("authorization", "")
    scheme, _, raw = header.partition(" ")
    if scheme.lower() != "bearer" or not raw:
        raise HTTPException(status_code=401, detail="请先登录。")
    digest = token_digest(raw.strip())
    token = await session.scalar(select(Token).where(Token.token_hash == digest))
    if token is None:
        raise HTTPException(status_code=401, detail="登录已失效，请重新登录。")
    expires = token.expires_at
    if expires.tzinfo is None:
        expires = expires.replace(tzinfo=timezone.utc)
    if expires <= utcnow():
        raise HTTPException(status_code=401, detail="登录已过期，请重新登录。")
    user = await session.get(User, token.user_id)
    if user is None:
        raise HTTPException(status_code=401, detail="账号不存在。")
    token.last_used_at = utcnow()
    return token, user


async def current_user(pair: tuple[Token, User] = Depends(current_token)) -> User:
    return pair[1]
