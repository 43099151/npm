# ... (前面的代码保持不变) ...

# ==========================================
# 5. 启动 Tailscale (增加错误日志版)
# ==========================================
mkdir -p /var/lib/tailscale /var/run/tailscale

# 启动守护进程
tailscaled --tun=userspace-networking --state=/var/lib/tailscale/tailscaled.state --socket=$TS_SOCKET &
sleep 5

if [ -n "$TS_AUTH_KEY" ]; then
    # 组装命令
    TS_CMD="tailscale --socket=$TS_SOCKET up --authkey=${TS_AUTH_KEY} --hostname=${TS_NAME} --ssh --accept-routes --reset"
    
    if [ -n "$TS_TAGS" ]; then
        TS_CMD="$TS_CMD --advertise-tags=${TS_TAGS}"
    fi

    echo "[INFO] Running Tailscale up..."
    
    # 运行并捕获错误
    if $TS_CMD; then
        echo "[SUCCESS] Tailscale is ONLINE!"
    else
        echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
        echo "[ERROR] Tailscale failed to connect! Check your Key below:"
        echo "1. Is the key 'Reusable'?"
        echo "2. Did you set Tags in the key but not in the script?"
        echo "3. Is the key expired?"
        echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
        # 不退出，让 NPM 继续运行，方便查看日志
    fi
fi

# ... (后面的代码保持不变) ...
