#!/usr/bin/env bash
# Corre los análisis de seguridad y calidad fuera de Jenkins y deja los
# resultados en reports/. Usa las imágenes oficiales de cada herramienta, así
# no hace falta instalarlas.
#   Semgrep   -> reports/semgrep-report.txt
#   Snyk      -> reports/snyk-report.txt
#   Trivy     -> reports/trivy-backend.txt, reports/trivy-frontend.txt
#   Slim/Dive -> reports/image-layers.txt (insumo de reports/image-analysis.md)
#   KubeLinter-> reports/kubelinter.txt
source "$(dirname "$0")/lib.sh"
need docker
load_env

SEMGREP_IMAGE=semgrep/semgrep:1.185.0
TRIVY_IMAGE=aquasec/trivy:0.76.2
SNYK_IMAGE=snyk/snyk:python-3.13
SLIM_IMAGE=dslim/slim:1.40.11
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
if [ -n "${SNYK_TOKEN:-}" ]; then
  report_header "$REPORTS/snyk-report.txt" "Snyk: dependencias Python (requirements.txt)"
  docker run --rm --platform linux/amd64 -e SNYK_TOKEN -v "$ROOT:/project" -w /project "$SNYK_IMAGE" \
    sh -c 'pip install -q --root-user-action=ignore -r requirements.txt >/dev/null 2>&1;
           snyk test --file=requirements.txt --package-manager=pip --show-vulnerable-paths=all' \
    >> "$REPORTS/snyk-report.txt" 2>&1 || true
  {
    echo
    echo "## Control: misma prueba agregando PyYAML==5.3 (lo que hace el pipeline con SIMULAR_DEPENDENCIA_VULNERABLE)"
    docker run --rm --platform linux/amd64 -e SNYK_TOKEN -v "$ROOT:/project:ro" "$SNYK_IMAGE" \
      sh -c 'mkdir /w && cd /w && cp /project/requirements.txt . && echo "PyYAML==5.3" >> requirements.txt &&
             pip install -q --root-user-action=ignore -r requirements.txt >/dev/null 2>&1;
             snyk test --file=requirements.txt --package-manager=pip --severity-threshold=critical; echo "exit code: $?"' 2>&1 || true
  } >> "$REPORTS/snyk-report.txt"
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

step "Capas y tamaño (docker history + SlimToolkit xray)"
{
  for image in "$BACKEND" "$FRONTEND"; do
    echo "################ $image"
    docker image inspect "$image" --format 'Tamaño: {{.Size}} bytes · Capas: {{len .RootFS.Layers}} · Arquitectura: {{.Architecture}}'
    echo
    docker history --format 'table {{.Size}}\t{{.CreatedBy}}' --no-trunc "$image" | cut -c1-160
    echo
    docker run --rm -v /var/run/docker.sock:/var/run/docker.sock "$SLIM_IMAGE" \
      --quiet xray --target "$image" 2>&1 | grep -iE "size|layers|image\.|stat" | head -30 || true
    echo
  done
} > "$REPORTS/image-layers.txt"
ok "reports/image-layers.txt"

step "KubeLinter sobre el Helm chart"
report_header "$REPORTS/kubelinter.txt" "KubeLinter: helm-chart/ (checks por defecto)"
docker run --rm -v "$ROOT:/src" -w /src "$KUBELINTER_IMAGE" lint helm-chart/ \
  >> "$REPORTS/kubelinter.txt" 2>&1 || true
ok "reports/kubelinter.txt"
