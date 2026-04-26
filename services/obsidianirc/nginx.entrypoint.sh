#!/bin/sh
if [ -z "${OBSIDIANIRC_ROOT}.unpatched" ] || [ ! -d "${OBSIDIANIRC_ROOT}.unpatched" ]; then
  echo "[ERROR] ${OBSIDIANIRC_ROOT}.unpatched is not set or does not exists"
  exit 1
fi
cp --reflink=auto -ra "${OBSIDIANIRC_ROOT}.unpatched" "${OBSIDIANIRC_ROOT}"

# Patching - TODO: add a environment variable to only patch the app when user asked for it
if [ -d "/etc/obsidianirc/servers.d" ]; then
  echo "[INFO] Collecting ObsidianIRC server json files to /etc/obsidianirc/servers.json"
  jq -s '.' /etc/obsidianirc/servers.d/*.json >/etc/obsidianirc/servers.json
  echo "[INFO] patching ObsidianIRC to use local servers.json instead of fetching it from github at runtime"
  sed -i'.bak' 's#https://raw.githubusercontent.com/ObsidianIRC/server-list/refs/heads/main/servers.json#../servers.json#g' "${OBSIDIANIRC_ROOT}/assets/"*.js
else
  echo "[INFO] No servers are preconfigured for ObsidianIRC. it will load default ones from github at runtime."
fi

echo "[INFO] patching ObsidianIRC to prevent connect to googleapis for fonts(because this cause long loading if they are not availble in runtime)"
sed -i -E '/https:\/\/fonts\.(googleapis|gstatic)\.com/d' "${OBSIDIANIRC_ROOT}/index.html"
