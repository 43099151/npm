# ==========================================
# 阶段 1: 下载工具 (使用纯净 Debian 环境)
# ==========================================
FROM debian:bookworm-slim AS builder

# 安装下载工具
RUN apt-get update && apt-get install -y curl tar unzip

# 1. 下载 Tailscale (静态二进制)
WORKDIR /tmp/tailscale
RUN curl -fsSL "https://pkgs.tailscale.com/stable/tailscale_1.92.5_amd64.tgz" -o tailscale.tgz && \
    tar -xzf tailscale.tgz && \
    mv tailscale_1.92.5_amd64/tailscale /tmp/tailscale/tailscale && \
    mv tailscale_1.92.5_amd64/tailscaled /tmp/tailscale/tailscaled

# 2. 下载 Rclone (静态二进制)
WORKDIR /tmp/rclone
RUN curl -fsSL "https://downloads.rclone.org/v1.72.1/rclone-v1.72.1-linux-amd64.zip" -o rclone.zip && \
    unzip rclone.zip && \
    mv rclone-v1.72.1-linux-amd64/rclone /tmp/rclone/rclone

# ==========================================
# 阶段 2: 构建最终镜像 (极简策略)
# ==========================================
FROM jc21/nginx-proxy-manager:latest

# 1. 必须切回 Root 用户，否则无法安装
USER root
ENV DEBIAN_FRONTEND=noninteractive

# 2. 极简安装逻辑
# 不去猜测 Debian 版本，只删除会导致超时的第三方源 (.d/*)
# 直接使用镜像自带的 sources.list (它肯定是匹配当前系统的)
RUN rm -rf /etc/apt/sources.list.d/* && \
    rm -rf /var/lib/apt/lists/* && \
    apt-get update && \
    apt-get install -y --no-install-recommends \
        openssh-server \
        socat \
        iptables \
        iproute2 \
        ca-certificates \
        && \
    mkdir -p /var/run/sshd && \
    sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin yes/' /etc/ssh/sshd_config && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

# 从构建阶段复制文件
COPY --from=builder /tmp/tailscale/tailscale /usr/bin/tailscale
COPY --from=builder /tmp/tailscale/tailscaled /usr/bin/tailscaled
COPY --from=builder /tmp/rclone/rclone /usr/bin/rclone

# 赋予权限
RUN chmod +x /usr/bin/tailscale /usr/bin/tailscaled /usr/bin/rclone

# 复制脚本
COPY scripts/start.sh /usr/local/bin/start.sh
COPY scripts/backup.sh /usr/local/bin/backup.sh
RUN chmod +x /usr/local/bin/start.sh /usr/local/bin/backup.sh

# 端口和入口
EXPOSE 7860 80 81 443
ENTRYPOINT ["/usr/local/bin/start.sh"]
