"""Abstract repository interface (generic)."""
from __future__ import annotations

from abc import ABC, abstractmethod
from typing import Generic, TypeVar

T = TypeVar("T")


class Repository(ABC, Generic[T]):
    @abstractmethod
    def get_by_id(self, id: object) -> T: ...

    @abstractmethod
    def save(self, aggregate: T) -> None: ...
