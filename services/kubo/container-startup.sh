#!/bin/sh
set -e

# Enable libp2p stream mounting
if [ -n "${KUBO_LIBP2P_STREAM_MOUNTING-}" ]; then
  ipfs config --json Experimental.Libp2pStreamMounting "$KUBO_LIBP2P_STREAM_MOUNTING"
fi
if [ -n "${KUBO_AUTOCONF_URL-}" ]; then
  ipfs config --json AutoConf.URL "\"${KUBO_AUTOCONF_URL}\""
fi

# Add other configurations as needed
# ipfs config --json Addresses.Swarm '["/ip4/0.0.0.0/tcp/4001"]'
