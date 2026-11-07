# syntax=docker/dockerfile:1

# Build the Vite/React SPA.
# Pinned patch-level tag per Semgrep node-brotli-usage (CVE-2026-111497 fix is
# in 22.23.4); keep in sync with upgrades.
FROM node:22.23.4-alpine AS build

WORKDIR /src
COPY package.json package-lock.json* ./
RUN npm ci
COPY . .
RUN npm run build

# Publish the static files onto a shared volume: the container copies its
# build output to /srv and keeps running, and the Caddy service mounts the
# same named volume to serve the files. A rebuild republishes on start.
FROM alpine:3.21

COPY --from=build /src/dist /www
CMD ["sh", "-c", "rm -rf /srv/* 2>/dev/null; mkdir -p /srv; cp -a /www/. /srv/; exec sleep infinity"]
