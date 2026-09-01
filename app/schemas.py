import uuid
from datetime import date, datetime

from pydantic import BaseModel, ConfigDict, Field, field_validator

from app.models import Mood


class EntryPayload(BaseModel):
    content: str = Field(min_length=1, max_length=20_000)
    mood: Mood

    model_config = ConfigDict(extra="forbid")

    @field_validator("content")
    @classmethod
    def content_must_not_be_blank(cls, value: str) -> str:
        value = value.strip()
        if not value:
            raise ValueError("El texto no puede estar vacío")
        return value

class EntryCreate(EntryPayload):
    pass


class EntryUpdate(EntryPayload):
    pass


class EntryRead(EntryPayload):
    id: uuid.UUID
    entry_date: date
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
