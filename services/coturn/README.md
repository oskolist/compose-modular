# Intro
good well-known STUN/TURN server

# Status
not fully tested because

# Notes
i use docker rootless which does not support `network_mode: host`/`--network host` and port forwarding too many port cause a huge deley in container start(look https://continuwuity.org/calls/livekit.html#docker-loopback-networking-issues). so i suggest if you can just use `network_mode: host` to avoid these problems or adjust `COTURN_MIN_PORT` and `COTURN_MAX_PORT`.

# TODO
create ipmonitor service and listen for public ip change and restart coturn or somehow inform it about this.
