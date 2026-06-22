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
  cache-from = ["type=registry,ref=${REGISTRY}/backend:buildcache"]
  cache-to   = ["type=registry,ref=${REGISTRY}/backend:buildcache,mode=max"]
}

target "_frontend-base" {
  context    = "."
  dockerfile = "frontend/Dockerfile"
  platforms  = ["linux/amd64"]
  cache-from = ["type=registry,ref=${REGISTRY}/frontend:buildcache"]
  cache-to   = ["type=registry,ref=${REGISTRY}/frontend:buildcache,mode=max"]
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
  inherits = ["_backend-base"]
  target   = "staging"
  tags     = ["${REGISTRY}/backend:staging-${TAG}"]
}

target "frontend-staging" {
  inherits = ["_frontend-base"]
  target   = "staging"
  tags     = ["${REGISTRY}/frontend:staging-${TAG}"]
  args = {
    VITE_API_URL = VITE_API_URL_STAGING
    VITE_ENV     = "staging"
  }
}

# ─────────────────────────────────────────────
# Production targets
# ─────────────────────────────────────────────

target "backend-prod" {
  inherits = ["_backend-base"]
  target   = "production"
  tags = [
    "${REGISTRY}/backend:prod-${TAG}",
    "${REGISTRY}/backend:latest",
  ]
}

target "frontend-prod" {
  inherits = ["_frontend-base"]
  target   = "production"
  tags = [
    "${REGISTRY}/frontend:prod-${TAG}",
    "${REGISTRY}/frontend:latest",
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
