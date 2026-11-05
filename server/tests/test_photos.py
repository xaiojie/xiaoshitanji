"""External photo transfer and schema compatibility regressions."""
import hashlib

import pytest


def photo(data=b"photo fixture"):
    return f"photo-{hashlib.sha256(data).hexdigest()}.jpg", data


@pytest.mark.parametrize("version", [1, 2, 3, 4, 5])
async def test_supported_schemas_round_trip(client, auth, version):
    payload = {"schemaVersion": version, "records": [], "workouts": [], "plans": []}
    response = await client.put("/v1/sync/snapshot", headers=auth,
                                json={"baseVersion": 0, "payload": payload})
    assert response.status_code == 201, response.text
    assert (await client.get("/v1/sync/snapshot", headers=auth)).json()["payload"] == payload


@pytest.mark.parametrize("version", [True, 0, 6, "5"])
async def test_invalid_schema_rejected(client, auth, version):
    response = await client.put("/v1/sync/snapshot", headers=auth,
                                json={"baseVersion": 0, "payload": {"schemaVersion": version}})
    assert response.status_code == 422


async def test_photos_require_authentication(client):
    name, data = photo()
    assert (await client.put(f"/v1/sync/photos/{name}", content=data)).status_code == 401
    assert (await client.get(f"/v1/sync/photos/{name}")).status_code == 401
    assert (await client.post("/v1/sync/photos/missing", json={"names": [name]})).status_code == 401


async def test_photo_round_trip_idempotence_and_missing_list(client, auth):
    name, data = photo()
    missing = await client.post("/v1/sync/photos/missing", headers=auth, json={"names": [name]})
    assert missing.status_code == 200, missing.text
    assert missing.json() == {"missing": [name]}
    first = await client.put(f"/v1/sync/photos/{name}", headers=auth, content=data)
    assert first.status_code == 201, first.text
    again = await client.put(f"/v1/sync/photos/{name}", headers=auth, content=data)
    assert again.status_code == 200, again.text
    download = await client.get(f"/v1/sync/photos/{name}", headers=auth)
    assert download.status_code == 200
    assert download.content == data
    assert (await client.post("/v1/sync/photos/missing", headers=auth, json={"names": [name]})).json() == {"missing": []}


async def test_photo_is_private_to_its_account(client, auth):
    name, data = photo()
    assert (await client.put(f"/v1/sync/photos/{name}", headers=auth, content=data)).status_code == 201
    second = await client.post("/v1/auth/register", json={"username": "second", "password": "fixture-pass"})
    other = {"Authorization": f"Bearer {second.json()['token']}"}
    assert (await client.get(f"/v1/sync/photos/{name}", headers=other)).status_code == 404
    assert (await client.post("/v1/sync/photos/missing", headers=other, json={"names": [name]})).json() == {"missing": [name]}
    response = await client.put("/v1/sync/snapshot", headers=other, json={"baseVersion": 0, "payload": {
        "schemaVersion": 5, "records": [{"photoFileName": name}]}})
    assert response.status_code == 422


async def test_photo_hash_size_and_name_validation(client, auth):
    name, data = photo()
    assert (await client.put(f"/v1/sync/photos/{name}", headers=auth, content=b"different")).status_code == 422
    assert (await client.put("/v1/sync/photos/invalid.jpg", headers=auth, content=data)).status_code == 422
    assert (await client.put(f"/v1/sync/photos/{name}", headers=auth, content=b"x" * 5_000_001)).status_code == 413


async def test_snapshot_requires_all_referenced_photos(client, auth):
    name, data = photo()
    payload = {"schemaVersion": 5, "records": [{"photoFileName": name}],
               "smoking": {"packs": [{"photoFileName": name}]}}
    before = await client.put("/v1/sync/snapshot", headers=auth, json={"baseVersion": 0, "payload": payload})
    assert before.status_code == 422, before.text
    await client.put(f"/v1/sync/photos/{name}", headers=auth, content=data)
    after = await client.put("/v1/sync/snapshot", headers=auth, json={"baseVersion": 0, "payload": payload})
    assert after.status_code == 201, after.text
    old = await client.get("/v1/sync/snapshot?version=1", headers=auth)
    assert old.json()["payload"] == payload


async def test_old_versions_keep_their_original_images(client, auth):
    first_name, first = photo(b"first image")
    second_name, second = photo(b"replacement image")
    for version, (name, data) in enumerate([(first_name, first), (second_name, second)]):
        assert (await client.put(f"/v1/sync/photos/{name}", headers=auth, content=data)).status_code == 201
        payload = {"schemaVersion": 5, "records": [{"photoFileName": name}]}
        assert (await client.put("/v1/sync/snapshot", headers=auth,
            json={"baseVersion": version, "payload": payload})).status_code == 201
    assert (await client.post("/v1/sync/restore/1", headers=auth)).status_code == 201
    snapshot = (await client.get("/v1/sync/snapshot", headers=auth)).json()
    assert snapshot["payload"]["records"][0]["photoFileName"] == first_name
    assert (await client.get(f"/v1/sync/photos/{first_name}", headers=auth)).content == first
    assert (await client.get(f"/v1/sync/photos/{second_name}", headers=auth)).content == second


async def test_concurrent_photo_upload_is_idempotent(client, auth):
    import asyncio
    name, data = photo()
    results = await asyncio.gather(*[
        client.put(f"/v1/sync/photos/{name}", headers=auth, content=data) for _ in range(2)
    ])
    assert sorted(r.status_code for r in results) == [200, 201]


async def test_lookup_is_bounded(client, auth):
    names = [photo(str(i).encode())[0] for i in range(251)]
    assert (await client.post("/v1/sync/photos/missing", headers=auth, json={"names": names})).status_code == 422


async def test_delete_account_removes_its_photo_data(client, auth, app):
    from sqlalchemy import select, func
    from app.models import Photo
    name, data = photo()
    await client.put(f"/v1/sync/photos/{name}", headers=auth, content=data)
    assert (await client.delete("/v1/account", headers=auth)).status_code == 204
    async with app.state.database.session_factory() as session:
        assert await session.scalar(select(func.count(Photo.id))) == 0
