# Intro
a nostr relay built specially for [flotilla](https://gitea.coracle.social/coracle/flotilla) nostr client

# Status
seems stable

# Note
i only tried this on non-443 port. there is a chance that using `host = "${ZOOID_DOMAIN}:443"` instead of `host = "${ZOOID_DOMAIN}"` in zooid configuration cause some problems.

# TODO
- add a note for NIP19 to hex conventaion for private and public keys in here(which is needed for `.env`)
