# Kubernetes Configuration for AKS

Production Kubernetes manifests for the Django + React application on Azure Kubernetes Service.

---

## Folder structure

```
k8s/
├── namespace.yaml          # Creates the "production" namespace
├── configmap.yaml          # Non-sensitive environment variables
├── secrets.yaml            # Placeholder template for sensitive values
├── ingress.yaml            # Single public entry point (nginx ingress controller)
│
├── backend/
│   ├── deployment.yaml     # Django/Gunicorn — 2 replicas
│   ├── service.yaml        # ClusterIP — internal only, port 8000
│   └── hpa.yaml            # Auto-scales 2–10 pods on CPU/memory
│
├── frontend/
│   ├── deployment.yaml     # nginx serving React static files — 2 replicas
│   ├── service.yaml        # ClusterIP — internal only, port 80
│   └── hpa.yaml            # Auto-scales 2–10 pods on CPU/memory
│
├── db/
│   ├── pvc.yaml            # 20Gi Azure Managed Disk for PostgreSQL data
│   ├── deployment.yaml     # PostgreSQL 16 — 1 replica (see note below)
│   ├── service.yaml        # ClusterIP — internal only, port 5432
│   └── hpa.yaml            # Locked to 1 replica (PostgreSQL cannot scale horizontally)
│
└── redis/
    ├── deployment.yaml     # Redis 7 — 1 replica (see note below)
    ├── service.yaml        # ClusterIP — internal only, port 6379
    └── hpa.yaml            # Locked to 1 replica (standalone Redis cannot scale horizontally)
```

**Note on db and redis:** For production workloads, replace these with managed Azure services:
- Azure Database for PostgreSQL (Flexible Server) → delete `k8s/db/`, update `DATABASE_URL`
- Azure Cache for Redis → delete `k8s/redis/`, update `REDIS_URL`

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

**2. Metrics Server** (required for HPA to function)
```bash
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
# Verify:
kubectl top nodes
```

**3. ACR pull secret** (required for pods to pull images from your ACR)
```bash
kubectl create secret docker-registry acr-secret \
  --docker-server=<ACR_NAME>.azurecr.io \
  --docker-username=<SERVICE_PRINCIPAL_CLIENT_ID> \
  --docker-password=<SERVICE_PRINCIPAL_CLIENT_SECRET> \
  -n production
```
Alternatively, assign the `AcrPull` role to the AKS kubelet managed identity — then remove `imagePullSecrets` from the deployments entirely (cleaner for AKS).

---

## How to replace secrets before first deploy

`k8s/secrets.yaml` contains `<REPLACE_ME>` placeholders. **Never apply it with placeholders.**

**Step 1: Generate your values**
```bash
# Django secret key
python -c "from django.core.management.utils import get_random_secret_key; print(get_random_secret_key())"

# PostgreSQL password
openssl rand -base64 32

# Build your DATABASE_URL
# Format: postgres://<user>:<password>@db:5432/<dbname>
# Example: postgres://postgres:s3cr3tpassword@db:5432/myapp_prod
```

**Step 2: Base64-encode each value**
```bash
echo -n "your-actual-value" | base64
# Use -n to avoid encoding a trailing newline — it will break the connection string.
```

**Step 3: Replace placeholders in secrets.yaml**
Open `k8s/secrets.yaml` and replace each `<REPLACE_ME>` with the base64-encoded value.

**Step 4: Apply the secret (do not commit the file with real values)**
```bash
kubectl apply -f k8s/secrets.yaml
```

**Step 5: Immediately delete the file from your local disk or restore the placeholder version**
```bash
git checkout k8s/secrets.yaml  # Restore the placeholder version
```

For production, manage secrets via Azure Key Vault + Secrets Store CSI Driver instead of this file.
See: https://learn.microsoft.com/en-us/azure/aks/csi-secrets-store-driver

---

## How to apply everything (first deploy)

Apply in this order to satisfy dependencies:

```bash
# 1. Namespace first — everything else lives inside it
kubectl apply -f k8s/namespace.yaml

# 2. Shared config and secrets
kubectl apply -f k8s/configmap.yaml
kubectl apply -f k8s/secrets.yaml     # Ensure <REPLACE_ME> is replaced first

# 3. Storage (must exist before the db Deployment mounts it)
kubectl apply -f k8s/db/pvc.yaml

# 4. All remaining manifests
kubectl apply -f k8s/ --recursive

# 5. Verify everything is running
kubectl get all -n production
```

**After the first deploy, the CI/CD pipeline handles all subsequent deploys automatically.**

---

## Required GitHub secrets

Go to: GitHub repository → Settings → Secrets and variables → Actions → New repository secret

| Secret name | Where to find it | Example |
|---|---|---|
| `AZURE_CLIENT_ID` | Azure AD → App registrations → your app → Application (client) ID | `a1b2c3d4-...` |
| `AZURE_TENANT_ID` | Azure AD → Overview → Directory (tenant) ID | `e5f6g7h8-...` |
| `AZURE_SUBSCRIPTION_ID` | Azure portal → Subscriptions | `i9j0k1l2-...` |
| `ACR_NAME` | Azure Container Registry → name (without .azurecr.io) | `myappregistry` |
| `AKS_CLUSTER_NAME` | AKS → your cluster name | `myapp-aks-prod` |
| `AKS_RESOURCE_GROUP` | AKS → resource group name | `myapp-rg-prod` |

**OIDC federated credential setup** (required for `azure/login@v2` to work):

1. Go to Azure AD → App registrations → your app → Certificates & secrets → Federated credentials
2. Add a credential:
   - Federated credential scenario: GitHub Actions deploying Azure resources
   - Organization: your GitHub org or username
   - Repository: your repository name
   - Entity: Branch
   - Branch: main
3. Grant the app the following roles:
   - `AcrPush` on your Azure Container Registry
   - `Azure Kubernetes Service Cluster User Role` on your AKS cluster
   - `Azure Kubernetes Service RBAC Writer` on the `production` namespace (or cluster-level `Contributor` for simplicity)

---

## How to debug

### Check pod status
```bash
# List all pods and their status
kubectl get pods -n production

# Watch pod status in real time
kubectl get pods -n production -w

# Show events (useful for "Pending" or "CrashLoopBackOff" pods)
kubectl describe pod <pod-name> -n production
```

### Read logs
```bash
# Logs from a specific pod
kubectl logs <pod-name> -n production

# Logs from all pods of a deployment (most useful)
kubectl logs -l app=backend -n production --tail=100

# Follow logs in real time
kubectl logs -l app=backend -n production -f

# Previous container logs (useful after a crash/restart)
kubectl logs <pod-name> -n production --previous
```

### Inspect a failing deployment
```bash
# Check rollout status (shows if pods are progressing or stuck)
kubectl rollout status deployment/backend -n production

# Describe the deployment (shows replica counts, conditions, events)
kubectl describe deployment backend -n production

# Check recent events in the namespace (catches image pull errors, OOMKills, etc.)
kubectl get events -n production --sort-by='.lastTimestamp' | tail -30
```

### Check HPA status
```bash
# Show current vs target metrics and replica counts
kubectl get hpa -n production

# Detailed HPA info including scaling events and conditions
kubectl describe hpa backend-hpa -n production

# "unknown" in TARGETS means Metrics Server is not running — see Prerequisites above
```

### Roll back a bad deploy
```bash
# Option 1: Roll back to the previous Deployment revision
kubectl rollout undo deployment/backend -n production
kubectl rollout undo deployment/frontend -n production

# Option 2: Roll back to a specific git SHA (preferred — precise)
kubectl set image deployment/backend \
  backend=<ACR_NAME>.azurecr.io/backend:<PREVIOUS_SHA> \
  -n production

# Verify rollback
kubectl rollout status deployment/backend -n production
```

### Get a shell inside a running pod
```bash
# Open a shell in a backend pod (useful for running manage.py commands)
kubectl exec -it <pod-name> -n production -- /bin/sh

# Run a one-off management command without opening a shell
kubectl exec -it <pod-name> -n production -- python manage.py shell
kubectl exec -it <pod-name> -n production -- python manage.py migrate --plan
```

### Check resource usage
```bash
# CPU and memory per pod (requires Metrics Server)
kubectl top pods -n production

# CPU and memory per node
kubectl top nodes
```
