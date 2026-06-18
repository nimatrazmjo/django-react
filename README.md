# Django + React

Full-stack web application with a Domain-Driven Design backend and a React/TypeScript frontend, fully containerised with Docker. Kubernetes manifests and a production Helm chart are included for cluster deployment.

---

## Tech stack

| Layer | Technology |
|---|---|
| Backend API | Python 3.12, Django 5, Django REST Framework |
| Frontend | React 18, TypeScript, Vite 5 |
| Database | PostgreSQL 16 |
| Cache | Redis 7 |
| Web server (prod) | nginx 1.25 |
| Containerisation | Docker, Docker Compose |
| Orchestration | Kubernetes + Helm 3 |

---

## Architecture

The backend follows **Hexagonal Architecture / Domain-Driven Design** with four strict layers. The dependency arrow points inward only — the domain never imports from any outer layer.

```
interfaces  →  application  →  domain
                    ↑
             infrastructure
```

| Layer | Location | Responsibility |
|---|---|---|
| Domain | `backend/domain/` | Business rules, entities, value objects, abstract ports. Zero framework dependencies. |
| Application | `backend/application/` | Use cases (`execute()` pattern). Orchestrates domain objects. No Django. |
| Infrastructure | `backend/infrastructure/` | Concrete adapters: PostgreSQL, Redis. Django ORM models live here only. |
| Interfaces | `backend/interfaces/` | DRF views, serializers, URL routing. HTTP boundary. |

---

## Project structure

```
.
├── backend/
│   ├── domain/               # Business rules — pure Python
│   │   ├── shared/           # Base Entity, ValueObject, exceptions
│   │   └── health/           # Health bounded context
│   ├── application/          # Use cases and DTOs
│   ├── infrastructure/       # Django/Redis adapters and ORM models
│   │   └── persistence/      # All Django models live here
│   ├── interfaces/api/       # DRF views, serializers, urls
│   ├── config/               # Django settings (split by environment)
│   │   └── settings/         # dev.py / staging.py / prod.py
│   └── scripts/              # Dev tooling (layer import validator)
├── frontend/
│   └── src/
├── k8s/
│   ├── base/                 # Kustomize base: deployments, services, RBAC, NetworkPolicies, PDBs
│   ├── cert-manager/         # Let's Encrypt ClusterIssuers
│   ├── helm/django-react/    # Production Helm chart
│   └── overlays/             # Per-environment Kustomize overrides (local/qa/staging/production)
├── nginx/                    # nginx config for prod/staging
├── docker-compose.yml        # Dev (hot reload)
├── docker-compose.staging.yml
└── docker-compose.prod.yml
```

---

## Getting started locally

### Prerequisites

- [Docker Desktop](https://docs.docker.com/get-docker/) (includes Compose v2) — or Docker Engine + the `docker compose` plugin
- Ports **5173** and **8000** free on your machine

Verify before starting:

```bash
docker --version        # Docker version 24+ recommended
docker compose version  # v2.x required (not legacy docker-compose)
lsof -i :5173 -i :8000  # should return nothing
```

### 1. Clone and enter the project

```bash
git clone <repo-url>
cd django-react
```

### 2. Environment variables

`.env.dev` is pre-configured and works out of the box — no changes needed for local development:

```
DATABASE_URL=postgres://postgres:postgres@db:5432/myapp_dev
REDIS_URL=redis://redis:6379/0
CORS_ALLOWED_ORIGINS=http://localhost:5173
```

Never edit `.env.staging` or `.env.prod` locally. Those are injected by CI at deploy time.

### 3. Start all services

```bash
docker compose up --build
```

This builds four containers and starts them in order:

1. **db** (PostgreSQL) — health-checked before anything else starts
2. **redis** — health-checked before the backend starts
3. **backend** — waits for DB, runs `migrate --noinput`, then starts the Django dev server
4. **frontend** — starts the Vite dev server with HMR

First run takes ~2 minutes (pulling base images, installing deps). Subsequent starts are under 10 seconds.

### 4. Confirm everything is healthy

```bash
# In a second terminal — check all four containers are Up (not Restarting)
docker compose ps

# Quick health check
curl http://localhost:8000/api/health/
```

Expected response:

```json
{
  "status": "ok",
  "services": [
    { "name": "db", "status": "ok" },
    { "name": "cache", "status": "ok" }
  ]
}
```

| Service | URL |
|---|---|
| Frontend (Vite HMR) | http://localhost:5173 |
| Backend health | http://localhost:8000/api/health/ |
| Backend ping | http://localhost:8000/api/ping/ |

### 5. Stopping and resetting

```bash
# Stop containers (preserves DB data)
docker compose down

# Stop and wipe the database volume (full reset)
docker compose down -v

# Rebuild a single service after a Dockerfile change
docker compose up --build backend
```

---

## Development workflow

### Backend

```bash
# Django management commands run inside the container
docker compose exec backend python manage.py makemigrations
docker compose exec backend python manage.py migrate
docker compose exec backend python manage.py createsuperuser
docker compose exec backend python manage.py shell

# Run tests
docker compose exec backend pytest

# Validate DDD layer imports (catches architectural violations before commit)
docker compose exec backend python scripts/check_layer_imports.py --all
```

The layer import validator also runs automatically after every file edit via the Claude Code `PostToolUse` hook in `.claude/settings.json`.

### Frontend

The Vite dev server with hot module replacement is already running inside the `frontend` container. Most of the time you just edit files and the browser updates instantly.

If you need to run npm commands directly (outside Docker):

```bash
cd frontend
npm install
npm run dev      # starts on :5173
npm run build    # production build → dist/
npm run lint
```

### Watching logs

```bash
# All services
docker compose logs -f

# Single service
docker compose logs -f backend
docker compose logs -f frontend
```

### Rebuilding after dependency changes

```bash
# After editing backend/requirements.txt
docker compose up --build backend

# After editing frontend/package.json
docker compose up --build frontend
```

---

## Troubleshooting

**Port already in use**

```bash
# Find what's using port 8000
lsof -i :8000
# Kill it or change the port in docker-compose.yml
```

**Backend stuck on "Waiting for database..."**

The backend loops until PostgreSQL passes its health check. If it spins for more than 30 seconds:

```bash
docker compose logs db         # look for startup errors
docker compose restart db      # restart Postgres and let backend retry
```

**Migrations failed on startup**

```bash
docker compose logs backend    # read the traceback
docker compose exec backend python manage.py migrate  # re-run manually
```

**Frontend shows blank page or Vite proxy errors**

```bash
docker compose logs frontend   # check for build errors
# Vite proxies /api/* to localhost:8000 — confirm the backend is up first
curl http://localhost:8000/api/ping/
```

**"relation does not exist" errors**

The database volume exists but migrations haven't run. Run them manually:

```bash
docker compose exec backend python manage.py migrate
```

**Full reset** (when all else fails)

```bash
docker compose down -v --remove-orphans
docker compose up --build
```

---

## Adding a new feature (bounded context)

1. **Domain** — `backend/domain/<context>/entities.py`, `services.py`, `exceptions.py`
2. **Application** — `backend/application/<context>/dtos.py`, `queries.py`, `commands.py`
3. **Infrastructure** — `backend/infrastructure/<context>/adapters.py` + models in `infrastructure/persistence/`
4. **Interface** — `backend/interfaces/api/<context>/views.py`, `serializers.py`, `urls.py`
5. Wire the new URL file into `backend/config/urls.py`
6. Run `makemigrations` if you added models

Each layer has its own `CLAUDE.md` with precise import rules. The hook enforces these automatically on every edit.

---

## Environment variables

All env files share the same keys — only values differ per environment.

| Variable | Description | Dev default |
|---|---|---|
| `DJANGO_SETTINGS_MODULE` | Settings file to load | `config.settings.dev` |
| `DJANGO_SECRET_KEY` | Django signing key — never commit real values | `dev-secret-key-not-for-production` |
| `DATABASE_URL` | PostgreSQL connection string | `postgres://postgres:postgres@db:5432/myapp_dev` |
| `REDIS_URL` | Redis connection string | `redis://redis:6379/0` |
| `CORS_ALLOWED_ORIGINS` | Allowed frontend origins | `http://localhost:5173` |
| `VITE_API_URL` | Backend origin for the Vite proxy | `http://localhost:8000` |
| `VITE_ENV` | Frontend environment label | `development` |

---

## API reference

| Method | Path | Description |
|---|---|---|
| `GET` | `/api/health/` | Checks DB and Redis connectivity |
| `GET` | `/api/ping/` | Always returns `{ "message": "pong" }` |

---

## Layer import rules (enforced)

The `backend/scripts/check_layer_imports.py` validator runs after every file edit (Claude Code hook) and on CI:

| Layer | May import from |
|---|---|
| `domain/` | stdlib only |
| `application/` | `domain/`, stdlib |
| `infrastructure/` | `domain/`, Django, third-party libs |
| `interfaces/` | `application/`, `infrastructure/`, `domain/`, DRF |

Cross-context interface imports are blocked — `interfaces/api/orders/` cannot import from `interfaces/api/users/`. Data flows through the application layer.

```bash
# Run manually at any time
python3 backend/scripts/check_layer_imports.py --all
```

---

## Running Kubernetes locally

Testing the full Kubernetes stack on your laptop before pushing to AKS. Two cluster options — pick one.

### Option A: Docker Desktop (simplest)

Docker Desktop ships a single-node Kubernetes cluster. You already have it if you're using Docker Desktop.

**Enable it:** Docker Desktop → Settings → Kubernetes → Enable Kubernetes → Apply & Restart. Wait for the green "Kubernetes running" indicator (~60 seconds).

```bash
# Verify it's up
kubectl cluster-info
kubectl get nodes   # should show one node, STATUS Ready
```

### Option B: kind (better for NetworkPolicy testing)

kind runs Kubernetes inside Docker containers. It's closer to a real cluster and supports NetworkPolicy enforcement with Cilium.

```bash
brew install kind   # or: go install sigs.k8s.io/kind@latest

# Standard cluster (no NetworkPolicy enforcement)
kind create cluster --name local

# With Cilium CNI (enforces NetworkPolicies — matches production behaviour)
kind create cluster --name local --config - <<EOF
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
networking:
  disableDefaultCNI: true
  podSubnet: "10.244.0.0/16"
nodes:
  - role: control-plane
  - role: worker
EOF
kubectl apply -f https://raw.githubusercontent.com/cilium/cilium/v1.14/install/kubernetes/quick-install.yaml
```

Switch between clusters at any time: `kubectl config use-context kind-local` or `kubectl config use-context docker-desktop`

---

### 1. Build images

The local cluster shares your Docker daemon (Docker Desktop) or needs images loaded explicitly (kind).

```bash
# Build both images
docker build --target production \
  -f backend/Dockerfile \
  -t backend:local .

docker build --target production \
  -f frontend/Dockerfile \
  --build-arg VITE_API_URL=http://localhost \
  --build-arg VITE_ENV=development \
  -t frontend:local .
```

**Docker Desktop only** — images built above are automatically available. Skip to step 2.

**kind only** — load images into the cluster after building:

```bash
kind load docker-image backend:local frontend:local --name local
```

Verify they're available inside the cluster:
```bash
docker exec -it local-worker crictl images | grep -E "backend|frontend"
```

---

### 2. Install nginx ingress controller

One-time setup. Skippable if you plan to use `kubectl port-forward` instead.

```bash
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo update

helm install ingress-nginx ingress-nginx/ingress-nginx \
  --namespace ingress-nginx --create-namespace \
  --set controller.service.type=NodePort   # NodePort works on kind; LoadBalancer works on Docker Desktop

# Wait for it to be ready
kubectl rollout status deployment/ingress-nginx-controller -n ingress-nginx
```

---

### 3. Deploy with Helm (recommended)

```bash
helm upgrade --install django-react ./k8s/helm/django-react \
  -f k8s/helm/django-react/values-local.yaml \
  --set backend.image.tag=local \
  --set frontend.image.tag=local \
  --set secrets.djangoSecretKey=local-dev-secret-key \
  --set "secrets.databaseUrl=postgres://postgres:postgres@db:5432/myapp_local" \
  --set secrets.redisUrl=redis://redis:6379/0 \
  --set secrets.postgresUser=postgres \
  --set secrets.postgresPassword=postgres \
  --set secrets.postgresDb=myapp_local \
  -n local --create-namespace
```

Watch everything come up:

```bash
kubectl get pods -n local -w
# Wait until all pods are Running (db takes ~20s, backend waits for migrations)
```

The `pre-upgrade` migration Job runs automatically before any app pods start. Check it:

```bash
kubectl get jobs -n local
kubectl logs job/db-migrate-django-react -n local
```

### 3 (alt). Deploy with Kustomize

```bash
kubectl apply -k k8s/overlays/local

# Check status
kubectl get all -n local
```

---

### 4. Access the app

**With nginx ingress controller installed:**

```bash
# Docker Desktop — ingress controller binds to localhost:80
curl http://localhost/api/health/
open http://localhost

# kind — get the NodePort
kubectl get svc -n ingress-nginx ingress-nginx-controller
# Look for 80:<NodePort>/TCP — access via http://localhost:<NodePort>
```

**Without ingress — port-forward directly to services:**

```bash
kubectl port-forward svc/backend  8000:8000 -n local &
kubectl port-forward svc/frontend 8080:80   -n local &

curl http://localhost:8000/api/health/
open http://localhost:8080
```

---

### 5. Run smoke tests

```bash
helm test django-react -n local --logs
```

This runs a pod inside the cluster that curls `/api/health/`, `/api/ping/`, and `/health` against the ClusterIP services directly.

---

### 6. Useful commands while developing

```bash
# Watch all pods
kubectl get pods -n local -w

# Tail backend logs
kubectl logs -f deployment/backend -n local

# Re-run migrations manually
kubectl exec deployment/backend -n local -- python manage.py migrate

# Open a Django shell
kubectl exec -it deployment/backend -n local -- python manage.py shell

# Check HPA (won't scale — metrics-server not installed — but shows config)
kubectl get hpa -n local

# Check PDB status (ALLOWED DISRUPTIONS column)
kubectl get pdb -n local

# Verify NetworkPolicies were applied (enforcement depends on CNI)
kubectl get networkpolicies -n local
```

### 7. Tear down

```bash
# Helm
helm uninstall django-react -n local
kubectl delete namespace local

# Kustomize
kubectl delete -k k8s/overlays/local

# Stop the cluster entirely
kind delete cluster --name local         # kind
# Docker Desktop: Settings → Kubernetes → Reset Kubernetes Cluster
```

---

### What differs from production

| | Local | Production (AKS) |
|---|---|---|
| Images | Built locally, `imagePullPolicy: Never` | Pulled from ACR, `imagePullPolicy: Always` |
| StorageClass | `hostpath` (Docker Desktop) / `standard` (kind) | `managed-premium` (Azure Premium SSD) |
| TLS | Disabled | cert-manager + Let's Encrypt |
| NetworkPolicies | Not enforced (Docker Desktop) | Enforced by Calico/Cilium |
| Replicas | 1 each | 2+ with HPA |
| Resource limits | Minimal | Sized for real traffic |
| HPA | Disabled (no metrics-server) | Active, scales on CPU/memory |

---

## Deployment

### Docker Compose (staging / prod)

```bash
# Staging
docker compose -f docker-compose.staging.yml up --build -d

# Production
docker compose -f docker-compose.prod.yml up --build -d
```

nginx serves the built React assets and proxies `/api/*` to gunicorn.

### Kubernetes (production)

Install cluster-level infrastructure once per cluster:

```bash
# nginx ingress controller
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm install ingress-nginx ingress-nginx/ingress-nginx \
  --namespace ingress-nginx --create-namespace

# cert-manager (TLS via Let's Encrypt)
helm repo add jetstack https://charts.jetstack.io
helm install cert-manager jetstack/cert-manager \
  --namespace cert-manager --create-namespace \
  --version v1.14.0 --set installCRDs=true

# Let's Encrypt ClusterIssuers (staging + production)
kubectl apply -f k8s/cert-manager/clusterissuers.yaml
```

Deploy the application with Helm:

```bash
helm upgrade --install django-react ./k8s/helm/django-react \
  -f k8s/helm/django-react/values-production.yaml \
  --set global.image.registry=myacr.azurecr.io \
  --set backend.image.tag=$(git rev-parse --short HEAD) \
  --set frontend.image.tag=$(git rev-parse --short HEAD) \
  --set secrets.djangoSecretKey=$DJANGO_SECRET_KEY \
  --set secrets.databaseUrl=$DATABASE_URL \
  --set secrets.redisUrl=$REDIS_URL \
  --set secrets.postgresUser=$POSTGRES_USER \
  --set secrets.postgresPassword=$POSTGRES_PASSWORD \
  --set secrets.postgresDb=$POSTGRES_DB \
  -n production --create-namespace \
  --atomic --timeout 5m

# Validate the deployment
helm test django-react -n production --logs
```

The Helm chart runs `python manage.py migrate` as a `pre-upgrade` Job before any new pods come up. If migrations fail, the deploy aborts and the previous release stays running.

Or use Kustomize directly:

```bash
kubectl apply -k k8s/overlays/production
```

See `k8s/README.md` for the full Kubernetes architecture — RBAC, NetworkPolicies, PodDisruptionBudgets, StorageClasses, and cert-manager are all wired in.
