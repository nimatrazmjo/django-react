# docker-bake.hcl
# Docker Buildx Bake — modular multi-service, multi-env build definitions.
#
# Usage:
#   docker buildx bake <group|target> [--set <override>]
#
# Examples:
#   docker buildx bake staging                              # build all services for staging
#   docker buildx bake backend-prod                        # single service, prod
#   docker buildx bake prod --set "*.tags=myrepo/backend:v1.2.3"
#   TAG=v1.2.3 docker buildx bake prod
#   REGISTRY=123456789.dkr.ecr.us-east-1.amazonaws.com TAG=abc123 docker buildx bake prod --push

# ─────────────────────────────────────────────
# Variables  (override via env or --set flag)
# ─────────────────────────────────────────────

variable "REGISTRY" {
  # e.g. 123456789.dkr.ecr.us-east-1.amazonaws.com  or  ghcr.io/myorg
  default = "myregistry"
}

variable "TAG" {
  default = "latest"
}

# Vite build-arg values — override per deploy if needed
variable "VITE_API_URL_STAGING" {
  default = "https://staging.127.0.0.1.nip.io"
}

variable "VITE_API_URL_PROD" {
  default = "https://api.example.com"
}

# ─────────────────────────────────────────────
# Base targets  (never built directly — inherited only)
# ─────────────────────────────────────────────

target "_backend-base" {
  context    = "./backend"
  dockerfile = "Dockerfile"
  platforms  = ["linux/amd64"]
  # pull=true: always check for a fresher base image digest on each build.
  # Replaces the removed `apt-get upgrade` as the mechanism for picking up
  # upstream OS/runtime patches without busting the dependency layer cache.
  pull = true
  cache-from = [
    "type=registry,ref=${REGISTRY}/backend:buildcache",
    "type=gha,scope=backend",
  ]
  cache-to = [
    "type=registry,ref=${REGISTRY}/backend:buildcache,mode=min",
    "type=gha,scope=backend,mode=min",
  ]
}

target "_frontend-base" {
  context    = "."
  dockerfile = "frontend/Dockerfile"
  platforms  = ["linux/amd64"]
  pull = true
  cache-from = [
    "type=registry,ref=${REGISTRY}/frontend:buildcache",
    "type=gha,scope=frontend",
  ]
  cache-to = [
    "type=registry,ref=${REGISTRY}/frontend:buildcache,mode=min",
    "type=gha,scope=frontend,mode=min",
  ]
}

# ─────────────────────────────────────────────
# Dev targets
# ─────────────────────────────────────────────

target "backend-dev" {
  inherits = ["_backend-base"]
  target   = "development"
  tags     = ["${REGISTRY}/backend:dev-${TAG}"]
  # Dev images are local only — skip remote cache push
  cache-to = []
}

target "frontend-dev" {
  inherits = ["_frontend-base"]
  target   = "development"
  tags     = ["${REGISTRY}/frontend:dev-${TAG}"]
  cache-to = []
}

# ─────────────────────────────────────────────
# Staging targets
# ─────────────────────────────────────────────

target "backend-staging" {
  inherits   = ["_backend-base"]
  target     = "production"
  tags       = ["${REGISTRY}/backend:staging-${TAG}"]
  # provenance=false: suppress build-stage provenance attestations so Trivy
  # doesn't flag builder-only packages (e.g. pip build tools) in the final image.
  provenance = false
  args = {
    GUNICORN_WORKERS = "2"
  }
}

target "frontend-staging" {
  inherits   = ["_frontend-base"]
  target     = "staging"
  tags       = ["${REGISTRY}/frontend:staging-${TAG}"]
  # provenance=false: the builder stage installs npm (which bundles node-tar);
  # those packages don't exist in the final nginx image, but Buildx provenance
  # attestations expose them to Trivy. Disable to keep scans accurate.
  provenance = false
  args = {
    VITE_API_URL = VITE_API_URL_STAGING
    VITE_ENV     = "staging"
  }
}

# ─────────────────────────────────────────────
# Production targets
# ─────────────────────────────────────────────

target "backend-prod" {
  inherits   = ["_backend-base"]
  target     = "production"
  provenance = false
  tags = [
    "${REGISTRY}/backend:prod-${TAG}",
  ]
  args = {
    GUNICORN_WORKERS = "4"
  }
}

target "frontend-prod" {
  inherits   = ["_frontend-base"]
  target     = "production"
  provenance = false
  tags = [
    "${REGISTRY}/frontend:prod-${TAG}",
  ]
  args = {
    VITE_API_URL = VITE_API_URL_PROD
    VITE_ENV     = "production"
  }
}

# ─────────────────────────────────────────────
# Groups  (build all services for a given env)
# ─────────────────────────────────────────────

group "dev" {
  targets = ["backend-dev", "frontend-dev"]
}

group "staging" {
  targets = ["backend-staging", "frontend-staging"]
}

group "prod" {
  targets = ["backend-prod", "frontend-prod"]
}
