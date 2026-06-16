from django.apps import AppConfig


class PersistenceConfig(AppConfig):
    """
    Django app that owns all ORM models.
    Each bounded context's models live in subdirectories here
    rather than being scattered across the domain layer.
    """

    name = "infrastructure.persistence"
    label = "persistence"
