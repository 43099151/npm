# ==========================================
# 阶段 1: 下载工具 (使用干净的 Debian 镜像)
# ==========================================
FROM debian:bullseye-slim AS builder

# 安装下载工具
RUN apt-get update && apt-get install -y curl tar unzip

# 1. 下载并解压 Tailscale (静态二进制)
WORKDIR /tmp/tailscale
# 使用你指定的版本
RUN curl -fsSL "https://pkgs.tailscale.com/stable/tailscale_1.92.5_amd64.tgz" -o tailscale.tgz && \
    tar -xzf tailscale.tgz && \
    mv tailscale_1.92.5_amd64/tailscale /tmp/tailscale/tailscale && \
    mv tailscale_1.92.5_amd64/tailscaled /tmp/tailscale/tailscaled

# 2. 下载并解压 Rclone
WORKDIR /tmp/rclone
# 使用最新的 1.72.1
RUN curl -fsSL "https://downloads.rclone.org/v1.72.1/rclone-v1.72.1-linux-amd64.zip" -o rclone.zip && \
    unzip rclone.zip && \
    mv rclone-v1.72.1-linux-amd64/rclone /tmp/rclone/rclone

# ==========================================
# 阶段 2: 构建最终镜像 (基于 NPM)
# ==========================================
FROM jc21/nginx-proxy-manager:latest

# 【关键点 1】强制 Root 权限
USER root

# 设置非交互模式
ENV DEBIAN_FRONTEND=noninteractive

# 【关键点 2】使用 Bullseye 源 (Debian 11) 以匹配基础镜像
# 同时清理 OpenResty 等可能导致超时的第三方源
RUN echo "Running atomic install script..." && \
    # 1. 清除锁文件 (防止之前的构建残留锁死 dpkg)
    rm -f /var/lib/dpkg/lock* && \
    rm -f /var/cache/apt/archives/lock && \
    rm -f /var/lib/apt/lists/lock && \
    # 2. 移除不稳定的第三方源
    rm -rf /etc/apt/sources.list.d/* && \
    rm -rf /var/lib/apt/lists/* && \
    # 3. 写入 Bullseye 官方源 (使用 http 避免 https 证书问题，Debian 官方支持 http)
    echo "deb http://deb.debian.org/debian bullseye main contrib non-free" > /etc/apt/sources.list && \
    echo "deb http://deb.debian.org/debian-security bullseye-security main contrib non-free" >> /etc/apt/sources.list && \
    echo "deb http://deb.debian.org/debian bullseye-updates main contrib non-free" >> /etc/apt/sources.list && \
    # 4. 更新并安装 (增加 --allow-releaseinfo-change 以防源元数据变动)
    apt-get update --allow-releaseinfo-change && \
    apt-get install -y --no-install-recommends \
        openssh-server \
        cron \
        socat \
        iptables \
        iproute2 \
        ca-certificates \
        && \
    # 5. 配置 SSH
    mkdir -p /var/run/sshd && \
    sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin yes/' /etc/ssh/sshd_config && \
    # 6. 清理
    apt-get clean && \
    rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

# 从构建阶段复制二进制文件
COPY --from=builder /tmp/tailscale/tailscale /usr/bin/tailscale
COPY --from=builder /tmp/tailscale/tailscaled /usr/bin/tailscaled
COPY --from=builder /tmp/rclone/rclone /usr/bin/rclone

# 赋予可执行权限
RUN chmod +x /usr/bin/tailscale /usr/bin/tailscaled /usr/bin/rclone

# 复制你的脚本
COPY scripts/start.sh /usr/local/bin/start.sh
COPY scripts/backup.sh /usr/local/bin/backup.sh
RUN chmod +x /usr/local/bin/start.sh /usr/local/bin/backup.sh

# 端口和入口
EXPOSE 7860 80 81 443
ENTRYPOINT ["/usr/local/bin/start.sh"]
