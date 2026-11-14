#!/usr/bin/env bash
# Funciones comunes de los scripts. Se usa con: source "$(dirname "$0")/lib.sh"
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

# Versiones fijas de los charts de los operadores.
KYVERNO_CHART_VERSION="3.10.0"
PROM_STACK_CHART_VERSION="93.3.0"
FALCO_CHART_VERSION="9.2.2"

APP_NAMESPACE="journal"
REPORTS="$ROOT/reports"
mkdir -p "$REPORTS"

if [ -t 1 ]; then BOLD=$'\e[1m'; GREEN=$'\e[32m'; YELLOW=$'\e[33m'; RED=$'\e[31m'; RESET=$'\e[0m'
else BOLD=""; GREEN=""; YELLOW=""; RED=""; RESET=""; fi

step() { echo; echo "${BOLD}==> $*${RESET}"; }
ok()   { echo "${GREEN}  ✓ $*${RESET}"; }
warn() { echo "${YELLOW}  ! $*${RESET}"; }
fail() { echo "${RED}  ✗ $*${RESET}" >&2; exit 1; }

need() {
  for cmd in "$@"; do
    command -v "$cmd" >/dev/null 2>&1 || fail "Falta '$cmd'. Instalalo y volvé a correr el script."
  done
}

# Carga .env.lab4 (tokens) si existe.
load_env() {
  if [ -f "$ROOT/.env.lab4" ]; then
    set -a; . "$ROOT/.env.lab4"; set +a
  fi
}

# Escribe un encabezado en un reporte.
report_header() { # archivo título
  {
    echo "# $2"
    echo "# Generado: $(date -u '+%Y-%m-%d %H:%M:%S UTC') · commit $(git rev-parse --short HEAD 2>/dev/null || echo '-')"
    echo
  } > "$1"
}
