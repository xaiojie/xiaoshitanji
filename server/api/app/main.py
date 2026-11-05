"""小食痰记同步服务：账号与快照 API。"""

import asyncio
import httpx
import hashlib
import json
import re
from datetime import datetime

from fastapi import Depends, FastAPI, HTTPException, Request
from fastapi.responses import JSONResponse, Response
from pydantic import BaseModel, Field
from sqlalchemy import delete, func, select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.exc import IntegrityError

from .ai import router as ai_router
from .config import Settings, settings as default_settings
from .db import Database, get_session
from .models import Photo, Snapshot, Token, User, utcnow
from .security import (
    AttemptLimiter,
    client_key,
    current_token,
    current_user,
    hash_password,
    new_token,
    needs_rehash,
    token_digest,
    token_expiry,
    validate_credentials,
    verify_password,
)


class Credentials(BaseModel):
    username: str = Field(max_length=64)
    password: str = Field(max_length=256)
    deviceName: str = Field(default="", max_length=64)


class ChangePassword(BaseModel):
    currentPassword: str = Field(max_length=256)
    newPassword: str = Field(max_length=256)


class SnapshotUpload(BaseModel):
    baseVersion: int = Field(ge=0)
    payload: dict
    deviceName: str = Field(default="", max_length=64)


class PhotoLookup(BaseModel):
    names: list[str] = Field(max_length=250)


PHOTO_LIMIT = 5_000_000
PHOTO_NAME = re.compile(r"photo-([0-9a-f]{64})\.jpg")


def photo_checksum(name: str) -> str:
    match = PHOTO_NAME.fullmatch(name)
    if match is None:
        raise HTTPException(status_code=422, detail="照片文件名无效，请更新 App 后重试。")
    return match.group(1)


def referenced_photos(payload: dict) -> set[str]:
    records = payload.get("records", [])
    smoking = payload.get("smoking", {})
    packs = smoking.get("packs", []) if isinstance(smoking, dict) else []
    names = set()
    for item in (records if isinstance(records, list) else []) + (packs if isinstance(packs, list) else []):
        if not isinstance(item, dict) or item.get("photoJPEG") is not None:
            continue
        name = item.get("photoFileName")
        if name is not None:
            if not isinstance(name, str):
                raise HTTPException(status_code=422, detail="照片文件名无效。")
            photo_checksum(name)
            names.add(name)
    return names


class UserOut(BaseModel):
    username: str
    createdAt: datetime


class SessionOut(BaseModel):
    token: str
    expiresAt: datetime
    username: str
    version: int


class SyncState(BaseModel):
    version: int
    updatedAt: datetime | None
    checksum: str | None


class SnapshotOut(SyncState):
    payload: dict


class VersionOut(BaseModel):
    version: int
    createdAt: datetime
    checksum: str
    sizeBytes: int
    deviceName: str


def payload_bytes(payload: dict) -> bytes:
    return json.dumps(payload, ensure_ascii=False, separators=(",", ":"), sort_keys=True).encode("utf-8")


def checksum(payload: dict) -> str:
    return hashlib.sha256(payload_bytes(payload)).hexdigest()


def validate_payload(payload: dict, limit: int) -> bytes:
    if not isinstance(payload, dict) or "schemaVersion" not in payload:
        raise HTTPException(status_code=422, detail="快照必须是包含 schemaVersion 的日记对象。")
    schema_version = payload.get("schemaVersion")
    if type(schema_version) is not int or not 1 <= schema_version <= 5:
        raise HTTPException(status_code=422, detail="不支持的日记版本。")
    raw = payload_bytes(payload)
    if len(raw) > limit:
        raise HTTPException(status_code=413, detail="快照超过 8 MB，请先清理内嵌照片后再同步。")
    return raw


async def lifespan(app: FastAPI):
    await app.state.database.create_all()
    yield
    await app.state.ai_client.aclose()
    await app.state.database.dispose()


def create_app(app_settings: Settings | None = None) -> FastAPI:
    config = app_settings or default_settings
    app = FastAPI(title="小食痰记同步服务", version="1.0.1", docs_url=None, redoc_url=None, lifespan=lifespan)
    app.include_router(ai_router)
    app.state.ai_client = httpx.AsyncClient(timeout=httpx.Timeout(80, connect=10), follow_redirects=False)
    app.state.ai_semaphore = asyncio.Semaphore(config.ai_max_concurrent)
    app.state.ai_recent = {}
    app.state.settings = config
    app.state.database = Database(config.database_url)
    app.state.limiter = AttemptLimiter(config.auth_attempts_per_minute)

    @app.middleware("http")
    async def limit_body(request: Request, call_next):
        if request.method in {"PUT", "POST"}:
            length = request.headers.get("content-length")
            if length and length.isdigit() and int(length) > config.max_payload_bytes + 64 * 1024:
                return JSONResponse(status_code=413, content={"detail": "请求体过大。"})
        return await call_next(request)

    @app.get("/healthz")
    async def healthz() -> dict:
        return {"status": "ok", "schemaVersion": 5, "photoTransferVersion": 1}

    async def issue_token(session: AsyncSession, user: User, device_name: str) -> tuple[str, Token]:
        raw = new_token()
        token = Token(
            user_id=user.id,
            token_hash=token_digest(raw),
            expires_at=token_expiry(config.token_ttl_days),
            device_name=device_name[:64],
        )
        session.add(token)
        await session.flush()
        return raw, token

    @app.post("/v1/auth/register", status_code=201, response_model=SessionOut)
    async def register(body: Credentials, request: Request, session: AsyncSession = Depends(get_session)) -> SessionOut:
        name = validate_credentials(body.username, body.password)
        app.state.limiter.check(client_key(request, name))
        existing = await session.scalar(select(User).where(User.username == name))
        if existing is not None:
            raise HTTPException(status_code=409, detail="这个名字已经有人用了，换一个吧。")
        total = await session.scalar(select(func.count(User.id)))
        if total is not None and total >= config.max_users:
            raise HTTPException(status_code=403, detail="服务器名额已满。")
        user = User(username=name, password_hash=hash_password(body.password))
        session.add(user)
        await session.flush()
        raw, token = await issue_token(session, user, body.deviceName)
        await session.commit()
        return SessionOut(token=raw, expiresAt=token.expires_at, username=user.username, version=user.current_version)

    @app.post("/v1/auth/login", response_model=SessionOut)
    async def login(body: Credentials, request: Request, session: AsyncSession = Depends(get_session)) -> SessionOut:
        name = validate_credentials(body.username, body.password)
        app.state.limiter.check(client_key(request, name))
        user = await session.scalar(select(User).where(User.username == name))
        if user is None or not verify_password(user.password_hash, body.password):
            raise HTTPException(status_code=401, detail="用户名或密码不对。")
        if needs_rehash(user.password_hash):
            user.password_hash = hash_password(body.password)
        raw, token = await issue_token(session, user, body.deviceName)
        await session.commit()
        return SessionOut(token=raw, expiresAt=token.expires_at, username=user.username, version=user.current_version)

    @app.post("/v1/auth/logout", status_code=204)
    async def logout(pair: tuple[Token, User] = Depends(current_token), session: AsyncSession = Depends(get_session)) -> None:
        token, _ = pair
        await session.delete(token)
        await session.commit()

    @app.get("/v1/me", response_model=UserOut)
    async def me(user: User = Depends(current_user)) -> UserOut:
        return UserOut(username=user.username, createdAt=user.created_at)

    @app.post("/v1/auth/password", status_code=204)
    async def change_password(
        body: ChangePassword,
        pair: tuple[Token, User] = Depends(current_token),
        session: AsyncSession = Depends(get_session),
    ) -> None:
        token, user = pair
        if not verify_password(user.password_hash, body.currentPassword):
            raise HTTPException(status_code=401, detail="当前密码不对。")
        validate_credentials(user.username, body.newPassword)
        user.password_hash = hash_password(body.newPassword)
        await session.execute(
            delete(Token).where(Token.user_id == user.id, Token.id != token.id)
        )
        await session.commit()

    @app.delete("/v1/account", status_code=204)
    async def delete_account(
        pair: tuple[Token, User] = Depends(current_token), session: AsyncSession = Depends(get_session)
    ) -> None:
        _, user = pair
        await session.delete(user)
        await session.commit()

    async def state_of(session: AsyncSession, user: User) -> SyncState:
        if user.current_version == 0:
            return SyncState(version=0, updatedAt=None, checksum=None)
        latest = await session.scalar(
            select(Snapshot).where(Snapshot.user_id == user.id, Snapshot.version == user.current_version)
        )
        if latest is None:
            return SyncState(version=user.current_version, updatedAt=user.updated_at, checksum=None)
        return SyncState(version=latest.version, updatedAt=latest.created_at, checksum=latest.checksum)

    @app.post("/v1/sync/photos/missing")
    async def missing_photos(body: PhotoLookup, user: User = Depends(current_user),
                             session: AsyncSession = Depends(get_session)) -> dict:
        names = list(dict.fromkeys(body.names))
        for name in names:
            photo_checksum(name)
        found = set((await session.scalars(select(Photo.name).where(
            Photo.user_id == user.id, Photo.name.in_(names)
        ))).all())
        return {"missing": [name for name in names if name not in found]}

    @app.put("/v1/sync/photos/{name}")
    async def put_photo(name: str, request: Request, user: User = Depends(current_user),
                        session: AsyncSession = Depends(get_session)) -> JSONResponse:
        owner_id = user.id
        digest = photo_checksum(name)
        content = bytearray()
        async for chunk in request.stream():
            content.extend(chunk)
            if len(content) > PHOTO_LIMIT:
                raise HTTPException(status_code=413, detail="单张照片不能超过5 MB。")
        if not content or hashlib.sha256(content).hexdigest() != digest:
            raise HTTPException(status_code=422, detail="照片校验失败，请重新上传。")
        existing = await session.scalar(select(Photo.id).where(Photo.user_id == owner_id, Photo.name == name))
        if existing is not None:
            return JSONResponse(status_code=200, content={"name": name, "checksum": digest})
        session.add(Photo(user_id=owner_id, name=name, checksum=digest, content=bytes(content)))
        try:
            await session.commit()
        except IntegrityError:
            await session.rollback()
            existing = await session.scalar(select(Photo.id).where(Photo.user_id == owner_id, Photo.name == name))
            if existing is None:
                raise
            return JSONResponse(status_code=200, content={"name": name, "checksum": digest})
        return JSONResponse(status_code=201, content={"name": name, "checksum": digest})

    @app.get("/v1/sync/photos/{name}")
    async def get_photo(name: str, user: User = Depends(current_user),
                        session: AsyncSession = Depends(get_session)) -> Response:
        photo_checksum(name)
        photo = await session.scalar(select(Photo).where(Photo.user_id == user.id, Photo.name == name))
        if photo is None:
            raise HTTPException(status_code=404, detail="找不到这张照片。")
        return Response(content=photo.content, media_type="image/jpeg", headers={"Cache-Control": "private, no-store"})

    @app.get("/v1/sync/state", response_model=SyncState)
    async def sync_state(
        user: User = Depends(current_user), session: AsyncSession = Depends(get_session)
    ) -> SyncState:
        return await state_of(session, user)

    @app.get("/v1/sync/snapshot", response_model=SnapshotOut)
    async def get_snapshot(
        version: int | None = None,
        user: User = Depends(current_user),
        session: AsyncSession = Depends(get_session),
    ) -> SnapshotOut:
        target = version if version is not None else user.current_version
        if target == 0:
            raise HTTPException(status_code=404, detail="还没有同步过数据。")
        snapshot = await session.scalar(
            select(Snapshot).where(Snapshot.user_id == user.id, Snapshot.version == target)
        )
        if snapshot is None:
            raise HTTPException(status_code=404, detail="找不到这个版本。")
        return SnapshotOut(
            version=snapshot.version,
            updatedAt=snapshot.created_at,
            checksum=snapshot.checksum,
            payload=snapshot.payload,
        )

    @app.put("/v1/sync/snapshot", status_code=201)
    async def put_snapshot(
        body: SnapshotUpload,
        user: User = Depends(current_user),
        session: AsyncSession = Depends(get_session),
    ) -> JSONResponse:
        raw = validate_payload(body.payload, config.max_payload_bytes)
        names = referenced_photos(body.payload)
        if names:
            found = set((await session.scalars(select(Photo.name).where(
                Photo.user_id == user.id, Photo.name.in_(names)
            ))).all())
            if found != names:
                raise HTTPException(status_code=422, detail="快照引用的照片尚未上传，请重新同步。")
        user = await session.scalar(select(User).where(User.id == user.id).with_for_update()
                                    .execution_options(populate_existing=True))
        current = user.current_version
        if body.baseVersion != current:
            latest = await state_of(session, user)
            return JSONResponse(status_code=409, content={
                "detail": "服务器上有更新的数据，请先下载合并。",
                "version": latest.version,
                "updatedAt": latest.updatedAt.isoformat() if latest.updatedAt else None,
            })
        digest = hashlib.sha256(raw).hexdigest()
        if current > 0:
            previous = await session.scalar(
                select(Snapshot).where(Snapshot.user_id == user.id, Snapshot.version == current)
            )
            if previous is not None and previous.checksum == digest:
                return JSONResponse(status_code=200, content={
                    "version": previous.version,
                    "updatedAt": previous.created_at.isoformat(),
                    "checksum": previous.checksum,
                    "unchanged": True,
                })
        snapshot = Snapshot(
            user_id=user.id,
            version=current + 1,
            payload=body.payload,
            checksum=digest,
            size_bytes=len(raw),
            device_name=body.deviceName[:64],
        )
        session.add(snapshot)
        user.current_version = current + 1
        user.updated_at = utcnow()
        await session.flush()
        floor = user.current_version - config.versions_kept
        if floor > 0:
            await session.execute(
                delete(Snapshot).where(Snapshot.user_id == user.id, Snapshot.version <= floor)
            )
        await session.commit()
        return JSONResponse(status_code=201, content={
            "version": snapshot.version,
            "updatedAt": snapshot.created_at.isoformat(),
            "checksum": snapshot.checksum,
            "unchanged": False,
        })

    @app.get("/v1/sync/versions", response_model=list[VersionOut])
    async def versions(
        user: User = Depends(current_user), session: AsyncSession = Depends(get_session)
    ) -> list[VersionOut]:
        rows = (await session.scalars(
            select(Snapshot)
            .where(Snapshot.user_id == user.id)
            .order_by(Snapshot.version.desc())
            .limit(config.versions_kept)
        )).all()
        return [
            VersionOut(version=row.version, createdAt=row.created_at, checksum=row.checksum,
                       sizeBytes=row.size_bytes, deviceName=row.device_name)
            for row in rows
        ]

    @app.post("/v1/sync/restore/{version}", status_code=201)
    async def restore(
        version: int,
        user: User = Depends(current_user),
        session: AsyncSession = Depends(get_session),
    ) -> JSONResponse:
        user = await session.scalar(select(User).where(User.id == user.id).with_for_update()
                                    .execution_options(populate_existing=True))
        source = await session.scalar(
            select(Snapshot).where(Snapshot.user_id == user.id, Snapshot.version == version)
        )
        if source is None:
            raise HTTPException(status_code=404, detail="找不到这个版本。")
        snapshot = Snapshot(
            user_id=user.id,
            version=user.current_version + 1,
            payload=source.payload,
            checksum=source.checksum,
            size_bytes=source.size_bytes,
            device_name="restore",
        )
        session.add(snapshot)
        user.current_version += 1
        user.updated_at = utcnow()
        await session.flush()
        floor = user.current_version - config.versions_kept
        if floor > 0:
            await session.execute(
                delete(Snapshot).where(Snapshot.user_id == user.id, Snapshot.version <= floor)
            )
        await session.commit()
        return JSONResponse(status_code=201, content={
            "version": snapshot.version,
            "updatedAt": snapshot.created_at.isoformat(),
            "checksum": snapshot.checksum,
            "restoredFrom": version,
        })

    return app


app = create_app()
