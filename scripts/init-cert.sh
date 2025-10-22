#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
PROJECT_DIR=$(dirname "$SCRIPT_DIR")
ENV_FILE="${PROJECT_DIR}/.env.core"

error() {
    echo "ERROR: $1" >&2
    exit 1
}

[ -f "$ENV_FILE" ] || error ".env.core not found at ${ENV_FILE}."

# shellcheck source=/dev/null
set -a
. "$ENV_FILE"
set +a

DOMAIN=${DOMAIN:-}
LETSENCRYPT_EMAIL=${LETSENCRYPT_EMAIL:-}
STAGING=${STAGING:-0}

[ -n "$DOMAIN" ] || error "DOMAIN is not set in .env.core."
printf '%s' "$DOMAIN" | grep -Eq '^[A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?(\.[A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?)+$' || error "DOMAIN must be a valid DNS name."

[ -n "$LETSENCRYPT_EMAIL" ] || error "LETSENCRYPT_EMAIL is not set in .env.core."
printf '%s' "$LETSENCRYPT_EMAIL" | grep -Eq '^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$' || error "LETSENCRYPT_EMAIL must be a valid email address."

case "$STAGING" in
    0|1) ;;
    *) error "STAGING must be '0' or '1'." ;;
esac

STAGING_FLAG=""
if [ "$STAGING" = "1" ]; then
    STAGING_FLAG="--staging"
fi

echo "Requesting certificate for ${DOMAIN}..."
certbot certonly \
  --webroot -w /var/www/certbot \
  -d "$DOMAIN" \
  --email "$LETSENCRYPT_EMAIL" \
  --agree-tos \
  --no-eff-email \
  $STAGING_FLAG

echo "Reloading nginx service..."
docker compose -f "${PROJECT_DIR}/compose.base.yml" exec -T nginx nginx -s reload || true
