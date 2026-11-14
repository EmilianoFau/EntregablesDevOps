from datetime import date

from fastapi import Depends, FastAPI
from prometheus_client import make_asgi_app
from app.config import get_settings
from app.clock import journal_today
from app.metrics import MetricsMiddleware, register_business_metrics
from app.repository import JsonJournalRepository, get_repository
from app.routes.entries import router as entries_router
from app.schemas import Mood, VersionInfo

app = FastAPI(
    title="El Último Renglón",
    description="Un diario personal para cerrar el día con calma.",
    version="2.0.0",
)
# El frontend vive en su propio contenedor (nginx): esta app solo expone la API.
app.add_middleware(MetricsMiddleware)
app.include_router(entries_router)
app.mount("/metrics", make_asgi_app())
register_business_metrics()


@app.get("/api/day", tags=["metadata"])
def current_day(today: date = Depends(journal_today)) -> dict[str, str]:
    return {"date": today.isoformat(), "timezone": get_settings().journal_timezone}


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
def ready(repository: JsonJournalRepository = Depends(get_repository)) -> dict[str, str]:
    if not repository.ready():
        raise RuntimeError("El archivo de datos no está disponible")
    return {"status": "ready"}
