#!/usr/bin/env bash
# Abre port-forwards a la app, Grafana y Prometheus.
# Uso: scripts/start-ui.sh          (los deja corriendo en segundo plano)
#      scripts/start-ui.sh --stop   (los cierra)
source "$(dirname "$0")/lib.sh"
need kubectl

PIDS="$ROOT/.port-forwards.pids"

stop() {
  if [ -f "$PIDS" ]; then
    while read -r pid; do kill "$pid" 2>/dev/null || true; done < "$PIDS"
    rm -f "$PIDS"
    ok "Port-forwards cerrados"
  fi
}

if [ "${1:-}" = "--stop" ]; then stop; exit 0; fi
stop

forward() { # namespace servicio puerto_local puerto_remoto
  kubectl port-forward -n "$1" "svc/$2" "$3:$4" >/dev/null 2>&1 &
  echo $! >> "$PIDS"
}

step "Abriendo port-forwards"
forward "$APP_NAMESPACE" journal-frontend 8080 80
forward monitoring monitoring-grafana 3000 80
forward monitoring monitoring-kube-prometheus-prometheus 9090 9090
sleep 3

cat <<EOF

  App         http://localhost:8080
  Grafana     http://localhost:3000   (admin / admin) → Dashboards → El Último Renglón
  Prometheus  http://localhost:9090   → Status → Targets (journal-backend)
  Jenkins     http://localhost:8081   (admin / admin, si corriste scripts/start-jenkins.sh)

  Para generar tráfico:  scripts/load-traffic.sh
  Para cerrarlos:        scripts/start-ui.sh --stop
EOF
