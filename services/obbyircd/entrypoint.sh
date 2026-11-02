#!/bin/sh
# obbyircd-entrypoint.sh — compose-modular entrypoint wrapper for obbyircd.
#
# ObbyIRCd's official image ships its own ENTRYPOINT
# (/usr/local/bin/docker-entrypoint.sh) which renders obbyircd.conf from a
# baked-in template via envsubst, generates random cloak keys / an oper password
# when none are supplied, issues a self-signed TLS cert if none is found,
# validates the config and starts the IRCd in the foreground.
#
# This wrapper only injects the shared LetsEncrypt certificate (provided through
# the `ssl_certificate` / `ssl_certificate_key` secrets at /run/secrets) into the
# TLS directory the image expects, so native ircs:// on port 6697 is served with a
# trusted cert instead of a throwaway self-signed one — mirroring how the `ergo`
# service is wired in this repo.  It then delegates to the upstream entrypoint
# with the original CMD args ($@), so `docker compose run ...` overrides work too.
set -e

TLS_DIR="/home/obbyircd/obby/tls"
mkdir -p "$TLS_DIR"

if [ -e /run/secrets/fullchain.pem ]; then
  cp -f /run/secrets/fullchain.pem "$TLS_DIR/server.cert.pem"
  echo "# [INFO] Injected shared TLS certificate -> $TLS_DIR/server.cert.pem"
else
  echo "# [WARNING] /run/secrets/fullchain.pem not found; obbyircd will self-sign a TLS cert"
fi
if [ -e /run/secrets/privkey.pem ]; then
  cp -f /run/secrets/privkey.pem "$TLS_DIR/server.key.pem"
else
  echo "# [WARNING] /run/secrets/privkey.pem not found"
fi
chmod 644 "$TLS_DIR/server.cert.pem" 2>/dev/null || true
chmod 600 "$TLS_DIR/server.key.pem" 2>/dev/null || true
chown -R obbyircd:obbyircd "$TLS_DIR" 2>/dev/null || true

exec /usr/local/bin/docker-entrypoint.sh "$@"
