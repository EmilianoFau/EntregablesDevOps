# Paso a paso

Esta guía recorre el proyecto desde una máquina limpia hasta tener todo corriendo, con los comandos en orden y lo que se debería ver en cada paso. Las salidas son las que obtuvimos nosotros en una Mac con chip M2 y Docker Desktop. Algunos nombres de pods, horas y hashes van a cambiar en cada corrida.

## 0. Requisitos

- Docker Desktop con al menos 8 GB de memoria asignados (Settings → Resources). Minikube usa 6 GB y Jenkins necesita un poco más aparte.
- Minikube, kubectl y Helm. En macOS: `brew install minikube kubectl helm`.
- Una cuenta de Snyk (alcanza con el plan gratis) y un token de acceso de Docker Hub con permiso de lectura y escritura.

En la raíz del repositorio hay que crear el archivo `.env.lab4`, que está en `.gitignore` y nunca se sube:

```bash
SNYK_TOKEN=<token de Snyk: Account settings → Auth Token>
DOCKERHUB_USER=<usuario de Docker Hub>
DOCKERHUB_TOKEN=<token de Docker Hub: Account settings → Personal access tokens>
```

## 1. Probar la app en local con Docker Compose

Antes de ir a Kubernetes conviene ver que las dos imágenes funcionan juntas.

```bash
docker build --target test -t journal-backend:test .
docker run --rm journal-backend:test
```

```text
............                                                             [100%]
12 passed, 1 warning in 0.11s
```

```bash
docker compose up -d --build
curl -s localhost:8080/api/day
docker compose exec backend id
docker compose exec frontend id
docker compose down
```

```text
{"date":"2026-11-15","timezone":"America/Montevideo"}
uid=100(journal) gid=101(journal) groups=101(journal)
uid=101(nginx) gid=101(nginx) groups=101(nginx)
```

La app queda en <http://localhost:8080>. La API directa y su documentación están en <http://localhost:8000/docs>.

## 2. Levantar el cluster con todo instalado

```bash
scripts/setup.sh
```

El script hace ocho pasos y avisa en cada uno:

1. Arranca Minikube con 4 CPU y 6 GB y habilita los addons `ingress` y `metrics-server`.
2. Agrega los repositorios de Helm de Kyverno, Prometheus y Falco.
3. Instala Kyverno 1.20 (chart 3.10.0).
4. Instala kube-prometheus-stack 93.3.0, que trae el Prometheus Operator, Prometheus, Grafana y kube-state-metrics.
5. Instala Falco 0.45.2 (chart 9.2.2) con nuestra regla propia.
6. Aplica las 4 políticas de Kyverno y carga el dashboard en Grafana.
7. Construye las imágenes de la app dentro de Minikube con la etiqueta `dev`.
8. Despliega la app con Helm y corre `helm test`.

La primera vez tarda entre 10 y 15 minutos, casi todo descargando imágenes. Si se vuelve a correr, saltea los operadores que ya están instalados.

Al final se ve algo así:

```text
==> 8/8 Despliegue con Helm
NAME                               READY   STATUS    RESTARTS   AGE
journal-backend-6b999c97bb-hs8zc   1/1     Running   0          82s
journal-frontend-df858f784-vj5ct   1/1     Running   0          82s
TEST SUITE:     journal-test
Phase:          Succeeded
POD LOGS: journal-test (curl)
{"date":"2026-11-15","timezone":"America/Montevideo"}
  ✓ La app responde. Siguiente paso: scripts/start-ui.sh
```

Para ver todo lo que quedó corriendo:

```bash
kubectl get pods -A
helm list -A
kubectl get validatingpolicy
```

```text
NAME         NAMESPACE   REVISION  STATUS    CHART                         APP VERSION
falco        falco       1         deployed  falco-9.2.2                   0.45.2
journal      journal     1         deployed  journal-1.0.0                 3.0.0
kyverno      kyverno     1         deployed  kyverno-3.10.0                v1.20.0
monitoring   monitoring  1         deployed  kube-prometheus-stack-93.3.0  v0.95.2

NAME                            AGE   READY
disallow-latest-tag             12s   true
disallow-privilege-escalation   12s   true
require-requests-limits         11s   true
require-run-as-non-root         10s   true
```

### Instalar el chart a mano

El setup ya lo hace, pero el comando que pide la letra es este:

```bash
helm install journal ./helm-chart -n journal --create-namespace -f helm-chart/values-dev.yaml
```

Para producción se cambia el archivo de valores. Con eso el frontend pasa a 2 réplicas y se crea el PodDisruptionBudget:

```bash
helm upgrade journal ./helm-chart -n journal -f helm-chart/values-prod.yaml
kubectl get pods,pdb -n journal
```

Para verificar el chart sin instalarlo:

```bash
helm lint ./helm-chart -f helm-chart/values-dev.yaml
helm template journal ./helm-chart -f helm-chart/values-prod.yaml | less
```

## 3. Abrir la app, Grafana y Prometheus

```bash
scripts/start-ui.sh
```

```text
  App         http://localhost:8080
  Grafana     http://localhost:3000   (admin / admin) → Dashboards → El Último Renglón
  Prometheus  http://localhost:9090   → Status → Targets (journal-backend)
  Jenkins     http://localhost:8081   (admin / admin, si corriste scripts/start-jenkins.sh)
```

Los port-forwards quedan en segundo plano. Si se redespliega la app (por ejemplo desde Jenkins), los pods cambian y hay que volver a correr `scripts/start-ui.sh`.

En Prometheus, **Status → Targets** tiene que mostrar `journal-backend` en estado `UP`.

Si se prefiere entrar por el Ingress, hay que correr `minikube tunnel` en otra terminal y agregar `127.0.0.1 journal.dev.local` a `/etc/hosts`. Después la app queda en <http://journal.dev.local>.

## 4. Generar tráfico para el dashboard

```bash
scripts/load-traffic.sh 300
```

Durante 5 minutos simula tres lectores, alguien que crea y edita la entrada del día y peticiones con errores. Mientras tanto, en Grafana (**Dashboards → El Último Renglón**) se van llenando los paneles de RPS, latencia, CPU, memoria y negocio. Si hay más de 5 escrituras en 5 minutos, el panel de la alerta `MuchasOperaciones` pasa a **ALERTA**.

Para consultar Prometheus directamente:

```bash
curl -s -G localhost:9090/api/v1/query --data-urlencode 'query=sum(rate(http_requests_total{namespace="journal"}[1m]))'
curl -s -G localhost:9090/api/v1/query --data-urlencode 'query=sum by (mood) (journal_entries)'
```

## 5. Jenkins y el pipeline

```bash
scripts/start-jenkins.sh
```

```text
==> Construyendo la imagen de Jenkins (la primera vez tarda unos minutos)
==> Generando el kubeconfig para que Jenkins llegue a Minikube
  ✓ kubeconfig apuntando a https://192.168.49.2:8443
==> Levantando Jenkins
  ✓ Jenkins en http://localhost:8081 (admin / admin)
  Job: journal-pipeline → Build with Parameters
```

En <http://localhost:8081> ya está el job `journal-pipeline`. La primera vez se lanza con **Build Now** (Jenkins todavía no conoce los parámetros porque están en el Jenkinsfile). Desde la segunda vez aparece **Build with Parameters**.

El pipeline clona la rama `entrega4` del repositorio en GitHub, así que lo que se construye es lo que está pusheado, no lo que hay en la carpeta local.

Una corrida correcta termina así (el log completo está en `reports/jenkins-build-2-ok.log`):

```text
12 passed, 1 warning in 0.14s
Total: 201 (LOW: 65, MEDIUM: 89, HIGH: 47, CRITICAL: 0)
...
Despliegue OK: guilleacq/journal-backend:2-6f628f8 y guilleacq/journal-frontend:2-6f628f8 corriendo en journal
Finished: SUCCESS
```

Después del deploy se puede ver qué imagen quedó corriendo:

```bash
kubectl get deploy -n journal -o wide
helm history journal -n journal
```

### Ver el corte por vulnerabilidad crítica

En **Build with Parameters** se tilda `SIMULAR_DEPENDENCIA_VULNERABLE`. El pipeline se detiene en la etapa 3 (log en `reports/jenkins-build-3-falla-snyk.log`):

```text
>> Simulación: se agrega PyYAML==5.3 (vulnerabilidad crítica conocida)
Tested 18 dependencies for known issues, found 2 issues, 2 vulnerable paths.
  ✗ Arbitrary Code Execution [CRITICAL] ... in pyyaml@5.3
  ✗ Arbitrary Code Execution [CRITICAL] ... in pyyaml@5.3
PIPELINE DETENIDO: Snyk encontró vulnerabilidades CRÍTICAS en las dependencias
Finished: FAILURE
```

En la vista de etapas, de la 3 en adelante aparecen en rojo y no se publicó ni desplegó nada.

## 6. Análisis de seguridad e imágenes

```bash
scripts/security-scans.sh
```

Construye las imágenes y corre Semgrep, Snyk, Trivy, Dive y KubeLinter. Los resultados quedan en `reports/`:

| Archivo | Resultado esperado |
|---|---|
| `semgrep-report.txt` | 0 hallazgos en `app/` y 8 en el archivo de control |
| `snyk-report.txt` | 0 vulnerabilidades, y 2 críticas en la prueba con PyYAML 5.3 |
| `trivy-backend.txt` | 0 críticas, 47 altas de Debian sin parche |
| `trivy-frontend.txt` | 0 vulnerabilidades |
| `image-layers.txt` | Capas, tamaños y eficiencia según Dive |
| `kubelinter.txt` | `No lint errors found!` |

El análisis comentado de las imágenes está en `reports/image-analysis.md`.

## 7. Validar las políticas de Kyverno

```bash
scripts/kyverno-validate.sh
```

Aplica un pod que viola cada política, otro que viola todas y uno correcto. Lo esperado es cinco rechazos y una admisión:

```text
$ kubectl apply -f k8s/policies/test/2-no-limits.yaml
Error from server: ... denied the request: Policy require-requests-limits failed: Todos los contenedores deben definir resources.requests y resources.limits de cpu y memory.
RESULTADO: RECHAZADO por Kyverno (esperado)
...
$ kubectl apply -f k8s/policies/test/0-compliant.yaml
pod/good-pod created
RESULTADO: ADMITIDO (esperado)
```

También se puede probar a mano que un Deployment con `latest` se rechaza de entrada:

```bash
kubectl create deployment prueba --image=nginx:latest -n journal
```

```text
error: failed to create deployment: admission webhook "vpol.validate.kyverno.svc-fail" denied the request: Policy require-run-as-non-root failed: ...; Policy disallow-latest-tag failed: No se permite la etiqueta 'latest': usá una versión fija.
```

La evidencia queda en `reports/kyverno-validation.log`.

## 8. Disparar una alerta de Falco

```bash
scripts/falco-trigger.sh
```

Ejecuta dentro del backend `cat /etc/shadow` y una conexión al API server de Kubernetes, las dos sin abrir una shell. Falco las registra así:

```text
Warning Proceso inesperado en el backend del diario (comando=cat /etc/shadow usuario_uid=100 padre=containerd-shim pod=journal-backend-... namespace=journal ...)
Notice Unexpected connection to K8s API Server from container | connection=10.244.0.101:36608->10.96.0.1:443 ... process=python ...
```

Para ver las alertas de Falco en cualquier momento:

```bash
kubectl logs -n falco -l app.kubernetes.io/name=falco -c falco | grep -E "Proceso inesperado|K8s API Server"
```

El log con la descripción del evento queda en `reports/falco-event.log`.

## 9. Borrar todo

```bash
scripts/teardown.sh          # desinstala la app, los operadores y sus CRDs; Minikube queda vacío
scripts/teardown.sh --all    # además borra Minikube, Jenkins y su volumen
```

## Problemas frecuentes

- **Grafana se reinicia en loop la primera vez.** Está migrando su base de datos y tarda. El `monitoring/values.yaml` ya le da 5 minutos de margen; si igual pasa, hay que esperar.
- **Un deploy falla con `failed calling webhook "vpol.validate.kyverno.svc-fail"`.** Kyverno no respondió a tiempo, casi siempre porque Minikube se quedó sin memoria. Ver `kubectl top node` y, si hace falta, recrear Minikube con más memoria (`minikube delete` y de nuevo `scripts/setup.sh`).
- **Minikube no toma la memoria nueva.** `--memory` solo se aplica al crear el cluster. Si el perfil ya existía, hay que borrarlo con `minikube delete`.
- **Los port-forwards dejan de responder.** Pasa cuando se reemplazan los pods. Se vuelve a correr `scripts/start-ui.sh`.
