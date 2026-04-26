FROM debian:bookworm AS builder
COPY 
FROM debian:bookworm-slim
COPY /opt/turn-server /usr/local/bin/turn-server
COPY turn-server.toml /etc/turn-server/config.toml
CMD turn-server --config=/etc/turn-server/config.toml
