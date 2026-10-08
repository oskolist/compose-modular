#!/usr/bin/env bash

# Re-exec with bash if started via `sh script.sh`
if [ -z "${BASH_VERSION:-}" ]; then
    exec bash "$0" "$@"
fi

set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
DEFAULT_COMPOSE_FILE="$SCRIPT_DIR/../compose.yaml"
INPLACE=0

usage() {
    echo "Usage: $0 [-i|--inplace] [--] [compose-file]"
    echo "  -i, --inplace edit file in place (default: print to stdout)"
    echo "  -h, --help    show this help"
    echo "  compose-file  path to compose.yaml (default: \$SCRIPT_DIR/../compose.yaml);"
    echo "                relative paths are resolved from caller's current directory"
}

while [ $# -gt 0 ]; do
    case "$1" in
        -i|--inplace) INPLACE=1 ;;
        -h|--help)    usage; exit 0 ;;
        --)           shift; break ;;
        -*)           echo "Error: unknown option '$1'" >&2; usage >&2; exit 2 ;;
        *)            break ;;
    esac
    shift
done

# Optional compose-file path (relative paths are based on caller's cwd)
if [ $# -gt 1 ]; then
    echo "Error: too many arguments (expected at most 1 compose-file)" >&2
    usage >&2
    exit 2
elif [ $# -eq 1 ]; then
    COMPOSE_FILE="$1"
else
    COMPOSE_FILE="$DEFAULT_COMPOSE_FILE"
fi

if [ ! -f "$COMPOSE_FILE" ]; then
    echo "Error: file not found: $COMPOSE_FILE" >&2
    exit 1
fi

SED_EXPR='s/^([[:space:]]*)#(-[[:space:]]+[^[:space:]]+\.ya?ml)/\1\2/'

if [ "$INPLACE" -eq 1 ]; then
    sed -i -E "$SED_EXPR" "$COMPOSE_FILE"
    echo "Wrote $COMPOSE_FILE" >&2
else
    sed -E "$SED_EXPR" "$COMPOSE_FILE"
fi
