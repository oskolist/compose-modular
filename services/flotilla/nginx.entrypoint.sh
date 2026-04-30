#!/bin/bash

set -eu # TODO should be eu

if [ "${DEBUG-}" = "true" ]; then 
  export PS4='+ ${BASH_SOURCE}:${LINENO}: '
  set -x
fi
shopt -s nullglob

echo "# [DEBUG] $BASH_SOURCE:$LINENO: flotilla nginx entrypoint.sh started"

if [ -z "${FLOTILLA_ROOT}.unpatched" ] || [ ! -d "${FLOTILLA_ROOT}.unpatched" ]; then
  echo "# [ERROR] $BASH_SOURCE:$LINENO: ${FLOTILLA_ROOT}.unpatched is not set or does not exists"
  exit 1
fi
# note: `/.` will force merging if dest directory already exists
cp --reflink=auto -ra "${FLOTILLA_ROOT}.unpatched"/. "${FLOTILLA_ROOT}"


patch_string_in_root() {
  # Minimal version
  #sed -i "s|$1|$(echo "$2" | sed 's/[&/\]/\\&/g')|g" $(grep -r -l -F "$1" "${FLOTILLA_ROOT}")
  local search_term="$1"
  local replace_term="$2"
  local root_dir="${3:-${FLOTILLA_ROOT}}"
  if [[ -z "$search_term" ]] && [ -n "${replace_term+x}" ]; then # we only check if replace_term is empty as it will be still valid.
    echo "# [ERROR] $BASH_SOURCE:$LINENO patch_string_in_root(...): Usage: replace_string_in_root <search_term> <replace_term> [<root_dir>]"
    return 1
  fi
  if [[ "$search_term" == "$replace_term" ]]; then
    echo "# [DEBUG] $BASH_SOURCE:$LINENO patch_string_in_root(...): \$search_term=\$replace_term=$search_term, skipping the patch..."
    return 0
  fi
  if [[ ! -d "${root_dir}" ]]; then
    echo "# [ERROR] $BASH_SOURCE:$LINENO patch_string_in_root(...): $root_dir do not exists or is not directory"
    return 1
  fi
  echo "# [INFO] $BASH_SOURCE:$LINENO patch_string_in_root(...): Searching for \"$search_term\" in \"${root_dir}\"..."
  # 1. Use grep -r -l -F to find files containing the literal string
  # 2. Use xargs to pass the file list to sed
  # 3. -print0 and -0 are used to handle filenames with spaces safely
  grep -r -l -F "$search_term" "${root_dir}" | while read -r file; do
    echo "# [INFO] $BASH_SOURCE:$LINENO patch_string_in_root(...): Processing: $file"
    #echo "$replace_term" | sed -i "s|$search_term|_|g" "$file" # i thought this would work but it didn't
    replace_term_escaped="$(echo "$replace_term" | sed 's/[&/\]/\\&/g')"
    sed -i "s|$search_term|$replace_term_escaped|g" "$file"
  done
}

# https://stackoverflow.com/questions/3685970/check-if-a-bash-array-contains-a-value
containsElement () {
  local e match="$1"
  shift
  for e; do [[ "$e" == "$match" ]] && return 0; done
  return 1
}

containsElement() {
  local e match="$1"
  shift
  for e; do [[ "$e" == "$match" ]] && return 0; done
  return 1
}

merge_and_patch_relays () {
  # Prepare input data
  local -n target_array=$1  # Create a nameref to the variable name passed as $1
  local defaults_str="$2"
  local defaults=(${2//,/ })
  local conf_dir="$3"
  # Some quick checks
  conf_dir="${conf_dir%/}" # remove trailing slash if exists
  if [ ! -d "$conf_dir" ]; then
    echo "# [ERROR] $BASH_SOURCE:$LINENO merge_and_patch_relays(...): \"$conf_dir\" does not exists or is not directory"
    return 1
  fi
  if [[ "$defaults_str" =~ [[:space:]] ]]; then
    echo "# [ERROR] $BASH_SOURCE:$LINENO merge_and_patch_relays(...): \"$defaults_str\" contains whitespace character"
    return 1
  fi
  # Main section
  echo "# [DEBUG] $BASH_SOURCE:$LINENO merge_and_patch_relays(...): Main section started for \$$1"
  if [ ${#target_array[@]} -eq 0 ]; then
    #echo "# [DEBUG] $BASH_SOURCE:$LINENO merge_and_patch_relays(...): target_array(\$$1) is Empty. filling it with defaults..."
    target_array=("${defaults[@]}")
  elif [ "${target_array[*]}" = "None" ] || [ "${target_array[*]}" = "none" ]; then
    #echo "# [DEBUG] $BASH_SOURCE:$LINENO merge_and_patch_relays(...): target_array(\$$1) is None"
    target_array=()
  fi
  for file in "$conf_dir/"*.conf; do
    echo "# [INFO] $BASH_SOURCE:$LINENO merge_and_patch_relays(...): adding content of \"$file\" to \$$1"
    item="$(cat "$file" | head -n1)"
    if ! containsElement "$item" "${target_array[@]}"; then
      #echo "$ [DEBUG] $BASH_SOURCE:$LINENO merge_and_patch_relays(...): adding \"$item\" to \$$1"
      target_array+=("$item")
    fi
  done
  echo "# [DEBUG] $BASH_SOURCE:$LINENO merge_and_patch_relays(...): patching \"$(IFS=, ; echo "${defaults[*]}")\" with \"$(IFS=, ; echo "${target_array[*]}")\""
  patch_string_in_root "$(IFS=, ; echo "${defaults[*]}")" "$(IFS=, ; echo "${target_array[*]}")"
  ## If `defaults` array is not bigger array(if there is at least one extra item in target_array that does not exists in `defaults`) when patch defaults
  #for default in "${defaults[@]}"; do
  #  echo "# [DEBUG] merge_and_patch_relays(...): checking if \"$default\" is in \$target_array"
  #  if ! containsElement "$default" "${target_array[@]}"; then
  #    patch_string_in_root "$(IFS=, ; echo "${defaults[*]}")" "$(IFS=, ; echo "${target_array[*]}")"
  #  fi
  #done
}




# TODO: seems we can automate this with reading default values using sourcing `.env.template` from flotilla source code.
if [ -n "${FLOTILLA_DEFAULT_PUBKEYS-}" ]; then
  default="06639a386c9c1014217622ccbcf40908c4f1a0c33e23f8d6d68f4abf655f8f71,266815e0c9210dfa324c6cba3573b14bee49da4209a9456f9484e5106cd408a5,391819e2f2f13b90cac7209419eb574ef7c0d1f4e81867fc24c47a3ce5e8a248,3bf0c63fcb93463407af97a5e5ee64fa883d107ef9e558472c4eb9aaaefa459d,3f770d65d3a764a9c5cb503ae123e62ec7598ad035d836e2a810f3877a745b24,55f04590674f3648f4cdc9dc8ce32da2a282074cd0b020596ee033d12d385185,58c741aa630c2da35a56a77c1d05381908bd10504fdd2d8b43f725efa6d23196,61066504617ee79387021e18c89fb79d1ddbc3e7bff19cf2298f40466f8715e9,6389be6491e7b693e9f368ece88fcd145f07c068d2c1bbae4247b9b5ef439d32,63fe6318dc58583cfe16810f86dd09e18bfd76aabc24a0081ce2856f330504ed,6e75f7972397ca3295e0f4ca0fbc6eb9cc79be85bafdd56bd378220ca8eee74e,76c71aae3a491f1d9eec47cba17e229cda4113a0bbb6e6ae1776d7643e29cafa,7fa56f5d6962ab1e3cd424e758c3002b8665f7b0d8dcee9fe9e288d7751ac194,82341f882b6eabcd2ba7f1ef90aad961cf074af15b9ef44a09f9d2a8fbfbe6a2,84dee6e676e5bb67b4ad4e042cf70cbd8681155db535942fcc6a0533858a7240,97c70a44366a6535c145b333f973ea86dfdc2d7a99da618c40c64705ad98e322,b676ded7c768d66a757aa3967b1243d90bf57afb09d1044d3219d8d424e4aea0,dace63b00c42e6e017d00dd190a9328386002ff597b841eb5ef91de4f1ce8491,eeb11961b25442b16389fe6c7ebea9adf0ac36dd596816ea7119e521b8821b9e,fe7f6bc6f7338b76bbf80db402ade65953e20b2f23e66e898204b63cc42539a3"
  FLOTILLA_DEFAULT_PUBKEYS=(${FLOTILLA_DEFAULT_PUBKEYS//,/ })
  mkdir -p "/etc/flotilla/default_pubkeys.d/"
  merge_and_patch_relays FLOTILLA_DEFAULT_PUBKEYS "$default" "/etc/flotilla/default_pubkeys.d/"
fi
if [ -n "${FLOTILLA_DEFAULT_BLOSSOM_SERVERS-}" ]; then
  default="https://blossom.primal.net/"
  mkdir -p "/etc/flotilla/default_blossom_servers.d/"
  merge_and_patch_relays FLOTILLA_DEFAULT_BLOSSOM_SERVERS "$default" "/etc/flotilla/default_blossom_servers.d/"
fi
if [ -n "${FLOTILLA_POMADE_SIGNERS-}" ]; then
  default="https://pomade.coracle.social,https://pomade.fiatjaf.com,https://pomade.nostrver.se,https://pomade.scuttle.works"
  FLOTILLA_POMADE_SIGNERS=(${FLOTILLA_POMADE_SIGNERS//,/ })
  mkdir -p "/etc/flotilla/pomade_signers.d/"
  merge_and_patch_relays FLOTILLA_POMADE_SIGNERS "$default" "/etc/flotilla/pomade_signers.d/"
fi
if [ -n "${FLOTILLA_PLATFORM_URL-}" ]; then
  default="https://app.flotilla.social"
  if [ "$FLOTILLA_PLATFORM_URL" = "None" ]; then
    echo "# [WARNING] $BASH_SOURCE:$LINENO: \$FLOTILLA_PLATFORM_URL is None. which is probably not a good idea"
    FLOTILLA_PLATFORM_URL=""
  fi
  patch_string_in_root "$default" "$FLOTILLA_PLATFORM_URL"
fi
# // TODO: add more
if [ -n "${FLOTILLA_BLOCKED_RELAYS-}" ]; then 
  default="brb.io,relay.nostr.band,nostr.mutinywallet.com,feeds.nostr.band,nostr.zbd.gg,wot.utxo.one,blastr.f7z.xyz,relay.current.fyi"
  FLOTILLA_BLOCKED_RELAYS=(${FLOTILLA_BLOCKED_RELAYS//,/ })
  patch_string_in_root "$default" "$FLOTILLA_BLOCKED_RELAYS"
  mkdir -p "/etc/flotilla/blocked_relays.d"
  merge_and_patch_relays FLOTILLA_BLOCKED_RELAYS "$default" "/etc/flotilla/blocked_relays.d/"
fi
if [ -n "${FLOTILLA_INDEXER_RELAYS-}" ]; then 
  default="purplepag.es,relay.damus.io,indexer.coracle.social"
  FLOTILLA_INDEXER_RELAYS=(${FLOTILLA_INDEXER_RELAYS//,/ })
  mkdir -p "/etc/flotilla/indexer_relays.d"
  merge_and_patch_relays FLOTILLA_INDEXER_RELAYS "$default" "/etc/flotilla/indexer_relays.d/"
fi
if [ -n "${FLOTILLA_DEFAULT_RELAYS-}" ]; then 
  default="relay.damus.io,relay.primal.net,nostr.mom"
  FLOTILLA_DEFAULT_RELAYS=(${FLOTILLA_DEFAULT_RELAYS//,/ })
  mkdir -p "/etc/flotilla/default_relays.d"
  merge_and_patch_relays FLOTILLA_DEFAULT_RELAYS "$default" "/etc/flotilla/default_relays.d/"
fi
if [ -n "${FLOTILLA_DEFAULT_MESSAGING_RELAYS-}" ]; then 
  default="auth.nostr1.com,relay.keychat.io"
  FLOTILLA_DEFAULT_MESSAGING_RELAYS=(${FLOTILLA_DEFAULT_MESSAGING_RELAYS//,/ })
  mkdir -p "/etc/flotilla/default_messaging_relays.d"
  merge_and_patch_relays FLOTILLA_DEFAULT_MESSAGING_RELAYS "$default" "/etc/flotilla/default_messaging_relays.d/"
fi
if [ -n "${FLOTILLA_SIGNER_RELAYS-}" ]; then 
  default="relay.nsec.app,ephemeral.snowflare.cc,bucket.coracle.social"
  FLOTILLA_SIGNER_RELAYS=(${FLOTILLA_SIGNER_RELAYS//,/ })
  mkdir -p "/etc/flotilla/signer_relays.d"
  merge_and_patch_relays FLOTILLA_SIGNER_RELAYS "$default" "/etc/flotilla/signer_relays.d/"
fi
