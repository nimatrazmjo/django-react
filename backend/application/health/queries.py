"""
GetSystemHealth — query use case (read, no side effects).

Depends on the HealthCheckPort abstraction; the concrete adapter
is injected by the interface layer via constructor injection.
"""
from __future__ import annotations

from domain.health.services import HealthCheckPort

from .dtos import ServiceStatusDTO, SystemHealthDTO


class GetSystemHealthUseCase:
    def __init__(self, port: HealthCheckPort) -> None:
        self._port = port

    def execute(self) -> SystemHealthDTO:
        health = self._port.check()

        services = tuple(
            ServiceStatusDTO(
                name=s.name,
                status="ok" if s.ok else "error",
                detail=s.detail,
            )
            for s in health.services
        )

        return SystemHealthDTO(
            status=health.overall_status,
            services=services,
            http_status=200 if health.is_healthy else 503,
        )
