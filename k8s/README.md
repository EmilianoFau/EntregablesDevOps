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

Cada pod guarda sus cambios en su propio archivo JSON. Ambos comienzan con los mismos datos de prueba, pero una entrada creada en blue no aparece en green. Es una simplificación consciente para esta entrega; una aplicación real usaría almacenamiento compartido.
