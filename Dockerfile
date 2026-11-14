# Backend: API FastAPI de "El Último Renglón".
# Multi-stage: "builder" instala las dependencias en un venv; "runtime" copia
# solo ese venv y el código. Compiladores, caché y pip quedan fuera.

ARG PYTHON_IMAGE=python:3.13.18-slim-trixie

# ---------- Etapa 1: dependencias ----------
FROM ${PYTHON_IMAGE} AS builder
ENV PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1
# El venv se crea SIN pip: se instala desde afuera con el pip de la imagen base,
# así la imagen final no hereda pip dentro del venv.
RUN python -m venv --without-pip /opt/venv
ENV PATH=/opt/venv/bin:$PATH
COPY requirements.txt ./
RUN /usr/local/bin/python -m pip --python /opt/venv/bin/python install -r requirements.txt

# ---------- Etapa 2: tests (la usa el pipeline: docker build --target test) ----------
FROM builder AS test
WORKDIR /app
ENV PYTHONPATH=/app PYTHONDONTWRITEBYTECODE=1
COPY requirements.txt requirements-dev.txt ./
RUN /usr/local/bin/python -m pip --python /opt/venv/bin/python install -r requirements-dev.txt
COPY app ./app
COPY tests ./tests
RUN chown -R 100:101 /app
USER 100:101
CMD ["pytest", "-q"]

# ---------- Etapa 3: imagen final ----------
FROM ${PYTHON_IMAGE} AS runtime
ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PYTHONPATH=/app \
    PATH=/opt/venv/bin:$PATH
WORKDIR /app

# Parches de seguridad del sistema base; usuario sin privilegios con UID/GID
# numéricos fijos (100:101) para que Kubernetes pueda verificar runAsNonRoot.
# pip no se usa en ejecución y trae librerías vendorizadas con CVEs: se borra.
RUN apt-get update \
    && apt-get upgrade -y --no-install-recommends \
    && rm -rf /var/lib/apt/lists/* \
    && addgroup --system --gid 101 journal \
    && adduser --system --uid 100 --ingroup journal journal \
    && python -m pip uninstall -y pip \
    && rm -rf /usr/local/lib/python3.13/ensurepip

COPY --from=builder /opt/venv /opt/venv
COPY --chown=100:101 app ./app
COPY --chown=100:101 data ./data

USER 100:101
EXPOSE 8000
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000"]
