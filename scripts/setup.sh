#!/usr/bin/env bash
# Levanta todo el entorno desde cero: Minikube, operadores (Kyverno,
# kube-prometheus-stack, Falco), políticas, dashboard y la app con Helm.
# Uso: scripts/setup.sh [--sin-falco] [--tag <tag de Docker Hub>]
#   Sin --tag construye las imágenes dentro de Minikube con el tag "dev".
#   Con --tag usa las imágenes publicadas por Jenkins en Docker Hub.
source "$(dirname "$0")/lib.sh"

WITH_FALCO=true
IMAGE_TAG=""
while [ $# -gt 0 ]; do
  case "$1" in
    --sin-falco) WITH_FALCO=false ;;
    --tag) IMAGE_TAG="$2"; shift ;;
    *) fail "Opción desconocida: $1" ;;
  esac
  shift
done

need docker minikube kubectl helm

step "1/8 Minikube"
if minikube status >/dev/null 2>&1; then
  ok "Minikube ya está corriendo"
else
  minikube start --driver=docker --cpus=4 --memory=6g
fi
minikube addons enable ingress >/dev/null
minikube addons enable metrics-server >/dev/null
ok "Addons ingress y metrics-server habilitados"

step "2/8 Repositorios de Helm"
helm repo add kyverno https://kyverno.github.io/kyverno >/dev/null 2>&1 || true
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts >/dev/null 2>&1 || true
helm repo add falcosecurity https://falcosecurity.github.io/charts >/dev/null 2>&1 || true
helm repo update >/dev/null
ok "kyverno, prometheus-community y falcosecurity"

# Instala un chart solo si ese release no está ya desplegado en esa versión.
# Así el script se puede correr varias veces sin reinstalar los operadores.
install_once() { # release namespace chart version [args...]
  local release=$1 ns=$2 chart=$3 version=$4; shift 4
  if helm list -n "$ns" --deployed -o json 2>/dev/null | grep -q "\"name\":\"$release\".*\"chart\":\"[a-z-]*-$version\""; then
    ok "$release $version ya estaba instalado"
    return
  fi
  helm upgrade --install "$release" "$chart" --version "$version" \
    -n "$ns" --create-namespace --wait "$@"
}

step "3/8 Operador: Kyverno ${KYVERNO_CHART_VERSION}"
install_once kyverno kyverno kyverno/kyverno "$KYVERNO_CHART_VERSION" --timeout 10m
ok "Kyverno listo"

step "4/8 Operador: kube-prometheus-stack ${PROM_STACK_CHART_VERSION} (Prometheus + Grafana)"
install_once monitoring monitoring prometheus-community/kube-prometheus-stack \
  "$PROM_STACK_CHART_VERSION" -f monitoring/values.yaml --timeout 15m
ok "Prometheus Operator, Prometheus y Grafana listos"

step "5/8 Falco ${FALCO_CHART_VERSION}"
if $WITH_FALCO; then
  install_once falco falco falcosecurity/falco "$FALCO_CHART_VERSION" \
    -f falco/values.yaml --timeout 10m
  ok "Falco corriendo con la regla propia del diario"
else
  warn "Salteado (--sin-falco)"
fi

step "6/8 Políticas de Kyverno y dashboard de Grafana"
kubectl create namespace "$APP_NAMESPACE" --dry-run=client -o yaml | kubectl apply -f - >/dev/null
kubectl apply -f k8s/policies/
kubectl wait --for=jsonpath="{.status.conditionStatus.ready}"=true validatingpolicy --all --timeout=120s
kubectl create configmap journal-dashboard -n monitoring \
  --from-file=journal.json=grafana/dashboard.json --dry-run=client -o yaml \
  | kubectl label --local -f - grafana_dashboard=1 -o yaml \
  | kubectl apply -f - >/dev/null
ok "4 políticas en modo Deny y dashboard cargado en Grafana"

step "7/8 Imágenes de la app"
HELM_IMAGE_ARGS=()
if [ -n "$IMAGE_TAG" ]; then
  load_env
  : "${DOCKERHUB_USER:?Definí DOCKERHUB_USER en .env.lab4}"
  HELM_IMAGE_ARGS=(--set backend.image.repository="$DOCKERHUB_USER/journal-backend"
                   --set frontend.image.repository="$DOCKERHUB_USER/journal-frontend"
                   --set backend.image.tag="$IMAGE_TAG" --set frontend.image.tag="$IMAGE_TAG")
  ok "Se usarán las imágenes $DOCKERHUB_USER/journal-*:$IMAGE_TAG de Docker Hub"
else
  # Se construyen con el Docker de Minikube, así el cluster las ve sin registro.
  eval "$(minikube docker-env)"
  docker build -q --target runtime -t guilleacq/journal-backend:dev . >/dev/null
  docker build -q -t guilleacq/journal-frontend:dev frontend/ >/dev/null
  eval "$(minikube docker-env --unset)"
  ok "journal-backend:dev y journal-frontend:dev construidas dentro de Minikube"
fi

step "8/8 Despliegue con Helm"
helm upgrade --install journal ./helm-chart -n "$APP_NAMESPACE" \
  -f helm-chart/values-dev.yaml ${HELM_IMAGE_ARGS[@]+"${HELM_IMAGE_ARGS[@]}"} --wait --timeout 5m
kubectl get pods -n "$APP_NAMESPACE"
helm test journal -n "$APP_NAMESPACE" --logs
ok "La app responde. Siguiente paso: scripts/start-ui.sh"
