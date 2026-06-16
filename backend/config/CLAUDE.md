# Config

Django project configuration — settings, root URLs, WSGI/ASGI. Changes here affect the entire application.

---

## Settings split

| Module | When it loads | Key differences |
|---|---|---|
| `settings/base.py` | Always (imported by all) | No `DEBUG`, no host lists — only shared config |
| `settings/dev.py` | `DJANGO_SETTINGS_MODULE=config.settings.dev` | `DEBUG=True`, browsable API, relaxed CORS |
| `settings/staging.py` | `DJANGO_SETTINGS_MODULE=config.settings.staging` | `DEBUG=False`, HTTPS headers, no SSL redirect |
| `settings/prod.py` | `DJANGO_SETTINGS_MODULE=config.settings.prod` | `DEBUG=False`, SSL redirect, secure cookies |

**Never put secrets in any settings file.** All secrets come from `python-decouple`'s `config()` calls reading environment variables.

---

## Rules

- `base.py` must never read `DJANGO_SETTINGS_MODULE` or call `config("DEBUG")` — those belong in the environment-specific files.
- Do not import from `domain/`, `application/`, `infrastructure/`, or `interfaces/` in settings files.
- New third-party Django apps go into `INSTALLED_APPS` in `base.py`.
- New local Django apps (i.e., new ORM model groups) go into `infrastructure/persistence/` and are registered **once** via `"infrastructure.persistence"` — not as separate entries.
- `REST_FRAMEWORK` defaults live in `base.py`; `dev.py` may extend with `BrowsableAPIRenderer`.

---

## Adding a new URL namespace

In `config/urls.py`:
```python
path("api/<context>/", include("interfaces.api.<context>.urls")),
```

All API routes are prefixed with `/api/`. Never add top-level routes without the prefix.

---

## INSTALLED_APPS checklist

Before adding an entry to `INSTALLED_APPS`, ask:
- Is this a third-party package? → `base.py`.
- Is this a new Django app with models? → It must live inside `infrastructure/persistence/` and be registered as `"infrastructure.persistence"`. Do not add separate app entries.
- Is this a domain, application, or interface package? → Do **not** add it; these are plain Python packages, not Django apps.

---

## Skills

- When adding a new environment variable, add it to all three `.env.*` files at the repo root (with an appropriate placeholder value in `.env.dev`).
- When changing `DATABASES` or `CACHES`, update the corresponding health adapter in `infrastructure/health/adapters.py` to reflect the new backend.
