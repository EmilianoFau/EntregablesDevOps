#!/usr/bin/env bash
# Corre los análisis de seguridad y calidad fuera de Jenkins y deja los
# resultados en reports/. Usa las imágenes oficiales de cada herramienta, así
# no hace falta instalarlas.
#   Semgrep   -> reports/semgrep-report.txt
#   Snyk      -> reports/snyk-report.txt
#   Trivy     -> reports/trivy-backend.txt, reports/trivy-frontend.txt
#   Dive      -> reports/image-layers.txt (insumo de reports/image-analysis.md)
#   KubeLinter-> reports/kubelinter.txt
source "$(dirname "$0")/lib.sh"
need docker
load_env

SEMGREP_IMAGE=semgrep/semgrep:1.185.0
TRIVY_IMAGE=aquasec/trivy:0.76.2
DIVE_IMAGE=wagoodman/dive:v0.13.1
KUBELINTER_IMAGE=stackrox/kube-linter:v0.8.3-alpine
BACKEND=journal-backend:scan
FRONTEND=journal-frontend:scan

step "Construyendo las imágenes a analizar"
docker build -q --target runtime -t "$BACKEND" . >/dev/null
docker build -q -t "$FRONTEND" frontend/ >/dev/null
ok "$BACKEND y $FRONTEND"

step "Semgrep (reglas propias + p/python)"
report_header "$REPORTS/semgrep-report.txt" "Semgrep: análisis estático de app/"
docker run --rm -v "$ROOT:/src" -w /src "$SEMGREP_IMAGE" \
  semgrep scan --metrics=off --config semgrep/rules.yaml --config p/python \
  --exclude tests --text app/ >> "$REPORTS/semgrep-report.txt" 2>&1 || true
{
  echo
  echo "## Control: las reglas propias sobre un archivo con malas prácticas a propósito"
  docker run --rm -v "$ROOT:/src" -w /src "$SEMGREP_IMAGE" \
    semgrep scan --metrics=off --config semgrep/rules.yaml --text semgrep/ejemplo-inseguro.py 2>&1 || true
} >> "$REPORTS/semgrep-report.txt"
ok "reports/semgrep-report.txt"

step "Snyk (dependencias de requirements.txt)"
# Se usa la imagen de Jenkins (scripts/start-jenkins.sh): trae el mismo binario
# de Snyk que el pipeline, compilado para la arquitectura de la máquina.
JENKINS_IMAGE=journal-jenkins:2.580.2
docker image inspect "$JENKINS_IMAGE" >/dev/null 2>&1 || docker build -q -t "$JENKINS_IMAGE" jenkins/ >/dev/null
snyk_run() { # requirements extra
  docker run --rm --entrypoint bash -e SNYK_TOKEN -e EXTRA="$1" -v "$ROOT:/project:ro" "$JENKINS_IMAGE" -c '
    set -e; mkdir -p /tmp/w && cd /tmp/w && cp /project/requirements.txt .
    [ -n "$EXTRA" ] && echo "$EXTRA" >> requirements.txt
    python3 -m venv venv && venv/bin/pip install -q -r requirements.txt
    set +e; snyk test --file=requirements.txt --package-manager=pip --command=venv/bin/python '"$2"'; echo "(código de salida de snyk: $?)"'
}
if [ -n "${SNYK_TOKEN:-}" ]; then
  report_header "$REPORTS/snyk-report.txt" "Snyk: dependencias Python (requirements.txt)"
  snyk_run "" "--show-vulnerable-paths=all" >> "$REPORTS/snyk-report.txt" 2>&1
  {
    echo
    echo "## Control: misma prueba agregando PyYAML==5.3 (lo que hace el pipeline con SIMULAR_DEPENDENCIA_VULNERABLE)"
    snyk_run "PyYAML==5.3" "--severity-threshold=critical"
  } >> "$REPORTS/snyk-report.txt" 2>&1
  ok "reports/snyk-report.txt"
else
  warn "Sin SNYK_TOKEN en .env.lab4: se saltea Snyk"
fi

step "Trivy (vulnerabilidades de las imágenes)"
for pair in backend:$BACKEND frontend:$FRONTEND; do
  name=${pair%%:*}; image=${pair#*:}
  report_header "$REPORTS/trivy-$name.txt" "Trivy: imagen $name"
  docker run --rm -v /var/run/docker.sock:/var/run/docker.sock -v trivy-cache:/root/.cache "$TRIVY_IMAGE" \
    image --quiet --scanners vuln "$image" >> "$REPORTS/trivy-$name.txt" 2>&1 || true
  ok "reports/trivy-$name.txt"
done

step "Capas y tamaño (docker history + Dive)"
{
  for image in "$BACKEND" "$FRONTEND"; do
    echo "################ $image"
    docker image inspect "$image" --format 'Capas: {{len .RootFS.Layers}} · Arquitectura: {{.Architecture}}'
    docker image ls "$image" --format 'Tamaño en disco: {{.Size}}'
    echo
    docker history --format 'table {{.Size}}\t{{.CreatedBy}}' --no-trunc "$image" | cut -c1-160
    echo
    # SlimToolkit 1.40 usa la API 1.24 de Docker, que Docker 29 ya no acepta;
    # se usa Dive (la otra herramienta que permite la letra) en modo CI.
    docker run --rm -e CI=true -v /var/run/docker.sock:/var/run/docker.sock "$DIVE_IMAGE" "$image" 2>&1 \
      | sed 's/\x1b\[[0-9;]*m//g' | grep -E "efficiency:|wastedBytes:|userWastedPercent:|PASS|FAIL|Result" || true
    echo
  done
} > "$REPORTS/image-layers.txt"
ok "reports/image-layers.txt"

step "KubeLinter sobre el Helm chart"
report_header "$REPORTS/kubelinter.txt" "KubeLinter: helm-chart/ (checks por defecto)"
docker run --rm -v "$ROOT:/src" -w /src "$KUBELINTER_IMAGE" lint helm-chart/ \
  >> "$REPORTS/kubelinter.txt" 2>&1 || true
ok "reports/kubelinter.txt"
