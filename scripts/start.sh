#!/bin/bash

echo "[INFO] Starting Container..."

# Define Tailscale Socket Location globally
export TS_SOCKET=/tmp/tailscaled.sock

# 1. Rclone Configuration
if [ -n "$R2_ACCESS_KEY_ID" ]; then
    mkdir -p /root/.config/rclone
    cat <<EOF > /root/.config/rclone/rclone.conf
[r2]
type = s3
provider = Cloudflare
access_key_id = $R2_ACCESS_KEY_ID
secret_access_key = $R2_SECRET_ACCESS_KEY
endpoint = $R2_ENDPOINT
acl = private
EOF
fi

# 2. Restore Backup
# Note: It is normal to see "No such file" errors on the very first run.
if [ -n "$R2_BUCKET" ]; then
    if rclone lsf "r2:$R2_BUCKET/npm_backup.tar.gz" >/dev/null 2>&1; then
        echo "[INFO] Restoring backup..."
        rclone copy "r2:$R2_BUCKET/npm_backup.tar.gz" /tmp/
        tar -xzf /tmp/npm_backup.tar.gz -C /
        rm /tmp/npm_backup.tar.gz
    else
        echo "[INFO] No backup found."
    fi
fi

# 3. Start Tailscale
mkdir -p /var/lib/tailscale /var/run/tailscale

# Start Daemon
# We pass the socket explicitly here, and use userspace networking for HF
tailscaled --tun=userspace-networking --state=/var/lib/tailscale/tailscaled.state --socket=$TS_SOCKET &
sleep 5

if [ -n "$TS_AUTH_KEY" ]; then
    # Start Client
    # REMOVED --socket from here, because we exported TS_SOCKET at the top of the script
    TS_ARGS="--authkey=${TS_AUTH_KEY} --hostname=${TS_NAME:-npm-hf} --ssh --accept-routes"
    
    if [ -n "$TS_TAGS" ]; then
        TS_ARGS="$TS_ARGS --advertise-tags=${TS_TAGS}"
    fi

    # Bring up the node
    tailscale up $TS_ARGS --reset
    echo "[INFO] Tailscale up command executed."
fi

# 4. Start Backup Loop
(
    while true; do
        sleep 14400
        /bin/bash /usr/local/bin/backup.sh >> /var/log/backup.log 2>&1
    done
) &

# 5. Port Mapping (HF 7860 -> NPM 80)
socat TCP-LISTEN:7860,fork,bind=0.0.0.0 TCP:127.0.0.1:80 &
echo "[INFO] Port 80 mapped to 7860 via socat."

# 6. Start NPM
echo "[INFO] Starting NPM..."
exec /init
