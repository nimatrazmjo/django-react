# Backend — Django DDD

Django 5 + DRF backend structured with Domain-Driven Design (Hexagonal Architecture). Read this before touching any Python file.

---

## Layer map

```
backend/
  domain/           ← business rules, zero framework deps  →  domain/CLAUDE.md
  application/      ← use cases, orchestration             →  application/CLAUDE.md
  infrastructure/   ← Django/Redis/ORM adapters            →  infrastructure/CLAUDE.md
  interfaces/       ← DRF views, serializers, urls         →  interfaces/CLAUDE.md
  config/           ← Django settings, urls, wsgi          →  config/CLAUDE.md
  scripts/          ← validation and dev tooling
```

---

## Dependency rules (enforced by hook)

```
interfaces   can import from   application, infrastructure, domain
application  can import from   domain
infrastructure can import from domain (+ Django/third-party)
domain       can import from   stdlib only
```

**Violations are caught automatically** by the `PostToolUse` hook which runs `scripts/check_layer_imports.py` after every file edit. Fix them before moving on — do not suppress the check.

---

## INSTALLED_APPS

Only `infrastructure.persistence` is registered as a Django app. Do **not** add domain, application, or interface packages to `INSTALLED_APPS`. When you add a new Django model, put it in `infrastructure/persistence/` and it will be discovered automatically.

---

## Naming conventions

| Concept | File | Class |
|---|---|---|
| Domain entity | `domain/<ctx>/entities.py` | `Order`, `User` |
| Value object | `domain/<ctx>/entities.py` | `Money`, `Email` (frozen dataclass) |
| Domain port | `domain/<ctx>/services.py` | `PaymentPort` (ABC) |
| Domain exception | `domain/<ctx>/exceptions.py` | `InsufficientFundsError` |
| DTO | `application/<ctx>/dtos.py` | `CreateOrderDTO` (frozen dataclass) |
| Use case | `application/<ctx>/commands.py` or `queries.py` | `PlaceOrderUseCase` |
| Adapter | `infrastructure/<ctx>/adapters.py` | `StripePaymentAdapter` |
| ORM model | `infrastructure/persistence/<ctx>_models.py` | `OrderModel` |
| View | `interfaces/api/<ctx>/views.py` | function-based via `@api_view` |
| Serializer | `interfaces/api/<ctx>/serializers.py` | `CreateOrderSerializer` |

---

## Use case convention

Every use case is a class with a single public method:

```python
class PlaceOrderUseCase:
    def __init__(self, payment_port: PaymentPort, order_repo: OrderRepository) -> None:
        self._payment_port = payment_port
        self._order_repo = order_repo

    def execute(self, dto: PlaceOrderDTO) -> OrderDTO:
        ...
```

- Queries (reads, no side effects) → `queries.py`
- Commands (writes, side effects) → `commands.py`
- Constructor injection only — never pull dependencies from Django settings inside a use case.

---

## Commands

```bash
# Run dev server (inside container or with local venv)
python manage.py runserver 0.0.0.0:8000

# Migrations
python manage.py makemigrations
python manage.py migrate

# Validate layer imports on a file
python scripts/check_layer_imports.py path/to/file.py

# Validate entire backend
python scripts/check_layer_imports.py --all

# Run tests
pytest
```

---

## Adding a new bounded context — checklist

- [ ] `domain/<ctx>/entities.py` — entities and value objects
- [ ] `domain/<ctx>/services.py` — abstract port interfaces
- [ ] `domain/<ctx>/exceptions.py` — domain exceptions
- [ ] `application/<ctx>/dtos.py` — input/output DTOs (frozen dataclasses)
- [ ] `application/<ctx>/queries.py` and/or `commands.py` — use cases
- [ ] `infrastructure/<ctx>/adapters.py` — concrete port implementations
- [ ] `infrastructure/persistence/<ctx>_models.py` — Django ORM models (if needed)
- [ ] `interfaces/api/<ctx>/views.py`, `serializers.py`, `urls.py`
- [ ] Wire `interfaces/api/<ctx>/urls.py` into `config/urls.py`
- [ ] Create a migration if you added models: `python manage.py makemigrations`

---

## Skills

When generating code in this backend:

- Always check the target layer's `CLAUDE.md` before writing.
- Prefer editing over creating new files — look for existing entities, DTOs, or adapters that can be extended.
- When asked to add a feature, scaffold all four layers at once rather than just the view.
- Never put `try/except` inside use cases for business flow — raise domain exceptions instead and handle them in the interface layer.
- Type-annotate every function signature. Return types are mandatory.
