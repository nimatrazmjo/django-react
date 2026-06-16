# Django + React

Full-stack web application with a Domain-Driven Design backend and a React/TypeScript frontend, fully containerised with Docker.

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
│   │   ├── shared/
│   │   └── health/
│   ├── infrastructure/       # Django/Redis adapters and ORM models
│   │   ├── health/
│   │   └── persistence/      # All Django models live here
│   ├── interfaces/api/       # DRF views, serializers, urls
│   │   ├── health/
│   │   └── core/
│   ├── config/               # Django settings (split by environment)
│   │   └── settings/
│   └── scripts/              # Dev tooling (layer import validator)
├── frontend/
│   └── src/
│       ├── App.tsx
│       └── main.tsx
├── nginx/                    # nginx config for prod/staging
├── .claude/                  # Claude Code hooks
├── docker-compose.yml        # Dev
├── docker-compose.staging.yml
├── docker-compose.prod.yml
├── .env.dev
├── .env.staging
└── .env.prod
```

---

## Getting started

### Prerequisites

- [Docker](https://docs.docker.com/get-docker/) and Docker Compose v2

### 1. Copy and configure environment variables

The `.env.dev` file is pre-configured for local development and works out of the box. For staging/prod, fill in real values before deploying.

```bash
# .env.dev is already ready — no changes needed for local dev
```

### 2. Start all services

```bash
docker compose up --build
```

This starts four containers: `backend`, `frontend`, `db` (PostgreSQL), `redis`. On first run it will pull base images, install dependencies, and run migrations automatically via the entrypoint script.

### 3. Verify everything is running

| Service | URL |
|---|---|
| Frontend (Vite HMR) | http://localhost:5173 |
| Backend health check | http://localhost:8000/api/health/ |
| Backend ping | http://localhost:8000/api/ping/ |

A healthy system returns:

```json
// GET /api/health/
{
  "status": "ok",
  "services": [
    { "name": "db", "status": "ok" },
    { "name": "cache", "status": "ok" }
  ]
}
```

---

## Environment variables

All environment files use the same keys. Only values differ per target.

| Variable | Description | Example |
|---|---|---|
| `DJANGO_SETTINGS_MODULE` | Settings module to load | `config.settings.dev` |
| `DJANGO_SECRET_KEY` | Django secret key — never commit real values | `dev-secret-key` |
| `DATABASE_URL` | PostgreSQL connection string | `postgres://user:pass@db:5432/myapp_dev` |
| `REDIS_URL` | Redis connection string | `redis://redis:6379/0` |
| `CORS_ALLOWED_ORIGINS` | Comma-separated allowed origins | `http://localhost:5173` |
| `VITE_API_URL` | Backend origin used by the Vite proxy | `http://localhost:8000` |
| `VITE_ENV` | Frontend environment label | `development` |

> Never commit `.env.staging` or `.env.prod` files with real credentials.

---

## Development workflow

### Backend

```bash
# Run Django management commands inside the running container
docker compose exec backend python manage.py <command>

# Create and apply migrations
docker compose exec backend python manage.py makemigrations
docker compose exec backend python manage.py migrate

# Open a Django shell
docker compose exec backend python manage.py shell

# Validate DDD layer imports (catches architectural violations)
docker compose exec backend python scripts/check_layer_imports.py --all

# Run tests
docker compose exec backend pytest
```

### Frontend

```bash
# The Vite dev server with HMR is already running inside the container.
# To run npm commands locally (outside Docker):
cd frontend
npm install
npm run dev     # :5173
npm run build   # production build → dist/
npm run lint
```

---

## API reference

| Method | Path | Description |
|---|---|---|
| `GET` | `/api/health/` | System health — checks DB and Redis connectivity |
| `GET` | `/api/ping/` | Liveness check — always returns `{ "message": "pong" }` |

---

## Adding a new feature (bounded context)

1. **Domain** — `backend/domain/<context>/entities.py`, `services.py`, `exceptions.py`
2. **Application** — `backend/application/<context>/dtos.py`, `queries.py`, `commands.py`
3. **Infrastructure** — `backend/infrastructure/<context>/adapters.py` + models in `infrastructure/persistence/`
4. **Interface** — `backend/interfaces/api/<context>/views.py`, `serializers.py`, `urls.py`
5. Wire the new URL file into `backend/config/urls.py`
6. Run `makemigrations` if you added models

Each layer has its own `CLAUDE.md` with precise rules. The hook in `.claude/settings.json` validates imports automatically after every file edit.

---

## Deployment

### Staging

```bash
docker compose -f docker-compose.staging.yml up --build -d
```

### Production

```bash
docker compose -f docker-compose.prod.yml up --build -d
```

In both environments, nginx serves the built React assets and proxies `/api/*` to the Django backend running under gunicorn.

---

## Layer import rules (enforced)

The `backend/scripts/check_layer_imports.py` validator runs after every file edit (via the Claude Code `PostToolUse` hook) and on CI. It enforces:

| Layer | May import from |
|---|---|
| `domain/` | stdlib only |
| `application/` | `domain/`, stdlib |
| `infrastructure/` | `domain/`, Django, third-party libs |
| `interfaces/` | `application/`, `infrastructure/`, `domain/`, DRF |

Cross-context interface imports are also blocked — `interfaces/api/orders/` cannot import from `interfaces/api/users/`. Data must flow through the application layer.

Run the check manually at any time:

```bash
python3 backend/scripts/check_layer_imports.py --all
```
