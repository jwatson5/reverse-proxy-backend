#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
PROJECT_DIR=$(dirname "$SCRIPT_DIR")
COMPOSE_FILE="${PROJECT_DIR}/compose.base.yml"

if command -v docker >/dev/null 2>&1; then
    docker compose -f "$COMPOSE_FILE" exec -T nginx nginx -s reload >/dev/null 2>&1 || true
fi

exit 0
