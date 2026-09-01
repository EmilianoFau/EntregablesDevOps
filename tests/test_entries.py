from fastapi.testclient import TestClient


ENTRY = {
    "entry_date": "2026-09-01",
    "content": "Hoy encontré un rato de calma.",
    "mood": "SERENO",
}


def test_crud_entry(client: TestClient) -> None:
    created = client.post("/api/entries", json=ENTRY)
    assert created.status_code == 201
    entry_id = created.json()["id"]

    listed = client.get("/api/entries")
    assert listed.status_code == 200
    assert listed.json()["total"] == 1

    updated = client.put(
        f"/api/entries/{entry_id}",
        json={**ENTRY, "content": "Un día sereno y agradecido.", "mood": "AGRADECIDO"},
    )
    assert updated.status_code == 200
    assert updated.json()["mood"] == "AGRADECIDO"

    deleted = client.delete(f"/api/entries/{entry_id}")
    assert deleted.status_code == 204
    assert client.get("/api/entries").json()["total"] == 0


def test_rejects_duplicate_date(client: TestClient) -> None:
    assert client.post("/api/entries", json=ENTRY).status_code == 201
    duplicate = client.post("/api/entries", json=ENTRY)
    assert duplicate.status_code == 409


def test_rejects_blank_content_and_invalid_mood(client: TestClient) -> None:
    blank = client.post("/api/entries", json={**ENTRY, "content": "   "})
    assert blank.status_code == 422
    invalid = client.post("/api/entries", json={**ENTRY, "mood": "ENOJADO"})
    assert invalid.status_code == 422


def test_filters_by_mood(client: TestClient) -> None:
    client.post("/api/entries", json=ENTRY)
    result = client.get("/api/entries?mood=SERENO")
    assert result.status_code == 200
    assert result.json()["total"] == 1
    assert client.get("/api/entries?mood=TRISTE").json()["total"] == 0


def test_health_and_metadata(client: TestClient) -> None:
    assert client.get("/health/live").json() == {"status": "ok"}
    assert client.get("/health/ready").json() == {"status": "ready"}
    assert "SERENO" in client.get("/api/moods").json()

