import json
import os
import threading
import uuid
from datetime import date, datetime, timezone
from functools import lru_cache
from pathlib import Path

from app.config import get_settings
from app.schemas import EntryCreate, EntryRead, EntryUpdate, Mood


class JsonJournalRepository:
    """Simple JSON storage for a single-process course demo."""

    def __init__(self, path: str | Path):
        self.path = Path(path)
        self._lock = threading.Lock()
        self.path.parent.mkdir(parents=True, exist_ok=True)
        if not self.path.exists():
            self._write([])

    def _read(self) -> list[EntryRead]:
        raw = json.loads(self.path.read_text(encoding="utf-8"))
        return [EntryRead.model_validate(item) for item in raw]

    def _write(self, entries: list[EntryRead]) -> None:
        temporary = self.path.with_suffix(".tmp")
        temporary.write_text(
            json.dumps(
                [entry.model_dump(mode="json") for entry in entries],
                ensure_ascii=False,
                indent=2,
            ),
            encoding="utf-8",
        )
        os.replace(temporary, self.path)

    def list(
        self,
        *,
        limit: int,
        offset: int,
        mood: Mood | None = None,
        from_date: date | None = None,
        to_date: date | None = None,
    ) -> tuple[list[EntryRead], int]:
        with self._lock:
            entries = self._read()
        filtered = [
            entry
            for entry in entries
            if (mood is None or entry.mood == mood)
            and (from_date is None or entry.entry_date >= from_date)
            and (to_date is None or entry.entry_date <= to_date)
        ]
        filtered.sort(key=lambda entry: entry.entry_date, reverse=True)
        return filtered[offset : offset + limit], len(filtered)

    def get(self, entry_id: uuid.UUID) -> EntryRead | None:
        with self._lock:
            return next((entry for entry in self._read() if entry.id == entry_id), None)

    def get_by_date(self, entry_date: date) -> EntryRead | None:
        with self._lock:
            return next((entry for entry in self._read() if entry.entry_date == entry_date), None)

    def create(self, payload: EntryCreate, today: date) -> EntryRead:
        with self._lock:
            entries = self._read()
            if any(entry.entry_date == today for entry in entries):
                raise ValueError("Ya existe una entrada para esta fecha")
            now = datetime.now(timezone.utc)
            entry = EntryRead(
                id=uuid.uuid4(),
                entry_date=today,
                created_at=now,
                updated_at=now,
                **payload.model_dump(),
            )
            entries.append(entry)
            self._write(entries)
            return entry

    def update(self, entry_id: uuid.UUID, payload: EntryUpdate) -> EntryRead | None:
        with self._lock:
            entries = self._read()
            for index, entry in enumerate(entries):
                if entry.id == entry_id:
                    updated = entry.model_copy(
                        update={**payload.model_dump(), "updated_at": datetime.now(timezone.utc)}
                    )
                    entries[index] = updated
                    self._write(entries)
                    return updated
        return None

    def delete(self, entry_id: uuid.UUID) -> bool:
        with self._lock:
            entries = self._read()
            remaining = [entry for entry in entries if entry.id != entry_id]
            if len(remaining) == len(entries):
                return False
            self._write(remaining)
            return True

    def ready(self) -> bool:
        with self._lock:
            self._read()
        return os.access(self.path, os.R_OK | os.W_OK)


@lru_cache
def get_repository() -> JsonJournalRepository:
    return JsonJournalRepository(get_settings().data_file)
