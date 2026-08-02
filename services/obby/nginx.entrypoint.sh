#!/bin/sh
if [ -z "${OBBY_ROOT}.unpatched" ] || [ ! -d "${OBBY_ROOT}.unpatched" ]; then
  echo "[ERROR] ${OBBY_ROOT}.unpatched is not set or does not exists"
  exit 1
fi
cp --reflink=auto -ra "${OBBY_ROOT}.unpatched"/. "${OBBY_ROOT}"

# Patching
# TODO: add a environment variable to only patch the app when user asked for it

if [ -d "/etc/obby/servers.d" ]; then
  echo "[INFO] Collecting Obby server json files to /etc/obby/servers.json"
  jq -s '.' /etc/obby/servers.d/*.json >/etc/obby/servers.json
  echo "[INFO] patching Obby to use local servers.json instead of fetching it from github at runtime"
  sed -i'.bak' 's#https://raw.githubusercontent.com/obbyworld/server-list/refs/heads/main/servers.json#../servers.json#g' "${OBBY_ROOT}/assets/"*.js
else
  echo "[INFO] No servers are preconfigured for Obby. it will load default ones from github at runtime."
fi

#echo "[INFO] patching Obby to prevent connect to googleapis for fonts(because this cause long loading if they are not availble in runtime)"
#sed -i -E '/https:\/\/fonts\.(googleapis|gstatic)\.com/d' "${OBBY_ROOT}/index.html"
