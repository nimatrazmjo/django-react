#!/bin/sh
set -e

echo "Waiting for database..."
until python -c "
import os, sys, time
import django
os.environ.setdefault('DJANGO_SETTINGS_MODULE', os.getenv('DJANGO_SETTINGS_MODULE', 'config.settings.dev'))
django.setup()
from django.db import connection
connection.ensure_connection()
" 2>/dev/null; do
    echo "  DB not ready — retrying in 1s"
    sleep 1
done
echo "Database ready."

echo "Running migrations..."
python manage.py migrate --noinput

echo "Starting server..."
exec "$@"
