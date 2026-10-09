#!/usr/bin/env bash

# Convert floating image tags in images.env (e.g. "stable-alpine", "latest",
# "alpine") to fixed version tags (e.g. "1.30.5-alpine") so that Renovate can
# update them.
#
# For every <PREFIX>_IMAGE_SRC / _TAG / _DIGEST group the script:
#   1. skips the image if the tag is already a fixed version,
#   2. determines the digest the floating tag points to (the pinned digest in
#      images.env if there is a real one, otherwise whatever the registry
#      currently returns for the tag),
#   3. lists the tags of the repository and looks for a fixed version tag with
#      the same variant (suffix) that resolves to that very same digest,
#   4. rewrites _TAG (and _DIGEST) in place.
#
# Requires: bash, curl, jq, GNU sort.

# Re-exec with bash if started via `sh script.sh`
if [ -z "${BASH_VERSION:-}" ]; then
    exec bash "$0" "$@"
fi

set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
IMAGES_ENV="$SCRIPT_DIR/../images.env"
DRY_RUN=0
MIN_PARTS=3      # a tag with fewer numeric parts (1.30 -> 2) is not "fixed"
MAX_CHECKS=300   # max number of candidate tags to resolve per image
ZERO_DIGEST="sha256:$(printf '0%.0s' {1..64})"

# Leading words that describe a release channel and not an image variant.
CHANNEL_KEYWORDS='latest|stable|mainline|lts|current|release|main|master'

ACCEPT='application/vnd.oci.image.index.v1+json,application/vnd.docker.distribution.manifest.list.v2+json,application/vnd.oci.image.manifest.v1+json,application/vnd.docker.distribution.manifest.v2+json'

usage() {
    echo "Usage: $0 [-n|--dry-run] [--min-parts N] [--max-checks N] [images.env]"
    echo "  -n, --dry-run     only print what would change"
    echo "  --min-parts N     numeric parts a tag needs to count as fixed (default: $MIN_PARTS)"
    echo "  --max-checks N    max candidate tags to resolve per image (default: $MAX_CHECKS)"
    echo "  -h, --help        show this help"
    echo "  images.env        file to modify (default: \$SCRIPT_DIR/../images.env)"
}

while [ $# -gt 0 ]; do
    case "$1" in
        -n|--dry-run)  DRY_RUN=1 ;;
        --min-parts)   MIN_PARTS="${2:?missing value}"; shift ;;
        --max-checks)  MAX_CHECKS="${2:?missing value}"; shift ;;
        -h|--help)     usage; exit 0 ;;
        --)            shift; [ $# -gt 0 ] && IMAGES_ENV="$1"; break ;;
        -*)            echo "Error: unknown option '$1'" >&2; usage >&2; exit 2 ;;
        *)             IMAGES_ENV="$1" ;;
    esac
    shift
done

for cmd in curl jq sort; do
    command -v "$cmd" >/dev/null 2>&1 || { echo "Error: '$cmd' is required but not installed." >&2; exit 1; }
done
[ -f "$IMAGES_ENV" ] || { echo "Error: '$IMAGES_ENV' not found." >&2; exit 1; }

log()  { echo "$*" >&2; }
warn() { echo "[WARNING] $*" >&2; }

# ---------------------------------------------------------------------------
# Registry helpers
# ---------------------------------------------------------------------------

# Split an image reference into REGISTRY_HOST (API host) and REPO.
parse_image() {
    local src="$1" first rest
    src="${src#docker://}"
    first="${src%%/*}"
    rest="${src#*/}"
    if [ "$first" != "$src" ] && { [[ "$first" == *.* ]] || [[ "$first" == *:* ]] || [ "$first" = localhost ]; }; then
        REGISTRY_HOST="$first"
        REPO="$rest"
    else
        REGISTRY_HOST="docker.io"
        REPO="$src"
    fi
    case "$REGISTRY_HOST" in
        docker.io|index.docker.io|registry-1.docker.io)
            REGISTRY_HOST="registry-1.docker.io"
            [[ "$REPO" == */* ]] || REPO="library/$REPO"
            ;;
    esac
}

# Obtain a bearer token (if the registry wants one) into TOKEN.
registry_login() {
    local host="$1" repo="$2" headers auth realm service resp
    TOKEN=""
    headers=$(curl -s -D - -o /dev/null "https://$host/v2/" || true)
    auth=$(printf '%s' "$headers" | tr -d '\r' | grep -i '^www-authenticate:' | head -n1 || true)
    [[ "$auth" == *[Bb]earer* ]] || return 0
    realm=$(printf '%s' "$auth" | sed -n 's/.*realm="\([^"]*\)".*/\1/p')
    service=$(printf '%s' "$auth" | sed -n 's/.*service="\([^"]*\)".*/\1/p')
    resp=$(curl -fsS -G "$realm" \
        --data-urlencode "service=$service" \
        --data-urlencode "scope=repository:$repo:pull") || return 1
    TOKEN=$(printf '%s' "$resp" | jq -r '.token // .access_token // empty')
}

# curl with registry auth
rcurl() {
    if [ -n "$TOKEN" ]; then
        curl -sS -H "Authorization: Bearer $TOKEN" "$@"
    else
        curl -sS "$@"
    fi
}

# Print the manifest digest for a tag (empty if it does not exist).
tag_digest() {
    local tag="$1" hdr
    hdr=$(rcurl -sIL -H "Accept: $ACCEPT" "https://$REGISTRY_HOST/v2/$REPO/manifests/$tag" || true)
    printf '%s' "$hdr" | tr -d '\r' | awk 'tolower($1)=="docker-content-digest:" {print $2}' | tail -n1
}

# Print all tags of the repository (follows pagination).
list_tags() {
    local url="https://$REGISTRY_HOST/v2/$REPO/tags/list?n=1000" tmp_h tmp_b next
    tmp_h=$(mktemp); tmp_b=$(mktemp)
    while [ -n "$url" ]; do
        rcurl -fL -D "$tmp_h" -o "$tmp_b" "$url" || { rm -f "$tmp_h" "$tmp_b"; return 1; }
        jq -r '.tags[]?' "$tmp_b"
        next=$(tr -d '\r' < "$tmp_h" | sed -n 's/^[Ll]ink:.*<\([^>]*\)>.*rel="next".*/\1/p' | tail -n1)
        case "$next" in
            "")      url="" ;;
            http*)   url="$next" ;;
            *)       url="https://$REGISTRY_HOST$next" ;;
        esac
    done
    rm -f "$tmp_h" "$tmp_b"
}

# ---------------------------------------------------------------------------
# Tag logic
# ---------------------------------------------------------------------------

regex_escape() { printf '%s' "$1" | sed 's/[][\.^$*+?(){}|/]/\\&/g'; }

# Number of numeric parts in the leading version of a tag ("v1.30.5-alpine" -> 3).
version_parts() {
    local v
    v=$(printf '%s' "$1" | sed -n 's/^v\{0,1\}\([0-9][0-9.]*\).*/\1/p')
    [ -n "$v" ] || { echo 0; return; }
    awk -F. '{print NF}' <<<"$v"
}

# Find a fixed tag for $1 (current tag) whose digest is $2. Prints the tag.
find_fixed_tag() {
    local cur="$1" want="$2"
    local vprefix="" ver="" variant="" re ver_re

    if [[ "$cur" =~ ^(v?)([0-9]+(\.[0-9]+)*)(-(.+))?$ ]]; then
        vprefix="${BASH_REMATCH[1]}"; ver="${BASH_REMATCH[2]}"; variant="${BASH_REMATCH[5]}"
    elif [[ "$cur" =~ ^($CHANNEL_KEYWORDS)(-(.+))?$ ]]; then
        variant="${BASH_REMATCH[3]}"
    else
        variant="$cur"
    fi

    if [ -n "$ver" ]; then
        ver_re="$(regex_escape "$vprefix")$(regex_escape "$ver")(\.[0-9]+)+"
    else
        ver_re="v?[0-9]+(\.[0-9]+)*"
    fi
    re="^${ver_re}"
    [ -n "$variant" ] && re+="-$(regex_escape "$variant")"
    re+='$'

    local tags candidates tag n checks=0 d
    tags=$(list_tags) || { warn "could not list tags"; return 1; }

    # "<parts>\t<version>\t<tag>" sorted: most specific first, then newest first
    candidates=$(
        printf '%s\n' "$tags" | grep -E "$re" | while IFS= read -r tag; do
            n=$(version_parts "$tag")
            [ "$n" -ge "$MIN_PARTS" ] || continue
            printf '%s\t%s\t%s\n' "$n" "$(printf '%s' "$tag" | sed -n 's/^v\{0,1\}\([0-9][0-9.]*\).*/\1/p')" "$tag"
        done | sort -t$'\t' -k1,1nr -k2,2Vr | cut -f3
    )
    [ -n "$candidates" ] || { warn "no fixed-version candidates matching /$re/"; return 1; }

    while IFS= read -r tag; do
        checks=$((checks + 1))
        if [ "$checks" -gt "$MAX_CHECKS" ]; then
            warn "gave up after $MAX_CHECKS candidates (see --max-checks)"
            return 1
        fi
        d=$(tag_digest "$tag")
        if [ "$d" = "$want" ]; then
            printf '%s\n' "$tag"
            return 0
        fi
    done <<<"$candidates"
    return 1
}

# ---------------------------------------------------------------------------
# images.env helpers
# ---------------------------------------------------------------------------

get_var() { sed -n "s/^$1=\(.*\)\$/\1/p" "$IMAGES_ENV" | head -n1; }

set_var() {
    local key="$1" value="$2" tmp
    tmp=$(mktemp "${IMAGES_ENV}.XXXXXX")
    awk -v k="$key" -v v="$value" 'index($0, k "=") == 1 { print k "=" v; next } { print }' "$IMAGES_ENV" > "$tmp"
    cat "$tmp" > "$IMAGES_ENV"   # keep permissions/ownership of the original file
    rm -f "$tmp"
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

changed=0 failed=0

mapfile -t PREFIXES < <(sed -n 's/^\([A-Za-z0-9_]*\)_IMAGE_SRC=.*/\1/p' "$IMAGES_ENV")
[ "${#PREFIXES[@]}" -gt 0 ] || { log "No *_IMAGE_SRC entries found in $IMAGES_ENV"; exit 0; }

for p in "${PREFIXES[@]}"; do
    src=$(get_var "${p}_IMAGE_SRC")
    tag=$(get_var "${p}_IMAGE_TAG")
    digest=$(get_var "${p}_IMAGE_DIGEST")
    digest="${digest#@}"

    if [ -z "$src" ] || [ -z "$tag" ]; then
        warn "$p: missing SRC or TAG, skipping"
        continue
    fi

    if [ "$(version_parts "$tag")" -ge "$MIN_PARTS" ]; then
        log "$p: $src:$tag is already a fixed tag, skipping"
        continue
    fi

    log "$p: resolving $src:$tag ..."
    parse_image "$src"
    if ! registry_login "$REGISTRY_HOST" "$REPO"; then
        warn "$p: authentication against $REGISTRY_HOST failed"
        failed=$((failed + 1)); continue
    fi

    current=$(tag_digest "$tag")
    if [ -z "$current" ]; then
        warn "$p: tag '$tag' not found in $REGISTRY_HOST/$REPO"
        failed=$((failed + 1)); continue
    fi

    new_tag=""
    # Prefer the digest that is pinned in images.env (what is actually deployed)
    if [ -n "$digest" ] && [ "$digest" != "$ZERO_DIGEST" ] && [ "$digest" != "$current" ]; then
        if new_tag=$(find_fixed_tag "$tag" "$digest"); then
            current="$digest"
        else
            warn "$p: pinned digest matches no fixed tag, using current digest of '$tag'"
            new_tag=""
        fi
    fi
    if [ -z "$new_tag" ] && ! new_tag=$(find_fixed_tag "$tag" "$current"); then
        warn "$p: no fixed tag found with digest $current, leaving unchanged"
        failed=$((failed + 1)); continue
    fi

    log "$p: $tag -> $new_tag (@$current)"
    if [ "$DRY_RUN" -eq 0 ]; then
        set_var "${p}_IMAGE_TAG" "$new_tag"
        set_var "${p}_IMAGE_DIGEST" "@$current"
    fi
    changed=$((changed + 1))
done

log "Done: $changed updated, $failed unresolved."
[ "$failed" -eq 0 ]
