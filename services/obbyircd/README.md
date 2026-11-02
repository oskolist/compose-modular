# Intro
[ObbyIRCd](https://github.com/obbyworld/ObbyIRCd) is a fork of [UnrealIRCd](https://www.unrealircd.com/) — an open source IRC server with over 25 years of history. It builds on UnrealIRCd's advanced, modular, and secure foundation and adds native account registration (backed by SQLite/Argon2id), JavaScript scripting (`obbyscript`), WebRTC voice channels and a REST/JWT backend. All inherited UnrealIRCd features are included: full IRCv3, SSL/TLS, cloaking, JSON-RPC, anti-flood/anti-spam, GeoIP, remote includes, and more.

This service pulls the official `obbyworld/obbyircd` image and reuses the image's own entrypoint, which renders `obbyircd.conf` from a template via `envsubst`, generates random cloak keys / an oper password when none are supplied, validates the configuration and starts the IRCd. The only addition on top of the upstream image is injecting the shared LetsEncrypt certificate (provided through the `ssl_certificate` / `ssl_certificate_key` secrets — see `prepare_env.sh`) into the TLS directory, so native `ircs://` on port 6697 is served with a trusted cert instead of a throwaway self-signed one. This mirrors how the `ergo` service is wired in this repo.

ObbyIRCd is fully configurable through environment variables, so there is **no** config file committed to this repo — set everything in `.env` (copied from `.env.template`).

The companion Obby web IRC client lives in `services/obby/`.

# Status
not tested

# Notes
- **Re-rendering the config**: The image renders `obbyircd.conf` from its baked-in template only on first start (it writes a `.docker_initialized` marker in `data/obbyircd/conf/`). To apply `.env` changes to an already-running instance, delete the marker and restart so the conf is re-rendered:
  ```bash
  rm -f data/obbyircd/conf/.docker_initialized
  docker compose up -d obbyircd
  ```
  (`.default.conf` files such as `modules.default.conf` are still refreshed from the image on every start, so module updates apply without re-rendering.)
- **Oper password.** `OBBYIRCD_OPER_PASSWORD` is intentionally left empty: the image auto-generates a strong random password on first run (printed to the log once, persisted to `data/obbyircd/data/.oper_password`). Set it in `.env` for stable credentials.
- **Ports.** `ircs://` on `6697` is published publicly (real LetsEncrypt cert). The plain-text WebSocket on `8080` is bound to loopback only — front it with the shared Nginx behind `wss://` if you want the Obby web client to reach this server. See `services/obby/ergo.nginx.compose.yaml` (plus `ergo.server.json`) as a reference for mirroring that setup with obbyircd.
- **Voice channels** (`^`-prefixed) require the separate [hosted-backend](https://github.com/obbyworld/hosted-backend) API service, which is not part of this repo. Only configure the `OBBYIRCD_VOICE_TURN_*` vars if you operate an external TURN service and have set `OBBYIRCD_VOICE_TURN_EXTERNAL_URLS`.
