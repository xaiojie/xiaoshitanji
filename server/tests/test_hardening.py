"""回归审计补的硬性契约：健康检查、限流分桶、并发上传。"""

import asyncio

import pytest
from httpx import ASGITransport, AsyncClient

from app.config import Settings
from app.main import create_app
from app.security import AttemptLimiter

DOC = {"schemaVersion": 2, "records": [], "templates": [], "energy": {"goalMode": "lose"}}


def make_app(tmp_path, **overrides):
    options = dict(
        database_url=f"sqlite+aiosqlite:///{tmp_path / 'test.db'}",
        max_payload_bytes=64 * 1024,
        versions_kept=3,
        max_users=5,
        auth_attempts_per_minute=1000,
        # 直连形态：不采信转发头，测试与生产（nginx 前置，显式打开）两种取值。
        trust_proxy_headers=False,
    )
    options.update(overrides)
    return create_app(Settings(**options))


@pytest.fixture
async def open_app(tmp_path):
    application = make_app(tmp_path)
    await application.state.database.create_all()
    yield application
    await application.state.ai_client.aclose()
    await application.state.database.dispose()


@pytest.fixture
async def open_client(open_app):
    async with AsyncClient(transport=ASGITransport(app=open_app), base_url="http://sync.test") as http:
        yield http


@pytest.fixture
async def proxied_client(tmp_path):
    application = make_app(tmp_path, trust_proxy_headers=True)
    await application.state.database.create_all()
    async with AsyncClient(transport=ASGITransport(app=application), base_url="http://sync.test") as http:
        yield http
    await application.state.ai_client.aclose()
    await application.state.database.dispose()


async def test_healthz_contract(open_client):
    response = await open_client.get("/healthz")
    assert response.status_code == 200
    # 客户端依赖这两个版本号协商照片传输与快照格式。
    assert response.json() == {"status": "ok", "schemaVersion": 5, "photoTransferVersion": 1}


async def test_limiter_rejects_repeated_login_attempts(open_app, open_client):
    open_app.state.limiter = AttemptLimiter(2)
    statuses = []
    for _ in range(3):
        response = await open_client.post(
            "/v1/auth/login", json={"username": "frog", "password": "wrong-password"}
        )
        statuses.append(response.status_code)
    assert statuses == [401, 401, 429]
    assert "频繁" in (await open_client.post(
        "/v1/auth/login", json={"username": "frog", "password": "wrong-password"}
    )).json()["detail"]


async def test_limiter_ignores_spoofed_forwarded_header(open_app, open_client):
    open_app.state.limiter = AttemptLimiter(2)
    statuses = []
    for index in range(3):
        # 直连部署：X-Forwarded-For 可被客户端任意伪造，不能用来分桶。
        response = await open_client.post(
            "/v1/auth/login",
            json={"username": "frog", "password": "wrong-password"},
            headers={"X-Forwarded-For": f"10.0.0.{index}"},
        )
        statuses.append(response.status_code)
    assert statuses == [401, 401, 429]


async def test_limiter_uses_forwarded_header_behind_proxy(proxied_client):
    proxied_client._transport.app.state.limiter = AttemptLimiter(2)
    statuses = []
    for index in range(3):
        response = await proxied_client.post(
            "/v1/auth/login",
            json={"username": "frog", "password": "wrong-password"},
            headers={"X-Forwarded-For": f"10.0.0.{index}, 127.0.0.1"},
        )
        statuses.append(response.status_code)
    # 反向代理后面每个真实 IP 独立计数，不会被同一次重试打满。
    assert statuses == [401, 401, 401]


async def test_concurrent_upload_same_base_version_is_a_conflict(open_client):
    registered = await open_client.post(
        "/v1/auth/register",
        json={"username": "frog", "password": "milk-tea-1", "deviceName": "iPhone"},
    )
    assert registered.status_code == 201, registered.text
    auth = {"Authorization": f"Bearer {registered.json()['token']}"}

    async def upload(records: int):
        return await open_client.put(
            "/v1/sync/snapshot",
            headers=auth,
            json={"baseVersion": 0, "payload": {**DOC, "records": [{"id": str(i)} for i in range(records)]}},
        )

    first, second = await asyncio.gather(upload(1), upload(2))
    statuses = sorted([first.status_code, second.status_code])
    # 双设备同时同步：一台写成功，另一台必须拿到 409 去合并，不能 500。
    assert statuses == [201, 409], (first.text, second.text)

    state = (await open_client.get("/v1/sync/state", headers=auth)).json()
    assert state["version"] == 1
