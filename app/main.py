from pathlib import Path

from fastapi import Depends, FastAPI
from fastapi.responses import FileResponse
from sqlalchemy import text
from sqlalchemy.orm import Session

from app.config import get_settings
from app.database import get_db
from app.models import Mood
from app.routes.entries import router as entries_router
from app.schemas import VersionInfo

app = FastAPI(
    title="El Último Renglón",
    description="Un diario personal para cerrar el día con calma.",
    version="2.0.0",
)
app.include_router(entries_router)

INDEX_FILE = Path(__file__).parent / "static" / "index.html"


@app.get("/api/moods", response_model=list[str], tags=["metadata"])
def list_moods() -> list[str]:
    return [mood.value for mood in Mood]


@app.get("/api/version", response_model=VersionInfo, tags=["metadata"])
def version() -> VersionInfo:
    settings = get_settings()
    return VersionInfo(version=settings.app_version, color=settings.deployment_color)


@app.get("/health/live", tags=["health"])
def live() -> dict[str, str]:
    return {"status": "ok"}


@app.get("/health/ready", tags=["health"])
def ready(db: Session = Depends(get_db)) -> dict[str, str]:
    db.execute(text("SELECT 1"))
    return {"status": "ready"}


@app.get("/", include_in_schema=False)
def index() -> FileResponse:
    return FileResponse(INDEX_FILE)

