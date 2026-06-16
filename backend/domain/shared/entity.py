"""
Base Entity — identity-based equality.
All domain entities inherit from this.
"""
from __future__ import annotations

import uuid
from dataclasses import dataclass, field


@dataclass
class Entity:
    id: uuid.UUID = field(default_factory=uuid.uuid4)

    def __eq__(self, other: object) -> bool:
        if not isinstance(other, type(self)):
            return NotImplemented
        return self.id == other.id

    def __hash__(self) -> int:
        return hash(self.id)
