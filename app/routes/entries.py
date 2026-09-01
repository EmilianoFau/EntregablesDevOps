import uuid
from datetime import date

from fastapi import APIRouter, Depends, Header, HTTPException, Query, Response, status
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from app import repository
from app.clock import journal_today
from app.database import get_db
from app.models import Mood
from app.schemas import EntryCreate, EntryList, EntryRead, EntryUpdate

router = APIRouter(prefix="/api/entries", tags=["entries"])


def writable_day(
    today: date = Depends(journal_today),
    x_journal_day: date | None = Header(default=None),
) -> date:
    if x_journal_day is not None and x_journal_day != today:
        raise HTTPException(status_code=412, detail="El día cambió. Abrí la página de hoy.")
    return today


@router.get("", response_model=EntryList)
def list_entries(
    limit: int = Query(20, ge=1, le=100),
    offset: int = Query(0, ge=0),
    mood: Mood | None = None,
    from_date: date | None = None,
    to_date: date | None = None,
    db: Session = Depends(get_db),
) -> EntryList:
    items, total = repository.list_entries(
        db, limit=limit, offset=offset, mood=mood, from_date=from_date, to_date=to_date
    )
    return EntryList(items=items, total=total, limit=limit, offset=offset)


@router.get("/by-date/{entry_date}", response_model=EntryRead)
def get_entry_by_date(entry_date: date, db: Session = Depends(get_db)) -> EntryRead:
    entry = repository.get_entry_by_date(db, entry_date)
    if not entry:
        raise HTTPException(status_code=404, detail="No hay una entrada para esa fecha")
    return entry


@router.get("/{entry_id}", response_model=EntryRead)
def get_entry(entry_id: uuid.UUID, db: Session = Depends(get_db)) -> EntryRead:
    entry = repository.get_entry(db, entry_id)
    if not entry:
        raise HTTPException(status_code=404, detail="Entrada no encontrada")
    return entry


@router.post("", response_model=EntryRead, status_code=status.HTTP_201_CREATED)
def create_entry(
    payload: EntryCreate, db: Session = Depends(get_db), today: date = Depends(writable_day)
) -> EntryRead:
    try:
        return repository.create_entry(db, payload, today)
    except IntegrityError:
        db.rollback()
        raise HTTPException(status_code=409, detail="Ya existe una entrada para esta fecha")


@router.put("/{entry_id}", response_model=EntryRead)
def update_entry(
    entry_id: uuid.UUID, payload: EntryUpdate, db: Session = Depends(get_db),
    today: date = Depends(writable_day),
) -> EntryRead:
    entry = repository.get_entry(db, entry_id)
    if not entry:
        raise HTTPException(status_code=404, detail="Entrada no encontrada")
    if entry.entry_date != today:
        raise HTTPException(status_code=403, detail="Las páginas de otros días son solo de lectura")
    return repository.update_entry(db, entry, payload)


@router.delete("/{entry_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_entry(
    entry_id: uuid.UUID, db: Session = Depends(get_db), today: date = Depends(journal_today)
) -> Response:
    entry = repository.get_entry(db, entry_id)
    if not entry:
        raise HTTPException(status_code=404, detail="Entrada no encontrada")
    if entry.entry_date != today:
        raise HTTPException(status_code=403, detail="Las páginas de otros días son solo de lectura")
    repository.delete_entry(db, entry)
    return Response(status_code=status.HTTP_204_NO_CONTENT)
