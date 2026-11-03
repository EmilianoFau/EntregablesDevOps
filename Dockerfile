FROM python:3.13-slim-trixie AS base

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    PYTHONPATH=/app

WORKDIR /app

# Parches de seguridad del sistema base y usuario sin privilegios con UID/GID fijos
# (100:101, los mismos que tenía la V1) para que Kubernetes pueda verificar runAsNonRoot.
RUN apt-get update \
    && apt-get upgrade -y --no-install-recommends \
    && rm -rf /var/lib/apt/lists/* \
    && addgroup --system --gid 101 journal \
    && adduser --system --uid 100 --ingroup journal journal

COPY requirements.txt ./
RUN pip install --no-cache-dir -r requirements.txt

COPY app ./app
COPY data ./data

RUN chown -R journal:journal /app

FROM base AS test
COPY requirements-dev.txt ./
COPY tests ./tests
RUN pip install --no-cache-dir -r requirements-dev.txt
USER 100:101
CMD ["pytest", "-q"]

FROM base AS runtime
# pip no se usa en ejecución y trae librerías vendorizadas con CVEs (urllib3, msgpack).
RUN python -m pip uninstall -y pip \
    && rm -rf /usr/local/lib/python3.13/ensurepip
USER 100:101

EXPOSE 8000

CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000"]
