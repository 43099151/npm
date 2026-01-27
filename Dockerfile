# ==========================================
# 阶段 1: 资源猎人 (只负责下载和压缩)
# ==========================================
FROM debian:bookworm-slim AS builder

# 安装下载和压缩工具 (binutils 包含 strip)
RUN apt-get update && apt-get install -y curl tar unzip socat binutils

# 1. 提取 Socat (用于端口转发)
RUN cp /usr/bin/socat /tmp/socat

# 2. 下载 Tailscale
ARG TS_VERSION=""
ARG TS_ARCH=amd64
RUN set -eux; \
    if [ -z "$TS_VERSION" ] || [ "$TS_VERSION" = "latest" ]; then \
      TS_VERSION=$(curl -fsSL https://tailscale.com/changelog/index.xml | sed -n 's/.*<title>Tailscale v\([0-9][0-9.]*\).*/\1/p' | head -n1); \
      if [ -z "$TS_VERSION" ]; then \
        echo "Failed to detect TS_VERSION from changelog; aborting"; exit 1; \
      fi; \
    fi; \
    echo "Installing tailscale version: $TS_VERSION (arch: $TS_ARCH)"; \
    curl -fsSL "https://pkgs.tailscale.com/stable/tailscale_${TS_VERSION}_${TS_ARCH}.tgz" -o /tmp/tailscale.tgz; \
    cd /tmp; \
    tar xzf tailscale.tgz; \
    mv "tailscale_${TS_VERSION}_${TS_ARCH}/tailscaled" /usr/sbin/tailscaled; \
    mv "tailscale_${TS_VERSION}_${TS_ARCH}/tailscale" /usr/bin/tailscale; \
    chmod +x /usr/sbin/tailscaled /usr/bin/tailscale; \
    rm -rf /tmp/tailscale.tgz /tmp/"tailscale_${TS_VERSION}_${TS_ARCH}"

# 3. 下载 Rclone
WORKDIR /tmp/rclone
RUN curl -fsSL "https://downloads.rclone.org/v1.72.1/rclone-v1.72.1-linux-amd64.zip" -o rclone.zip && \
    unzip rclone.zip && \
    mv rclone-v1.72.1-linux-amd64/rclone /tmp/rclone/rclone

# ------------------------------------------
# 关键步骤：给二进制文件“抽脂” (Strip)
# 这会移除调试符号，显著减小体积
# ------------------------------------------
RUN strip --strip-unneeded /tmp/tailscale/tailscale
RUN strip --strip-unneeded /tmp/tailscale/tailscaled
RUN strip --strip-unneeded /tmp/rclone/rclone
RUN strip --strip-unneeded /tmp/socat

# ==========================================
# 阶段 2: 最终组装 (纯净版)
# ==========================================
FROM jc21/nginx-proxy-manager:latest

# 切换 Root 以便操作
USER root

# 1. 破解 NPM 启动检查 (去掉了之前的 apt 清理步骤，因为根本没用 apt)
RUN echo "Patching startup scripts..." && \
    find /etc -type f -exec sed -i 's/if ! mountpoint -q/if false; then #/g' {} + || true && \
    find /etc -type f -exec sed -i 's/echo "ERROR: .* is not mounted/echo "WARNING: Mount bypassed/g' {} + || true && \
    find /etc -type f -exec sed -i 's/exit 1/true/g' {} + || true

# 2. 只复制瘦身后的二进制文件
COPY --from=builder /tmp/tailscale/tailscale /usr/bin/tailscale
COPY --from=builder /tmp/tailscale/tailscaled /usr/bin/tailscaled
COPY --from=builder /tmp/rclone/rclone /usr/bin/rclone
COPY --from=builder /tmp/socat /usr/bin/socat

# 3. 赋予执行权限
RUN chmod +x /usr/bin/tailscale /usr/bin/tailscaled /usr/bin/rclone /usr/bin/socat

# 4. 创建必要的目录
RUN mkdir -p /var/run/tailscale /var/lib/tailscale /root/.config/rclone \
    /data /etc/letsencrypt

# 5. 复制脚本
COPY scripts/start.sh /usr/local/bin/start.sh
COPY scripts/backup.sh /usr/local/bin/backup.sh
RUN chmod +x /usr/local/bin/start.sh /usr/local/bin/backup.sh

# 6. 端口
EXPOSE 7860 80 81 443

# 7. 启动
ENTRYPOINT ["/usr/local/bin/start.sh"]
