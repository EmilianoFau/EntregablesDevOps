import uuid
from datetime import date

from fastapi import APIRouter, Depends, HTTPException, Query, Response, status
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from app import repository
from app.database import get_db
from app.models import Mood
from app.schemas import EntryCreate, EntryList, EntryRead, EntryUpdate

router = APIRouter(prefix="/api/entries", tags=["entries"])


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
def create_entry(payload: EntryCreate, db: Session = Depends(get_db)) -> EntryRead:
    try:
        return repository.create_entry(db, payload)
    except IntegrityError:
        db.rollback()
        raise HTTPException(status_code=409, detail="Ya existe una entrada para esta fecha")


@router.put("/{entry_id}", response_model=EntryRead)
def update_entry(
    entry_id: uuid.UUID, payload: EntryUpdate, db: Session = Depends(get_db)
) -> EntryRead:
    entry = repository.get_entry(db, entry_id)
    if not entry:
        raise HTTPException(status_code=404, detail="Entrada no encontrada")
    conflicting = repository.get_entry_by_date(db, payload.entry_date)
    if conflicting and conflicting.id != entry.id:
        raise HTTPException(status_code=409, detail="Ya existe una entrada para esta fecha")
    return repository.update_entry(db, entry, payload)


@router.delete("/{entry_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_entry(entry_id: uuid.UUID, db: Session = Depends(get_db)) -> Response:
    entry = repository.get_entry(db, entry_id)
    if not entry:
        raise HTTPException(status_code=404, detail="Entrada no encontrada")
    repository.delete_entry(db, entry)
    return Response(status_code=status.HTTP_204_NO_CONTENT)

