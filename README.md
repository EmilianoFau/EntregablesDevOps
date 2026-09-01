# Somos Los Bandidos©

## El Último Renglón

Diario personal minimalista: una hoja blanca, tipografía editorial y pequeños acentos vivos. Desarrollado con FastAPI, PostgreSQL y un frontend completo en un único archivo HTML/CSS/JS.

## Funcionalidades

- Dos pestañas: Escribir y Mis logs.
- Crear y editar únicamente la entrada de hoy, con texto libre y estado de ánimo.
- Fecha automática del servidor en America/Montevideo, mostrada como DD/MM/AAAA. No se acepta una fecha elegida por el cliente.
- Las entradas de otros días son solo lectura: la API rechaza su modificación y eliminación.
- Los días sin entradas se omiten; no se pueden completar retroactivamente.
- Consultar y filtrar los logs, abrir su contenido completo y contar palabras al escribir.
- Si cambia el día con el editor abierto, el borrador queda visible pero bloqueado hasta abrir la página nueva.
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

Las pruebas cubren CRUD de hoy, validaciones, fechas no seleccionables, bloqueo del pasado, días omitidos y cambio de día.

## Datos de ejemplo

```bash
docker compose exec app python -m app.seed_demo
```

Carga dos entradas ficticias, de ayer y de hace tres días. Es una operación explícita, no automática: conserva cualquier entrada existente para esas fechas y puede repetirse sin duplicar datos. No habilita creación retroactiva por API.

La variable `JOURNAL_TIMEZONE` define la zona horaria del diario (por defecto `America/Montevideo`).

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
- `GET /api/day`
- `GET /api/version`
- `GET /health/live`
- `GET /health/ready`

## Versiones blue/green

- `v1` (blue): versión vintage inicial conservada en el commit `4e3e73e`.
- `v2` (green): hoja blanca minimalista, pestañas y escritura limitada al día actual.

Las imágenes se construyen desde cada versión del código; `APP_VERSION` solo identifica la versión mostrada. Kubernetes mantiene ambos deployments activos y el `Service` selecciona cuál recibe tráfico. Ambas versiones comparten esquema de datos. El rollback a v1 también recupera sus reglas de edición anteriores. Las instrucciones reproducibles están en [`k8s/README.md`](k8s/README.md).

## Datos y privacidad

Es un MVP de un solo usuario, sin autenticación. Debe exponerse únicamente en un entorno local o protegido. Los logs no registran el contenido de las entradas.
