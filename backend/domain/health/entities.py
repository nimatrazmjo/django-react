"""
Health bounded context — domain entities and value objects.
Zero framework dependencies; importable in isolation.
"""
from __future__ import annotations

from dataclasses import dataclass

from domain.shared.value_object import ValueObject


@dataclass(frozen=True)
class ServiceStatus(ValueObject):
    """Represents the liveness of a single infrastructure dependency."""

    name: str
    ok: bool
    detail: str | None = None

    def __post_init__(self) -> None:
        if not self.name:
            raise ValueError("ServiceStatus.name must not be empty")


@dataclass(frozen=True)
class SystemHealth(ValueObject):
    """
    Aggregate root for system health.
    Composed of one ServiceStatus per infrastructure dependency.
    """

    services: tuple[ServiceStatus, ...]

    @property
    def is_healthy(self) -> bool:
        return all(s.ok for s in self.services)

    @property
    def overall_status(self) -> str:
        return "ok" if self.is_healthy else "degraded"
