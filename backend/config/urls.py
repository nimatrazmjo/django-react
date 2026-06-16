from django.urls import path, include

urlpatterns = [
    # Health bounded context
    path("api/health/", include("interfaces.api.health.urls")),
    # Core / utility
    path("api/", include("interfaces.api.core.urls")),
]
