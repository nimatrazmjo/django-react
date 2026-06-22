# Makefile — manual Docker image builder
# Wraps `docker buildx bake` for each service × environment.
#
# ─────────── Variables (override on the command line) ───────────
#   ENV      dev | staging | prod          (default: dev)
#   SERVICE  backend | frontend | all      (default: all)
#   TAG      image tag                     (default: git short SHA)
#   PUSH     true | false                  (default: false)
#   REGISTRY registry prefix               (default: myregistry)
#
# ─────────── Quick reference ────────────────────────────────────
#   make build                             # dev, all services
#   make build ENV=staging                 # staging, all services
#   make build ENV=prod SERVICE=backend    # prod, backend only
#   make build ENV=prod TAG=v1.2.3 PUSH=true
#   make push  ENV=staging TAG=abc123      # build + push shortcut
#   make print ENV=prod                    # dry-run, no build
# ────────────────────────────────────────────────────────────────

ENV      ?= dev
SERVICE  ?= all
PUSH     ?= false
REGISTRY ?= myregistry
TAG      ?= $(shell git rev-parse --short HEAD 2>/dev/null || echo latest)

# Resolve the bake target from SERVICE + ENV
ifeq ($(SERVICE),all)
  BAKE_TARGET := $(ENV)
else
  BAKE_TARGET := $(SERVICE)-$(ENV)
endif

# Pass --push only when requested
ifeq ($(PUSH),true)
  PUSH_FLAG := --push
else
  PUSH_FLAG :=
endif

BAKE_CMD := docker buildx bake $(BAKE_TARGET) $(PUSH_FLAG) \
              --set "*.platform=linux/amd64" \
              REGISTRY=$(REGISTRY) TAG=$(TAG)

# ─────────────────────────────────────────────
.PHONY: build push print \
        build-dev build-staging build-prod \
        build-backend-dev build-backend-staging build-backend-prod \
        build-frontend-dev build-frontend-staging build-frontend-prod \
        help

# ─────────────────────────────────────────────
# Primary targets
# ─────────────────────────────────────────────

## build: build SERVICE for ENV  (make build ENV=staging SERVICE=backend)
build:
	@echo "→ Building $(BAKE_TARGET)  [TAG=$(TAG)  PUSH=$(PUSH)]"
	$(BAKE_CMD)

## push: build + push shortcut  (make push ENV=prod TAG=v1.2.3)
push: PUSH=true
push: PUSH_FLAG=--push
push: build

## print: dry-run — print resolved bake config without building
print:
	docker buildx bake $(BAKE_TARGET) --print REGISTRY=$(REGISTRY) TAG=$(TAG)

# ─────────────────────────────────────────────
# Convenience one-liner targets
# ─────────────────────────────────────────────

build-dev:            ; @$(MAKE) build ENV=dev
build-staging:        ; @$(MAKE) build ENV=staging
build-prod:           ; @$(MAKE) build ENV=prod

build-backend-dev:    ; @$(MAKE) build ENV=dev     SERVICE=backend
build-backend-staging:; @$(MAKE) build ENV=staging SERVICE=backend
build-backend-prod:   ; @$(MAKE) build ENV=prod    SERVICE=backend

build-frontend-dev:    ; @$(MAKE) build ENV=dev     SERVICE=frontend
build-frontend-staging:; @$(MAKE) build ENV=staging SERVICE=frontend
build-frontend-prod:   ; @$(MAKE) build ENV=prod    SERVICE=frontend

# ─────────────────────────────────────────────
# Help
# ─────────────────────────────────────────────

## help: list available targets
help:
	@echo ""
	@echo "Usage:  make <target> [ENV=dev|staging|prod] [SERVICE=backend|frontend|all] [TAG=<tag>] [PUSH=true]"
	@echo ""
	@grep -E '^##' $(MAKEFILE_LIST) | sed 's/^## /  /'
	@echo ""
	@echo "One-liners:"
	@echo "  make build-backend-staging"
	@echo "  make build-frontend-prod TAG=v2.0.0"
	@echo "  make push ENV=prod TAG=v2.0.0"
	@echo ""
