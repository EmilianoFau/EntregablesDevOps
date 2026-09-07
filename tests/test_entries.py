from fastapi.testclient import TestClient
from datetime import date
from app.clock import journal_today
from app.main import app


ENTRY = {
    "content": "Hoy encontré un rato de calma.",
    "mood": "SERENO",
}


def test_crud_entry(client: TestClient) -> None:
    created = client.post("/api/entries", json=ENTRY)
    assert created.status_code == 201
    entry_id = created.json()["id"]
    assert created.json()["entry_date"] == "2026-09-01"

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
    assert client.get("/api/day").json()["date"] == "2026-09-01"
    assert client.get("/api/version").json()["version"] == "v2"


def test_cannot_choose_a_date(client: TestClient) -> None:
    for chosen in ["2026-08-31", "2026-09-01", "2026-09-02"]:
        assert client.post("/api/entries", json={**ENTRY, "entry_date": chosen}).status_code == 422


def test_past_entries_are_read_only(client: TestClient) -> None:
    entry_id = client.post("/api/entries", json=ENTRY).json()["id"]
    app.dependency_overrides[journal_today] = lambda: date(2026, 9, 2)
    assert client.get(f"/api/entries/{entry_id}").status_code == 200
    assert client.put(f"/api/entries/{entry_id}", json=ENTRY).status_code == 403
    assert client.delete(f"/api/entries/{entry_id}").status_code == 403
    assert client.get(f"/api/entries/{entry_id}").json()["content"] == ENTRY["content"]


def test_skipped_days_are_not_created(client: TestClient) -> None:
    client.post("/api/entries", json=ENTRY)
    app.dependency_overrides[journal_today] = lambda: date(2026, 9, 5)
    assert client.post("/api/entries", json=ENTRY).status_code == 201
    result = client.get("/api/entries").json()
    assert result["total"] == 2
    assert [item["entry_date"] for item in result["items"]] == ["2026-09-05", "2026-09-01"]


def test_midnight_precondition_preserves_draft(client: TestClient) -> None:
    response = client.post("/api/entries", json=ENTRY, headers={"X-Journal-Day": "2026-08-31"})
    assert response.status_code == 412
    assert client.get("/api/entries").json()["total"] == 0


def test_update_cannot_change_date(client: TestClient) -> None:
    entry_id = client.post("/api/entries", json=ENTRY).json()["id"]
    assert client.put(f"/api/entries/{entry_id}", json={**ENTRY, "entry_date": "2026-08-31"}).status_code == 422
