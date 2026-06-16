# Application Layer

Thin orchestration layer. Coordinates domain objects and ports to fulfil a single use case. Contains no business logic and no framework code.

---

## Hard rules

1. **Allowed imports:** `domain/` and `stdlib` only.
2. **Forbidden imports (hook-enforced):** `django`, `rest_framework`, `infrastructure`, `interfaces`, or any third-party package.
3. **No business logic** — if you're writing an `if` that enforces a domain rule, it belongs in `domain/`.
4. **No I/O** — use cases receive ports via constructor injection; they never instantiate adapters themselves.
5. **One use case per class**, one public method: `execute()`.

---

## What lives here

### `application/shared/`

| File | Purpose |
|---|---|
| `use_case.py` | `UseCase[TInput, TOutput]` protocol |

### `application/<context>/`

| File | Purpose |
|---|---|
| `dtos.py` | Frozen dataclasses — input and output shapes for use cases |
| `queries.py` | Read use cases (no side effects) |
| `commands.py` | Write use cases (side effects: DB writes, emails, events) |

---

## Patterns

### DTO
```python
# application/orders/dtos.py
from __future__ import annotations
from dataclasses import dataclass

@dataclass(frozen=True)
class PlaceOrderDTO:          # input
    customer_id: str
    line_items: tuple[LineItemDTO, ...]

@dataclass(frozen=True)
class LineItemDTO:
    product_id: str
    quantity: int

@dataclass(frozen=True)
class OrderCreatedDTO:        # output
    order_id: str
    total_cents: int
    status: str
```

### Command use case
```python
# application/orders/commands.py
from domain.orders.entities import Order
from domain.orders.services import OrderRepository, PaymentPort
from .dtos import PlaceOrderDTO, OrderCreatedDTO

class PlaceOrderUseCase:
    def __init__(
        self,
        order_repo: OrderRepository,
        payment_port: PaymentPort,
    ) -> None:
        self._order_repo = order_repo
        self._payment_port = payment_port

    def execute(self, dto: PlaceOrderDTO) -> OrderCreatedDTO:
        order = Order(customer_id=dto.customer_id, ...)
        self._payment_port.charge(order.total_cents)
        self._order_repo.save(order)
        return OrderCreatedDTO(order_id=str(order.id), ...)
```

### Query use case
```python
# application/orders/queries.py
from domain.orders.services import OrderRepository
from .dtos import OrderDetailDTO

class GetOrderUseCase:
    def __init__(self, order_repo: OrderRepository) -> None:
        self._order_repo = order_repo

    def execute(self, order_id: str) -> OrderDetailDTO:
        order = self._order_repo.get_by_id(order_id)
        return OrderDetailDTO(...)
```

---

## Error handling

- Let domain exceptions (`DomainException` subclasses) propagate up to the interface layer.
- The interface layer (view) catches and maps them to HTTP responses.
- Use cases should not catch domain exceptions; they are not responsible for HTTP error codes.

---

## Skills

When generating use cases:

- Separate queries (reads) from commands (writes) into different files.
- Every constructor parameter is a port interface (ABC), never a concrete class.
- DTOs are always frozen dataclasses — never plain dicts, never Django model instances.
- If a use case needs more than ~4 injected ports, that's a signal the bounded context should be split.
- Output DTOs carry `http_status` only when the caller (interface layer) genuinely needs to differentiate on it — otherwise keep it out.
