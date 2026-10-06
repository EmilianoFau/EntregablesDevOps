# Blue/green en Minikube

El ejemplo usa solamente dos manifiestos:

- `config.yaml`: configuración compartida por las dos versiones.
- `blue-green.yaml`: dos Deployments y el Service que permite elegir uno.

```text
                         -> Deployment blue  -> journal:v1
Navegador -> Service ---|
                         -> Deployment green -> journal:v2
```

Los dos Deployments están encendidos. El selector del Service determina cuál recibe las visitas.

## 1. Construir las dos versiones

La V1 está guardada en el tag Git `v1`. Desde la raíz del proyecto:

```bash
minikube start

git switch --detach v1
docker build --target runtime -t journal:v1 .

git switch --detach v2
docker build --target runtime -t journal:v2 .

git switch main
minikube image load journal:v1
minikube image load journal:v2
```

## 2. Crear las piezas

```bash
kubectl apply -f k8s/config.yaml
kubectl apply -f k8s/blue-green.yaml
kubectl rollout status deployment/journal-blue
kubectl rollout status deployment/journal-green
minikube service journal
```

El Service comienza apuntando a blue. Se verá la V1 azul.

## 3. Pasar de V1 a V2

```bash
kubectl patch service journal -p '{"spec":{"selector":{"app":"journal","color":"green"}}}'
```

Al refrescar la página se verá la V2 coral y su pregunta del día. No se reconstruyó ningún contenedor: solamente se cambió el destino del Service.

## 4. Volver a V1

```bash
kubectl patch service journal -p '{"spec":{"selector":{"app":"journal","color":"blue"}}}'
```

Este regreso inmediato es el rollback de la estrategia blue/green.

## Ver qué está ocurriendo

```bash
kubectl get deployments,pods,service
kubectl get service journal -o jsonpath='{.spec.selector.color}'
```

## Limitación conocida

Cada pod guarda sus cambios en su propio archivo JSON. Por eso cada color corre con una sola réplica: con dos, la misma entrada existiría en un pod y no en el otro. Blue y green comienzan con los mismos datos de prueba, pero una entrada creada en blue no aparece en green. Es una simplificación consciente para esta entrega; una aplicación real usaría almacenamiento compartido.

## Monitoreo y alertas

`monitoring.yaml` agrega Prometheus y Grafana. La app cuenta cada escritura de entradas (crear, editar y borrar) en la métrica `journal_entry_operations_total`, expuesta en `/metrics`.

```text
Pods green (/metrics) <- Prometheus (regla de alerta) <- Grafana (dashboard)
```

La alerta `MuchasOperaciones` se dispara si hay **más de 5 operaciones en 5 minutos**. La regla está en el ConfigMap `prometheus-config`.

Solo se monitorea green, porque blue ejecuta la V1 y no tiene métricas. Hay que reconstruir `journal:v2` desde `main` para incluirlas. Se construye dentro de Minikube, porque `minikube image load` no reemplaza una imagen que ya existe con el mismo tag:

```bash
minikube image build -t journal:v2 --build-opt=target=runtime .
kubectl apply -f k8s/blue-green.yaml
kubectl rollout restart deployment/journal-green
kubectl patch service journal -p '{"spec":{"selector":{"app":"journal","color":"green"}}}'

kubectl apply -f k8s/monitoring.yaml
kubectl rollout status deployment/prometheus
kubectl rollout status deployment/grafana
minikube service prometheus
minikube service grafana
```

- Prometheus: en **Status → Targets** aparecen los pods green. En **Alerts** aparece `MuchasOperaciones`.
- Grafana: el dashboard **El Último Renglón** muestra las operaciones de los últimos 5 minutos y el estado de la alerta.

### Disparar la alerta

Con la entrada de hoy ya creada desde la página:

```bash
URL=$(minikube service journal --url)
ID=$(curl -s "$URL/api/entries?limit=1" | python3 -c 'import json,sys; print(json.load(sys.stdin)["items"][0]["id"])')
for i in $(seq 6); do
  curl -s -o /dev/null -X PUT "$URL/api/entries/$ID" -H 'Content-Type: application/json' \
    -d "{\"content\": \"Prueba $i\", \"mood\": \"SERENO\"}"
done
```

En menos de un minuto la alerta pasa a **Firing** en Prometheus y el panel de Grafana muestra **ALERTA**. Cuando pasan 5 minutos sin escrituras, vuelve a OK.
