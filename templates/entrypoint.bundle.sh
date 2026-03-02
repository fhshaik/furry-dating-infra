#!/usr/bin/env bash
set -euo pipefail

export HOME=/home/appuser
export PATH=/home/appuser/.local/bin:$PATH

if [ "${RUN_DB_MIGRATIONS:-true}" = "true" ]; then
  su appuser -s /bin/sh -c 'cd /app/backend && alembic upgrade head'
fi

exec /usr/bin/supervisord -n -c /etc/supervisor/supervisord.conf
