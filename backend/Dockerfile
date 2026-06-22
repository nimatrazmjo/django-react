# backend/Dockerfile

# ================================
# Stage 1: Base
# ================================
FROM python:3.12-slim AS base

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

WORKDIR /app

# apt-get upgrade applies security patches from Debian's repos that aren't
# baked into the upstream python:slim image yet, clearing most OS-level CVEs.
RUN apt-get update && apt-get upgrade -y && apt-get install -y --no-install-recommends \
    build-essential \
    libpq-dev \
    curl \
    && rm -rf /var/lib/apt/lists/*

# ================================
# Stage 2: Dependencies
# ================================
FROM base AS dependencies

COPY requirements*.txt ./
# --no-cache-dir: skip writing the pip cache — it's discarded when the layer
# is committed anyway, so caching it just wastes image space and build time.
RUN pip install --no-cache-dir -r requirements.txt

# ================================
# Stage 3: Development
# ================================
FROM dependencies AS development

RUN pip install --no-cache-dir -r requirements-dev.txt

COPY . .
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

EXPOSE 8000

ENTRYPOINT ["/entrypoint.sh"]
CMD ["python", "manage.py", "runserver", "0.0.0.0:8000"]

# ================================
# Stage 4: Production / Staging
#
# Staging and production are the same binary — environment differences are
# handled at runtime via env vars and Kubernetes config. The only build-time
# difference is worker count: staging runs 2 workers to mirror rolling-update
# behaviour; production runs 4. Pass GUNICORN_WORKERS as a build arg.
# ================================
FROM dependencies AS production

ARG GUNICORN_WORKERS=4

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
