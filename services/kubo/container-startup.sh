#!/bin/sh
set -e

case "${KUBO_IS_NETWORK_MODE_HOST-}" in
    true|True|y|yes|1)
	# https://github.com/ipfs/kubo/blob/master/bin/container_daemon
	ipfs config Addresses.API "/ip4/${KUBO_API_BIND:-127.0.0.1}/tcp/${KUBO_API_PORT:-5001}"
	ipfs config Addresses.Gateway "/ip4/${KUBO_GATEWAY_BIND:-127.0.0.1}/tcp/${KUBO_GATEWAY_PORT:-8080}"
        ;;
esac

# Enable libp2p stream mounting
if [ -n "${KUBO_LIBP2P_STREAM_MOUNTING-}" ]; then
  ipfs config --json Experimental.Libp2pStreamMounting "$KUBO_LIBP2P_STREAM_MOUNTING"
fi
if [ -n "${KUBO_AUTOCONF_URL-}" ]; then
  ipfs config --json AutoConf.URL "\"${KUBO_AUTOCONF_URL}\""
fi

# Add other configurations as needed
#ipfs config --json Addresses.Swarm '["/ip4/0.0.0.0/tcp/4001"]'
