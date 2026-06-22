"""
Domain-layer tests for the health bounded context.

These tests import nothing outside stdlib + domain/ — no Django, no DB.
They verify the business invariants enforced by domain entities.
"""
import pytest

from domain.health.entities import ServiceStatus, SystemHealth


class TestServiceStatus:
    def test_healthy_service_is_ok(self) -> None:
        status = ServiceStatus(name="database", ok=True)

        assert status.ok is True

    def test_unhealthy_service_is_not_ok(self) -> None:
        status = ServiceStatus(name="redis", ok=False, detail="connection refused")

        assert status.ok is False
        assert status.detail == "connection refused"

    def test_empty_name_raises(self) -> None:
        with pytest.raises(ValueError, match="name must not be empty"):
            ServiceStatus(name="", ok=True)

    def test_value_object_equality_by_value(self) -> None:
        a = ServiceStatus(name="db", ok=True)
        b = ServiceStatus(name="db", ok=True)

        assert a == b

    def test_value_object_is_immutable(self) -> None:
        status = ServiceStatus(name="db", ok=True)

        with pytest.raises(AttributeError):
            status.ok = False  # type: ignore[misc]


class TestSystemHealth:
    def test_all_services_healthy_means_system_is_healthy(self) -> None:
        health = SystemHealth(
            services=(
                ServiceStatus(name="db", ok=True),
                ServiceStatus(name="redis", ok=True),
            )
        )

        assert health.is_healthy is True
        assert health.overall_status == "ok"

    def test_one_unhealthy_service_degrades_the_system(self) -> None:
        health = SystemHealth(
            services=(
                ServiceStatus(name="db", ok=True),
                ServiceStatus(name="redis", ok=False),
            )
        )

        assert health.is_healthy is False
        assert health.overall_status == "degraded"

    def test_empty_services_is_healthy(self) -> None:
        health = SystemHealth(services=())

        assert health.is_healthy is True
