import enum
import uuid
from datetime import date, datetime, timezone

from sqlalchemy import Date, DateTime, Enum, String, Text
from sqlalchemy.orm import Mapped, mapped_column

from app.database import Base


class Mood(str, enum.Enum):
    SERENO = "SERENO"
    FELIZ = "FELIZ"
    AGRADECIDO = "AGRADECIDO"
    CANSADO = "CANSADO"
    TRISTE = "TRISTE"
    ANSIOSO = "ANSIOSO"
    REFLEXIVO = "REFLEXIVO"


class JournalEntry(Base):
    __tablename__ = "journal_entries"

    id: Mapped[uuid.UUID] = mapped_column(primary_key=True, default=uuid.uuid4)
    entry_date: Mapped[date] = mapped_column(Date, nullable=False, unique=True, index=True)
    content: Mapped[str] = mapped_column(Text, nullable=False)
    mood: Mapped[Mood] = mapped_column(
        Enum(Mood, name="mood", native_enum=False, length=20), nullable=False, index=True
    )
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=lambda: datetime.now(timezone.utc), nullable=False
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        default=lambda: datetime.now(timezone.utc),
        onupdate=lambda: datetime.now(timezone.utc),
        nullable=False,
    )

