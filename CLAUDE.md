# Project: Django + React (DDD)

Full-stack web application. Django REST Framework backend structured with Domain-Driven Design; Vite + React 18 + TypeScript frontend. All services run in Docker.

---

## Stack

| Layer | Technology |
|---|---|
| Backend API | Django 5, Django REST Framework |
| Frontend | React 18, TypeScript, Vite |
| Database | PostgreSQL 16 |
| Cache | Redis 7 |
| Web server | nginx (prod/staging) |
| Containerisation | Docker Compose |

---

## Repo layout

```
.
├── backend/          ← Django project, DDD-structured (see backend/CLAUDE.md)
├── frontend/         ← Vite/React app (see frontend/CLAUDE.md)
├── nginx/            ← nginx config for prod/staging
├── .claude/          ← Claude Code hooks and settings
├── docker-compose.yml            ← dev (hot-reload)
├── docker-compose.staging.yml
├── docker-compose.prod.yml
├── .env.dev / .env.staging / .env.prod
```

---

## Running the project

```bash
# Dev — hot reload on both sides
docker compose up --build

# Frontend:  http://localhost:5173
# Backend:   http://localhost:8000/api/health/
# API ping:  http://localhost:8000/api/ping/
```

---

## Environment variables

All env files follow the same keys; only values differ per environment.

| Variable | Description |
|---|---|
| `DJANGO_SETTINGS_MODULE` | Which settings file to load (`config.settings.dev` / `.staging` / `.prod`) |
| `DJANGO_SECRET_KEY` | Django secret key |
| `DATABASE_URL` | `postgres://user:pass@host:port/db` |
| `REDIS_URL` | `redis://host:port/db` |
| `CORS_ALLOWED_ORIGINS` | Comma-separated list of allowed origins |
| `VITE_API_URL` | Backend origin for the frontend dev server proxy |
| `VITE_ENV` | `development` / `staging` / `production` |

Never commit `.env.*` files that contain real secrets.

---

## Architecture overview

The backend follows Hexagonal Architecture / DDD with four strict layers:

```
interfaces  →  application  →  domain
                    ↑
             infrastructure
```

Each layer has its own `CLAUDE.md` with precise rules. The single most important invariant is **the dependency arrow only points inward** — domain never imports from any other layer.

See `backend/CLAUDE.md` for the full breakdown.

---

## Adding a new bounded context

1. Create `backend/domain/<context>/` — entities, value objects, port interfaces.
2. Create `backend/application/<context>/` — DTOs, use cases.
3. Create `backend/infrastructure/<context>/` — concrete adapters.
4. Create `backend/interfaces/api/<context>/` — views, serializers, urls.
5. Register new ORM models inside `backend/infrastructure/persistence/`.
6. Wire urls into `backend/config/urls.py`.
7. Do **not** register anything in `INSTALLED_APPS` except `infrastructure.persistence`.

---

## Hooks

Claude Code hooks live in `.claude/settings.json`. They automatically run `backend/scripts/check_layer_imports.py` after every file edit to catch layer violations before they reach review.

---

## Non-negotiables

- No business logic in views or serializers.
- No Django imports in `domain/` or `application/`.
- No cross-context imports between `interfaces/api/<context_a>` and `interfaces/api/<context_b>` — route through the application layer instead.
- All new Python files must pass `python3 backend/scripts/check_layer_imports.py <file>` with exit code 0.
