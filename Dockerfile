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

# 1. 安装核心依赖（注意加入了 wget, nginx, apache2-utils）
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
    apache2-utils \
    wget

# 2. 安装 Tailscale（分步执行，去掉了 -q 以便看到下载进度和错误）
# 如果这一步报错，说明您的构建环境无法连接 pkgs.tailscale.com
RUN wget https://pkgs.tailscale.com/stable/tailscale_1.92.5_amd64.tgz -O /tmp/tailscale.tgz \
    && tar xzf /tmp/tailscale.tgz -C /tmp \
    && mv /tmp/tailscale*/tailscale /usr/local/bin/tailscale \
    && mv /tmp/tailscale*/tailscaled /usr/local/bin/tailscaled \
    && rm -rf /tmp/tailscale* /tmp/tailscale.tgz

# 3. 安装 Rclone
RUN wget https://downloads.rclone.org/rclone-current-linux-amd64.zip -O /tmp/rclone.zip \
    && unzip -q /tmp/rclone.zip -d /tmp \
    && mv /tmp/rclone*/rclone /usr/bin/rclone \
    && chmod +x /usr/bin/rclone \
    && rm -rf /tmp/rclone*

COPY --from=build /app /app

# 4. 创建必要的目录
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
# 如果您本地没有 rclone.conf.template，请注释掉下面这行
# COPY rclone.conf.template /data/rclone/rclone.conf 

RUN chmod +x /scripts/*.sh

EXPOSE 81 443 7860

WORKDIR /app
ENTRYPOINT ["/scripts/entrypoint.sh"]
