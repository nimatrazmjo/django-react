"""
Output DTOs for the health bounded context.
These are plain dataclasses — no framework, no ORM.
"""
from __future__ import annotations

from dataclasses import dataclass


@dataclass(frozen=True)
class ServiceStatusDTO:
    name: str
    status: str          # "ok" | "error"
    detail: str | None = None


@dataclass(frozen=True)
class SystemHealthDTO:
    status: str          # "ok" | "degraded"
    services: tuple[ServiceStatusDTO, ...]
    http_status: int     # 200 | 503 — decided in the use case, not the view
