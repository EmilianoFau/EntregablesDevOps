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

step "Esperando a que Falco registre el evento"
sleep 8
ALERTS=$(kubectl logs -n falco -l app.kubernetes.io/name=falco -c falco --since-time="$SINCE" --tail=-1 \
  | grep -E "Sensitive file opened|Proceso inesperado en el backend" || true)
[ -n "$ALERTS" ] || fail "Falco no registró alertas todavía; volvé a correr el script en unos segundos."

{
  echo "# Falco: detección en tiempo de ejecución"
  echo "# Generado: $(date -u '+%Y-%m-%d %H:%M:%S UTC')"
  echo "# Instalación: helm install falco falcosecurity/falco --version $FALCO_CHART_VERSION -n falco -f falco/values.yaml"
  echo "#"
  echo "# Acción ejecutada (no interactiva, sin shell):"
  echo "#   kubectl exec -n $APP_NAMESPACE deploy/journal-backend -c backend -- cat /etc/shadow"
  echo "# Salida en el pod: $ACTION_OUTPUT"
  echo "#"
  echo "# Qué pasó:"
  echo "#   Alguien con acceso al cluster ejecutó un binario (cat) dentro del contenedor"
  echo "#   del backend para leer /etc/shadow, el archivo con los hashes de contraseñas."
  echo "#   El contenedor corre como UID 100, así que el kernel le negó la lectura, pero"
  echo "#   Falco ve el intento a nivel de syscalls (openat) y lo reporta igual."
  echo "#   Se dispararon dos reglas:"
  echo "#   - 'Sensitive file opened for reading by non-trusted program' (regla por defecto)"
  echo "#   - 'Proceso inesperado en el backend del diario' (regla propia, falco/values.yaml):"
  echo "#     el backend solo debería ejecutar python/uvicorn."
  echo "#"
  echo "# Alertas registradas:"
  echo "#   kubectl logs -n falco -l app.kubernetes.io/name=falco -c falco | grep -E 'Sensitive file|Proceso inesperado'"
  echo
  echo "$ALERTS"
} > "$LOG"

echo "$ALERTS"
ok "Alertas guardadas en reports/falco-event.log"
