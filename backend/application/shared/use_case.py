"""Generic use-case protocol — typed input/output contract."""
from __future__ import annotations

from typing import Generic, Protocol, TypeVar

TInput = TypeVar("TInput", contravariant=True)
TOutput = TypeVar("TOutput", covariant=True)


class UseCase(Protocol[TInput, TOutput]):
    def execute(self, input_dto: TInput) -> TOutput: ...
