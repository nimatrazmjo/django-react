# Interfaces Layer

Primary adapters — the HTTP boundary. Translates HTTP requests into use case calls and maps results back to HTTP responses. The only layer that touches DRF.

---

## Hard rules

1. **Allowed imports:** `application/`, `infrastructure/`, `domain/`, Django, DRF, `stdlib`.
2. **Forbidden cross-context imports (hook-enforced):** `interfaces/api/<context_a>` must not import from `interfaces/api/<context_b>`. If context A needs data from context B, add a use case in `application/` and call it from both views.
3. **No business logic in views** — if you're writing domain-level `if` statements in a view, move them to the domain or use case.
4. **No ORM calls in views** — all data access goes through use cases.
5. **Constructor injection** — views instantiate concrete adapters and inject them into use cases. Never call `django.conf.settings` inside a use case.

---

## What lives here

```
interfaces/api/
  <context>/
    views.py        ← @api_view functions (or ViewSet classes)
    serializers.py  ← DRF Serializer subclasses (input validation + output shape)
    urls.py         ← urlpatterns list
```

---

## Patterns

### View
```python
# interfaces/api/orders/views.py
from rest_framework.decorators import api_view
from rest_framework.request import Request
from rest_framework.response import Response
from rest_framework import status

from application.orders.commands import PlaceOrderUseCase
from application.orders.dtos import PlaceOrderDTO
from domain.orders.exceptions import OrderNotFoundError
from infrastructure.orders.adapters import DjangoOrderRepository
from infrastructure.payments.adapters import StripePaymentAdapter

from .serializers import PlaceOrderSerializer, OrderCreatedSerializer


@api_view(["POST"])
def place_order(request: Request) -> Response:
    serializer = PlaceOrderSerializer(data=request.data)
    serializer.is_valid(raise_exception=True)

    use_case = PlaceOrderUseCase(
        order_repo=DjangoOrderRepository(),
        payment_port=StripePaymentAdapter(),
    )

    try:
        result = use_case.execute(
            PlaceOrderDTO(**serializer.validated_data)
        )
    except OrderNotFoundError as exc:
        return Response({"detail": str(exc)}, status=status.HTTP_404_NOT_FOUND)

    return Response(OrderCreatedSerializer(result).data, status=status.HTTP_201_CREATED)
```

### Serializer
```python
# interfaces/api/orders/serializers.py
from rest_framework import serializers

class LineItemSerializer(serializers.Serializer):
    product_id = serializers.CharField()
    quantity   = serializers.IntegerField(min_value=1)

class PlaceOrderSerializer(serializers.Serializer):
    customer_id = serializers.CharField()
    line_items  = LineItemSerializer(many=True)

class OrderCreatedSerializer(serializers.Serializer):
    order_id    = serializers.CharField()
    total_cents = serializers.IntegerField()
    status      = serializers.CharField()
```

### URL registration
```python
# interfaces/api/orders/urls.py
from django.urls import path
from .views import place_order, get_order

urlpatterns = [
    path("orders/", place_order, name="place-order"),
    path("orders/<str:order_id>/", get_order, name="get-order"),
]
```

Then in `config/urls.py`:
```python
path("api/", include("interfaces.api.orders.urls")),
```

---

## Exception mapping

Catch domain exceptions at the view boundary and map them to HTTP status codes:

| Domain exception | HTTP status |
|---|---|
| `NotFoundError` | 404 |
| `ValidationError` | 400 |
| `DomainException` (generic) | 422 |

Use DRF's `exception_handler` in `config/settings/base.py` for cross-cutting error formatting.

---

## Skills

When generating views and serializers:

- Use `@api_view` for simple endpoints, `ViewSet` only when you need the full CRUD router.
- Input serializers validate; output serializers shape. Keep them separate when the shapes differ.
- Never return raw ORM querysets from a view — always go through a use case that returns a DTO.
- When a view needs more than 3 injected adapters, reconsider whether the use case is doing too much.
- All URL names must be kebab-case and globally unique within the project.
