from datetime import date

import pytest
from fastapi.testclient import TestClient

from app.clock import journal_today
from app.main import app
from app.repository import JsonJournalRepository, get_repository


@pytest.fixture()
def client(tmp_path) -> TestClient:
    repository = JsonJournalRepository(tmp_path / "entries.json")
    app.dependency_overrides[get_repository] = lambda: repository
    app.dependency_overrides[journal_today] = lambda: date(2026, 9, 1)
    with TestClient(app) as test_client:
        yield test_client
    app.dependency_overrides.clear()
