# Somos Los Bandidos©

## El Último Renglón

Diario personal minimalista desarrollado con FastAPI, almacenamiento JSON y un frontend completo en un único archivo HTML/CSS/JS.

## Funcionalidades

- Dos pestañas: Escribir y Mis logs.
- Crear y editar únicamente la entrada de hoy, con texto libre y estado de ánimo.
- Fecha automática del servidor en America/Montevideo, mostrada como DD/MM/AAAA. No se acepta una fecha elegida por el cliente.
- Las entradas de otros días son solo lectura: la API rechaza su modificación y eliminación.
- Los días sin entradas se omiten; no se pueden completar retroactivamente.
- Consultar y filtrar los logs, abrir su contenido completo y contar palabras al escribir.
- Si cambia el día con el editor abierto, el borrador queda visible pero bloqueado hasta abrir la página nueva.
- Guardar las entradas en `data/entries.json`.

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

## Datos

El repositorio incluye dos entradas ficticias en `data/entries.json`. Para volver a agregar ejemplos relativos al día actual si esas fechas están libres:

```bash
docker compose exec app python -m app.seed_demo
```

Carga entradas de ayer y de hace tres días. Conserva cualquier entrada existente y puede repetirse sin duplicarlas.

El JSON vive dentro del contenedor. Sus cambios sobreviven a un reinicio del mismo contenedor, pero se pierden al eliminarlo o reconstruirlo. Esta limitación mantiene la v1 simple y se evaluará nuevamente al preparar blue/green.

La variable `JOURNAL_TIMEZONE` define la zona horaria del diario (por defecto `America/Montevideo`).

## Arquitectura

```text
Navegador -> FastAPI (API + index.html) -> data/entries.json
```

- `app/static/index.html`: frontend completo sin framework ni compilación.
- `app/routes`: API REST.
- `data/entries.json`: almacenamiento y datos de ejemplo.
- `tests`: pruebas funcionales de la API.
- `k8s`: un Deployment, un Service y un ConfigMap para ejecutar la v1 en Minikube.

## Endpoints principales

- `GET/POST /api/entries`
- `GET/PUT/DELETE /api/entries/{id}`
- `GET /api/moods`
- `GET /api/day`
- `GET /api/version`
- `GET /health/live`
- `GET /health/ready`

## Estado del versionado

- La versión actual será la base de `journal:v1`.
- Blue/green todavía no está configurado en esta etapa.
- El próximo paso será guardar esta v1, desarrollar un cambio visible para v2 y recién entonces crear los dos Deployments.

Las instrucciones de la v1 están en [`k8s/README.md`](k8s/README.md).

## Datos y privacidad

Es un MVP de un solo usuario, sin autenticación. Debe exponerse únicamente en un entorno local o protegido. Los logs no registran el contenido de las entradas.
