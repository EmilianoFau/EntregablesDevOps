# Entregable 3 — Informe DevSecOps

Resultados de las herramientas de seguridad sobre "El Último Renglón" (FastAPI, imagen `journal:v1`/`journal:v2`, blue/green en Minikube). Fecha de ejecución: 03/11/2026.

| Archivo | Herramienta | Resultado |
|---|---|---|
| `npm-audit.txt` | pip-audit (equivalente a npm audit) | 14 vulnerabilidades → **0** |
| `semgrep.txt` | Semgrep | 9 hallazgos → 5 (falsos positivos, justificados) |
| `trivyreport.txt` | Trivy | v2: **0 CRITICAL**, 45 HIGH sin parche publicado (documentadas) |
| `kyverno-test.txt` | Kyverno | Pod no conforme **rechazado** por las 3 políticas |
| `kubelinter.txt` | KubeLinter | **0 errores** con los checks por defecto |
| `falco-event.log` | Falco | Alertas de shell interactiva y lectura de `/etc/shadow` |

---

## 1. Seguridad en el código

### Dependencias (`npm-audit.txt`)

El proyecto es Python y no tiene `package.json`, así que `npm audit` no tiene nada que revisar. Se usó **pip-audit**, que cumple la misma función para `requirements*.txt`. El archivo conserva el nombre pedido.

```bash
pip install pip-audit
pip-audit -r requirements-dev.txt
```

| Paquete | Antes | Después | Motivo |
|---|---|---|---|
| fastapi | 0.116.1 | 0.162.0 | arrastraba `starlette 0.47.3` con 12 avisos (DoS por Range, SSRF en StaticFiles, formularios) |
| starlette (transitiva) | 0.47.3 | 1.10.0 | ídem |
| pytest | 8.4.1 | 9.2.0 | PYSEC-2026-1845 |
| uvicorn, pydantic-settings, prometheus-client | — | última versión | mantenerlas alineadas con FastAPI |

Los 11 tests pasan con las versiones nuevas (`docker build --target test -t journal:test . && docker run --rm journal:test`).

### Análisis estático (`semgrep.txt`)

```bash
semgrep scan --metrics=off --config p/python --config p/dockerfile \
  --config p/kubernetes --config p/javascript --exclude data .
```

| Hallazgo | Dónde | Acción |
|---|---|---|
| `dockerfile.security.missing-user` | etapa `test` del Dockerfile corría como root | **Corregido**: `USER 100:101` |
| `run-as-non-root` (×4) | Deployments blue, green, Prometheus, Grafana | **Corregido**: `securityContext.runAsNonRoot: true` + UID explícito |
| `writable-filesystem-container` (×4) | mismos contenedores | **Corregido**: `readOnlyRootFilesystem: true` + volúmenes `emptyDir` solo donde se escribe |

**Se mantienen (5 falsos positivos):** la regla `run-as-non-root` marca las líneas `spec:` de `k8s/policies/*.yaml`. Esos archivos son `ClusterPolicy` de Kyverno: su `spec` es un *patrón de validación*, no un Pod. Justamente son las políticas que **exigen** `runAsNonRoot`.

El código Python y el frontend (`app/static/index.html`) no tuvieron hallazgos.

---

## 2. Seguridad en la imagen (`trivyreport.txt`)

```bash
trivy image --severity CRITICAL,HIGH journal:v2
trivy image --severity CRITICAL,HIGH --ignore-unfixed journal:v2
```

Cambios en el `Dockerfile`:

- Base explícita `python:3.13-slim-trixie` + `apt-get upgrade` para aplicar los parches de Debian disponibles.
- Usuario con UID/GID fijos (`100:101`, los mismos de la V1) y `USER 100:101` numérico, para que kubelet pueda verificar `runAsNonRoot`.
- Se **desinstala `pip`** en la etapa `runtime`. No se usa en ejecución y su código vendorizado traía `urllib3` (2 HIGH), `msgpack` (2 HIGH) y `setuptools` (1 HIGH).

**Resultado en `journal:v2`:** 0 CRITICAL, 0 vulnerabilidades en paquetes Python y **0 con parche disponible** (`--ignore-unfixed`).

### HIGH que se mantienen (sin parche de Debian a la fecha)

Las 45 HIGH restantes son 9 CVEs repetidas en paquetes base de Debian 13 (`Status: affected` / `fix_deferred`, sin *Fixed Version*). No se pueden resolver actualizando: se documentan y se aceptan con estas mitigaciones.

| CVE | Paquetes | Por qué el riesgo es bajo en este contenedor |
|---|---|---|
| CVE-2026-76642, -78408, -78409, -78410 | util-linux (`mount`, `nsenter`, libmount…) | Afectan montajes y `nsenter` privilegiados. El contenedor corre como UID 100, sin capabilities (`drop: ALL`), sin `allowPrivilegeEscalation` y no ejecuta `mount` |
| CVE-2026-16742 | libsystemd0, libudev1 | Afecta a `systemd-homed`, que no existe ni corre en el contenedor |
| CVE-2026-54369 | libacl1 | Escalada por *symlink traversal*: requiere un proceso privilegiado que use ACLs, y no lo hay |
| CVE-2025-69720 | ncurses | Requiere procesar datos de terminal maliciosos. La app no usa ncurses |
| CVE-2026-119373 | libsqlite3-0 | DoS en FTS5 de SQLite. La app guarda en JSON y no usa SQLite |
| CVE-2026-9538 | perl-base (Archive-Tar) | La app no ejecuta Perl ni procesa archivos tar |

Mitigaciones comunes: usuario no root, raíz de solo lectura, `capabilities.drop: ALL`, `seccompProfile: RuntimeDefault` y Falco vigilando la ejecución. Hay que volver a escanear cuando Debian publique los parches y reconstruir la imagen. Alternativa futura: una base *distroless*, que no trae util-linux ni perl.

### Imagen V1 (rollback de blue)

`journal:v1` se construye desde el tag Git `v1` con el Dockerfile anterior. Tiene **1 CRITICAL** (`certifi`, dentro de pip) y 8 HIGH en dependencias Python (starlette 0.47.3, pip vendorizado), además de las mismas 45 HIGH de Debian. Se deja documentada como versión legada: solo existe como destino de rollback de blue/green. Si hubiera que seguir usándola, se reconstruiría con el Dockerfile y las dependencias actuales.

---

## 3. Seguridad en Kubernetes

### Kyverno (`kyverno-test.txt`)

Instalación:

```bash
helm repo add kyverno https://kyverno.github.io/kyverno
helm install kyverno kyverno/kyverno -n kyverno --create-namespace
kubectl apply -f k8s/policies/
```

| Política | Archivo | Qué exige |
|---|---|---|
| 1. Sin `latest` | `k8s/policies/disallow-latest-tag.yaml` | Etiqueta explícita y distinta de `latest` en todos los contenedores |
| 2. Recursos | `k8s/policies/require-requests-limits.yaml` | `requests` y `limits` de cpu y memory en contenedores e initContainers |
| 3. No root | `k8s/policies/require-run-as-non-root.yaml` | `runAsNonRoot: true` (pod o contenedor) y prohíbe `runAsUser: 0` |

Las tres están en modo **Enforce** y excluyen los namespaces de sistema (`kube-system`, `kyverno`, `falco`). Falco necesita privilegios para leer eventos del kernel.

**Validación:** `kubectl apply -f k8s/policies/test/noncompliant-pod.yaml` (`nginx:latest`, sin resources, `runAsUser: 0`) es rechazado por el admission webhook, con un mensaje por cada política. Los manifiestos del proyecto se despliegan sin errores con las políticas activas.

Notas:

- Kyverno 1.19 avisa que `ClusterPolicy` está *deprecated* en favor de `ValidatingPolicy` (CEL). Sigue funcionando y es el formato habitual de la documentación del curso.
- En el informe aparecen `FAIL` en ReplicaSets viejos (revisiones anteriores con 0 réplicas, creadas antes de endurecer los manifiestos). Los pods y Deployments actuales pasan las 5 reglas.

### Cambios en los manifiestos

- `k8s/blue-green.yaml`: `securityContext` de pod (`runAsNonRoot`, UID 100, `seccompProfile`) y de contenedor (`readOnlyRootFilesystem`, `allowPrivilegeEscalation: false`, `drop: ALL`). También `requests`/`limits`, probes en `/health/ready` y `/health/live` y `automountServiceAccountToken: false`.
- Como la raíz es de solo lectura, un **initContainer `seed-data`** copia `data/entries.json` de la imagen a un `emptyDir` montado en `/app/data`. Así se mantiene el comportamiento anterior: cada pod arranca con los datos de ejemplo y escribe en su propio archivo.
- `k8s/monitoring.yaml`: lo mismo para Prometheus (UID 65534, `emptyDir` en `/prometheus`) y Grafana (UID 472, `emptyDir` en `/var/lib/grafana` y `/tmp`). Prometheus ahora scrapea solo el puerto 8000, porque el initContainer generaba un target sin puerto que figuraba como caído.

### KubeLinter (`kubelinter.txt`)

```bash
kube-linter lint k8s/config.yaml k8s/blue-green.yaml k8s/monitoring.yaml
```

- **Checks por defecto: 0 errores.** Los manifiestos originales tenían 16: falta de cpu/memory, `runAsNonRoot` y raíz escribible en los 4 Deployments (sección 4 del informe).
- Control: el manifiesto no conforme de prueba sí da 5 errores.
- Como análisis extra se corrieron **todos** los checks opcionales (`addAllBuiltIn`). Dieron 42 avisos, que se aceptan:

| Check opcional | Justificación |
|---|---|
| `minimum-three-replicas` | Cada pod guarda sus datos en su propio JSON: con más réplicas los datos divergen (limitación documentada en `k8s/README.md`) |
| `use-namespace` | Demo de un solo equipo en Minikube; todo vive en `default` |
| `exposed-services` (NodePort) | Es la forma de acceder desde el navegador con `minikube service` |
| `non-isolated-pod` | No hay NetworkPolicies; el CNI por defecto de Minikube no las aplica. Mejora pendiente para un cluster real |
| `no-rolling-update-strategy`, `restart-policy` | Kubernetes usa por defecto `RollingUpdate` y `Always`; el check solo pide declararlos explícitamente |
| `no-node-affinity`, `dnsconfig-options`, `required-label-owner`, `required-annotation-email` | Convenciones organizativas sin efecto en un cluster de un solo nodo |

---

## 4. Seguridad en tiempo de ejecución (`falco-event.log`)

```bash
helm repo add falcosecurity https://falcosecurity.github.io/charts
helm install falco falcosecurity/falco -n falco --create-namespace \
  --set driver.kind=modern_ebpf --set tty=true \
  --set falcoctl.artifact.install.enabled=false \
  --set falcoctl.artifact.follow.enabled=false
```

`falcoctl` intenta descargar las reglas de `ghcr.io` y recibió `429 Too Many Requests`. Por eso se desactivó la descarga y se usan las reglas incluidas en la imagen de Falco (`/etc/falco/falco_rules.yaml`).

Acción sospechosa:

```bash
kubectl exec -it deploy/journal-green -c journal -- sh
# dentro: id; cat /etc/shadow
```

Falco registró:

- `Notice A shell was spawned in a container with an attached terminal`: regla *Terminal shell in container*.
- `Warning Sensitive file opened for reading by non-trusted program | file=/etc/shadow`.

El `cat /etc/shadow` devolvió *Permission denied*: el contenedor corre como UID 100 y no puede leerlo. Igual Falco detecta el intento.

```bash
kubectl logs -n falco -l app.kubernetes.io/name=falco -c falco | grep -E "shell was spawned|Sensitive file"
```
