#!/usr/bin/env bash
# Genera tráfico realista contra la app para poblar el dashboard de Grafana.
# Uso: scripts/load-traffic.sh [segundos] [url]
#   por defecto 300 segundos contra http://localhost:8080 (port-forward de start-ui.sh)
source "$(dirname "$0")/lib.sh"
need curl python3

DURATION="${1:-300}"
URL="${2:-http://localhost:8080}"
MOODS=(SERENO FELIZ AGRADECIDO CANSADO TRISTE ANSIOSO REFLEXIVO)

curl -fsS "$URL/api/day" >/dev/null || fail "La app no responde en $URL. ¿Corriste scripts/start-ui.sh?"

TODAY=$(curl -fsS "$URL/api/day" | python3 -c 'import json,sys; print(json.load(sys.stdin)["date"])')
END=$(( $(date +%s) + DURATION ))

# Lectores: navegan la página y los listados (la mayor parte del tráfico).
reader() {
  while [ "$(date +%s)" -lt "$END" ]; do
    curl -s -o /dev/null "$URL/"
    curl -s -o /dev/null "$URL/api/day"
    curl -s -o /dev/null "$URL/api/moods"
    curl -s -o /dev/null "$URL/api/version"
    curl -s -o /dev/null "$URL/api/entries?limit=20"
    curl -s -o /dev/null "$URL/api/entries?mood=${MOODS[RANDOM % 7]}"
    curl -s -o /dev/null "$URL/api/entries/by-date/$TODAY"
    sleep 0.$(( RANDOM % 5 ))
  done
}

# Escritor: crea, edita y a veces borra la entrada de hoy (métricas de negocio).
writer() {
  while [ "$(date +%s)" -lt "$END" ]; do
    mood=${MOODS[RANDOM % 7]}
    id=$(curl -s "$URL/api/entries/by-date/$TODAY" | python3 -c 'import json,sys
try: print(json.load(sys.stdin).get("id",""))
except Exception: print("")')
    body="{\"content\": \"Prueba de carga $(date +%T)\", \"mood\": \"$mood\"}"
    if [ -z "$id" ]; then
      curl -s -o /dev/null -X POST "$URL/api/entries" -H 'Content-Type: application/json' -d "$body"
    elif [ $(( RANDOM % 6 )) -eq 0 ]; then
      curl -s -o /dev/null -X DELETE "$URL/api/entries/$id"
    else
      curl -s -o /dev/null -X PUT "$URL/api/entries/$id" -H 'Content-Type: application/json' -d "$body"
    fi
    sleep $(( 5 + RANDOM % 10 ))
  done
}

# Errores: rutas inexistentes (404) y datos inválidos (422).
noise() {
  while [ "$(date +%s)" -lt "$END" ]; do
    curl -s -o /dev/null "$URL/api/entries/00000000-0000-0000-0000-000000000000"
    curl -s -o /dev/null -X POST "$URL/api/entries" -H 'Content-Type: application/json' -d '{"content": "", "mood": "X"}'
    sleep 2
  done
}

step "Generando tráfico durante ${DURATION}s contra $URL"
reader & reader & reader &
writer &
noise &
trap 'kill $(jobs -p) 2>/dev/null; exit 0' INT TERM

while [ "$(date +%s)" -lt "$END" ]; do
  printf "\r  quedan %3ss" $(( END - $(date +%s) ))
  sleep 5
done
wait
echo
ok "Listo. Mirá el dashboard 'El Último Renglón' en Grafana."
