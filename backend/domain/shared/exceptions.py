"""Domain exception hierarchy — no framework dependencies."""


class DomainException(Exception):
    """Base for all domain exceptions."""


class ValidationError(DomainException):
    """Raised when an invariant is violated during construction."""


class NotFoundError(DomainException):
    """Raised when an aggregate cannot be located."""
