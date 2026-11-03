# Plan — Laboratorio 4: Trabajo integrador

## Contexto

El Laboratorio 4 (`Laboratorio 4.pdf`) integra todo el curso sobre "El Último Renglón" (FastAPI + almacenamiento JSON). Pide:

- un Dockerfile por componente;
- Helm Chart con valores por entorno;
- pipeline Jenkins (Semgrep → Snyk → build/test → push → deploy con Helm) que se corta ante vulnerabilidades críticas;
- Prometheus + Grafana con dashboard de RPS, latencia, CPU/memoria y una métrica de negocio;
- Kyverno con 4 políticas;
- Falco con una alerta que **no** sea abrir una shell;
- scripts de inicio, carga y borrado;
- un informe técnico extenso.

Punto de partida:

- La rama `feature/entregable4` está al día con `origin/main`, que ya incluye el Lab 3.
- Del Lab 3 (commit `e34626b`, PR #1) se reutilizan: Dockerfile endurecido, dependencias sin CVEs, 3 políticas Kyverno, manifiestos con `securityContext` y reportes.
- `origin/entrega-cicd` ya publicaba en Docker Hub con GitHub Actions. Se reutiliza la idea, pero con tags versionados (no `latest`).

Decisiones tomadas:

- Publicar en **Docker Hub**.
- **Separar frontend y backend** en 2 componentes.
- El usuario no tiene cuenta Snyk: el plan incluye el paso a paso (§0).

## 0. Preparación (manual, una sola vez)

### 0.1 Cuenta y token de Snyk

1. Entrar a <https://app.snyk.io/login> → **Sign up with GitHub** (plan Free).
2. Saltear el asistente de "importar proyectos" (no hace falta).
3. Abajo a la izquierda: tu nombre → **Account settings** → **General** → **Auth Token** → *Click to show* → copiar.
4. Guardarlo en un archivo `.env.lab4` en la raíz del repo, que **no** se versiona (se agrega a `.gitignore`): `SNYK_TOKEN=xxxxxxxx`.
5. Probarlo: `docker run --rm -e SNYK_TOKEN snyk/snyk:python snyk auth check`. El plan Free permite 200 tests/mes de open source, más que suficiente.

### 0.2 Token de Docker Hub

1. <https://hub.docker.com> → avatar → **Account settings** → **Personal access tokens** → **Generate new token**, permiso *Read & Write*.
2. Agregar a `.env.lab4`: `DOCKERHUB_USER=<usuario>` y `DOCKERHUB_TOKEN=<token>`.
3. Si el repo de GitHub es privado, agregar también `GITHUB_TOKEN=<PAT con permiso repo>` para que Jenkins pueda clonarlo.

### 0.3 Rama

Hecho: `feature/entregable4` se rebaseó sobre `origin/main` (`31957e5`), que ya incluye el Lab 3 (PR #1).

## 1. Contenerización (2 componentes)

```text
Dockerfile            # backend (FastAPI)  -> <user>/journal-backend:<versión>
frontend/Dockerfile   # nginx sin root     -> <user>/journal-frontend:<versión>
frontend/index.html   # movido desde app/static/index.html
frontend/nginx.conf   # sirve el HTML y hace proxy de /api -> backend:8000
```

- **Backend:** multi-stage real. La etapa `builder` crea un venv con las dependencias; `runtime` (`python:3.13-slim-trixie`, versión fija) copia solo `/opt/venv` + `app/` + `data/`. Así no queda pip en la imagen final. Se mantienen `USER 100:101` y la etapa `test`.
- Se quitan la ruta `/` y `app/static` del backend; se ajustan los tests si referencian `/`.
- **Frontend:** etapa 1 (`alpine` fijo) precomprime con gzip; etapa 2 `nginxinc/nginx-unprivileged:<versión fija>-alpine`, puerto 8080, UID 101.
- `compose.yaml` pasa a 2 servicios (frontend → backend) para desarrollo local.
- **Calidad de imagen:** `scripts/security-scans.sh` corre Trivy en las dos imágenes, además de `slim xray` (SlimToolkit, Linux) y `docker history`. Resultado en `reports/image-analysis.md`: tamaño total, cantidad de capas, comparación antes/después del multi-stage y optimizaciones posibles (distroless, `--no-compile`, `.dockerignore`).

## 2. Helm Chart (`helm-chart/`)

```text
helm-chart/
  Chart.yaml
  values.yaml            # base: imágenes, tags, puertos, réplicas, recursos, securityContext, ingress, monitoring
  values-dev.yaml        # 1 réplica frontend, recursos chicos, ingress journal.dev.local, LOG debug
  values-prod.yaml       # 2 réplicas frontend, recursos mayores, ingress journal.local, PDB
  templates/
    _helpers.tpl
    backend-deployment.yaml   backend-service.yaml   backend-configmap.yaml
    frontend-deployment.yaml  frontend-service.yaml  frontend-configmap.yaml (nginx.conf)
    ingress.yaml              # condicional: .Values.ingress.enabled
    servicemonitor.yaml       # condicional: .Values.monitoring.enabled
    grafana-dashboard-cm.yaml # ConfigMap con label grafana_dashboard=1, incluye grafana/dashboard.json
    NOTES.txt
```

- Se reutilizan del Lab 3 (`k8s/blue-green.yaml`): `securityContext`, probes `/health/live` y `/health/ready`, el initContainer `seed-data` y los volúmenes `emptyDir`.
- El backend queda en **1 réplica** por la limitación del JSON por pod, ya documentada. Blue/green queda como historia en `k8s/`; el despliegue nuevo es con Helm.
- Instalación: `helm install journal ./helm-chart -f helm-chart/values-dev.yaml`. Se verifica con `kubectl get pods`, `helm test` (un pod de prueba que hace curl a `/api/day`) y `curl -H 'Host: journal.dev.local' http://$(minikube ip)/`.
- `helm lint` y `kube-linter lint helm-chart/` forman parte de los checks.

## 3. Jenkins

```text
jenkins/
  Dockerfile    # jenkins/jenkins:<lts fijo>-jdk21 + docker-cli, kubectl, helm, trivy, semgrep, snyk (versiones fijas), USER jenkins
  plugins.txt   # workflow-aggregator, git, configuration-as-code, credentials-binding, docker-workflow, timestamper, ansicolor, warnings-ng
  casc.yaml     # JCasC: admin, credenciales (dockerhub, snyk-token, github) desde env y job "journal-pipeline" (Pipeline from SCM)
Jenkinsfile
```

- `scripts/start-jenkins.sh` construye la imagen y la corre con:
  - `--network minikube`
  - `-v /var/run/docker.sock` + `--group-add <gid docker>`
  - un kubeconfig aplanado de Minikube montado de solo lectura
  - `--env-file .env.lab4`
  - volumen `jenkins_home`, en `localhost:8081`
- Etapas del `Jenkinsfile` (`options { timestamps(); ansiColor('xterm') }`):

| # | Etapa | Corte |
|---|---|---|
| 1 | Checkout (clonación) | — |
| 2 | Semgrep → `reports/semgrep-report.txt` | falla con hallazgos de severidad ERROR |
| 3 | Snyk (`snyk test --file=requirements.txt --severity-threshold=critical`) → `reports/snyk-report.txt` | **falla con CRITICAL** |
| 4 | Build & test (`docker build --target test` + run) | falla si fallan tests |
| 5 | Build & push de backend y frontend, tag `${BUILD_NUMBER}-${GIT_SHORT}` | — |
| 6 | Trivy sobre las imágenes (`--exit-code 1 --severity CRITICAL --ignore-unfixed`) | **falla con CRITICAL** |
| 7 | Deploy: `helm upgrade --install journal ./helm-chart -f values-dev.yaml --set ...tag=` + `--wait` | falla si el rollout falla |
| 8 | Smoke test (`helm test journal`) | — |

- `post { always { archiveArtifacts 'reports/**' } failure { echo "PIPELINE DETENIDO: ..." } }`.
- Evidencia: logs de consola exportados a `reports/jenkins-build-ok.log` y a `reports/jenkins-build-fail.log`. El de falla se genera en una corrida con una rama de prueba que fija una dependencia con CVE crítico (ej. una versión vieja de `starlette`) y muestra el corte en la etapa Snyk.

## 4. Monitoreo (Prometheus + Grafana)

- Operador: `kube-prometheus-stack` vía Helm (Prometheus Operator + Grafana + kube-state-metrics + cAdvisor del kubelet). Reemplaza al `k8s/monitoring.yaml` hecho a mano y cumple el pedido de "instalación de operadores".
- Instrumentación en `app/main.py`: middleware con `http_requests_total{method,route,status}` (Counter) y `http_request_duration_seconds` (Histogram), usando el `prometheus_client` existente. Se mantiene `journal_entry_operations_total` (`app/routes/entries.py`) y se agrega el gauge `journal_entries_total{mood}`.
- Scrape con el `ServiceMonitor` del chart (label `release: monitoring`).
- Dashboard `grafana/dashboard.json`, provisionado por ConfigMap con sidecar:
  - RPS: `sum(rate(http_requests_total[1m]))`, por ruta y por código.
  - Latencia promedio: `rate(..._sum[5m]) / rate(..._count[5m])` y p95 con `histogram_quantile`.
  - CPU por pod: `rate(container_cpu_usage_seconds_total{namespace="journal"}[5m])`. Memoria: `container_memory_working_set_bytes`.
  - Negocio: operaciones de escritura por tipo + entradas por estado de ánimo.
- Se conserva la alerta `MuchasOperaciones` como `PrometheusRule` del chart.

## 5. DevSecOps

- **Semgrep (5.1):** `semgrep/rules.yaml` con reglas propias para Python/FastAPI, además de `p/python`:
  1. prohibir `eval`/`exec`;
  2. `subprocess` con `shell=True`;
  3. `CORSMiddleware` con `allow_origins=["*"]`;
  4. abrir archivos con rutas armadas desde la request.

  Salida en `reports/semgrep-report.txt`, con corrección o justificación en el informe.
- **Snyk (5.2):** `snyk test --file=requirements.txt` (imagen `snyk/snyk:python`) y `snyk container test` de las imágenes. Salida en `reports/snyk-report.txt`, con tabla de críticos y su corrección propuesta.
- **Kyverno (5.3):** las 3 políticas del Lab 3 (`k8s/policies/`) más una cuarta, `disallow-privilege-escalation` (exige `allowPrivilegeEscalation: false`). `k8s/policies/test/` lleva **un manifiesto no conforme por política**. `scripts/kyverno-validate.sh` aplica cada uno y guarda los rechazos en `reports/kyverno-validation.log`, junto con el deploy conforme del chart.
- **Falco (5.4):** Helm oficial con `driver.kind=modern_ebpf` y `falcoctl.artifact.*.enabled=false`, porque en el Lab 3 ghcr.io devolvió 429. La acción es **no interactiva y sin shell**: `kubectl exec deploy/journal-backend -- cat /etc/shadow` → regla *Sensitive file opened for reading by non-trusted program*. Opcional como segunda alerta: una regla custom en `falco/custom-rules.yaml` para detectar conexiones salientes del backend. `scripts/falco-trigger.sh` dispara la acción y guarda `reports/falco-event.log` con una descripción del evento.

## 6. Scripts (consideraciones adicionales)

| Script | Qué hace |
|---|---|
| `scripts/setup.sh` | `minikube start --cpus 4 --memory 8g`, addons `ingress` y `metrics-server`, repos Helm, instala operadores (Kyverno, kube-prometheus-stack, Falco), aplica las políticas y despliega el chart |
| `scripts/start-jenkins.sh` | construye y levanta Jenkins configurado (JCasC) |
| `scripts/start-ui.sh` | port-forwards de Grafana (3000), Prometheus (9090) y app; imprime URLs y credenciales |
| `scripts/load-traffic.sh` | genera tráfico (GET de páginas y listados, POST/PUT de la entrada del día, 404s) durante N minutos para poblar el dashboard |
| `scripts/security-scans.sh` | Semgrep, Snyk, Trivy, SlimToolkit y KubeLinter → `reports/` |
| `scripts/kyverno-validate.sh`, `scripts/falco-trigger.sh` | evidencias de §5 |
| `scripts/teardown.sh` | `helm uninstall` de todo, borra namespaces y CRDs de los operadores, para y borra Jenkins y su volumen; `--all` además hace `minikube delete` |

Todos con `set -euo pipefail`, idempotentes y con mensajes de cada paso.

## 7. Informe técnico (`README.md` + `docs/`)

`README.md` reescrito con los apartados a–g:

- descripción;
- arquitectura con diagrama Mermaid (navegador → Ingress → frontend → backend; Prometheus/Grafana; Kyverno; Falco; Jenkins → Docker Hub → Helm);
- pipeline;
- métricas y dashboard;
- resultados de seguridad;
- problemas y soluciones (429 de ghcr, UID numérico para `runAsNonRoot`, raíz de solo lectura con `seed-data`, JSON por pod);
- conclusiones y mejoras.

Además:

- `docs/paso-a-paso.md` con cada comando y su salida esperada.
- Fragmentos de salida de las herramientas en el informe. Capturas en `docs/img/`: Jenkins (stage view OK y falla), Grafana y Prometheus targets. Las capturas las tomás vos; el plan indica cuándo.
- `grafana/dashboard.json` enlazado.

## Archivos críticos

- Nuevos: `frontend/`, `helm-chart/`, `jenkins/`, `Jenkinsfile`, `grafana/dashboard.json`, `semgrep/rules.yaml`, `scripts/*.sh`, `k8s/policies/disallow-privilege-escalation.yaml`, `docs/`.
- Modificados: `Dockerfile`, `app/main.py` (métricas HTTP, sin `/`), `app/routes/entries.py` (gauge), `tests/`, `compose.yaml`, `README.md`, `.gitignore`.

## Verificación

1. `scripts/setup.sh` desde cero → `kubectl get pods -A` todo `Running`. La app responde por Ingress.
2. `docker compose up` local → frontend en :8080 llama al backend; `pytest` verde.
3. Pipeline Jenkins verde de punta a punta; la imagen con tag `N-sha` aparece en Docker Hub y en el pod. La corrida con la dependencia vulnerable se corta en Snyk.
4. `scripts/load-traffic.sh` → los 4 grupos de paneles del dashboard muestran datos.
5. `scripts/kyverno-validate.sh` → 4 rechazos en el log. `scripts/falco-trigger.sh` → alerta en `reports/falco-event.log`.
6. `scripts/teardown.sh` → no quedan releases ni namespaces del lab.
