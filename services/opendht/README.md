# Intro
this service creates a public [opendht](https://github.com/savoirfairelinux/opendht) node where allows to be used as bootstrap node for opendht-based apps like [Jami](https://jami.net/)

# Status
underconstuction

# TODO
- testing
- complete `volumes` section to use a persistent certificate
- reverse proxy
- how client validates our node encryption? (as there is no need to valid SSL certificate and no fingerprint pinning)
- what is "DHT proxy server"? and does adding `--proxyserver 8000` argument to `dhtnode` means our node can be used as both bootstrap node and DHT proxy server?
