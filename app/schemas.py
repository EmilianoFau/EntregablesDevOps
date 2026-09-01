import uuid
from datetime import date, datetime, timedelta

from pydantic import BaseModel, ConfigDict, Field, field_validator

from app.models import Mood


class EntryPayload(BaseModel):
    entry_date: date
    content: str = Field(min_length=1, max_length=20_000)
    mood: Mood

    @field_validator("content")
    @classmethod
    def content_must_not_be_blank(cls, value: str) -> str:
        value = value.strip()
        if not value:
            raise ValueError("El texto no puede estar vacío")
        return value

    @field_validator("entry_date")
    @classmethod
    def date_must_be_reasonable(cls, value: date) -> date:
        if value > date.today() + timedelta(days=1):
            raise ValueError("La fecha no puede estar en el futuro")
        return value


class EntryCreate(EntryPayload):
    pass


class EntryUpdate(EntryPayload):
    pass


class EntryRead(EntryPayload):
    id: uuid.UUID
    created_at: datetime
    updated_at: datetime

    model_config = ConfigDict(from_attributes=True)


class EntryList(BaseModel):
    items: list[EntryRead]
    total: int
    limit: int
    offset: int


class VersionInfo(BaseModel):
    version: str
    color: str

