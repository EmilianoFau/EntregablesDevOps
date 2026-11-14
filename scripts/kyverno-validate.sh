#!/usr/bin/env bash
# Prueba las 4 políticas de Kyverno: aplica un pod que viola cada una (deben
# ser rechazados) y uno que cumple todo (debe ser admitido).
# Deja la evidencia en reports/kyverno-validation.log
source "$(dirname "$0")/lib.sh"
need kubectl

LOG="$REPORTS/kyverno-validation.log"
report_header "$LOG" "Kyverno: validación de políticas de admisión"
kubectl create namespace "$APP_NAMESPACE" --dry-run=client -o yaml | kubectl apply -f - >/dev/null

step "Políticas instaladas"
{
  echo '$ kubectl get clusterpolicy'
  kubectl get clusterpolicy
  echo
} | tee -a "$LOG"

rejected=0
for manifest in k8s/policies/test/[1-4]-*.yaml k8s/policies/test/noncompliant-all.yaml; do
  step "Aplicando $manifest (debe ser RECHAZADO)"
  {
    echo "----------------------------------------------------------------"
    echo "\$ kubectl apply -f $manifest"
    if output=$(kubectl apply -f "$manifest" 2>&1); then
      echo "$output"
      echo "RESULTADO: ADMITIDO (inesperado)"
      kubectl delete -f "$manifest" --ignore-not-found >/dev/null
    else
      echo "$output"
      echo "RESULTADO: RECHAZADO por Kyverno (esperado)"
      rejected=$((rejected + 1))
    fi
    echo
  } | tee -a "$LOG"
done

step "Aplicando k8s/policies/test/0-compliant.yaml (debe ser ADMITIDO)"
{
  echo "----------------------------------------------------------------"
  echo '$ kubectl apply -f k8s/policies/test/0-compliant.yaml'
  if kubectl apply -f k8s/policies/test/0-compliant.yaml 2>&1; then
    echo "RESULTADO: ADMITIDO (esperado)"
  else
    echo "RESULTADO: RECHAZADO (inesperado)"
  fi
  kubectl delete -f k8s/policies/test/0-compliant.yaml --ignore-not-found --wait=false >/dev/null
  echo
  echo "----------------------------------------------------------------"
  echo "Los pods de la app (desplegados con Helm) también pasan las 4 políticas:"
  echo "\$ kubectl get pods -n $APP_NAMESPACE"
  kubectl get pods -n "$APP_NAMESPACE"
  echo
  echo "\$ kubectl get policyreport -n $APP_NAMESPACE"
  kubectl get policyreport -n "$APP_NAMESPACE" 2>&1 || true
} | tee -a "$LOG"

ok "Evidencia guardada en reports/kyverno-validation.log"
