{{- define "mazevault-customer.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "mazevault-customer.fullname" -}}
{{- if .Values.fullnameOverride -}}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- printf "%s" .Release.Name | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}

{{- define "mazevault-customer.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "mazevault-customer.namespace" -}}
{{- default .Release.Namespace .Values.global.namespace -}}
{{- end -}}

{{- define "mazevault-customer.serviceAccountName" -}}
{{- if .Values.global.serviceAccount.name -}}
{{- .Values.global.serviceAccount.name -}}
{{- else -}}
{{- printf "%s-sa" (include "mazevault-customer.fullname" .) | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}

{{- define "mazevault-customer.secretStoreName" -}}
{{- if .Values.global.keyVault.secretStore.name -}}
{{- .Values.global.keyVault.secretStore.name -}}
{{- else -}}
{{- printf "%s-kv" (include "mazevault-customer.fullname" .) | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}

{{- define "mazevault-customer.runtimeSecretName" -}}
{{- if .Values.global.keyVault.targetSecretName -}}
{{- .Values.global.keyVault.targetSecretName -}}
{{- else -}}
{{- printf "%s-runtime" (include "mazevault-customer.fullname" .) | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}

{{- define "mazevault-customer.componentName" -}}
{{- printf "%s-%s" (include "mazevault-customer.fullname" .root) .component | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "mazevault-customer.componentSelectorLabels" -}}
app.kubernetes.io/name: {{ include "mazevault-customer.name" .root }}
app.kubernetes.io/instance: {{ .root.Release.Name }}
app.kubernetes.io/component: {{ .component }}
{{- end -}}

{{- define "mazevault-customer.componentLabels" -}}
helm.sh/chart: {{ include "mazevault-customer.chart" .root }}
{{ include "mazevault-customer.componentSelectorLabels" . }}
app.kubernetes.io/managed-by: {{ .root.Release.Service }}
{{- with .root.Values.global.commonLabels }}
{{ toYaml . }}
{{- end }}
{{- end -}}