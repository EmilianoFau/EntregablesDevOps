# V1 en Kubernetes

En esta etapa Kubernetes ejecuta una sola versión de la aplicación. Hay únicamente dos archivos:

- `config.yaml`: guarda la configuración que recibe el contenedor.
- `app.yaml`: crea un Deployment con un pod de `journal:v1` y un Service para acceder a él.

## Ejecutar en Minikube

```bash
minikube start
eval $(minikube docker-env)
docker build --target runtime -t journal:v1 .
kubectl apply -f k8s/config.yaml
kubectl apply -f k8s/app.yaml
kubectl rollout status deployment/journal-v1
minikube service journal
```

Para ver las piezas creadas:

```bash
kubectl get configmap,deployment,pod,service
```

El recorrido es:

```text
Navegador -> Service journal -> Deployment journal-v1 -> Pod -> FastAPI -> JSON
```

El Deployment crea y mantiene el pod. El Service le da un punto de acceso estable. El ConfigMap entrega variables de configuración al contenedor.

## Limitación conocida

El archivo JSON está dentro del contenedor. Si Kubernetes reemplaza el pod, vuelve a la copia incluida en la imagen y se pierden las entradas creadas durante esa ejecución. Es una decisión intencional para mantener esta primera versión fácil de entender; no es una solución de persistencia para producción.

Blue/green se agregará después de construir una V2 visible. En ese momento habrá dos Deployments y el Service elegirá cuál recibe el tráfico.
