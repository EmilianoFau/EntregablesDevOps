# Somos Los Bandidos©
## El Último Renglón

Diario personal de estética vintage y relajante, desarrollado con FastAPI, PostgreSQL y un frontend completo en un único archivo HTML/CSS/JS.

## Funcionalidades

- Crear una entrada por día con texto, fecha y estado de ánimo.
- Editar y eliminar entradas.
- Recorrer el diario en orden cronológico.
- Filtrar por estado de ánimo y ver el contador de palabras en v2.
- Ejecutar dos versiones en paralelo con despliegue blue/green.

## Levantar con Docker

Requisito: Docker Desktop o Docker Engine con Compose.

```bash
cp .env.example .env
docker compose up --build
```

Abrir <http://localhost:8000>. La documentación interactiva de la API queda en <http://localhost:8000/docs>.

Para detener el entorno:

```bash
docker compose down
```

Para eliminar también los datos locales:

```bash
docker compose down -v
```

## Desarrollo y pruebas

```bash
python -m venv .venv
source .venv/bin/activate
pip install -r requirements-dev.txt
pytest
```

También se pueden ejecutar sin instalar Python localmente:

```bash
docker build --target test -t journal:test .
docker run --rm journal:test
```

## Arquitectura

```text
Navegador -> FastAPI (API + index.html) -> PostgreSQL
```

- `app/static/index.html`: frontend completo sin framework ni compilación.
- `app/routes`: API REST.
- `alembic`: migraciones de base de datos.
- `tests`: pruebas funcionales de la API.
- `k8s`: PostgreSQL, migración, deployments blue/green y servicio.

## Endpoints principales

- `GET/POST /api/entries`
- `GET/PUT/DELETE /api/entries/{id}`
- `GET /api/moods`
- `GET /api/version`
- `GET /health/live`
- `GET /health/ready`

## Versiones blue/green

- `v1` (blue): editor, CRUD y cronología.
- `v2` (green): agrega filtro por ánimo y contador de palabras.

El mismo código se configura mediante `APP_VERSION`. Kubernetes mantiene ambos deployments activos y el `Service` selecciona cuál recibe tráfico. Las instrucciones reproducibles están en [`k8s/README.md`](k8s/README.md).

## Datos y privacidad

Es un MVP de un solo usuario, sin autenticación. Debe exponerse únicamente en un entorno local o protegido. Los logs no registran el contenido de las entradas.
