# Intro
a simple service to connect to SSL-VPN and expose a socks5 proxy for it

# Status
almost stable

# Note
seems it not works with "slirp4netns" network driver(see [here](https://docs.docker.com/engine/security/rootless/troubleshoot/#networking-errors)) use default docker network driver or `pasta` if you want [source IP propagation in docker rootless](https://docs.docker.com/engine/security/rootless/troubleshoot/#docker-run--p-does-not-propagate-source-ip-addresses)
