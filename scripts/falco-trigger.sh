#!/usr/bin/env bash
# Dispara alertas de Falco SIN abrir una shell: ejecuta directamente "cat
# /etc/shadow" dentro del backend con kubectl exec (sin sh, sin -it).
# Guarda las alertas en reports/falco-event.log
source "$(dirname "$0")/lib.sh"
need kubectl

LOG="$REPORTS/falco-event.log"
kubectl get pods -n falco -l app.kubernetes.io/name=falco >/dev/null 2>&1 || fail "Falco no está instalado (scripts/setup.sh)"

SINCE=$(date -u +%Y-%m-%dT%H:%M:%SZ)
step "Acción sospechosa: leer /etc/shadow dentro del backend"
set +e
ACTION_OUTPUT=$(kubectl exec -n "$APP_NAMESPACE" deploy/journal-backend -c backend -- cat /etc/shadow 2>&1)
set -e
echo "  salida en el pod: $ACTION_OUTPUT"

step "Acción sospechosa 2: conectarse al API server de Kubernetes desde el backend"
set +e
ACTION2_OUTPUT=$(kubectl exec -n "$APP_NAMESPACE" deploy/journal-backend -c backend -- \
  python -c "import socket; socket.create_connection(('kubernetes.default.svc', 443), 3); print('conexión abierta con el API server')" 2>&1)
set -e
echo "  salida en el pod: $ACTION2_OUTPUT"

step "Esperando a que Falco registre el evento"
sleep 8
ALERTS=$(kubectl logs -n falco -l app.kubernetes.io/name=falco -c falco --since-time="$SINCE" --tail=-1 \
  | grep -E "Sensitive file opened|Proceso inesperado en el backend|K8s API Server from container" || true)
[ -n "$ALERTS" ] || fail "Falco no registró alertas todavía; volvé a correr el script en unos segundos."

{
  echo "# Falco: detección en tiempo de ejecución"
  echo "# Generado: $(date -u '+%Y-%m-%d %H:%M:%S UTC')"
  echo "# Instalación: helm install falco falcosecurity/falco --version $FALCO_CHART_VERSION -n falco -f falco/values.yaml"
  echo "#"
  echo "# Acciones ejecutadas (ninguna abre una shell ni una terminal interactiva):"
  echo "#   1) kubectl exec -n $APP_NAMESPACE deploy/journal-backend -c backend -- cat /etc/shadow"
  echo "#      Salida en el pod: $ACTION_OUTPUT"
  echo "#   2) kubectl exec -n $APP_NAMESPACE deploy/journal-backend -c backend -- python -c \"socket.create_connection(('kubernetes.default.svc', 443))\""
  echo "#      Salida en el pod: $ACTION2_OUTPUT"
  echo "#"
  echo "# Qué pasó:"
  echo "#   1) Alguien con acceso al cluster ejecutó un binario (cat) dentro del backend"
  echo "#      para leer /etc/shadow, el archivo con los hashes de contraseñas. Como el"
  echo "#      contenedor corre con UID 100 el kernel negó la lectura, pero Falco ve la"
  echo "#      ejecución del proceso y dispara la regla propia 'Proceso inesperado en el"
  echo "#      backend del diario' (falco/values.yaml): ese contenedor solo debería"
  echo "#      ejecutar python/uvicorn."
  echo "#   2) Desde el backend se abrió una conexión al API server de Kubernetes. La app"
  echo "#      nunca necesita hablar con el API server, así que es típico de un atacante"
  echo "#      que entró al pod y quiere reconocer el cluster. Lo detecta la regla de"
  echo "#      fábrica 'Unexpected connection to K8s API Server from container'."
  echo "#"
  echo "# Alertas registradas:"
  echo "#   kubectl logs -n falco -l app.kubernetes.io/name=falco -c falco | grep -E 'Proceso inesperado|K8s API Server'"
  echo
  echo "$ALERTS"
} > "$LOG"

echo "$ALERTS"
ok "Alertas guardadas en reports/falco-event.log"
