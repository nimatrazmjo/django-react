{{/*
_helpers.tpl — Named templates (partials) reused across all chart templates.

Usage: {{ include "django-react.fullname" . }}
       {{ include "django-react.image" (dict "image" .Values.backend.image "global" .Values.global) }}
       {{ include "django-react.labels" . }}
*/}}

{{/*
Expand the chart name.
*/}}
{{- define "django-react.name" -}}
{{- .Chart.Name | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because Kubernetes label values must be <= 63 characters.
*/}}
{{- define "django-react.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default .Chart.Name .Values.nameOverride }}
{{- if contains $name .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "django-react.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels applied to all resources.
These appear on every resource so you can select/filter by release, chart, or version.
*/}}
{{- define "django-react.labels" -}}
helm.sh/chart: {{ include "django-react.chart" . }}
{{ include "django-react.selectorLabels" . }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/part-of: django-react
environment: {{ .Values.global.environment | default "production" }}
{{- end }}

{{/*
Selector labels — the minimal set used in podSelector / selector.matchLabels.
Keep this minimal: changing selector labels on an existing Deployment requires delete+recreate.
*/}}
{{- define "django-react.selectorLabels" -}}
app.kubernetes.io/name: {{ include "django-react.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Build a fully-qualified image reference: registry/repository:tag
Works for any component. Pass as:
  {{ include "django-react.image" (dict "image" .Values.backend.image "global" .Values.global) }}
*/}}
{{- define "django-react.image" -}}
{{- $registry := .global.image.registry | default "" -}}
{{- $repository := .image.repository -}}
{{- $tag := .image.tag | default "latest" -}}
{{- if $registry -}}
{{- printf "%s/%s:%s" $registry $repository $tag -}}
{{- else -}}
{{- printf "%s:%s" $repository $tag -}}
{{- end -}}
{{- end }}

{{/*
imagePullSecrets block — rendered when global.image.pullSecrets is non-empty.
*/}}
{{- define "django-react.imagePullSecrets" -}}
{{- with .Values.global.image.pullSecrets }}
imagePullSecrets:
  {{- toYaml . | nindent 2 }}
{{- end }}
{{- end }}

{{/*
Standard probes block for a container.
Pass: (dict "probes" .Values.backend.probes "port" 8000)
*/}}
{{- define "django-react.probes" -}}
readinessProbe:
  httpGet:
    path: {{ .probes.readiness.path }}
    port: {{ .port }}
  initialDelaySeconds: {{ .probes.readiness.initialDelaySeconds }}
  periodSeconds: {{ .probes.readiness.periodSeconds }}
  failureThreshold: {{ .probes.readiness.failureThreshold }}
  timeoutSeconds: {{ .probes.readiness.timeoutSeconds }}
livenessProbe:
  httpGet:
    path: {{ .probes.liveness.path }}
    port: {{ .port }}
  initialDelaySeconds: {{ .probes.liveness.initialDelaySeconds }}
  periodSeconds: {{ .probes.liveness.periodSeconds }}
  failureThreshold: {{ .probes.liveness.failureThreshold }}
  timeoutSeconds: {{ .probes.liveness.timeoutSeconds }}
{{- end }}

{{/*
TopologySpreadConstraints for multi-AZ pod distribution.
Spread backend and frontend pods across nodes and AZs to prevent all replicas
from landing on a single node or single AZ.
*/}}
{{- define "django-react.topologySpread" -}}
{{- if .enabled }}
topologySpreadConstraints:
  # Spread pods across availability zones
  - maxSkew: 1
    topologyKey: topology.kubernetes.io/zone
    whenUnsatisfiable: DoNotSchedule    # Hard requirement: fail scheduling rather than stack in one AZ
    labelSelector:
      matchLabels:
        app: {{ .appLabel }}
  # Also spread across nodes within each AZ
  - maxSkew: 1
    topologyKey: kubernetes.io/hostname
    whenUnsatisfiable: ScheduleAnyway   # Best-effort: allow on same node if no alternative
    labelSelector:
      matchLabels:
        app: {{ .appLabel }}
{{- end }}
{{- end }}

{{/*
Security context for application pods (non-root, read-only root filesystem).
*/}}
{{- define "django-react.securityContext" -}}
securityContext:
  runAsNonRoot: true
  runAsUser: 1000
  runAsGroup: 1000
  fsGroup: 1000
  seccompProfile:
    type: RuntimeDefault
{{- end }}

{{/*
Container security context — drop all capabilities, read-only root.
*/}}
{{- define "django-react.containerSecurityContext" -}}
securityContext:
  allowPrivilegeEscalation: false
  readOnlyRootFilesystem: false   # Set to true for frontend nginx; backend needs writes for tmp files
  runAsNonRoot: true
  runAsUser: 1000
  capabilities:
    drop:
      - ALL
{{- end }}
