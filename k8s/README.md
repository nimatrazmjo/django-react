# Kubernetes Configuration for AKS

Production-ready Kubernetes manifests for the Django + React application, structured with Kustomize for multi-environment support (QA, Staging, Production) with zero file duplication.

---

## Folder structure

```
k8s/
├── base/                          # Single source of truth — shared across all environments
│   ├── kustomization.yaml         # Lists every resource file in this base layer
│   ├── namespace.yaml             # Namespace template (name is overridden per overlay)
│   ├── configmap.yaml             # Non-sensitive env vars
│   ├── secrets.yaml               # Secret placeholder template
│   ├── ingress.yaml               # nginx ingress: /api/* → backend, /* → frontend
│   ├── backend/
│   │   ├── deployment.yaml        # Django/Gunicorn — probes on /api/health/
│   │   ├── service.yaml           # ClusterIP, port 8000
│   │   └── hpa.yaml               # CPU + memory autoscaling
│   ├── frontend/
│   │   ├── deployment.yaml        # nginx serving React static files — probes on /health
│   │   ├── service.yaml           # ClusterIP, port 80
│   │   └── hpa.yaml
│   ├── db/
│   │   ├── pvc.yaml               # 20Gi Azure Premium SSD
│   │   ├── deployment.yaml        # postgres:16-alpine, 1 replica (Recreate strategy)
│   │   ├── service.yaml           # ClusterIP, port 5432
│   │   └── hpa.yaml               # Locked to 1 replica
│   └── redis/
│       ├── deployment.yaml        # redis:7-alpine, 1 replica, maxmemory 400mb
│       ├── service.yaml           # ClusterIP, port 6379
│       └── hpa.yaml               # Locked to 1 replica
│
└── overlays/
    ├── qa/
    │   ├── kustomization.yaml     # Patches: namespace=qa, 1 replica, small resources
    │   └── values.yaml            # Human-readable QA profile (documentation)
    ├── staging/
    │   ├── kustomization.yaml     # Patches: namespace=staging, 2 replicas, medium resources
    │   └── values.yaml            # Human-readable staging profile
    └── production/
        ├── kustomization.yaml     # Patches: namespace=production, 2 replicas, full resources
        └── values.yaml            # Human-readable production profile
```

**How Kustomize works here in one sentence:** each overlay's `kustomization.yaml` points to `../../base`, inherits all 17 resource files, and then patches only the fields that differ — replica counts, CPU/memory, HPA thresholds, and namespace name. Nothing is copied or duplicated.

---

## Environment profiles at a glance

| Setting | QA | Staging | Production |
|---|---|---|---|
| Namespace | `qa` | `staging` | `production` |
| Branch | `qa` | `staging` | `main` |
| Replicas (backend/frontend) | 1 | 2 | 2 |
| CPU request | 100m | 200m | 250m |
| CPU limit | 200m | 400m | 500m |
| Memory request | 128Mi | 200Mi | 256Mi |
| Memory limit | 256Mi | 400Mi | 512Mi |
| HPA min replicas | 1 | 2 | 2 |
| HPA max replicas | 3 | 6 | 10 |
| HPA CPU target | 70% | 65% | 60% |
| HPA memory target | 80% | 75% | 70% |
| Redis maxmemory | 200mb | 320mb | 400mb |
| Image tag prefix | `qa-` | `staging-` | _(none)_ |

**QA:** single pod, minimal resources, high HPA thresholds. Cost over stability.
**Staging:** mirrors production pod count (2), medium resources. Validates rolling update behaviour.
**Production:** full resources, aggressive HPA thresholds, tightest scale-up triggers.

---

## How to deploy to a specific environment

Kustomize is built into `kubectl` — no extra tools needed.

```bash
# Deploy to QA
kubectl apply -k k8s/overlays/qa

# Deploy to staging
kubectl apply -k k8s/overlays/staging

# Deploy to production (prefer CI/CD — this is for emergencies)
kubectl apply -k k8s/overlays/production
```

**Preview the final rendered manifests without applying them:**
```bash
kubectl kustomize k8s/overlays/qa
kubectl kustomize k8s/overlays/staging
kubectl kustomize k8s/overlays/production
```
Use this to verify your overlay patches look correct before touching a live cluster.

---

## How to check which environment you are looking at

```bash
# List pods in each environment
kubectl get pods -n qa
kubectl get pods -n staging
kubectl get pods -n production

# Confirm resource sizes and replica counts
kubectl describe deployment backend -n qa
kubectl describe deployment backend -n staging
kubectl describe deployment backend -n production

# Check HPA state and current targets
kubectl get hpa -n qa
kubectl get hpa -n staging
kubectl get hpa -n production
```

---

## Prerequisites

Before applying anything, ensure the following are installed and configured in your AKS cluster:

**1. nginx ingress controller**
```bash
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo update
helm install ingress-nginx ingress-nginx/ingress-nginx \
  --namespace ingress-nginx --create-namespace
```

**2. Metrics Server** (required for HPA to report targets — shows "unknown" without it)
```bash
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
kubectl top nodes   # should return node CPU/memory after ~60 seconds
```

**3. ACR pull secret** (one per namespace — repeat for each env)
```bash
for NS in qa staging production; do
  kubectl create secret docker-registry acr-secret \
    --docker-server=<ACR_NAME>.azurecr.io \
    --docker-username=<SP_CLIENT_ID> \
    --docker-password=<SP_CLIENT_SECRET> \
    -n $NS
done
```
Alternatively, assign the `AcrPull` role to the AKS kubelet managed identity — then remove `imagePullSecrets` from base deployment files entirely (preferred for AKS).

---

## How to replace secrets before first deploy

`k8s/base/secrets.yaml` contains `<REPLACE_ME>` placeholders. Never apply it with placeholders.

**Step 1: Generate your values**
```bash
# Django secret key
python -c "from django.core.management.utils import get_random_secret_key; print(get_random_secret_key())"

# PostgreSQL password
openssl rand -base64 32
```

**Step 2: Base64-encode each value** (use `-n` to avoid encoding a trailing newline)
```bash
echo -n "your-actual-value" | base64
```

**Step 3: Replace each `<REPLACE_ME>` in secrets.yaml**

**Step 4: Apply, then restore the placeholder version immediately**
```bash
kubectl apply -f k8s/base/secrets.yaml -n qa
kubectl apply -f k8s/base/secrets.yaml -n staging
kubectl apply -f k8s/base/secrets.yaml -n production
git checkout k8s/base/secrets.yaml   # Do not commit real values
```

For production-grade secret management, use Azure Key Vault with the Secrets Store CSI Driver:
https://learn.microsoft.com/en-us/azure/aks/csi-secrets-store-driver

---

## How to apply everything for the first time

```bash
# 1. Apply the overlay — this creates the namespace and all resources in one shot.
#    Kustomize handles ordering; namespace is created before namespace-scoped resources.
kubectl apply -k k8s/overlays/qa
kubectl apply -k k8s/overlays/staging
kubectl apply -k k8s/overlays/production

# 2. Apply secrets (after replacing placeholders — see above)
#    The overlay applies the base secrets.yaml into the correct namespace,
#    but you still need to fill in the real values per namespace.
kubectl create secret generic app-secrets \
  --from-literal=DJANGO_SECRET_KEY="<real-value>" \
  --from-literal=DATABASE_URL="<real-value>" \
  --from-literal=REDIS_URL="<real-value>" \
  --from-literal=POSTGRES_USER="<real-value>" \
  --from-literal=POSTGRES_PASSWORD="<real-value>" \
  --from-literal=POSTGRES_DB="<real-value>" \
  -n production --dry-run=client -o yaml | kubectl apply -f -
# Repeat for -n staging and -n qa with their own values.

# 3. Verify everything is running
kubectl get all -n qa
kubectl get all -n staging
kubectl get all -n production
```

---

## Required GitHub secrets

Go to: GitHub → Settings → Secrets and variables → Actions → New repository secret

| Secret | Where to find it |
|---|---|
| `AZURE_CLIENT_ID` | Azure AD → App registrations → your app → Application (client) ID |
| `AZURE_TENANT_ID` | Azure AD → Overview → Directory (tenant) ID |
| `AZURE_SUBSCRIPTION_ID` | Azure portal → Subscriptions |
| `ACR_NAME` | ACR registry name without `.azurecr.io` (e.g. `myapp`) |
| `AKS_CLUSTER_NAME` | AKS cluster name |
| `AKS_RESOURCE_GROUP` | Resource group containing the AKS cluster |

**OIDC federated credential setup** — required for `azure/login@v2`:
1. Azure AD → App registrations → your app → Certificates & secrets → Federated credentials
2. Add one credential per branch (main, staging, qa), selecting Entity: Branch
3. Grant the app: `AcrPush` on ACR, `Azure Kubernetes Service Cluster User Role` + `RBAC Writer` on AKS

---

## Debugging

### Pod status and events
```bash
# List all pods and their status
kubectl get pods -n production

# Watch pods in real time (Ctrl+C to stop)
kubectl get pods -n production -w

# Show events for a failing pod (catches ImagePullBackOff, OOMKilled, etc.)
kubectl describe pod <pod-name> -n production

# Show all recent events in a namespace
kubectl get events -n production --sort-by='.lastTimestamp' | tail -30
```

### Logs
```bash
# Logs from all pods of a deployment
kubectl logs -l app=backend -n production --tail=100

# Follow logs in real time
kubectl logs -l app=backend -n production -f

# Logs from the previous container after a crash
kubectl logs <pod-name> -n production --previous
```

### Deployment health
```bash
# Check rollout progress
kubectl rollout status deployment/backend -n production

# Describe deployment (shows replica counts, conditions, and events)
kubectl describe deployment backend -n production

# Verify Kustomize overlay before applying
kubectl kustomize k8s/overlays/production
```

### HPA status
```bash
# Shows TARGETS (current/desired), MINPODS, MAXPODS, REPLICAS
kubectl get hpa -n production

# Full details including scaling events and conditions
kubectl describe hpa backend-hpa -n production
# "unknown" in TARGETS → Metrics Server not installed or pods have no resource requests
```

### Roll back a bad deploy
```bash
# Option 1: Roll back to the previous Deployment revision (fastest)
kubectl rollout undo deployment/backend -n production
kubectl rollout undo deployment/frontend -n production

# Option 2: Roll back to a specific git SHA (more precise)
kubectl set image deployment/backend \
  backend=<ACR_NAME>.azurecr.io/backend:<PREVIOUS_SHA> \
  -n production

# Confirm rollback
kubectl rollout status deployment/backend -n production
```

### Shell into a running pod
```bash
# Open an interactive shell
kubectl exec -it <pod-name> -n production -- /bin/sh

# Run a one-off Django management command
kubectl exec -it <pod-name> -n production -- python manage.py migrate --plan
```

### Resource usage
```bash
kubectl top pods -n production   # CPU + memory per pod (needs Metrics Server)
kubectl top nodes                # CPU + memory per node
```
