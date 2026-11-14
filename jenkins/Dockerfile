# Jenkins con todas las herramientas que usa el pipeline, en versiones fijas.
# Se construye y levanta con scripts/start-jenkins.sh.
FROM jenkins/jenkins:2.580.2-lts-jdk21

ARG TARGETARCH
ARG KUBECTL_VERSION=v1.35.1
ARG HELM_VERSION=v4.3.2
ARG TRIVY_VERSION=0.76.2
ARG SNYK_VERSION=v1.1308.4
ARG SEMGREP_VERSION=1.185.0

USER root

# Docker CLI (el daemon es el de la máquina, por el socket montado) y Python
# para Semgrep y para que Snyk pueda resolver las dependencias pip.
RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates curl gnupg python3 python3-venv \
    && install -m 0755 -d /etc/apt/keyrings \
    && curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/debian $(. /etc/os-release && echo $VERSION_CODENAME) stable" > /etc/apt/sources.list.d/docker.list \
    && apt-get update \
    && apt-get install -y --no-install-recommends docker-ce-cli docker-buildx-plugin \
    && rm -rf /var/lib/apt/lists/*

# kubectl y helm para desplegar en Minikube.
RUN curl -fsSL -o /usr/local/bin/kubectl "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/${TARGETARCH}/kubectl" \
    && chmod +x /usr/local/bin/kubectl \
    && curl -fsSL "https://get.helm.sh/helm-${HELM_VERSION}-linux-${TARGETARCH}.tar.gz" | tar -xz -C /tmp \
    && mv /tmp/linux-${TARGETARCH}/helm /usr/local/bin/helm && rm -rf /tmp/linux-*

# Trivy (imágenes) y Snyk (dependencias).
RUN case "${TARGETARCH}" in arm64) T=ARM64; S=snyk-linux-arm64 ;; *) T=64bit; S=snyk-linux ;; esac \
    && curl -fsSL "https://github.com/aquasecurity/trivy/releases/download/v${TRIVY_VERSION}/trivy_${TRIVY_VERSION}_Linux-${T}.tar.gz" | tar -xz -C /usr/local/bin trivy \
    && curl -fsSL -o /usr/local/bin/snyk "https://downloads.snyk.io/cli/${SNYK_VERSION}/${S}" \
    && chmod +x /usr/local/bin/snyk

# Semgrep en su propio venv.
RUN python3 -m venv /opt/semgrep \
    && /opt/semgrep/bin/pip install --no-cache-dir "semgrep==${SEMGREP_VERSION}" \
    && ln -s /opt/semgrep/bin/semgrep /usr/local/bin/semgrep

USER jenkins

# Plugins y configuración como código (JCasC): Jenkins arranca ya configurado,
# con el usuario admin, las credenciales y el job del pipeline.
COPY --chown=jenkins:jenkins plugins.txt /usr/share/jenkins/ref/plugins.txt
RUN jenkins-plugin-cli --plugin-file /usr/share/jenkins/ref/plugins.txt
COPY --chown=jenkins:jenkins casc.yaml /usr/share/jenkins/ref/casc.yaml
ENV CASC_JENKINS_CONFIG=/usr/share/jenkins/ref/casc.yaml \
    JAVA_OPTS="-Djenkins.install.runSetupWizard=false" \
    KUBECONFIG=/etc/kube/config
