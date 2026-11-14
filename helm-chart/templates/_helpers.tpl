{{/* Nombre base de los recursos: <release>-journal, o solo "journal" si el release ya se llama así. */}}
{{- define "journal.fullname" -}}
{{- if contains .Chart.Name .Release.Name -}}
{{- .Release.Name | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- printf "%s-%s" .Release.Name .Chart.Name | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}

{{/* Labels comunes recomendados por Kubernetes. */}}
{{- define "journal.labels" -}}
app.kubernetes.io/name: {{ .Chart.Name }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version }}
{{- end -}}

{{/* Labels que identifican a un componente (los usa el selector del Service). Uso: include "journal.selectorLabels" (list . "backend") */}}
{{- define "journal.selectorLabels" -}}
{{- $root := index . 0 -}}
app.kubernetes.io/name: {{ $root.Chart.Name }}
app.kubernetes.io/instance: {{ $root.Release.Name }}
app.kubernetes.io/component: {{ index . 1 }}
{{- end -}}

{{/* Imagen con etiqueta explícita: nunca se permite "latest". */}}
{{- define "journal.image" -}}
{{- if or (not .tag) (eq (toString .tag) "latest") -}}
{{- fail "La imagen necesita una etiqueta fija distinta de latest" -}}
{{- end -}}
{{- printf "%s:%s" .repository (toString .tag) -}}
{{- end -}}
