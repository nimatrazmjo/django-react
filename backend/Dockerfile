# backend/Dockerfile

# ================================
# Stage 1: Builder — installs deps into a venv
#
# All current dependencies (psycopg[binary], Django, DRF, redis) ship as
# binary wheels or pure Python — no system build tools are needed.
# If a future package requires compilation, add build-essential here only;
# the production stage will remain clean because it copies the venv, not
# the build environment.
# ================================
FROM python:3.12-slim AS builder

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

WORKDIR /app

RUN python -m venv /app/venv
ENV PATH="/app/venv/bin:$PATH"

COPY requirements*.txt ./
RUN pip install --no-cache-dir -r requirements.txt

# ================================
# Stage 2: Development
# ================================
FROM builder AS development

RUN pip install --no-cache-dir -r requirements-dev.txt

COPY . .
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

EXPOSE 8000

ENTRYPOINT ["/entrypoint.sh"]
CMD ["python", "manage.py", "runserver", "0.0.0.0:8000"]

# ================================
# Stage 3: Production / Staging
#
# Starts from a clean python:3.12-slim — no compiler toolchain, no libpq-dev.
# The venv is copied from the builder stage; psycopg[binary] bundles libpq so
# no extra system libraries are required at runtime.
#
# Staging and production are the same binary; env differences are handled at
# runtime via env vars and Kubernetes config. The only build-time difference is
# worker count: staging=2, production=4 (passed as GUNICORN_WORKERS build arg).
# ================================
FROM python:3.12-slim AS production

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PATH="/app/venv/bin:$PATH" \
    VIRTUAL_ENV=/app/venv

WORKDIR /app

# curl: used by entrypoint.sh for DB readiness probes
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    && rm -rf /var/lib/apt/lists/*

ARG GUNICORN_WORKERS=4

COPY --from=builder /app/venv /app/venv
COPY . .
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

RUN addgroup --system app && adduser --system --group app
USER app

EXPOSE 8000

ENTRYPOINT ["/entrypoint.sh"]
CMD gunicorn config.wsgi:application \
    --bind 0.0.0.0:8000 \
    --workers ${GUNICORN_WORKERS} \
    --timeout 120
