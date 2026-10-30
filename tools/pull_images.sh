#!/usr/bin/env bash
#
# pull_images.sh — emit (or run) image-pull commands for every image defined
# in images.env.
#
# Each enabled <PREFIX>_IMAGE_SRC / _IMAGE_TAG / _DIGEST group becomes one line
# on stdout, e.g.:
#
#   docker pull alpine:3.24.3
#
# The "docker pull" prefix is configurable through the IMAGE_PULL_CMD env var
# so the output can be pointed at another tool just as easily, e.g.:
#
#   IMAGE_PULL_CMD="skopeo copy docker://"  ./tools/pull_images.sh
#   IMAGE_PULL_CMD="ctr images pull"        ./tools/pull_images.sh
#   IMAGE_PULL_CMD="echo Would pull"        ./tools/pull_images.sh   # dry-run style
#
# By default images are referenced by tag. Use --by-digest to reference them by
# digest only, or --with-digest to append the digest to the tag, e.g.:
#
#   docker pull alpine:3.24.3@sha256:be2656061b536c1883c4034790e21d0a09...
#
# Pulling by "tag@digest" lets Docker verify the tag against the pinned digest
# while keeping the human-readable tag.
#
# Re-exec with bash if started via `sh script.sh`
if [ -z "${BASH_VERSION:-}" ]; then
    exec bash "$0" "$@"
fi

set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
IMAGES_ENV="$SCRIPT_DIR/../images.env"
BY_DIGEST=0
WITH_DIGEST=0
EXECUTE=0

usage() {
    cat <<EOF
Usage: $0 [options]

Emit (or execute) image-pull commands for every image defined in images.env.
Commands are printed to stdout, one per image.

Options:
  --env FILE        path to images.env (default: ../images.env)
  --by-digest       pull by digest (image@sha256:...) instead of by tag (image:tag)
  --with-digest       append the digest to the tag (image:tag@sha256:...) so the
                    tag is verified against the pinned digest
  -x, --execute     run the commands instead of printing them
  -h, --help        show this help

Environment:
  IMAGE_PULL_CMD    the pull command prefix (default: "docker pull").
                    Override to use another tool, e.g.:
                      IMAGE_PULL_CMD="skopeo copy docker://" $0
                      IMAGE_PULL_CMD="echo Would pull"       $0
EOF
}

while [ $# -gt 0 ]; do
    case "$1" in
        --env)        IMAGES_ENV="${2:?missing file}"; shift 2 ;;
        --by-digest)  BY_DIGEST=1; shift ;;
        --with-digest) WITH_DIGEST=1; shift ;;
        -x|--execute) EXECUTE=1; shift ;;
        -h|--help)    usage; exit 0 ;;
        --)           shift; break ;;
        -*)           echo "Error: unknown option '$1'" >&2; usage >&2; exit 2 ;;
        *)            echo "Error: unexpected argument '$1'" >&2; usage >&2; exit 2 ;;
    esac
done

[ -f "$IMAGES_ENV" ] || { echo "Error: '$IMAGES_ENV' not found." >&2; exit 1; }

if [ "$BY_DIGEST" -eq 1 ] && [ "$WITH_DIGEST" -eq 1 ]; then
    echo "Error: --by-digest and --with-digest are mutually exclusive." >&2
    exit 2
fi

# The command prefix used for every emitted line. Swap it out to target a
# different tool: IMAGE_PULL_CMD="skopeo copy docker://"  or  "ctr images pull"
PULL_CMD="${IMAGE_PULL_CMD:-docker pull}"

ZERO_DIGEST="sha256:$(printf '0%.0s' {1..64})"

get_var() { sed -n "s/^$1=\(.*\)\$/\1/p" "$IMAGES_ENV" | head -n1; }

# Collect image prefixes from enabled <PREFIX>_IMAGE_SRC lines. Commented-out
# entries (leading "#") and blank lines are ignored by the anchored regex.
mapfile -t PREFIXES < <(sed -n 's/^\([A-Za-z0-9_]*\)_IMAGE_SRC=.*/\1/p' "$IMAGES_ENV")

if [ "${#PREFIXES[@]}" -eq 0 ]; then
    echo "No enabled *_IMAGE_SRC entries found in $IMAGES_ENV" >&2
    exit 0
fi

for p in "${PREFIXES[@]}"; do
    src=$(get_var "${p}_IMAGE_SRC")
    tag=$(get_var "${p}_IMAGE_TAG")
    digest=$(get_var "${p}_IMAGE_DIGEST")
    digest="${digest#@}"   # strip leading "@" -> "sha256:..."

    [ -n "$src" ] || { echo "[warn] $p: missing SRC, skipping" >&2; continue; }

    if [ "$BY_DIGEST" -eq 1 ]; then
        # Pull the pinned digest if it is real, otherwise fall back to the tag.
        if [ -n "$digest" ] && [ "$digest" != "$ZERO_DIGEST" ]; then
            ref="${src}@${digest}"
        else
            ref="${src}:${tag}"
        fi
    elif [ "$WITH_DIGEST" -eq 1 ]; then
        # Tag plus digest: Docker verifies the tag against the pinned digest.
        if [ -n "$digest" ] && [ "$digest" != "$ZERO_DIGEST" ]; then
            ref="${src}:${tag}@${digest}"
        else
            ref="${src}:${tag}"
        fi
    else
        ref="${src}:${tag}"
    fi

    if [ "$EXECUTE" -eq 1 ]; then
        # Intentionally unquoted so "docker pull" / "ctr images pull" word-split
        # into the command and its arguments.
        $PULL_CMD "$ref"
    else
        printf '%s %s\n' "$PULL_CMD" "$ref"
    fi
done
