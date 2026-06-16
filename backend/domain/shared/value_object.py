"""
Base Value Object — structural equality, immutable.
All domain value objects inherit from this.
"""
from dataclasses import dataclass


@dataclass(frozen=True)
class ValueObject:
    """Frozen dataclass gives structural equality and immutability for free."""
