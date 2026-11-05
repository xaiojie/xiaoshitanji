"""注册、登录、会话与账号安全。"""

from datetime import datetime, timedelta, timezone

import pytest


async def test_register_returns_session(account):
    assert account["username"] == "frog"
    assert account["version"] == 0
    assert len(account["token"]) > 30


async def test_register_normalizes_username_and_rejects_duplicate(client):
    first = await client.post("/v1/auth/register", json={"username": "  Frog.User ", "password": "abcdefgh"})
    assert first.status_code == 201
    assert first.json()["username"] == "frog.user"
    again = await client.post("/v1/auth/register", json={"username": "Frog.User", "password": "abcdefgh"})
    assert again.status_code == 409


@pytest.mark.parametrize(
    "username,password",
    [("ab", "abcdefgh"), ("has space", "abcdefgh"), ("ok.frog", "short")],
)
async def test_register_validates_credentials(client, username, password):
    response = await client.post("/v1/auth/register", json={"username": username, "password": password})
    assert response.status_code == 422


async def test_login_rejects_wrong_password_and_unknown_user(client, account):
    wrong = await client.post("/v1/auth/login", json={"username": "frog", "password": "wrong-password"})
    assert wrong.status_code == 401
    unknown = await client.post("/v1/auth/login", json={"username": "nobody", "password": "abcdefgh"})
    assert unknown.status_code == 401


async def test_login_issues_a_second_token(client, account):
    second = await client.post("/v1/auth/login", json={"username": "frog", "password": "milk-tea-1"})
    assert second.status_code == 200
    assert second.json()["token"] != account["token"]


async def test_me_requires_a_valid_bearer_token(client, auth):
    assert (await client.get("/v1/me")).status_code == 401
    assert (await client.get("/v1/me", headers={"Authorization": "Bearer nope"})).status_code == 401
    me = await client.get("/v1/me", headers=auth)
    assert me.status_code == 200
    assert me.json()["username"] == "frog"


async def test_expired_token_is_rejected(client, app, account):
    from sqlalchemy import update

    from app.models import Token
    from app.security import token_digest

    async with app.state.database.session_factory() as session:
        await session.execute(
            update(Token)
            .where(Token.token_hash == token_digest(account["token"]))
            .values(expires_at=datetime.now(timezone.utc) - timedelta(days=40))
        )
        await session.commit()
    response = await client.get("/v1/me", headers={"Authorization": f"Bearer {account['token']}"})
    assert response.status_code == 401


async def test_logout_revokes_only_current_token(client, account):
    second = await client.post("/v1/auth/login", json={"username": "frog", "password": "milk-tea-1"})
    other = {"Authorization": f"Bearer {second.json()['token']}"}
    response = await client.post("/v1/auth/logout", headers={"Authorization": f"Bearer {account['token']}"})
    assert response.status_code == 204
    assert (await client.get("/v1/me", headers={"Authorization": f"Bearer {account['token']}"})).status_code == 401
    assert (await client.get("/v1/me", headers=other)).status_code == 200


async def test_change_password_requires_current_and_revokes_other_tokens(client, account):
    second = await client.post("/v1/auth/login", json={"username": "frog", "password": "milk-tea-1"})
    other = {"Authorization": f"Bearer {second.json()['token']}"}
    wrong = await client.post("/v1/auth/password", headers={"Authorization": f"Bearer {account['token']}"},
                              json={"currentPassword": "nope-nope", "newPassword": "new-password-2"})
    assert wrong.status_code == 401
    changed = await client.post("/v1/auth/password", headers={"Authorization": f"Bearer {account['token']}"},
                                json={"currentPassword": "milk-tea-1", "newPassword": "new-password-2"})
    assert changed.status_code == 204
    assert (await client.get("/v1/me", headers=other)).status_code == 401
    old = await client.post("/v1/auth/login", json={"username": "frog", "password": "milk-tea-1"})
    assert old.status_code == 401
    fresh = await client.post("/v1/auth/login", json={"username": "frog", "password": "new-password-2"})
    assert fresh.status_code == 200


async def test_delete_account_removes_access(client, auth):
    assert (await client.delete("/v1/account", headers=auth)).status_code == 204
    assert (await client.get("/v1/me", headers=auth)).status_code == 401
    assert (await client.post("/v1/auth/login", json={"username": "frog", "password": "milk-tea-1"})).status_code == 401


async def test_max_users_is_enforced(app):
    from httpx import ASGITransport, AsyncClient

    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://sync.test") as http:
        for index in range(5):
            response = await http.post("/v1/auth/register", json={"username": f"user{index}", "password": "abcdefgh"})
            assert response.status_code == 201
        overflow = await http.post("/v1/auth/register", json={"username": "user9", "password": "abcdefgh"})
        assert overflow.status_code == 403
