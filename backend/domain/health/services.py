"""
Domain service interface (Port) for health checking.
The concrete implementation lives in infrastructure/.
"""
from abc import ABC, abstractmethod

from domain.health.entities import SystemHealth


class HealthCheckPort(ABC):
    """
    Secondary port (driven adapter target).
    Infrastructure must provide a concrete implementation.
    """

    @abstractmethod
    def check(self) -> SystemHealth: ...
