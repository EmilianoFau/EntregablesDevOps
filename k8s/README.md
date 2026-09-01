# Despliegue en Minikube

Construir y cargar las dos versiones:

```bash
minikube start
eval $(minikube docker-env)
docker build -t journal:v1 .
docker build --build-arg VERSION=v2 -t journal:v2 .
```

Crear la infraestructura y ejecutar la migración:

```bash
kubectl apply -f k8s/namespace.yaml
kubectl apply -f k8s/config.yaml
kubectl apply -f k8s/postgres.yaml
kubectl -n journal rollout status statefulset/postgres
kubectl apply -f k8s/migration-job.yaml
kubectl -n journal wait --for=condition=complete job/journal-migrate --timeout=120s
kubectl apply -f k8s/app-blue-green.yaml
kubectl -n journal rollout status deployment/journal-blue
kubectl -n journal rollout status deployment/journal-green
minikube service journal -n journal
```

El servicio comienza apuntando a blue/v1. Para pasar a green/v2:

```bash
kubectl -n journal patch service journal -p '{"spec":{"selector":{"app":"journal","color":"green"}}}'
```

Rollback inmediato:

```bash
kubectl -n journal patch service journal -p '{"spec":{"selector":{"app":"journal","color":"blue"}}}'
```

Verificar la versión activa:

```bash
kubectl -n journal port-forward service/journal 8080:80
curl http://localhost:8080/api/version
```

Antes de una entrega real, reemplazar los valores de ejemplo de `k8s/config.yaml` por secretos administrados fuera de Git.

