# Contributor Manual — oskolist/compose-modular

> A quick-start + style reference for **humans and AI agents** adding, fixing, or
> extending a service. Read this first — you should **not** need to read every
> other file in the repo to know how to name your files and variables or how a
> service is wired together.

This project is a **modular Docker Compose** setup: every service lives in its
own directory under `services/`, and services are pulled together with Compose's
[`include:`](https://github.com/compose-spec/compose-spec/blob/master/spec.md#include)
directive. A single shared **nginx** container does SSL termination + reverse
proxying and is extended by each service through small override files.

---

## Table of contents

1. [Repository layout (at a glance)](#1-repository-layout-at-a-glance)
2. [Quick start — run it locally](#2-quick-start--run-it-locally)
3. [How a service is "enabled"](#3-how-a-service-is-enabled)
4. [Anatomy of a service directory](#4-anatomy-of-a-service-directory)
5. [Naming convention for files](#5-naming-convention-for-files)
6. [Naming convention for environment variables](#6-naming-convention-for-environment-variables)
7. [The envsubst / templating mechanism](#7-the-envsubst--templating-mechanism)
8. [Adding a new service — step by step](#8-adding-a-new-service--step-by-step)
9. [Adding a new service behind nginx (HTTP)](#9-adding-a-new-service-behind-nginx-http)
10. [Static-webapp services (no app container)](#10-static-webapp-services-no-app-container)
11. [Services that need the public IP (ipmonitor)](#11-services-that-need-the-public-ip-ipmonitor)
12. [Secrets & placeholders](#12-secrets--placeholders)
13. [Image pinning & Renovate](#13-image-pinning--renovate)
14. [Common pitfalls & gotchas](#14-common-pitfalls--gotchas)
15. [Templates you can copy](#15-templates-you-can-copy)

---

## 1. Repository layout (at a glance)

```
compose-modular/
├── compose.yaml                 # THE active file you run `docker compose up` with (GITIGNORED)
├── compose.yaml.template        # template for compose.yaml; services are commented out
├── .env.base                    # YOUR host-wide settings (GITIGNORED, copied from .env.base.template)
├── .env.base.template           # template: MAIN_DOMAIN, REAL_IP, HTTP(S)_PORT, GHCR_MIRROR
├── prepare_env.sh               # sources .env.base + every services/*/.env into the env
├── images.env                   # pinned <PREFIX>_IMAGE_SRC/TAG/DIGEST for every image (TRACKED)
├── renovate.json5               # Renovate regex manager for images.env
├── README.md                    # high-level project goals + quick start
├── CONTRIBUTING.md              # THIS FILE
├── snippets/
│   └── ssl.yaml                 # reusable `secrets:` block (ssl_certificate) snippet
├── temp/                        # runtime scratch (ipmonitor ipv4.txt) — GITIGNORED
│   └── pinning.txt              # notes/bookmarks for image pinning
├── tools/
│   ├── create_images_env.sh     # regenerate images.env from `docker compose config --variables`
│   ├── create_uncommented_composeyaml.sh  # turn compose.yaml.template → compose.yaml (uncomment)
│   └── pin_image_tags.sh        # resolve "floating" tags (latest, stable) → fixed version tags
└── services/
    ├── nginx/                   # the shared nginx container + core nginx config (http.d/stream.d/...)
    ├── ipmonitor/               # watches public IP and restarts dependents when it changes
    ├── <service>/               # one directory per service (see §4)
    │   ├── compose.yaml         # (most services) the service definition; ABSENT for static-webapps
    │   ├── .env.template        # (optional) service env template
    │   ├── <other_service_name>.<file>  # file tying <service> to another service — see pattern below
    │   ├── *.conf / *.toml / *.json    # service config files (mounted as .template, envsubst'd)
    │   ├── *.sh                       # entrypoint/init scripts
    │   ├── Dockerfile               # (optional) for custom images
    │   └── README.md               # REQUIRED: Intro / Status / Note / TODO
    └── ...
```

### The `<other_service_name>.<file>` pattern

A file inside `services/<service_name>/` is named `<other_service_name>.<file>`:
the **leading token is the name of the *other* service the file relates to** —
any service besides `<service_name>` itself. Most services lean on one of the two
**shared** services — `nginx` (reverse proxy / static hosting) and `ipmonitor`
(public-IP watcher) — so the repo is full of `nginx.*` and
`ipmonitor.compose.yaml` files. Some services lean on a **peer** instead:
`obby` carries `ergo.*` files, `screego` carries a `coturn.*` file, and so on
(full per-file reference in §5).

> Read the name left-to-right: **whose** is it, then **what** it is. The first
> token is always `<other_service_name>` (the service the file is *about*). A
> `nginx.*` file configures nginx; `ergo.nginx.compose.yaml` (in `services/obby/`)
> is an nginx override *about* ergo. Flip it the other way and the rule still
> holds: ergo's nginx override **would** be `services/ergo/nginx.compose.yaml`
> (a file *about* nginx) — ergo is just a standalone IRC server, so it carries none.

### Independence is one-way

`<other_service_name>` can run **independently** of whether `<service_name>`
exists at all — `nginx` and `ipmonitor` run fine with every other service
disabled, and `ergo` runs fine on its own. The reverse is **not** true:
`<service_name>` **needs** `<other_service_name>`, either:

- **optionally** — a feature it can live without (e.g. `obby` runs fine without
  `ergo`; the web client just shows no IRC server), **or**
- **not optionally** (mandatory) — a feature it can't function without
  (e.g. `obby` cannot serve its static files without `nginx`).

This is exactly why `ergo`'s directory has **no** `nginx.*`/`ergo.*`/`ipmonitor.*`
files: it relates to no other service and stands on its own. Only wire in a
`<other_service_name>.*` file when the corresponding `<other_service_name>` is
also enabled in `compose.yaml` — `compose.yaml.template` places each
`<other_service_name>.*` include right next to the include of the service it
depends on (e.g. `services/obby/ergo.nginx.compose.yaml` sits beside
`services/ergo/compose.yaml`).

### Static-webapp services — no `compose.yaml`

Some services are **only static files** served by the shared nginx container
(`element-web`, `sveltemark`, `maarkdown-viewer`, `flotilla`, `obby`). They have
**no** `services/<service>/compose.yaml` — there is no app container of their own
— and they exist purely through their `nginx.*` files. They still follow the
`<other_service_name>.<file>` convention for everything else they integrate with,
and more can be added later — e.g. a `caddy.*` set the day `caddy` joins the repo
as an alternative shared proxy.

### Concrete example: `ergo` and `obby`

`ergo` is a self-contained IRC server — its directory has **no** extra
`<other_service_name>` files (no `nginx.*`, no `ipmonitor.*`), because it can be
advertised and listened on with nothing else around:

```text
services/ergo/
├── compose.yaml                 # the IRC server itself (services: ergo:)
├── ergo.yaml                    # rendered config (envsubst'd → /ircd/ircd.yaml)
├── ergo-todo.yaml               # alternate config (see README "Notes")
├── .env.template
└── README.md
```

`obby` is the mirror image: a **static web app** (no `compose.yaml` of its own)
that **consumes** both `nginx` (served through it) and `ergo` (so the client can
reach an IRC server). Its directory therefore carries files for both:

```text
services/obby/
├── nginx.compose.yaml          # obby's own nginx override (image mount + domain conf)
├── nginx.entrypoint.sh         # patches the static webapp at nginx start
├── nginx.envsubst.conf         # dirs for the nginx envsubst loop
├── nginx.http.domain.conf      # obby's HTTP domain/server block
├── nginx.location.conf         # obby's location fragment
├── ergo.nginx.compose.yaml     # pulls ergo into obby's nginx server list
├── ergo.server.json            # ergo server entry shown in the web client
└── ergo.server.todo.json       # (todo) ergo server entry
```

The naming mirrors the relationship:

- `nginx.*` → **about nginx** (obby → nginx), included whenever `obby` is turned
  on, because obby can't serve without nginx.
- `ergo.*` → **about ergo** (obby → ergo), only meaningful once
  `services/ergo/compose.yaml` is also enabled — without ergo the web client
  simply has no IRC server to connect to.

---

## 2. Quick start — run it locally

```bash
# 1. host-wide settings
cp .env.base{.template,}
vi .env.base                       # set MAIN_DOMAIN, HTTPS_PORT, (optional) SSL_CERT/SSL_CERT_PATH

# 2. pick the services you want (compose.yaml is the active, gitignored file)
cp compose.yaml{.template,}
vi compose.yaml                    # uncomment the services/<svc>/compose.yaml (+ nginx.compose.yaml etc.) lines

# 3. configure each service
cd services/<your-service>/
cp .env.template .env             # if a .env.template exists
vi .env                           # fill {FILL} placeholders, change ports if you must
cd ../..

# 4. export everything into your shell so Compose can interpolate ${...} vars
. prepare_env.sh

# 5. lift it
docker compose up -d
```

> Tip: `compose.yaml.template` already lists **every** service in the repo,
> commented out. To enable a service, `uncomment` its lines (the first path is
> always the service itself; `nginx.compose.yaml` adds the reverse-proxy config;
> `ipmonitor.compose.yaml` adds public-IP handling). You can also use the helper:
> `./tools/create_uncommented_composeyaml.sh --inplace -- compose.yaml` — but
> that uncomments **all** services, so prefer doing it by hand for just the ones
> you want.

---

## 3. How a service is "enabled"

A service is "on" when its `compose.yaml` (and, for proxied services, its
`nginx.compose.yaml`) is listed under `include: path:` in the active
`compose.yaml`. Each service directory contributes **zero or more** Compose
files that `include` into the root model:

| File (in a service dir)        | Role |
| ------------------------------ | ---- |
| `compose.yaml`                 | The service container itself. **Always included for a real service.** |
| `nginx.compose.yaml`           | Adds a bind-mount + env to the shared `nginx` service (HTTP reverse proxy). Include **after** `compose.yaml`. |
| `ipmonitor.compose.yaml`       | Wires the service to `ipmonitor` (shared volume + `depends_on` + `pid: service:ipmonitor`). |
| `nginx.env.template`           | (Rarely used.) Alternative: a per-service env file for the **nginx** container. Usually replaced by passing vars directly via `environment:` in `nginx.compose.yaml`. |
| `nginx.http.domain.conf`       | The nginx `location /` block for this service's domain (envsubst'd at nginx startup). |
| nested, e.g. `outbounds/vless/compose.yaml` | Sub-modules of a service (see `3xui`). |

Order matters in `include:` — list a service's `compose.yaml` first, then its
`nginx.compose.yaml`, then its `ipmonitor.compose.yaml`, because later files
**override/extend** the earlier ones (Compose merges includes in order).

---

## 4. Anatomy of a service directory

Every real service directory contains at minimum a `compose.yaml` that defines a
**service whose name equals the directory name** (e.g. `services/coturn/compose.yaml`
defines `services: coturn:`). The service container is referenced by other
services (notably nginx) using that exact name as the Docker hostname.

Files that commonly appear, and what each one does:

### `compose.yaml` — the service definition
- Defines `services: <service-name>:` (name == directory name).
- `image:` follows the pinning pattern:
  `${PREFIX_IMAGE_SRC:-<default>}:${PREFIX_IMAGE_TAG:-<default>}${PREFIX_IMAGE_DIGEST:-}`
- `env_file:` points at the service's own **unstripped** `.env` (see §6):
  ```yaml
  env_file:
    - path: ../<service>/.env        # the leading "../" is on purpose (see Gotchas)
      required: true
  ```
  Some services also load `../../.env.base` so base vars (`MAIN_DOMAIN`, `HTTPS_PORT`,
  `REAL_IP`) are available to `env_file` substitution.
- `environment:` passes runtime vars to the container. Service vars should come
  **from `.env`**: `FOO=${FOO:-default}` (so the value lives in `.env`, not hardcoded).
- `volumes:` bind-mount service config files as `...template` (envsubst'd at runtime
  by the service's own `command`/`entrypoint`), and persist app data under
  `../../data/<service>/:` (note the `../../` — see Gotchas).
- For UDP-heavy services that use `network_mode: "host"` (coturn, kubo, screego,
  livekit, autossh), add `userns_mode: "host"` too.

### `nginx.compose.yaml` — nginx reverse-proxy override (HTTP services only)
Extends the shared `nginx` service. It:
1. bind-mounts the service's `nginx.http.domain.conf` to
   `/etc/nginx/conf.d/domains/${PREFIX_DOMAIN}/${<service>}.conf.template`
   (under a directory named after `<PREFIX_DOMAIN>`; the filename is the
   service dir name + `.conf.template` — e.g. `coturn.conf.template`).
2. passes the few env vars the **nginx** container needs to render that conf
   via `environment:` (the nginx container only auto-loads `.env.base`, **not**
   your service `.env`, so list each var explicitly):
   ```yaml
   environment:
     - PREFIX_PORT=${PREFIX_PORT:-XXXX}
     - PREFIX_DOMAIN ${PREFIX_DOMAIN:-...}   # pass-through
   ```
   The commented `env_file: ../<service>/nginx.env` pattern is the older
   alternative; prefer `environment:` for clarity.

### `ipmonitor.compose.yaml` — public-IP integration (optional)
Adds the shared `/mnt/ipmonitor/temp` volume to your service container and
declares `pid: "service:ipmonitor"` + `depends_on: ipmonitor: condition: service_healthy`.
Include it **after** the service and (optionally) nginx compose files.

### `nginx.http.domain.conf` — the nginx HTTP block
This file becomes a `server {}` `include` fragment. Use `$VAR` / `${VAR}` for
vars you want **envsubst'd** at nginx startup, and `$$<something>` for vars
that are **nginx-native** (`$$host` → `$host`, `$$http_upgrade` → `$http_upgrade`,
`$$remote_addr` → `$remote_addr`, `$$uri` → `$uri`, etc.).

### `*.conf` / `*.toml` / `*.json` config files in the service dir
Mounted read-only into the container with a `.template` suffix and rendered at
startup by `go-envsubst -no-unset -no-empty -i src.template -o dest`. They use
`${PREFIX_VAR}` references (e.g. `strfry.conf` uses `${STRFRY_PORT}`).

### `*.sh` — init/entrypoint scripts
Mounted to `/docker-entrypoint.d/*.sh` (runs in the **nginx** container before
nginx starts — used by `localsend`, `obby`) or used as the container's
`entrypoint`/`command`.

### `Dockerfile` (rare)
Only `turn-rs` has one — for building a custom image from a local Dockerfile.

---

## 5. Naming convention for files

| File name pattern | Meaning / rule |
| ----------------- | -------------- |
| `compose.yaml`    | **Required** for a real service. Service name inside == directory name. |
| `nginx.compose.yaml` | nginx override. Name is literally `nginx.compose.yaml` for **every** service (not `<svc>.compose.yaml`). |
| `nginx.http.domain.conf` | nginx HTTP fragment. Literal name for every HTTP service. |
| `nginx.stream.conf` | nginx stream fragment (TCP/TLS), e.g. `telemt`. |
| `nginx.upstream.conf` | nginx upstream fragment, e.g. `continuwuity`. |
| `nginx.<thing>.location.conf` | nginx location-level fragments pulled in by an http domain conf, e.g. `obby/nginx.obby.location.conf`. |
| `nginx.<thing>.server.json` | JSON snippet, e.g. `obby/nginx.obby.server.json`. |
| `nginx.<thing>.compose.yaml` | (Optional) **extra** nginx override whose source files live in a *different* service dir than the one they configure — e.g. `obby/nginx.ergo.compose.yaml` adds ergo to obby's server list. Include **after** that service's own `nginx.compose.yaml`. |
| `nginx.envsubst.conf` | List of directories the nginx container should run `go-envsubst` over (space for your service-owned config dirs, e.g. `obby` lists `/etc/obby/servers.d`). |
| `nginx.env.template` | **Deprecated/rarely used.** A per-service env file **for the nginx container**. Most services instead pass vars via `environment:` in `nginx.compose.yaml`. If you use it, the runtime file is `nginx.env` and it is **not** auto-loaded (the `env_file:` line is commented out by convention). |
| `.env.template` | The **template** of the service's env file. The configured copy is `.env` (GITIGNORED via `*.env`). Start with a comment `# <Human Name> Settings` then `PREFIX_...` vars. |
| `ipmonitor.compose.yaml` | Literal name for the ipmonitor integration file. |
| `flotilla.<list>.conf` | Nostr services register relays with `flotilla` by dropping a conf into `/etc/flotilla/<list>.d/<svc>.conf.template`. |
| `container-startup.sh` | e.g. `kubo`. |
| `README.md` | **Required.** At minimum: `# Intro`, `# Status`, and a `# TODO` (or `# Note`) section. Copy the structure of an existing one. |

---

## 6. Naming convention for environment variables

> This is the convention you asked for — `<SERVICE_NAME_UPPERCASE_WITH_HYPHENS (and spaces) REMOVED>` as the prefix.

Take the **service directory name**, convert to **UPPER_CASE**, and **remove hyphens/spaces** (but keep digits — a variable name may not, however, start with a digit, so a leading digit is replaced, see `3xui`).

### Canonical examples (prefix derivation)

| Service dir | Prefix | Notes |
| ----------- | ------ | ----- |
| `forgejo`            | `FORGEJO_`         |
| `coturn`             | `COTURN_`          |
| `microbin`           | `MICROBIN_`        |
| `pairdrop`           | `PAIRDROP_`        |
| `livekit`            | `LIVEKIT_`         |
| `strfry`             | `STRFRY_`          |
| `zooid`              | `ZOOID_`           |
| `ergo`               | `ERGO_`            |
| `obby`               | `OBBY_`            |
| `kubo`               | `KUBO_`            |
| `telemt`             | `TELEMT_`          |
| `sveltemark`         | `SVELTEMARK_`      |
| `dufs`               | `DUFS_`            |
| `element-web`        | `ELEMENTWEB_`      | hyphen removed |
| `sni-spoofing-rust`  | `SNISPOOFINGRUST_` | all hyphens removed |
| `fortivpn-to-socks5` | `FORTIVPNTOSOCKS_`   | (deviation — see Gotchas) |
| `hermes-webui`       | `HERMES_WEBUI_`      | (deviation — see Gotchas) |
| `3xui`               | `XUI_`               | leading digit → `X` prefix; same for image vars `XUI_IMAGE_*` |

**Two deviation notes** (match what the existing service already uses):
- `fortivpn-to-socks5` uses `FORTIVPNTOSOCKS_*` in `.env` (dropped the trailing `5`)
  while its image vars are `FORTIVPNSOCKS5_IMAGE_*`. Keep both as they are.
- `hermes-webui` uses `HERMES_WEBUI_*` in `.env` (underscore kept) while its image
  vars are `HERMESWEBUI_IMAGE_*`. Keep as is.

### Standard suffixes / "known" variable names

Within a prefix, the following suffixes are used consistently — **reuse them
rather than inventing new ones**:

| Suffix | Meaning | Example |
| ------ | ------- | ------- |
| `_DOMAIN` | Full domain (almost always `<svc>.${MAIN_DOMAIN}` or `main.${MAIN_DOMAIN}`). Also doubles as the nginx domain path. | `FORGEJO_DOMAIN=git.${MAIN_DOMAIN}` |
| `_PORT` | **Container's** listen port (the second colon target in `-p HOST:CONT:). Often == the app's internal port. | `FORGEJO_PORT=3003` |
| `_BIND` | Host bind address. Default `127.0.0.1` (loopback only) unless the service must be reached directly (e.g. behind another proxy). | `FORGEJO_BIND` (unused) , `PAIRDROP_BIND` |
| `_IMAGE_SRC` | Image repo/path (pinned in `images.env`). | `FORGEJO_IMAGE_SRC` |
| `_IMAGE_TAG` | Image tag (pinned in `images.env`). | `FORGEJO_IMAGE_TAG` |
| `_IMAGE_DIGEST` | Image digest `@sha256:...` (pinned in `images.env`). | `FORGEJO_IMAGE_DIGEST` |
| `_ROOT` | nginx html root for static-webapp services. | `OBBY_ROOT=/srv/http/Obby` |
| `_PATH_PREFIX` | nginx/web path prefix for path-based proxying. | `XUI_PATH_PREFIX` |
| `_EXTERNAL_IP` | Public IP (set from `ipmonitor` or `PUBLIC_IP`/`REAL_IP`). | `COTURN_EXTERNAL_IP` |
| `_STATIC_AUTH_SECRET` / `_SECRET` | Shared secrets. Use `{FILL}` placeholder in `.env.template`. | `COTURN_STATIC_AUTH_SECRET="{FILL}"` |

### Image variables live in `images.env`, NOT in the service `.env`
For **every** image (yours + helpers) there are three lines in `images.env`:
`<PREFIX>_IMAGE_SRC`, `<PREFIX>_IMAGE_TAG`, `<PREFIX>_IMAGE_DIGEST`.
Reference them in `compose.yaml` exactly like this:
```yaml
image: ${FORGEJO_IMAGE_SRC:-kleen/forgejo}:${FORGEJO_IMAGE_TAG:-latest}${FORGEJO_IMAGE_DIGEST:-}
```
- `_SRC` is what Renovate tracks as the dependency; `_TAG` is the version Renovate
  proposes to bump; `_DIGEST` pins to an immutable digest.
- After adding a service, run `./tools/create_images_env.sh` (or add the three
  lines by hand) so `images.env` and Renovate know about your image.
- Helper images reused across services (`ENVSUBST_IMAGE_*`, `BUSYBOX_IMAGE_*`,
  `JQ_IMAGE_*`, `NGINX_IMAGE_*`, `ALPINE_IMAGE_*`) **already exist** in
  `images.env` — reuse them, don't re-declare.

### Internal/derived variables
Variables that only exist to build another variable use a **leading underscore**
(private helper). e.g. in `livekit/.env.template`:
```env
_LIVEKIT_KEY="{FILL}"
_LIVEKIT_SECRET="{FILL}"
LIVEKIT_KEYS="${_LIVEKIT_KEY}: ${_LIIveKIT_SECRET}"
```
They are still loaded by `prepare_env.sh` (it globs all `.env*`), and they can
be referenced by other lines in the same `.env` via `${_VAR}`.

### Base / shared variables (from `.env.base`)
These are host-wide, not prefixed:
`MAIN_DOMAIN`, `REAL_IP`, `HTTP_PORT` (80), `HTTPS_PORT` (443).
You may also see `SSL_CERT`, `SSL_CERT_KEY`, `SSL_CERT_PATH`, `SSL_CERT_KEY_PATH`,
`GHCR_MIRROR`, `PUBLIC_IP`. Reference them directly (no prefix): `${MAIN_DOMAIN}`,
`${HTTPS_PORT}`.

---

## 7. The envsubst / templating mechanism

You will almost always mount a config file with a **`.template`** suffix and
render it at container start. Two renderers are used:

### 7a. Per-service `go-envsubst` (the "app" container)
Your `command`/`entrypoint` runs:
```sh
go-envsubst -no-unset -no-empty -i /path/to/foo.conf.template -o /path/to/foo.conf
exec <your-app> ...
```
- `-no-unset` → fail if a referenced var is missing (catches typos early).
- `-no-empty` → don't error on empty vars; they render as empty string.
- Always mount the go-envsubst binary via the shared image:
  ```yaml
  - type: image
    source: ${ENVSUBST_IMAGE_SRC:-ghcr.io/yasn77/envsubst-image}:${ENVSUBST_IMAGE_TAG:-1.4.2}${ENVSUBST_IMAGE_DIGEST:-}
    target: /usr/local/bin/go-envsubst
    image:
      subpath: usr/bin/envsubst
  ```
- Mount your config to `.../something.conf.template` (note `.template`).

### 7b. The nginx global envsubst loop (the "nginx" container)
The nginx `compose.yaml` `command:` loops over every directory listed in
`services/nginx/envsubst.conf`:
```
/etc/nginx/conf.d/
/etc/nginx/stream.d/
/etc/nginx/upstream.d/
/etc/nginx/snippet.d/
```
and runs `go-envsubst` on every `*.template` file found under them.

**This is the key consequence for HTTP services:** any file you bind-mount into
`nginx.compose.yaml` whose path ends in `.conf.template` and lives under one of
those four directories will be auto-rendered at nginx startup. That is exactly
what every `nginx.http.domain.conf` mount does:
```yaml
target: /etc/nginx/conf.d/domains/${PREFIX_DOMAIN}/${service}.conf.template
```
→ lives under `/etc/nginx/conf.d/` → gets envsubst'd → nginx `include`s the
resulting `/etc/nginx/conf.d/domains/<DOMAIN>/<service>.conf`.

### 7c. `$$` vs `$` inside nginx config files
This is the most commonly tripped rule:

- **`$VAR` / `${VAR}`** (single `$`) → replaced by envsubst with the variable's
  value (these are YOUR env vars: `$FORGEJO_PORT`, `$OBBY_ROOT`…).
- **`$$VAR`** (double `$`) → a **literal** nginx variable that must survive
  substitution: `$$host` → `$host`, `$$http_upgrade` → `$http_upgrade`,
  `$$remote_addr` → `$remote_addr`, `$$uri` → `$uri`, `$$scheme` → `$scheme`.

So a typical proxied HTTP domain conf looks like:
```nginx
location / {
  proxy_pass http://forgejo:$FORGEJO_PORT;          # envsubst'd
  proxy_set_header Host $$host;                     # nginx-native
  proxy_set_header X-Real-IP $$remote_addr;
  proxy_set_header X-Forwarded-For $$proxy_add_x_forwarded_for;
  proxy_set_header X-Forwarded-Proto $$scheme;
  proxy_http_version 1.1;
  proxy_set_header Upgrade $$http_upgrade;
  proxy_set_header Connection "upgrade";
}
```

---

## 8. Adding a new service — step by step

> Example service name: `neostarter` (a hypothetical pastebin). Prefix would be
> `NEOSTARTER_`.

1. **Create the directory:** `services/neostarter/`
2. **Create `compose.yaml`** (copy from `forgejo/compose.yaml` — the simplest
   good example — or `microbin/compose.yaml` for env-heavy apps):
   ```yaml
   services:
     neostarter:
       image: ${NEOSTARTER_IMAGE_SRC:-ghcr.io/your/neostarter}:${NEOSTARTER_IMAGE_TAG:-latest}${NEOSTARTER_IMAGE_DIGEST:-}
       restart: unless-stopped
       ports:
         - "${NEOSTARTER_BIND:-127.0.0.1}:${NEOSTARTER_PORT:-8003}:${NEOSTARTER_PORT:-8003}"
       volumes:
         - ../../data/neostarter:/data          # app data (persistent)
       env_file:
         - path: ../neostarter/.env
           required: true
       environment:
         - NEOSTARTER_BIND=0.0.0.0              # whatever the app expects
       # (if the app needs go-envsubst on a config file, add the binary + entrypoint, see §4)
   ```
   - Service name inside `services:` **must equal the directory name** (`neostarter`).
   - Paths going back to the repo root are `../../` (e.g. `../../data/...`),
     and pointing at sibling files in your own dir is `../neostarter/...` — see Gotchas.
3. **Create `.env.template`:**
   ```env
   # Neostarter Settings
   NEOSTARTER_DOMAIN=neostarter.${MAIN_DOMAIN}
   NEOSTARTER_PORT=8003
   # secrets
   NEOSTARTER_SECRET="{FILL}"
   ```
   - First line: `# <Human Readable Name> Settings`.
   - One var per line. Secrets use `{FILL}`.
4. **Create `README.md`** (copy structure):
   ```markdown
   # Intro
   One-line description + upstream link.

   # Status
   (pick one: good / ok / Seems ok / not enough tested but seems ok /
   underconstruction / not stable enough)

   # Note / TODO
   Anything a user/maintainer needs to know.
   ```
5. **Add image pins to `images.env`:** `NEOSTARTER_IMAGE_SRC/TAG/DIGEST`.
   Run `./tools/create_images_env.sh` to (re)generate it cleanly, OR add by hand
   in the same `<SPACE>_IMAGE_*` shape, grouped in alphabetical order by prefix.
6. **Register in `compose.yaml.template`:** add (usually) two lines under the
   appropriate category comment:
   ```yaml
   #- services/neostarter/compose.yaml
   #- services/neostarter/nginx.compose.yaml
   ```
   (The template is the catalogue of all services; leave them commented until
   you want to enable them.)
7. **Enable + configure locally** (see §2): copy templates to real names,
   `vi .env` / `.env.base`, `. prepare_env.sh`, `docker compose up -d`.

---

## 9. Adding a new service behind nginx (HTTP)

If your service speaks HTTP and you want nginx to terminate SSL and proxy to it:

1. Do steps 1–7 above, **plus**:
2. **Create `nginx.compose.yaml`** (copy `forgejo/nginx.compose.yaml`):
   ```yaml
   services:
     nginx:
       volumes:
         - type: bind
           source: ../neostarter/nginx.http.domain.conf
           target: /etc/nginx/conf.d/domains/${NEOSTARTER_DOMAIN}/neostarter.conf.template
           read_only: true
           bind:
             create_host_path: false
       environment:
         - NEOSTARTER_PORT=${NEOSTARTER_PORT:-8003}
   ```
   - Mount target path is **always**
     `/etc/nginx/conf.d/domains/${<PREFIX>_DOMAIN}/<service-dir-name>.conf.template`
     (that's what the nginx loop envsubst's and includes).
   - `environment:` lists **only the vars the nginx conf references** (e.g.
     `NEOSTARTER_PORT`). The nginx container does **not** load your service
     `.env`, so pass each needed var explicitly.
3. **Create `nginx.http.domain.conf`** (copy `forgejo/nginx.http.domain.conf` /
   `microbin/nginx.http.domain.conf`). Use `$NEOSTARTER_PORT` (envsubst) and
   `$$host`/`$$http_upgrade`/`$$remote_addr`/`$$scheme` (nginx-native, double `$`).
4. **In `compose.yaml`**, don't forget to `depends_on: - neostarter` in the nginx
   override **only if** nginx must start after the app (usually not required
   thanks to nginx `try_files`/proxy, but harmless).
5. **Enable** both `neostarter/compose.yaml` and `neostarter/nginx.compose.yaml`
   in `compose.yaml`.

---

## 10. Static-webapp services (no app container)

Some services are just static files served directly by nginx (e.g. `element-web`,
`sveltemark`, `maarkdown-viewer`, and `flotilla`/`obby` which ship a webapp).
For these:

- **No** `services/<svc>/compose.yaml` (no container). Only `nginx.compose.yaml`.
- `nginx.compose.yaml` bind-mounts the **image** (via `type: image`) to the
  configured `${<PREFIX>_ROOT}` and adds the http domain conf + env:
  ```yaml
  services:
    nginx:
      volumes:
        - type: image
          source: ${ELEMENTWEB_IMAGE_SRC:-vectorim/element-web}:${ELEMENTWEB_IMAGE_TAG:-latest}${ELEMENTWEB_IMAGE_DIGEST:-}
          target: ${ELEMENTWEB_ROOT:-/srv/http/element-web}
          image:
            subpath: app/          # the subpath inside the image containing the files
        - type: bind
          source: ../element-web/nginx.http.domain.conf
          target: /etc/nginx/conf.d/domains/${ELEMENTWEB_DOMAIN}/element-web.conf.template
          ...
      environment:
        - ELEMENTWEB_ROOT=${ELEMENTWEB_ROOT:-/srv/http/element-web}
  ```
- The http domain conf uses `root ${ELEMENTWEB_ROOT};` (envsubst'd) so nginx
  serves the mounted files.
- If the static app needs runtime patching (e.g. localsend rewrites a hardcoded
  WebSocket URL, obby merges server-list JSON), mount a script to
  `/docker-entrypoint.d/<svc>.sh` — the official nginx image runs everything in
  that directory (sorted) before starting nginx.

---

## 11. Services that need the public IP (`ipmonitor`)

Services whose app needs to know the host's public IP (coturn, kubo, livekit)
should integrate with the shared `ipmonitor` service:

1. Add `ipmonitor.compose.yaml`:
   ```yaml
   services:
     <service>:
       volumes:
         - type: bind
           source: ../../temp/ipmonitor
           target: /mnt/ipmonitor/temp
           read_only: true
           bind:
             create_host_path: true
       environment:
         # read this in your entrypoint to decide whether to use ipmonitor
         IPMONITOR_IS_ENABLED: true
       pid: "service:ipmonitor"
       depends_on:
         ipmonitor:
           condition: service_healthy
   ```
2. In the app container's `command`, read `/mnt/ipmonitor/temp/ipv4.txt`:
   ```sh
   IP="$$(cat /mnt/ipmonitor/temp/ipv4.txt || true)"
   [ -n "$$IP" ] && export COTURN_EXTERNAL_IP="$$IP"
   ```
3. Enable `ipmonitor/compose.yaml` and `<svc>/ipmonitor.compose.yaml` in
   `compose.yaml`. (`ipmonitor` itself is enabled by uncommenting
   `services/ipmonitor/compose.yaml`.)

---

## 12. Secrets & placeholders

- **Never commit secrets.** `.env` files and `.env.base` are GITIGNORED
  (`*.env` in `.gitignore`, `/.env.base` in `.gitignore`). Only `*.env.template`
  files (with `{FILL}` placeholders) are tracked.
- Secrets live in the service `.env` and are consumed two ways:
  - **Compose-level**: `env_file: ../<svc>/.env` + `environment: FOO=${FAKE_SECRET:-}`.
  - **Templated config-level**: the config file references `${FOO}` and is
    rendered by `go-envsubst`. **Do not** put secrets in tracked config files.
- SSL cert/key for nginx come from `.env.base` as `SSL_CERT` / `SSL_CERT_KEY`
  (loaded by `prepare_env.sh`, exposed to containers via the `secrets:` block).
  The `ssl_certificate`/`ssl_certificate_key` secret is declared in each
  service's `compose.yaml` (or via `snippets/ssl.yaml`) and referenced as
  `/run/secrets/fullchain.pem` & `/run/secrets/privkey.pem` inside the container.
- Use `{FILL}`, `{FILL-hex-value}`, `{FILL-uuid}` etc. as obvious placeholders
  in `.env.template` so humans know to replace them.

---

## 13. Image pinning & Renovate

- **One source of truth for images:** `images.env`, with `<PREFIX>_IMAGE_SRC`,
  `_IMAGE_TAG`, `_IMAGE_DIGEST` per image (yours + shared helpers).
- `compose.yaml` image lines use defaults that fall back to the pinned values:
  `${FORGEJO_IMAGE_SRC:-kleen/forgejo}:${FORGEJO_IMAGE_TAG:-latest}${FORGEJO_IMAGE_DIGEST:-}`.
  When `images.env` is loaded (by `prepare_env.sh` sourcing, or by Compose
  auto-loading `.env`/root env), the pinned values win.
- **To add an image:** add the three `_IMAGE_*` lines to `images.env`, then
  `docker compose pull` to fetch + verify.
- **Renovate** (`renovate.json5` + `.github/workflows/renovate.yaml`) runs the
  custom regex manager against `images.env` and PRs tag bumps + digest updates.
  `tools/create_images_env.sh` regenerates the file from
  `docker compose config --variables`; `tools/pin_image_tags.sh` converts
  floating tags (latest, stable) into fixed version tags.

---

## 14. Common pitfalls & gotchas

- **`../<svc>/` path quirk.** Compose's first file's directory is the working
  base, so a service's `nginx.compose.yaml` mount source `../<svc>/...` is
  correct, but references to the repo root are `../../` (e.g. `../../data/...`).
  You cannot rename a service directory or move it out of `services/` without
  updating every path.
- **The nginx container does NOT load your service `.env`.** It only loads
  `.env.base`. So in `nginx.compose.yaml` pass every env var the nginx conf
  needs via `environment:` — do **not** assume `${MYVAR}` is available in the
  nginx conf just because it's in your `.env`.
- **`$$` for nginx-native vars.** Forgetting the double-`$` makes envsubst eat
  the var and nginx breaks (e.g. writing `$host` instead of `$$host`).
- **Service name == directory name == Compose service name == nginx hostname.**
  Three places must agree; keep them identical.
- **`3xui` → `XUI`.** Service/container name stays `3xui`, but variable **and**
  image prefixes are `XUI_` (env var names may not start with a digit).
- **`.env` is never committed.** Always edit/copy the `.template` files.
  `prepare_env.sh` globs `services/*/.env*` (excluding `*.template`, `.env.base`,
  `.env.bak`) and exports them — if `.env` doesn't exist, Compose interpolation
  of `${PREFIX_...}` silently falls back to the `:-defaults` in `compose.yaml`.
- **UDP / host networking.** Services needing many UDP ports or stable public IP
  (coturn, kubo, livekit, screego) use `network_mode: "host"` **plus**
  `userns_mode: "host"` (required when Docker daemon runs with userns-remap).
- **Bind to loopback by default.** Exposed `ports:` use `${PREFIX_BIND:-127.0.0.1}`
  so services are not published until nginx proxies to them.
- **Helper images are shared.** Reuse `ENVSUBST_IMAGE_*`, `BUSYBOX_IMAGE_*`,
  `JQ_IMAGE_*` from `images.env` instead of re-declaring them.

---

## 15. Templates you can copy

The fastest way to add a service is to copy a neighbour and rename. These are
the best "starter" templates depending on your service type:

| Want to… | `cp -r` this service, then strip |
| -------- | --------------------------------- |
| A simple HTTP app behind nginx | `services/forgejo` (smallest good example; has `.env.template`, `compose.yaml`, `nginx.compose.yaml`, `nginx.http.domain.conf`, `README.md`) |
| An env-heavy app behind nginx, with secrets | `services/livekit` (lots of env vars, secrets, domain conf) |
| A static webapp served by nginx (image only) | `services/element-web` (image mount + root + http conf, no app container) |
| A service needing ipmonitor (public IP) | `services/coturn` (host-network + ipmonitor + go-envsubst on a config) |
| A service with no nginx/frontend, just a container + config | `services/strfry` (bind-mount a `.conf.template`, render with `go-envsubst`, run app) |
| A service with **secrets in the config file** that must be envsubst'd | `services/zooid` (TOML config w/ `${VAR}` refs, rendered then run) |
| A service that patches a static webapp at nginx start | `services/localsend` (mount `nginx.entrypoint.sh` to `/docker-entrypoint.d/`) |

Remember, after copying: rename `services/<old>/` → `services/<new>/`, rename
the `services:` key inside `compose.yaml` (and inside every `*.compose.yaml`),
replace every occurrence of `<OLD>` → `<NEW>` in prefixes, and update
`compose.yaml.template` + `images.env`.

---

Happy hacking. If something in this file disagrees with the actual code, the
code wins — fix the code **and** this file.
