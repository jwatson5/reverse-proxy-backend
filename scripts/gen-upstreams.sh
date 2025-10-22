#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
PROJECT_DIR=$(dirname "$SCRIPT_DIR")
UPSTREAMS_FILE="${PROJECT_DIR}/upstreams.json"
OUTPUT_FILE="${PROJECT_DIR}/nginx/conf.d/upstreams.conf"

if ! command -v jq >/dev/null 2>&1; then
    echo "ERROR: jq is required but not installed or not in PATH." >&2
    exit 1
fi

if [ ! -f "$UPSTREAMS_FILE" ]; then
    echo "ERROR: upstreams.json not found at ${UPSTREAMS_FILE}." >&2
    exit 1
fi

jq -e '
  (.workers | type == "array" and length > 0)
  and all(.workers[]; (.host | type == "string" and length > 0)
                     and (.port | type == "number"
                               and . == floor
                               and . >= 1
                               and . <= 65535)))
' "$UPSTREAMS_FILE" >/dev/null 2>&1 || {
    echo "ERROR: upstreams.json is invalid. Ensure it defines a non-empty workers array with valid host and port values." >&2
    exit 1
}

TMP_FILE=$(mktemp "${OUTPUT_FILE}.XXXXXX")
{
    echo "upstream app_upstream {"
    echo "    least_conn;"
    jq -r '.workers[] | "    server \(.host):\(.port) max_fails=3 fail_timeout=30s;"' "$UPSTREAMS_FILE"
    echo "}"
} >"$TMP_FILE"
mv "$TMP_FILE" "$OUTPUT_FILE"
echo "Generated ${OUTPUT_FILE}."
