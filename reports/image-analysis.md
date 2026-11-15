# Análisis de las imágenes

Analizamos las dos imágenes del proyecto con `docker history`, Dive (en modo CI) y Trivy. Todo se puede regenerar con `scripts/security-scans.sh`; la salida completa queda en `image-layers.txt`, `trivy-backend.txt` y `trivy-frontend.txt`.

La letra sugiere SlimToolkit para macOS. Lo intentamos (`dslim/slim:1.40.11`), pero su cliente habla con Docker usando la versión 1.24 de la API y Docker 29 ya no la acepta (`client version 1.24 is too old. Minimum supported API version is 1.40`). Por eso usamos Dive, que es la otra herramienta que permite la consigna.

## Resumen

| | Backend (`journal-backend`) | Frontend (`journal-frontend`) |
|---|---|---|
| Imagen base | `python:3.13.18-slim-trixie` | `nginxinc/nginx-unprivileged:1.30.6-alpine3.24` |
| Tamaño en disco | 261 MB | 100 MB |
| Cantidad de capas | 9 | 12 |
| Eficiencia (Dive) | 97,6 % | 81,9 % |
| Espacio desperdiciado (Dive) | 6,6 MB | 22 MB |
| Usuario | 100:101 | 101:101 |
| Vulnerabilidades (Trivy) | 0 críticas, 47 altas sin parche | 0 |

Los tamaños son los que informa `docker image ls` en Docker Desktop con arquitectura arm64.

## Backend

La mayor parte del peso no es nuestra. Según `docker history`, la imagen se reparte así:

| Capa | Tamaño |
|---|---|
| Debian trixie (sistema base) | 110 MB |
| Intérprete de Python 3.13 | 43,8 MB |
| Dependencias en `/opt/venv` (FastAPI, uvicorn, pydantic, prometheus-client) | 46,1 MB |
| `apt-get upgrade` y creación del usuario | 0,7 MB |
| Código (`app/`) y datos de ejemplo (`data/`) | 74 kB |

Comparamos con la imagen del Lab 3, que ya era `slim` y ya borraba pip pero se construía en una sola etapa. El tamaño quedó prácticamente igual (262 MB contra 261 MB) y las capas bajaron de 12 a 9. Tiene sentido: todas nuestras dependencias se instalan desde wheels precompilados, así que nunca hubo compiladores ni archivos temporales grandes para dejar atrás. Lo que gana el multi-stage acá es limpieza más que megas. La imagen final no tiene pip ni las herramientas de instalación, el venv llega armado desde otra etapa y los tests tienen su propia etapa (`test`) que nunca llega a producción.

Dive marca 6,6 MB desperdiciados. Son archivos de la base de datos de `dpkg` que se reescriben cuando hacemos `apt-get upgrade` para aplicar los parches de seguridad de Debian. Es un costo chico a cambio de tener el sistema actualizado.

Trivy encuentra 47 vulnerabilidades altas y ninguna crítica. Todas son de paquetes de Debian (`util-linux`, `login`, `mount` y sus librerías) y figuran como `affected` o `fix_deferred`, es decir que Debian todavía no publicó un parche. Ninguna está en las dependencias de Python. Por eso el pipeline las reporta pero no se corta: el corte es solo por críticas con parche disponible.

## Frontend

El frontend es nginx sobre alpine, mucho más liviano que una imagen con Python. La primera etapa del Dockerfile usa `alpine:3.24.4` para comprimir el HTML con gzip y la imagen final solo recibe el resultado (53 kB).

La primera corrida del pipeline se cortó en Trivy por una vulnerabilidad crítica en `brotli-libs` (CVE-2026-111497), una librería de la imagen base de nginx que ya tenía parche en alpine. La corregimos agregando `apk upgrade --no-cache` en el Dockerfile, y después de eso Trivy da cero vulnerabilidades.

Ese arreglo tiene un costo, y Dive lo muestra. Como el upgrade corre en una capa nueva encima de la imagen de nginx, los paquetes actualizados quedan dos veces, la versión vieja en la capa de abajo y la nueva arriba. Son 22 MB desperdiciados y la eficiencia baja a 81,9 %, por debajo del 90 % que Dive pide por defecto. Lo aceptamos a conciencia: preferimos una imagen 22 MB más grande antes que una con una vulnerabilidad crítica conocida.

## Optimizaciones posibles

- **Sacar el `apk upgrade` del frontend** cuando nginx publique una imagen con el parche incluido. Así se recuperan los 22 MB y la eficiencia vuelve a estar arriba del 90 %. Otra opción es partir de `alpine` puro e instalar nginx en una sola capa, aunque eso significa mantener a mano lo que hoy hace la imagen oficial.
- **Imagen distroless para el backend** (por ejemplo `gcr.io/distroless/python3`). No trae shell, gestor de paquetes ni utilidades como `mount` o `login`, que es justamente de donde salen las 47 vulnerabilidades altas. El costo es que depurar se vuelve más difícil y hay que fijar la misma versión de Python en las dos etapas.
- **Precompilar el bytecode** (`python -m compileall`) en la etapa `builder` para que el contenedor arranque un poco más rápido. Hoy está desactivado con `PYTHONDONTWRITEBYTECODE=1` porque la raíz es de solo lectura y Python no podría escribir los `.pyc` en tiempo de ejecución.
- **Revisar si hacen falta los extras de `uvicorn[standard]`**. Traen `uvloop`, `httptools` y `watchfiles`. Los dos primeros mejoran el rendimiento, pero `watchfiles` solo se usa para recargar en desarrollo y se podría excluir.
- **Construir para una sola arquitectura en CI.** Ya lo hacemos (arm64, la de la Mac). En un entorno real convendría publicar una imagen multiarquitectura con `docker buildx` para que corra igual en servidores amd64.
