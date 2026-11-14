#!/usr/bin/env bash
# Borra todo lo que crearon los scripts.
# Uso: scripts/teardown.sh          (deja Minikube encendido pero vacío)
#      scripts/teardown.sh --all    (además borra Minikube, Jenkins y su volumen)
source "$(dirname "$0")/lib.sh"
need kubectl helm

"$ROOT/scripts/start-ui.sh" --stop >/dev/null 2>&1 || true

step "Desinstalando releases de Helm"
for pair in journal:$APP_NAMESPACE falco:falco monitoring:monitoring kyverno:kyverno; do
  release=${pair%%:*}; ns=${pair##*:}
  if helm status "$release" -n "$ns" >/dev/null 2>&1; then
    helm uninstall "$release" -n "$ns" --wait >/dev/null
    ok "$release"
  fi
done

step "Borrando políticas, dashboard y namespaces"
kubectl delete -f k8s/policies/ --ignore-not-found >/dev/null 2>&1 || true
kubectl delete configmap journal-dashboard -n monitoring --ignore-not-found >/dev/null 2>&1 || true
kubectl delete namespace "$APP_NAMESPACE" falco monitoring kyverno --ignore-not-found --wait=false
ok "Namespaces en borrado"

step "Borrando CRDs de los operadores"
kubectl get crd -o name | grep -E 'monitoring\.coreos\.com|kyverno\.io|wgpolicyk8s\.io' \
  | xargs -r kubectl delete --ignore-not-found >/dev/null
ok "CRDs de Prometheus Operator y Kyverno eliminados"

if [ "${1:-}" = "--all" ]; then
  step "Borrando Jenkins y Minikube"
  docker rm -f jenkins-lab4 >/dev/null 2>&1 || true
  docker volume rm jenkins_home_lab4 >/dev/null 2>&1 || true
  rm -rf "$ROOT/.jenkins"
  minikube delete
  ok "Entorno completamente eliminado"
fi
