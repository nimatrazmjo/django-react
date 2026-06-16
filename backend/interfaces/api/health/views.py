"""
Health check endpoint — primary adapter (driving side).

Wires the concrete infrastructure adapter into the application use case
via constructor injection; the domain and application layers never import
anything from Django or DRF.
"""
from rest_framework.decorators import api_view
from rest_framework.request import Request
from rest_framework.response import Response

from application.health.queries import GetSystemHealthUseCase
from infrastructure.health.adapters import DjangoHealthAdapter

from .serializers import SystemHealthSerializer


@api_view(["GET"])
def health_check(request: Request) -> Response:
    use_case = GetSystemHealthUseCase(port=DjangoHealthAdapter())
    result = use_case.execute()
    return Response(
        SystemHealthSerializer(result).data,
        status=result.http_status,
    )
