"""Métricas Prometheus de la app.

- http_requests_total / http_request_duration_seconds: tráfico y latencia (RPS y
  latencia promedio del dashboard). Se etiquetan con la *plantilla* de la ruta
  (/api/entries/{entry_id}) y no con la URL real, para no crear una serie por id.
- journal_entries{mood}: métrica de negocio, cuántas entradas hay por estado de
  ánimo. Se calcula al momento de cada scrape leyendo el JSON.
- journal_entry_operations_total{operation}: escrituras (definida en routes/entries.py).
"""
import time

from prometheus_client import REGISTRY, Counter, Histogram
from prometheus_client.core import GaugeMetricFamily
from starlette.middleware.base import BaseHTTPMiddleware
from starlette.requests import Request

from app.repository import get_repository
from app.schemas import Mood

REQUESTS = Counter(
    "http_requests", "Peticiones HTTP procesadas", ["method", "route", "status"]
)
LATENCY = Histogram(
    "http_request_duration_seconds",
    "Duración de las peticiones HTTP",
    ["method", "route"],
    buckets=(0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1, 2.5),
)


class MetricsMiddleware(BaseHTTPMiddleware):
    async def dispatch(self, request: Request, call_next):
        start = time.perf_counter()
        status = 500
        try:
            response = await call_next(request)
            status = response.status_code
            return response
        finally:
            route = request.scope.get("route")
            path = getattr(route, "path", None) or "unmatched"
            if not path.startswith("/metrics"):
                REQUESTS.labels(request.method, path, str(status)).inc()
                LATENCY.labels(request.method, path).observe(time.perf_counter() - start)


class EntriesByMoodCollector:
    def collect(self):
        gauge = GaugeMetricFamily(
            "journal_entries", "Entradas guardadas por estado de ánimo", labels=["mood"]
        )
        try:
            entries, _ = get_repository().list(limit=10**6, offset=0)
        except Exception:  # sin datos legibles no se publica la métrica
            return
        counts = {mood.value: 0 for mood in Mood}
        for entry in entries:
            counts[entry.mood.value] += 1
        for mood, value in counts.items():
            gauge.add_metric([mood], value)
        yield gauge


_collector = EntriesByMoodCollector()


def register_business_metrics() -> None:
    try:
        REGISTRY.register(_collector)
    except ValueError:  # ya registrado (p. ej. al recargar en tests)
        pass
