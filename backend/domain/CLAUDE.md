# Domain Layer

The innermost ring. Contains business rules and domain concepts. **No framework dependencies of any kind.**

---

## Hard rules

1. **Allowed imports:** `stdlib` only — `dataclasses`, `abc`, `uuid`, `typing`, `datetime`, `enum`, etc.
2. **Forbidden imports (hook-enforced):** `django`, `rest_framework`, `redis`, `psycopg`, or any third-party package.
3. **No I/O** — no database calls, no HTTP calls, no file reads.
4. **No Django model inheritance** — domain objects are plain Python.
5. Cross-context imports within `domain/` are allowed only through `domain/shared/`.

---

## What lives here

### `domain/shared/` — shared kernel

| File | Purpose |
|---|---|
| `entity.py` | `Entity` base class — UUID identity, equality by id |
| `value_object.py` | `ValueObject` base class — frozen dataclass, equality by value |
| `exceptions.py` | `DomainException`, `ValidationError`, `NotFoundError` |
| `repository.py` | Abstract `Repository[T]` — `get_by_id`, `save` |

### `domain/<context>/` — per bounded context

| File | Purpose |
|---|---|
| `entities.py` | Entities and value objects for this context |
| `services.py` | Abstract port interfaces (ABCs) — what infrastructure must implement |
| `exceptions.py` | Domain exceptions specific to this context |

---

## Patterns

### Entity
```python
# domain/orders/entities.py
from dataclasses import dataclass, field
from domain.shared.entity import Entity

@dataclass
class Order(Entity):
    customer_id: str
    total_cents: int

    def __post_init__(self) -> None:
        if self.total_cents < 0:
            raise ValueError("Order total must be non-negative")
```

### Value object
```python
@dataclass(frozen=True)
class Money(ValueObject):
    amount: int   # cents
    currency: str

    def __post_init__(self) -> None:
        if self.amount < 0:
            raise ValueError("Money amount must be >= 0")
        if len(self.currency) != 3:
            raise ValueError("Currency must be ISO 4217 (3 chars)")
```

### Port (abstract service interface)
```python
# domain/orders/services.py
from abc import ABC, abstractmethod
from .entities import Order

class OrderRepository(ABC):
    @abstractmethod
    def get_by_id(self, order_id: str) -> Order: ...

    @abstractmethod
    def save(self, order: Order) -> None: ...
```

### Domain exception
```python
# domain/orders/exceptions.py
from domain.shared.exceptions import DomainException

class OrderNotFoundError(DomainException):
    def __init__(self, order_id: str) -> None:
        super().__init__(f"Order {order_id!r} not found")
```

---

## Invariants

- Enforce all business invariants inside `__post_init__` or factory methods — never in the use case or adapter.
- `Entity` subclasses are mutable by default; use `frozen=True` sparingly and only for aggregate roots that should not change after construction.
- `ValueObject` subclasses must always be `frozen=True`.

---

## Skills

When asked to add domain objects:

- Create the entity/value object first, enforce invariants via `__post_init__`.
- If the context needs infrastructure interaction, define the abstract port in `services.py` — never the concrete class.
- Raise named domain exceptions; never `raise Exception("...")` or `raise ValueError("...")` at the domain level.
- If a concept is used across two bounded contexts, put it in `domain/shared/` as a shared kernel type.
