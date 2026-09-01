import uuid
from datetime import date

from sqlalchemy import func, select
from sqlalchemy.orm import Session

from app.models import JournalEntry, Mood
from app.schemas import EntryCreate, EntryUpdate


def list_entries(
    db: Session,
    *,
    limit: int,
    offset: int,
    mood: Mood | None = None,
    from_date: date | None = None,
    to_date: date | None = None,
) -> tuple[list[JournalEntry], int]:
    filters = []
    if mood:
        filters.append(JournalEntry.mood == mood)
    if from_date:
        filters.append(JournalEntry.entry_date >= from_date)
    if to_date:
        filters.append(JournalEntry.entry_date <= to_date)

    query = select(JournalEntry).where(*filters)
    count_query = select(func.count()).select_from(JournalEntry).where(*filters)
    items = list(
        db.scalars(query.order_by(JournalEntry.entry_date.desc()).limit(limit).offset(offset))
    )
    return items, db.scalar(count_query) or 0


def get_entry(db: Session, entry_id: uuid.UUID) -> JournalEntry | None:
    return db.get(JournalEntry, entry_id)


def get_entry_by_date(db: Session, entry_date: date) -> JournalEntry | None:
    return db.scalar(select(JournalEntry).where(JournalEntry.entry_date == entry_date))


def create_entry(db: Session, payload: EntryCreate) -> JournalEntry:
    entry = JournalEntry(**payload.model_dump())
    db.add(entry)
    db.commit()
    db.refresh(entry)
    return entry


def update_entry(db: Session, entry: JournalEntry, payload: EntryUpdate) -> JournalEntry:
    for key, value in payload.model_dump().items():
        setattr(entry, key, value)
    db.commit()
    db.refresh(entry)
    return entry


def delete_entry(db: Session, entry: JournalEntry) -> None:
    db.delete(entry)
    db.commit()

