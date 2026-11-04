import os
import tempfile

import pytest
from httpx import ASGITransport, AsyncClient

from app.config import Settings
from app.main import create_app


@pytest.fixture
async def app(tmp_path):
    database = tmp_path / "test.db"
    application = create_app(
        Settings(
            database_url=f"sqlite+aiosqlite:///{database}",
            token_ttl_days=30,
            max_payload_bytes=64 * 1024,
            versions_kept=3,
            max_users=5,
            auth_attempts_per_minute=1000,
        )
    )
    await application.state.database.create_all()
    yield application
    await application.state.database.dispose()


@pytest.fixture
async def client(app):
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://sync.test") as http:
        yield http


@pytest.fixture
async def account(client):
    response = await client.post(
        "/v1/auth/register",
        json={"username": "frog", "password": "milk-tea-1", "deviceName": "iPhone"},
    )
    assert response.status_code == 201, response.text
    return response.json()


@pytest.fixture
def auth(account):
    return {"Authorization": f"Bearer {account['token']}"}
