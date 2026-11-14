#!/usr/bin/env bash
# Construye y levanta Jenkins en Docker, ya configurado (JCasC) con las
# credenciales de .env.lab4 y el job "journal-pipeline".
# Uso: scripts/start-jenkins.sh [--stop]
source "$(dirname "$0")/lib.sh"
need docker minikube kubectl

NAME=jenkins-lab4
IMAGE=journal-jenkins:2.580.2

if [ "${1:-}" = "--stop" ]; then
  docker rm -f "$NAME" >/dev/null 2>&1 || true
  ok "Jenkins detenido (el volumen jenkins_home_lab4 se conserva)"
  exit 0
fi

load_env
: "${SNYK_TOKEN:?Falta SNYK_TOKEN en .env.lab4}"
: "${DOCKERHUB_USER:?Falta DOCKERHUB_USER en .env.lab4}"
: "${DOCKERHUB_TOKEN:?Falta DOCKERHUB_TOKEN en .env.lab4}"
minikube status >/dev/null 2>&1 || fail "Minikube no está corriendo. Corré scripts/setup.sh primero."

step "Construyendo la imagen de Jenkins (la primera vez tarda unos minutos)"
docker build -q -t "$IMAGE" jenkins/ >/dev/null
ok "$IMAGE"

step "Generando el kubeconfig para que Jenkins llegue a Minikube"
# Jenkins corre en la red Docker "minikube", así que usa la IP interna del
# API server en lugar del puerto publicado en 127.0.0.1.
KUBEDIR="$ROOT/.jenkins"
mkdir -p "$KUBEDIR"
kubectl config view --flatten --minify --context minikube \
  | sed -E "s#server: https://[^ ]+#server: https://$(minikube ip):8443#" > "$KUBEDIR/kubeconfig"
chmod 644 "$KUBEDIR/kubeconfig"
ok "kubeconfig apuntando a https://$(minikube ip):8443"

step "Levantando Jenkins"
docker rm -f "$NAME" >/dev/null 2>&1 || true
# El socket de Docker pertenece al grupo 0 dentro de la VM de Docker Desktop:
# se agrega ese grupo al usuario jenkins en lugar de correr Jenkins como root.
docker run -d --name "$NAME" \
  --network minikube \
  -p 8081:8080 \
  --group-add "$(docker run --rm -v /var/run/docker.sock:/s alpine:3.24.4 stat -c %g /s)" \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -v "$KUBEDIR/kubeconfig:/etc/kube/config:ro" \
  -v jenkins_home_lab4:/var/jenkins_home \
  -e SNYK_TOKEN -e DOCKERHUB_USER -e DOCKERHUB_TOKEN \
  -e JENKINS_ADMIN_PASSWORD="${JENKINS_ADMIN_PASSWORD:-admin}" \
  -e REPO_URL="${REPO_URL:-https://github.com/EmilianoFau/EntregablesDevOps.git}" \
  -e REPO_BRANCH="${REPO_BRANCH:-entrega4}" \
  "$IMAGE" >/dev/null

printf "  esperando a que Jenkins arranque"
for _ in $(seq 60); do
  if curl -fsS -o /dev/null http://localhost:8081/login 2>/dev/null; then echo; break; fi
  printf "."; sleep 3
done
curl -fsS -o /dev/null http://localhost:8081/login || fail "Jenkins no respondió. Mirá: docker logs $NAME"
ok "Jenkins en http://localhost:8081 (admin / ${JENKINS_ADMIN_PASSWORD:-admin})"
echo "  Job: journal-pipeline → Build with Parameters"
