import pytest
"""快照上传、版本、冲突与恢复。"""

DOC = {"schemaVersion": 2, "records": [], "templates": [], "energy": {"goalMode": "lose"}}


def doc(records: int) -> dict:
    return {"schemaVersion": 2, "records": [{"id": str(i)} for i in range(records)]}


async def test_sync_requires_login(client):
    assert (await client.get("/v1/sync/state")).status_code == 401
    assert (await client.put("/v1/sync/snapshot", json={"baseVersion": 0, "payload": DOC})).status_code == 401


async def test_state_is_empty_before_first_upload(client, auth):
    response = await client.get("/v1/sync/state", headers=auth)
    assert response.status_code == 200
    assert response.json() == {"version": 0, "updatedAt": None, "checksum": None}


async def test_upload_and_download_round_trip(client, auth):
    upload = await client.put("/v1/sync/snapshot", headers=auth,
                              json={"baseVersion": 0, "payload": DOC, "deviceName": "iPhone"})
    assert upload.status_code == 201, upload.text
    body = upload.json()
    assert body["version"] == 1
    assert body["unchanged"] is False
    assert len(body["checksum"]) == 64

    state = (await client.get("/v1/sync/state", headers=auth)).json()
    assert state["version"] == 1

    snapshot = (await client.get("/v1/sync/snapshot", headers=auth)).json()
    assert snapshot["version"] == 1
    assert snapshot["payload"] == DOC


async def test_identical_payload_is_not_a_new_version(client, auth):
    await client.put("/v1/sync/snapshot", headers=auth, json={"baseVersion": 0, "payload": DOC})
    again = await client.put("/v1/sync/snapshot", headers=auth, json={"baseVersion": 1, "payload": DOC})
    assert again.status_code == 200
    assert again.json()["unchanged"] is True
    assert again.json()["version"] == 1
    assert (await client.get("/v1/sync/state", headers=auth)).json()["version"] == 1


async def test_stale_base_version_is_a_conflict(client, auth):
    await client.put("/v1/sync/snapshot", headers=auth, json={"baseVersion": 0, "payload": DOC})
    await client.put("/v1/sync/snapshot", headers=auth, json={"baseVersion": 1, "payload": doc(2)})
    conflict = await client.put("/v1/sync/snapshot", headers=auth, json={"baseVersion": 1, "payload": doc(3)})
    assert conflict.status_code == 409
    assert conflict.json()["version"] == 2
    assert "更新的数据" in conflict.json()["detail"]


async def test_versions_are_pruned_but_downloadable_until_then(client, auth):
    for index in range(5):
        response = await client.put("/v1/sync/snapshot", headers=auth,
                                    json={"baseVersion": index, "payload": doc(index + 1)})
        assert response.status_code == 201
    versions = (await client.get("/v1/sync/versions", headers=auth)).json()
    assert [item["version"] for item in versions] == [5, 4, 3]
    assert (await client.get("/v1/sync/snapshot?version=3", headers=auth)).status_code == 200
    assert (await client.get("/v1/sync/snapshot?version=2", headers=auth)).status_code == 404


async def test_restore_creates_a_new_head(client, auth):
    await client.put("/v1/sync/snapshot", headers=auth, json={"baseVersion": 0, "payload": doc(1)})
    await client.put("/v1/sync/snapshot", headers=auth, json={"baseVersion": 1, "payload": doc(2)})
    restored = await client.post("/v1/sync/restore/1", headers=auth)
    assert restored.status_code == 201
    assert restored.json()["version"] == 3
    assert restored.json()["restoredFrom"] == 1
    latest = (await client.get("/v1/sync/snapshot", headers=auth)).json()
    assert latest["payload"] == doc(1)


async def test_missing_version_is_404(client, auth):
    assert (await client.get("/v1/sync/snapshot", headers=auth)).status_code == 404
    assert (await client.get("/v1/sync/snapshot?version=99", headers=auth)).status_code == 404
    assert (await client.post("/v1/sync/restore/99", headers=auth)).status_code == 404


async def test_payload_must_be_a_diary_document(client, auth):
    missing = await client.put("/v1/sync/snapshot", headers=auth,
                               json={"baseVersion": 0, "payload": {"records": []}})
    assert missing.status_code == 422
    future = await client.put("/v1/sync/snapshot", headers=auth,
                              json={"baseVersion": 0, "payload": {"schemaVersion": 9}})
    assert future.status_code == 422


async def test_oversized_payload_is_rejected(client, auth):
    big = {"schemaVersion": 2, "records": [], "note": "x" * (70 * 1024)}
    response = await client.put("/v1/sync/snapshot", headers=auth, json={"baseVersion": 0, "payload": big})
    assert response.status_code == 413
    # 上限来自配置（测试里是 64 KB），提示文案必须跟着走，不能写死 8 MB。
    assert response.json()["detail"] == "快照超过 64 KB，请先清理内嵌照片后再同步。"


async def test_users_cannot_see_each_other(app):
    from httpx import ASGITransport, AsyncClient

    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://sync.test") as http:
        first = (await http.post("/v1/auth/register", json={"username": "alice", "password": "abcdefgh"})).json()
        second = (await http.post("/v1/auth/register", json={"username": "bob", "password": "abcdefgh"})).json()
        a = {"Authorization": f"Bearer {first['token']}"}
        b = {"Authorization": f"Bearer {second['token']}"}
        await http.put("/v1/sync/snapshot", headers=a, json={"baseVersion": 0, "payload": doc(1)})
        assert (await http.get("/v1/sync/state", headers=b)).json()["version"] == 0
        assert (await http.get("/v1/sync/snapshot?version=1", headers=b)).status_code == 404


async def test_body_over_the_hard_limit_is_rejected_before_parsing(app, client, auth):
    limit = app.state.settings.max_payload_bytes + 64 * 1024
    response = await client.put(
        "/v1/sync/snapshot", headers={**auth, "Content-Type": "application/json"},
        content=b"{" + b" " * limit,
    )
    assert response.status_code == 413
    assert response.json()["detail"] == "请求体过大。"


async def test_embedded_photos_do_not_require_a_prior_upload(client, auth):
    # 旧版文件把照片内嵌在 payload 里：这类记录不走照片表，也不需要先上传。
    embedded = dict(DOC) | {"records": [{
        "id": "11111111-1111-1111-1111-111111111111",
        "photoJPEG": "AAECAw==",
    }]}
    response = await client.put("/v1/sync/snapshot", headers=auth,
                                json={"baseVersion": 0, "payload": embedded})
    assert response.status_code == 201, response.text


async def test_external_photo_must_be_uploaded_first(client, auth):
    name = "photo-" + "a" * 64 + ".jpg"
    payload = dict(DOC) | {"records": [{"id": "22222222-2222-2222-2222-222222222222",
                                        "photoFileName": name}]}
    response = await client.put("/v1/sync/snapshot", headers=auth,
                                json={"baseVersion": 0, "payload": payload})
    assert response.status_code == 422
    assert "照片尚未上传" in response.json()["detail"]


@pytest.mark.parametrize("name", ["../../etc/passwd", "photo-xyz.jpg", "photo-" + "a" * 64 + ".png", ""])
async def test_invalid_photo_names_are_rejected(client, auth, name):
    payload = dict(DOC) | {"records": [{"id": "33333333-3333-3333-3333-333333333333",
                                        "photoFileName": name}]}
    response = await client.put("/v1/sync/snapshot", headers=auth,
                                json={"baseVersion": 0, "payload": payload})
    assert response.status_code == 422


async def test_versions_and_restore_are_isolated_per_user(app):
    from httpx import ASGITransport, AsyncClient

    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://sync.test") as http:
        first = (await http.post("/v1/auth/register", json={"username": "alice", "password": "abcdefgh"})).json()
        second = (await http.post("/v1/auth/register", json={"username": "bob", "password": "abcdefgh"})).json()
        a = {"Authorization": f"Bearer {first['token']}"}
        b = {"Authorization": f"Bearer {second['token']}"}
        await http.put("/v1/sync/snapshot", headers=a, json={"baseVersion": 0, "payload": doc(1)})
        await http.put("/v1/sync/snapshot", headers=a, json={"baseVersion": 1, "payload": doc(2)})

        assert (await http.get("/v1/sync/versions", headers=b)).json() == []
        assert (await http.post("/v1/sync/restore/1", headers=b)).status_code == 404
        # 越权恢复不能改动任何一方的数据。
        assert (await http.get("/v1/sync/state", headers=b)).json()["version"] == 0
        assert (await http.get("/v1/sync/state", headers=a)).json()["version"] == 2
