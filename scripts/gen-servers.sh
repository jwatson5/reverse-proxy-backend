#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
PROJECT_DIR=$(dirname "$SCRIPT_DIR")
ENV_FILE="${PROJECT_DIR}/.env.core"
CONF_DIR="${PROJECT_DIR}/nginx/conf.d"
HTTP_CONF="${CONF_DIR}/http.conf"
HTTPS_CONF="${CONF_DIR}/https.conf"

error() {
    echo "ERROR: $1" >&2
    exit 1
}

require_file() {
    [ -f "$1" ] || error "$2"
}

require_file "$ENV_FILE" ".env.core not found at ${ENV_FILE}."

# shellcheck source=/dev/null
set -a
. "$ENV_FILE"
set +a

DOMAIN=${DOMAIN:-}
HTTP_PORT=${HTTP_PORT:-80}
HTTPS_PORT=${HTTPS_PORT:-443}

[ -n "$DOMAIN" ] || error "DOMAIN is not set in .env.core."
printf '%s' "$DOMAIN" | grep -Eq '^[A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?(\.[A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?)+$' || error "DOMAIN must be a valid DNS name."

printf '%s' "$HTTP_PORT" | grep -Eq '^[0-9]+$' || error "HTTP_PORT must be an integer."
[ "$HTTP_PORT" -ge 1 ] && [ "$HTTP_PORT" -le 65535 ] || error "HTTP_PORT must be between 1 and 65535."

printf '%s' "$HTTPS_PORT" | grep -Eq '^[0-9]+$' || error "HTTPS_PORT must be an integer."
[ "$HTTPS_PORT" -ge 1 ] && [ "$HTTPS_PORT" -le 65535 ] || error "HTTPS_PORT must be between 1 and 65535."

mkdir -p "$CONF_DIR"

CERT_DIR="${PROJECT_DIR}/letsencrypt/live/${DOMAIN}"
HAS_CERT=0
if [ -f "${CERT_DIR}/fullchain.pem" ] && [ -f "${CERT_DIR}/privkey.pem" ]; then
    HAS_CERT=1
fi

TMP_HTTP=$(mktemp "${HTTP_CONF}.XXXXXX")
if [ "$HAS_CERT" -eq 1 ]; then
    cat >"$TMP_HTTP" <<EOF
server {
    listen 80;
    server_name ${DOMAIN};

    location /.well-known/acme-challenge/ {
        root /var/www/certbot;
        default_type "text/plain";
        try_files \$uri =404;
    }

    location / {
        return 301 https://\$host\$request_uri;
    }
}
EOF
else
    cat >"$TMP_HTTP" <<EOF
# HTTPS redirect placeholder until certificates are available.
server {
    listen 80;
    server_name ${DOMAIN};

    location /.well-known/acme-challenge/ {
        root /var/www/certbot;
        default_type "text/plain";
        try_files \$uri =404;
    }

    location / {
        proxy_pass http://app_upstream;
        proxy_http_version 1.1;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
EOF
fi
mv "$TMP_HTTP" "$HTTP_CONF"

TMP_HTTPS=$(mktemp "${HTTPS_CONF}.XXXXXX")
if [ "$HAS_CERT" -eq 1 ]; then
    OPTIONS_FILE="${PROJECT_DIR}/letsencrypt/options-ssl-nginx.conf"
    cat >"$TMP_HTTPS" <<EOF
server {
    listen 443 ssl http2;
    server_name ${DOMAIN};

    ssl_certificate /etc/letsencrypt/live/${DOMAIN}/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/${DOMAIN}/privkey.pem;
    ssl_session_cache shared:SSL:10m;
    ssl_session_timeout 1d;
    ssl_prefer_server_ciphers on;
EOF
    if [ -f "$OPTIONS_FILE" ]; then
        cat >>"$TMP_HTTPS" <<'EOF'
    include /etc/letsencrypt/options-ssl-nginx.conf;
EOF
    fi
    cat >>"$TMP_HTTPS" <<'EOF'

    location /.well-known/acme-challenge/ {
        root /var/www/certbot;
        default_type "text/plain";
        try_files $uri =404;
    }

    location / {
        proxy_pass http://app_upstream;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
EOF
else
    cat >"$TMP_HTTPS" <<'EOF'
# HTTPS configuration will be generated automatically after certificates are issued.
EOF
fi
mv "$TMP_HTTPS" "$HTTPS_CONF"

echo "Generated ${HTTP_CONF}."
echo "Generated ${HTTPS_CONF}."
