# Infrastructure Layer

Concrete implementations of domain ports. The only layer that imports Django, Redis, psycopg, or any third-party I/O library.

---

## Hard rules

1. **Allowed imports:** `domain/`, Django, third-party libraries, `stdlib`.
2. **Forbidden imports (hook-enforced):** `application/`, `interfaces/`.
3. Every class in `<context>/adapters.py` must implement an abstract port from `domain/<context>/services.py`.
4. Django ORM models live **only** in `infrastructure/persistence/` — never in `domain/` or scattered in adapter files.
5. Never raise `Http404`, `HttpResponse`, or any Django HTTP primitive — raise domain exceptions instead.

---

## What lives here

### `infrastructure/<context>/adapters.py`

Concrete implementations of the domain ports for that bounded context.

### `infrastructure/persistence/`

The single Django app. All ORM models for all bounded contexts live here, in per-context model files.

```
infrastructure/persistence/
  apps.py
  health_models.py      ← (add when health needs persistence)
  orders_models.py
  users_models.py
```

---

## Patterns

### Adapter
```python
# infrastructure/orders/adapters.py
from domain.orders.entities import Order
from domain.orders.exceptions import OrderNotFoundError
from domain.orders.services import OrderRepository
from infrastructure.persistence.orders_models import OrderModel

class DjangoOrderRepository(OrderRepository):
    def get_by_id(self, order_id: str) -> Order:
        try:
            record = OrderModel.objects.get(pk=order_id)
        except OrderModel.DoesNotExist:
            raise OrderNotFoundError(order_id)
        return self._to_domain(record)

    def save(self, order: Order) -> None:
        OrderModel.objects.update_or_create(
            pk=str(order.id),
            defaults={"customer_id": order.customer_id, ...},
        )

    @staticmethod
    def _to_domain(record: OrderModel) -> Order:
        return Order(id=record.pk, customer_id=record.customer_id, ...)
```

### ORM model
```python
# infrastructure/persistence/orders_models.py
import uuid
from django.db import models

class OrderModel(models.Model):
    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    customer_id = models.CharField(max_length=255, db_index=True)
    total_cents = models.PositiveIntegerField()
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        app_label = "persistence"
        db_table = "orders"
```

### Redis adapter
```python
# infrastructure/cache/adapters.py
import json
from django.core.cache import cache
from domain.cache.services import CachePort

class RedisCacheAdapter(CachePort):
    def get(self, key: str) -> dict | None:
        raw = cache.get(key)
        return json.loads(raw) if raw else None

    def set(self, key: str, value: dict, ttl: int = 300) -> None:
        cache.set(key, json.dumps(value), timeout=ttl)
```

---

## Migration workflow

When you add or change a model in `infrastructure/persistence/`:

```bash
python manage.py makemigrations persistence
python manage.py migrate
```

Migrations live in `infrastructure/persistence/migrations/`. Commit them with the model change.

---

## Skills

When generating adapters:

- The adapter class name should be `<Technology><PortName>` — e.g., `DjangoOrderRepository`, `StripePaymentAdapter`, `RedisSessionAdapter`.
- Map ORM exceptions (`DoesNotExist`, `IntegrityError`) to domain exceptions before letting them propagate.
- `_to_domain()` and `_to_model()` are private static methods — keep mapping logic isolated.
- Never call `.save()` directly on a Django model from a view — always go through the repository adapter.
- Avoid `select_related` / `prefetch_related` in the adapter unless you've confirmed it's needed via query analysis.
