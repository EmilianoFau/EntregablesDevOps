# Frontend: un único index.html servido por nginx.

# Etapa 1: preparar los archivos estáticos (precompresión gzip).
# Solo se copia el resultado; alpine y gzip no llegan a la imagen final.
FROM alpine:3.24.4 AS build
WORKDIR /site
COPY index.html ./
RUN gzip -9 -k index.html

# Etapa 2: nginx oficial "unprivileged" (corre como UID 101, puerto 8080).
FROM nginxinc/nginx-unprivileged:1.30.6-alpine3.24 AS runtime
# Parches de seguridad de alpine (Trivy encontró CVE-2026-111497 en brotli-libs).
# Hace falta root solo para instalar; después se vuelve al usuario 101.
USER root
RUN apk upgrade --no-cache
COPY nginx.conf /etc/nginx/nginx.conf
COPY --from=build /site/ /usr/share/nginx/html/
USER 101:101
EXPOSE 8080
CMD ["nginx", "-g", "daemon off;"]
