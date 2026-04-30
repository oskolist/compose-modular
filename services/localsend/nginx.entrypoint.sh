#!/bin/sh
#echo "# [DEBUG] localsend nginx.entrypoint.sh started"
set -e
if [ -z "${LOCALSEND_ROOT}.unpatched" ] || [ ! -d "${LOCALSEND_ROOT}.unpatched" ]; then
  echo "# [ERROR] ${LOCALSEND_ROOT}.unpatched is not set or does not exists"
  exit 1
fi

cp --reflink=auto -ra "${LOCALSEND_ROOT}.unpatched"/. "${LOCALSEND_ROOT}"

if [ -n "$LOCALSEND_SIGNALING_URL" ]; then
  echo "# [INFO] patching Localsend Web to use custom signaling url with $LOCALSEND_SIGNALING_URL..."
  # https://unix.stackexchange.com/questions/450725/can-i-use-sed-awk-etc-to-replace-parts-of-a-file-with-text-from-stdin
  LOCALSEND_SIGNALING_URL_ESCAPED=$(echo "$LOCALSEND_SIGNALING_URL" | sed 's/[&/\]/\\&/g')
  echo "# [DEBUG] \$LOCALSEND_SIGNALING_URL_ESCAPED is $LOCALSEND_SIGNALING_URL_ESCAPED"
  sed -i "s|wss://public.localsend.org/v1/ws|$LOCALSEND_SIGNALING_URL_ESCAPED|g" $(grep -r -l -F "wss://public.localsend.org/v1/ws" "${LOCALSEND_ROOT}")
fi
