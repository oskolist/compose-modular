# Intro
[Continuwuity](https://forgejo.ellis.link/continuwuation/continuwuity) is a community-driven Matrix homeserver

# Status
seems working but needs more testing

# Notes
after first run you should check continuwuity logs using `docker-compose logs continuwuity`. it will contains a random register token(even when `CONTINUWUITY_REGISTRATION_TOKEN` is already set) for first user creation which will become server admin.

# TODO
- dns cache setup
- allow to use federator over non-${HTTPS_PORT} port(e.g. 8448)
- redirct to matrix web client when "/" is opened
- fix these warning?
```
WARN conduwuit_core::config::check: Config parameter "domain" is unknown to conduwuit, ignoring.
WARN conduwuit_core::config::check: Config parameter "socket_dir" is unknown to conduwuit, ignoring.
WARN conduwuit_core::config::check: Config parameter "socket_name" is unknown to conduwuit, ignoring.
```
