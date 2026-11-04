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
    assert response.status_code in {413, 422}


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
