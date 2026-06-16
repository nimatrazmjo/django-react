# backend/Dockerfile

# ================================
# Stage 1: Base
# ================================
FROM python:3.12-slim AS base

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

WORKDIR /app

RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    libpq-dev \
    curl \
    && rm -rf /var/lib/apt/lists/*

# ================================
# Stage 2: Dependencies
# ================================
FROM base AS dependencies

COPY requirements*.txt ./
RUN pip install --upgrade pip && \
    pip install -r requirements.txt

# ================================
# Stage 3: Development
# ================================
FROM dependencies AS development

RUN pip install -r requirements-dev.txt

COPY . .
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

EXPOSE 8000

ENTRYPOINT ["/entrypoint.sh"]
CMD ["python", "manage.py", "runserver", "0.0.0.0:8000"]

# ================================
# Stage 4: Production
# ================================
FROM dependencies AS production

COPY . .
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# Create non-root user
RUN addgroup --system app && adduser --system --group app
USER app

EXPOSE 8000

ENTRYPOINT ["/entrypoint.sh"]
CMD ["gunicorn", "config.wsgi:application", "--bind", "0.0.0.0:8000", "--workers", "4", "--timeout", "120"]
