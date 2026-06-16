from rest_framework import serializers


class ServiceStatusSerializer(serializers.Serializer):
    name = serializers.CharField()
    status = serializers.CharField()
    detail = serializers.CharField(allow_null=True, required=False)


class SystemHealthSerializer(serializers.Serializer):
    status = serializers.CharField()
    services = ServiceStatusSerializer(many=True)
