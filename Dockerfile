FROM python:3.13-slim AS base

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    PYTHONPATH=/app

WORKDIR /app

RUN addgroup --system journal && adduser --system --ingroup journal journal

COPY requirements.txt ./
RUN pip install --no-cache-dir -r requirements.txt

COPY app ./app
COPY data ./data

RUN chown -R journal:journal /app

FROM base AS test
COPY requirements-dev.txt ./
COPY tests ./tests
RUN pip install --no-cache-dir -r requirements-dev.txt
CMD ["pytest", "-q"]

FROM base AS runtime
USER journal

EXPOSE 8000

CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000"]
