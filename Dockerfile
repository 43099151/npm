############################
# Stage 1: build NPM
############################
FROM node:20-alpine AS build

RUN apk add --no-cache \
    bash \
    curl \
    ca-certificates \
    tzdata \
    python3 \
    make \
    g++ \
    sqlite \
    openssl \
    unzip

WORKDIR /app

RUN curl -fsSL https://github.com/NginxProxyManager/nginx-proxy-manager/archive/refs/heads/develop.tar.gz \
    | tar xz --strip-components=1

RUN npm install --production \
    && npm cache clean --force \
    && rm -rf /root/.npm /root/.cache /tmp/*

############################
# Stage 2: runtime
############################
FROM node:20-alpine

ENV TS_SOCKET=/tmp/tailscaled.sock
ENV NPM_HOME=/data/npm

RUN apk add --no-cache \
    bash \
    ca-certificates \
    tzdata \
    sqlite \
    openssl \
    cron \
    tar \
    gzip

# Tailscale (static)
RUN wget -qO- https://pkgs.tailscale.com/stable/tailscale-linux-amd64.tgz \
    | tar xz \
    && mv tailscale*/tailscale* /usr/local/bin/ \
    && rm -rf tailscale*

# rclone (static)
RUN wget -qO- https://downloads.rclone.org/rclone-current-linux-amd64.zip \
    | unzip -q - \
    && mv rclone*/rclone /usr/bin/rclone \
    && chmod +x /usr/bin/rclone \
    && rm -rf rclone*

COPY --from=build /app /app

RUN mkdir -p \
    /data/npm \
    /data/tailscale \
    /data/rclone \
    /backup \
    /scripts

COPY entrypoint.sh /scripts/
COPY backup.sh /scripts/
COPY restore.sh /scripts/
COPY rclone.conf.template /data/rclone/rclone.conf

RUN chmod +x /scripts/*.sh

EXPOSE 7860

WORKDIR /app
ENTRYPOINT ["/scripts/entrypoint.sh"]
