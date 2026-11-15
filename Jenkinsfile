// Pipeline CI/CD de El Último Renglón.
// Cada etapa deja su salida en reports/ y el pipeline se corta si aparece
// una vulnerabilidad CRITICAL (Snyk o Trivy), un hallazgo ERROR de Semgrep,
// un test que falla o un despliegue que no levanta.
pipeline {
    agent any

    options {
        timestamps()
        ansiColor('xterm')
        skipDefaultCheckout(true)
        disableConcurrentBuilds()
        buildDiscarder(logRotator(numToKeepStr: '15'))
    }

    parameters {
        booleanParam(
            name: 'SIMULAR_DEPENDENCIA_VULNERABLE',
            defaultValue: false,
            description: 'Agrega PyYAML 5.3 (CVE-2020-14343, crítica) para demostrar que el pipeline se detiene en Snyk'
        )
        choice(name: 'ENTORNO', choices: ['dev', 'prod'], description: 'Archivo de valores de Helm a usar')
    }

    environment {
        BACKEND_IMAGE  = "${env.DOCKERHUB_USER}/journal-backend"
        FRONTEND_IMAGE = "${env.DOCKERHUB_USER}/journal-frontend"
        NAMESPACE      = 'journal'
        RELEASE        = 'journal'
        TRIVY_CACHE    = "${env.JENKINS_HOME}/.cache/trivy"
        // En la primera corrida de un job nuevo Jenkins todavía no conoce los
        // parámetros (están en este archivo), así que se usa dev por defecto.
        HELM_ENV       = "${params.ENTORNO ?: 'dev'}"
    }

    stages {
        stage('1. Clonación del repositorio') {
            steps {
                checkout scm
                script {
                    env.GIT_SHORT = sh(script: 'git rev-parse --short HEAD', returnStdout: true).trim()
                    env.TAG = "${env.BUILD_NUMBER}-${env.GIT_SHORT}"
                }
                sh 'mkdir -p reports && git log -1 --format="Commit %h · %an · %s"'
                echo "Las imágenes de este build se etiquetan como ${env.TAG}"
            }
        }

        stage('2. Análisis estático (Semgrep)') {
            steps {
                sh '''
                    # Reporte completo: reglas propias + reglas oficiales de Python.
                    semgrep scan --metrics=off --config semgrep/rules.yaml --config p/python \
                        --exclude tests --text app/ 2>&1 | tee reports/semgrep-report.txt || true
                    # Corte: cualquier hallazgo de severidad ERROR detiene el pipeline.
                    semgrep scan --metrics=off --config semgrep/rules.yaml --config p/python \
                        --exclude tests --severity ERROR --error --quiet app/
                '''
            }
        }

        stage('3. Dependencias (Snyk)') {
            steps {
                withCredentials([string(credentialsId: 'snyk-token', variable: 'SNYK_TOKEN')]) {
                    sh '''
                        cp requirements.txt /tmp/requirements-snyk.txt
                        if [ "$SIMULAR_DEPENDENCIA_VULNERABLE" = "true" ]; then
                            echo ">> Simulación: se agrega PyYAML==5.3 (vulnerabilidad crítica conocida)"
                            echo "PyYAML==5.3" >> /tmp/requirements-snyk.txt
                        fi
                        # Snyk necesita las dependencias instaladas para armar el árbol.
                        python3 -m venv .snyk-venv
                        .snyk-venv/bin/pip install -q -r /tmp/requirements-snyk.txt
                        cp /tmp/requirements-snyk.txt requirements-snyk.txt
                        set +e
                        snyk test --file=requirements-snyk.txt --package-manager=pip \
                            --command=.snyk-venv/bin/python --skip-unresolved \
                            --severity-threshold=critical > reports/snyk-report.txt 2>&1
                        status=$?
                        set -e
                        cat reports/snyk-report.txt
                        rm -f requirements-snyk.txt
                        if [ $status -eq 1 ]; then
                            echo "PIPELINE DETENIDO: Snyk encontró vulnerabilidades CRÍTICAS en las dependencias"
                            exit 1
                        elif [ $status -gt 1 ]; then
                            echo "Snyk no pudo completar el análisis (código $status)"
                            exit $status
                        fi
                    '''
                }
            }
        }

        stage('4. Build y tests') {
            steps {
                sh '''
                    docker build --target test -t journal-backend:test-$TAG .
                    docker rm -f journal-test-$TAG 2>/dev/null || true
                    docker run --name journal-test-$TAG journal-backend:test-$TAG \
                        pytest -q --junitxml=/tmp/junit.xml
                '''
            }
            post {
                always {
                    sh 'docker cp journal-test-$TAG:/tmp/junit.xml reports/junit.xml || true; docker rm -f journal-test-$TAG || true'
                    junit allowEmptyResults: true, testResults: 'reports/junit.xml'
                }
            }
        }

        stage('5. Construcción de imágenes') {
            steps {
                sh '''
                    docker build --target runtime -t $BACKEND_IMAGE:$TAG .
                    docker build -t $FRONTEND_IMAGE:$TAG frontend/
                    docker images --format "{{.Repository}}:{{.Tag}}  {{.Size}}" | grep ":$TAG"
                '''
            }
        }

        stage('6. Escaneo de imágenes (Trivy)') {
            steps {
                sh '''
                    for image in $BACKEND_IMAGE:$TAG $FRONTEND_IMAGE:$TAG; do
                        name=$(basename ${image%%:*})
                        trivy image --cache-dir $TRIVY_CACHE --quiet --scanners vuln \
                            --severity LOW,MEDIUM,HIGH,CRITICAL --output reports/trivy-$name.txt $image
                        cat reports/trivy-$name.txt
                        # Corte: CRITICAL con parche disponible.
                        trivy image --cache-dir $TRIVY_CACHE --quiet --scanners vuln \
                            --severity CRITICAL --ignore-unfixed --exit-code 1 $image \
                          || { echo "PIPELINE DETENIDO: $image tiene vulnerabilidades CRÍTICAS"; exit 1; }
                    done
                '''
            }
        }

        stage('7. Publicación en Docker Hub') {
            steps {
                withCredentials([usernamePassword(credentialsId: 'dockerhub',
                                                  usernameVariable: 'HUB_USER',
                                                  passwordVariable: 'HUB_TOKEN')]) {
                    sh '''
                        echo "$HUB_TOKEN" | docker login -u "$HUB_USER" --password-stdin
                        docker push $BACKEND_IMAGE:$TAG
                        docker push $FRONTEND_IMAGE:$TAG
                        docker logout
                    '''
                }
            }
        }

        stage('8. Despliegue en Kubernetes (Helm)') {
            steps {
                sh '''
                    helm upgrade --install $RELEASE ./helm-chart \
                        --namespace $NAMESPACE --create-namespace \
                        -f helm-chart/values-$HELM_ENV.yaml \
                        --set backend.image.repository=$BACKEND_IMAGE \
                        --set frontend.image.repository=$FRONTEND_IMAGE \
                        --set backend.image.tag=$TAG \
                        --set frontend.image.tag=$TAG \
                        --wait --timeout 5m
                    kubectl get pods -n $NAMESPACE -o wide
                '''
            }
        }

        stage('9. Prueba de humo') {
            steps {
                sh 'helm test $RELEASE -n $NAMESPACE --logs'
            }
        }
    }

    post {
        always {
            archiveArtifacts artifacts: 'reports/**', allowEmptyArchive: true
            sh 'docker image prune -f >/dev/null 2>&1 || true'
        }
        success {
            echo "Despliegue OK: ${env.BACKEND_IMAGE}:${env.TAG} y ${env.FRONTEND_IMAGE}:${env.TAG} corriendo en ${env.NAMESPACE}"
        }
        failure {
            echo 'PIPELINE DETENIDO. La etapa que falló aparece en rojo en la vista del pipeline; los reportes quedaron archivados.'
        }
    }
}
