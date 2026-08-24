{{/*
Gemeinsame Labels, die an JEDE Ressource angehaengt werden.
Aufruf:  {{ include "user-mgmt.labels" . }}
*/}}
{{- define "user-mgmt.labels" -}}
app.kubernetes.io/name: {{ .Chart.Name }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
helm.sh/chart: {{ .Chart.Name }}-{{ .Chart.Version }}
{{- end -}}

{{/*
Selektor-Label fuer eine einzelne Komponente.
Aufruf:  {{ include "user-mgmt.selectorLabels" "backend" }}  ->  app: backend
*/}}
{{- define "user-mgmt.selectorLabels" -}}
app: {{ . }}
{{- end -}}
