############################
# Stage 1: build NPM
############################
FROM node:20-alpine AS build

# ... (Stage 1 保持不变) ...
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

# 注意：使用 develop 分支可能不稳定，建议锁定版本
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

# 修复点 1: cron -> dcron
# 修复点 2: 添加 unzip (后面解压 rclone 需要)
# 修复点 3: 添加 nginx, apache2-utils (NPM 核心依赖)
RUN apk add --no-cache \
    bash \
    ca-certificates \
    tzdata \
    sqlite \
    openssl \
    iptables \
    dcron \
    tar \
    gzip \
    unzip \
    nginx \
    apache2-utils

# Tailscale (static)
RUN wget -qO- https://pkgs.tailscale.com/stable/tailscale-linux-amd64.tgz \
    | tar xz \
    && mv tailscale*/tailscale* /usr/local/bin/ \
    && rm -rf tailscale*

# rclone (static)
# 这里之前会报错，因为上面补全了 unzip，现在可以通过了
RUN wget -qO- https://downloads.rclone.org/rclone-current-linux-amd64.zip \
    | unzip -q - \
    && mv rclone*/rclone /usr/bin/rclone \
    && chmod +x /usr/bin/rclone \
    && rm -rf rclone*

COPY --from=build /app /app

# 创建 Nginx 需要的运行目录，防止启动报错
RUN mkdir -p \
    /data/npm \
    /data/tailscale \
    /data/rclone \
    /backup \
    /scripts \
    /run/nginx \
    /var/tmp/nginx

COPY entrypoint.sh /scripts/
COPY backup.sh /scripts/
COPY restore.sh /scripts/
# 确保这个文件在你本地存在，或者删除这行
COPY rclone.conf.template /data/rclone/rclone.conf 

RUN chmod +x /scripts/*.sh

# 你暴露的是 7860 端口 (Hugging Face常用端口)
# 记得在 entrypoint.sh 里配置 NPM 监听这个端口，否则默认是 81
EXPOSE 7860

WORKDIR /app
ENTRYPOINT ["/scripts/entrypoint.sh"]
