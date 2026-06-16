"""
Driven adapter — concrete implementation of HealthCheckPort.
This is the only place in the health bounded context that imports Django.
"""
from __future__ import annotations

from django.core.cache import cache
from django.db import connection

from domain.health.entities import ServiceStatus, SystemHealth
from domain.health.services import HealthCheckPort


class DjangoHealthAdapter(HealthCheckPort):
    """
    Probes the configured Django database and cache backends.
    Both checks are independent; a failure in one does not skip the other.
    """

    def check(self) -> SystemHealth:
        return SystemHealth(
            services=(
                self._check_db(),
                self._check_cache(),
            )
        )

    # ------------------------------------------------------------------
    # Private helpers
    # ------------------------------------------------------------------

    @staticmethod
    def _check_db() -> ServiceStatus:
        try:
            connection.ensure_connection()
            return ServiceStatus(name="db", ok=True)
        except Exception as exc:
            return ServiceStatus(name="db", ok=False, detail=str(exc))

    @staticmethod
    def _check_cache() -> ServiceStatus:
        try:
            cache.set("_health_probe", "1", timeout=5)
            if cache.get("_health_probe") != "1":
                raise RuntimeError("Cache probe value mismatch")
            return ServiceStatus(name="cache", ok=True)
        except Exception as exc:
            return ServiceStatus(name="cache", ok=False, detail=str(exc))
