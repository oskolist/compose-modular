#!/usr/bin/env bash

# Re-exec with bash if started via `sh script.sh`
if [ -z "${BASH_VERSION:-}" ]; then
    exec bash "$0" "$@"
fi

set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
OUTPUT_FILE="$SCRIPT_DIR/../images.env"
COMPOSE_FILE="$SCRIPT_DIR/../compose.yaml"
FORCE=0
KEEP_TAG=0

usage() {
    echo "Usage: $0 [--force] [--keep-tag]"
    echo "  -f, --force   overwrite existing images.env"
    echo "  -k, --keep-tag"
    echo "                keep TAG and DIGEST of images already present in images.env"
    echo "                (only if their SRC is unchanged); images no longer enabled"
    echo "                are dropped. Implies --force."
    echo "  -h, --help    show this help"
}

while [ $# -gt 0 ]; do
    case "$1" in
        -f|--force) FORCE=1 ;;
        -k|--keep-tag) KEEP_TAG=1 ;;
        -h|--help)  usage; exit 0 ;;
        *)          echo "Error: unknown option '$1'" >&2; usage >&2; exit 2 ;;
    esac
    shift
done

detect_compose() {
    if command -v docker >/dev/null 2>&1 && docker compose version >/dev/null 2>&1; then
        COMPOSE=(docker compose)
    elif command -v docker-compose >/dev/null 2>&1 && docker-compose version >/dev/null 2>&1; then
        COMPOSE=(docker-compose)
    else
        echo "Error: neither 'docker compose' (v2 plugin) nor 'docker-compose' is available." >&2
        return 1
    fi
}

if ! command -v jq >/dev/null 2>&1; then
    echo "Error: 'jq' is required but not installed or not in PATH." >&2
    exit 1
fi

if [ -e "$OUTPUT_FILE" ] && [ "$FORCE" -ne 1 ] && [ "$KEEP_TAG" -ne 1 ]; then
    echo "\"images.env\" already exists. Use --force to overwrite. Exiting..." >&2
    exit 1
fi

detect_compose || exit 1

# Existing file to take tags/digests from (empty input if not requested/missing)
EXISTING_FILE=/dev/null
if [ "$KEEP_TAG" -eq 1 ] && [ -f "$OUTPUT_FILE" ]; then
    EXISTING_FILE="$OUTPUT_FILE"
fi

# Write to a temp file first so a failure doesn't clobber/leave a partial images.env
TMP_FILE=$(mktemp "${OUTPUT_FILE}.XXXXXX")
trap 'rm -f "$TMP_FILE"' EXIT

"${COMPOSE[@]}" -f "$COMPOSE_FILE" config --variables --format json | jq -r --rawfile existing "$EXISTING_FILE" '
  ($existing
    | split("\n")
    | map(sub("\r$"; "") | select(test("^[A-Za-z_][A-Za-z0-9_]*=")) | capture("^(?<k>[^=]+)=(?<v>.*)$") | {(.k): .v})
    | add // {}) as $old
  | to_entries
  | map(select(.key | test("_IMAGE_(SRC|TAG|DIGEST)$")))
  | sort_by([
      (.key | sub("_IMAGE_.*$"; "")),
      (.key | if endswith("_SRC") then 0 elif endswith("_TAG") then 1 else 2 end)
    ])
  | group_by(.key | sub("_IMAGE_.*$"; ""))
  | map(
      (map(select(.key | endswith("_SRC"))) | first | .value.DefaultValue // "") as $src
      | (.[0].key | sub("_IMAGE_.*$"; "")) as $prefix
      # keep old TAG/DIGEST only when the image source is unchanged
      | ($old["\($prefix)_IMAGE_SRC"] == $src) as $keep
      | map(
          .key as $k
          | if ($keep and ($k | endswith("_SRC") | not) and ($old | has($k)))
            then "\($k)=\($old[$k])"
            elif ($k | endswith("_DIGEST"))
            then "\($k)=@sha256:" + ("0" * 64)
            else "\($k)=\(.value.DefaultValue // "")"
            end
        ) | join("\n")
    )
  | join("\n\n")
' > "$TMP_FILE"

mv -f "$TMP_FILE" "$OUTPUT_FILE"
trap - EXIT
echo "Wrote $OUTPUT_FILE"
