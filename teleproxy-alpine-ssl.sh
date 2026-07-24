#!/bin/sh

### REQUIRED ###
# export DOMAIN=""
# export PROXY_SECRET=""

### OPTIONAL ###
# export TG_BOT_TOKEN="""
# export TG_CHAT_ID=""

# ==========================================
# CONFIGURATION & VARIABLES
# ==========================================

TELEPROXY_BIN="/usr/sbin/teleproxy"
TELEPROXY_URL="https://github.com/teleproxy/teleproxy/releases/latest/download/teleproxy-linux-{TELEPROXY_ARCH}"
ACME_DIR="/root/acme.sh"
PURE_INDEX_URL="https://raw.githubusercontent.com/KurtSkinny/scripts/master/index.html"

export LE_WORKING_DIR="$ACME_DIR"

INSTALLER_FULL_PATH=$(readlink -f -- "$0")

fatal() {
    echo "ERROR: $1" >&2
    exit 1
}

# ==========================================
# PREREQUISITES & VALIDATION
# ==========================================

[ "$(id -u)" -eq 0 ] || fatal "Run as root."

ARCH=$(uname -m)
case "${ARCH}" in
    x86_64) TELEPROXY_ARCH="amd64" ;;
    aarch64) TELEPROXY_ARCH="arm64" ;;
    *) fatal "Unsupported architecture: ${ARCH}. Only x86_64 (amd64) and aarch64 (arm64) are supported." ;;
esac

if [ -z "${DOMAIN}" ]; then
    fatal "The DOMAIN environment variable is not set or empty. Please run: export DOMAIN=\"yourdomain.com\""
fi

if [ -z "${PROXY_SECRET}" ]; then
    GENERATED_SECRET=$(head -c 16 /dev/urandom | od -An -tx1 | tr -d '\n ')
    echo "--------------------------------------------------------------" >&2
    echo "ERROR: The PROXY_SECRET environment variable is empty or not set." >&2
    echo "Please provide your own secret or use the newly generated:" >&2
    echo "" >&2
    echo "export PROXY_SECRET=\"${GENERATED_SECRET}\"" >&2
    echo "--------------------------------------------------------------" >&2
    fatal "PROXY_SECRET is missing. Set the variable and rerun the script."
fi

if which nginx >/dev/null 2>&1 || [ -d "/etc/nginx" ]; then
    echo "--------------------------------------------------------------" >&2
    echo "ERROR: Nginx or its configuration directory already exists!" >&2
    echo "To avoid overwriting existing configurations, execution stopped." >&2
    echo "If you want to reinstall, remove them first (apk del nginx && rm -rf /etc/nginx)." >&2
    echo "--------------------------------------------------------------" >&2
    fatal "Nginx detected. Protection triggered."
fi

for PORT in 80 443 8443; do
    if netstat -tuln | grep -q ":${PORT} "; then
        echo "--------------------------------------------------------------" >&2
        echo "ERROR: Local port ${PORT} is already in use by another process!" >&2
        echo "Please stop any service using port ${PORT} before running this script." >&2
        echo "--------------------------------------------------------------" >&2
        fatal "Port ${PORT} is busy."
    fi
done

# ==========================================
# NETWORK & PORT FORWARDING VALIDATION
# ==========================================

apk update || fatal "apk update failed."

apk add curl wget ca-certificates || fatal "Failed to install required packages."

echo "### Running network validation for ${DOMAIN}..."

WAN_IP=$(curl -s --max-time 5 https://ifconfig.me || curl -s --max-time 5 https://portchecker.io/api/me)
DOMAIN_IP=$(getent hosts "${DOMAIN}" | awk '{print $1}')

if [ -z "${WAN_IP}" ]; then
    fatal "Network Error: Unable to detect external WAN IP."
fi

if [ -z "${DOMAIN_IP}" ]; then
    fatal "DNS Error: Cannot resolve domain ${DOMAIN}. Check your A-records."
fi

if [ "${WAN_IP}" != "${DOMAIN_IP}" ]; then
    echo "--------------------------------------------------------------" >&2
    echo "ERROR: DNS mismatch detected!" >&2
    echo "Your domain '${DOMAIN}' points to IP: ${DOMAIN_IP}" >&2
    echo "But your actual external WAN IP is: ${WAN_IP}" >&2
    echo "Please update your DNS A-records before running the script." >&2
    echo "--------------------------------------------------------------" >&2
    fatal "Domain IP does not match WAN IP."
fi

echo "### Verifying if ports 80,443 is accessible from the internet..."
for PORT in 80 443; do
    PORT_BEFORE_STATUS=$(curl -s --max-time 7 "https://portchecker.io/api/${WAN_IP}/${PORT}")
    if [ "${PORT_BEFORE_STATUS}" = "True" ]; then
        echo "--------------------------------------------------------------" >&2
        echo "ERROR: Port ${PORT} is already RESPONDING from the outside!" >&2
        echo "However, it is NOT forwarded to this container (local port check passed earlier)." >&2
        echo "Likely, MikroTik RouterOS or another service is listening on this port itself." >&2
        echo "Please fix your NAT rules so port ${PORT} routes directly to this container." >&2
        echo "--------------------------------------------------------------" >&2
        fatal "Port ${PORT} conflict detected on host/router."
    fi

    nc -lk -p ${PORT} -e echo -e "HTTP/1.1 200 OK\r\nContent-Length: 2\r\n\r\nOK" >/dev/null 2>&1 &
    NC_PID=$!
    sleep 1
    PORT_STATUS=$(curl -s --max-time 7 "https://portchecker.io/api/${WAN_IP}/${PORT}")
    kill -9 $NC_PID >/dev/null 2>&1

    if [ "${PORT_STATUS}" != "True" ]; then
        echo "--------------------------------------------------------------" >&2
        echo "ERROR: Port ${PORT} is NOT accessible from the outside internet!" >&2
        echo "Please forward port ${PORT} (TCP) in MikroTik RouterOS to this container." >&2
        echo "Check API response: ${PORT_STATUS}" >&2
        echo "--------------------------------------------------------------" >&2
        fatal "Port ${PORT} is blocked or not forwarded. Script execution stopped."
    fi
done

# ==========================================
# ENVIRONMENT & DEPENDENCIES SETUP
# ==========================================

apk add nginx openssl || fatal "Failed to install required packages."

TELEPROXY_URL=$(echo "$TELEPROXY_URL" | sed "s/{TELEPROXY_ARCH}/$TELEPROXY_ARCH/")
wget -O "${TELEPROXY_BIN}" "${TELEPROXY_URL}" || fatal "Failed to download teleproxy."
chmod +x "${TELEPROXY_BIN}"

cat << EOF > /etc/nginx/http.d/default.conf
server {
    listen 80 default_server;
    root /var/www/${DOMAIN};
}
EOF

mkdir -p /var/www/${DOMAIN}
mkdir -p /etc/nginx/ssl

wget -O /var/www/${DOMAIN}/index.html ${PURE_INDEX_URL} || fatal "Failed to download index.html."

sed -i "s/YOUR_DOMAIN_NAME/${DOMAIN}/g" /var/www/${DOMAIN}/index.html

wget -O - https://get.acme.sh | sh -s email=my@${DOMAIN} --home ${ACME_DIR} --no-cron \
|| fatal "Failed to install acme.sh."

# ==========================================
# INITIAL SSL CERTIFICATE ISSUANCE
# ==========================================

/usr/sbin/nginx

echo "### Changing directory to ${ACME_DIR}..."
cd "${ACME_DIR}"

echo "### Setting default Certificate Authority to Let's Encrypt..."
./acme.sh --set-default-ca --server letsencrypt 

echo "### Issuing SSL certificate via webroot validation for ${DOMAIN}..."
./acme.sh --issue -d ${DOMAIN} -w /var/www/${DOMAIN} \
|| fatal "Certificate issuance failed."

echo "### Installing certificate files to Nginx directory..."
./acme.sh --install-cert \
  -d ${DOMAIN} \
  --key-file       /etc/nginx/ssl/${DOMAIN}_privkey.pem \
  --fullchain-file /etc/nginx/ssl/${DOMAIN}_fullchain.pem \
  || fatal "Certificate installation failed."

cat << EOF > /etc/nginx/http.d/default.conf
server {
    listen 80 default_server;
    return 301 https://\$host\$request_uri;
}

server {
    listen 8443 ssl default_server;
    ssl_certificate     /etc/nginx/ssl/${DOMAIN}_fullchain.pem;
    ssl_certificate_key /etc/nginx/ssl/${DOMAIN}_privkey.pem;
    ssl_protocols TLSv1.3;
    ssl_prefer_server_ciphers off;
    root /var/www/${DOMAIN};
    location = /index.html {
        ssi on;
    }
}
EOF

/usr/sbin/nginx -s reload

# ==========================================
# ENTRYPOINT GENERATION & CLEANUP
# ==========================================

cat << EOF > /start.sh
#!/bin/sh

PROXY_SECRET="${PROXY_SECRET}"

TG_BOT_TOKEN="${TG_BOT_TOKEN}"
TG_CHAT_ID="${TG_CHAT_ID}"

DOMAIN="${DOMAIN}"
ACME_DIR="${ACME_DIR}"
TELEPROXY_BIN="${TELEPROXY_BIN}"
TELEPROXY_URL="${TELEPROXY_URL}"

DOMAIN_HEX=\$(echo -n "\${DOMAIN}" | od -An -tx1 | tr -d '\n ')
TG_LINK="tg://proxy?server=\${DOMAIN}&port=443&secret=ee\${PROXY_SECRET}\${DOMAIN_HEX}"

tg_message() {
    if [ -z "\${TG_BOT_TOKEN}" ] || [ -z "\${TG_CHAT_ID}" ] || [ -z "\$1" ]; then
        return 1
    fi
    curl -s -X POST "https://api.telegram.org/bot\${TG_BOT_TOKEN}/sendMessage" \\
    -d "chat_id=\${TG_CHAT_ID}" --data-urlencode "text=$1" > /dev/null
}

printf "\n127.0.0.1 %s\n" "\${DOMAIN}" >> /etc/hosts

/usr/sbin/nginx

export LE_WORKING_DIR="\$ACME_DIR"

\${ACME_DIR}/acme.sh --cron

/usr/sbin/nginx -s reload

# ==========================================
# AUTOMATIC TELEPROXY UPDATE CHECK
# ==========================================
echo "Checking for teleproxy updates..."
TELEPROXY_LATEST_VERSION=\$(curl -fLs -o /dev/null -w \%{url_effective} https://github.com/teleproxy/teleproxy/releases/latest)
TELEPROXY_LATEST_VERSION=\${TELEPROXY_LATEST_VERSION##*/}

TELEPROXY_CURRENT_VERSION=\$(\${TELEPROXY_BIN} null 2>&1 | grep -oE "teleproxy-[0-9]+\.[0-9]+\.[0-9]+" | head -n 1)
TELEPROXY_CURRENT_VERSION="v\${TELEPROXY_CURRENT_VERSION#teleproxy-}"

VALID_PATTERN="^v[0-9]+\.[0-9]+\.[0-9]+"

MSG_PREFIX="[\${DOMAIN}] Teleproxy update:"
if ! echo "\${TELEPROXY_LATEST_VERSION}" | grep -qE "\${VALID_PATTERN}"; then
    echo "WARNING: Failed to fetch a valid remote version from GitHub (Got: '\${TELEPROXY_LATEST_VERSION}'). Skipping update check."
    tg_message "\${MSG_PREFIX} Unable to check the latest release on GitHub, update check skipped."
elif ! echo "\${TELEPROXY_CURRENT_VERSION}" | grep -qE "\${VALID_PATTERN}"; then
    echo "WARNING: Failed to detect currently installed teleproxy version (Got: '\${TELEPROXY_CURRENT_VERSION}'). Skipping update check."
    tg_message "\${MSG_PREFIX} Unable to determine the installed Teleproxy version, update check skipped."
else
    if [ "\${TELEPROXY_CURRENT_VERSION}" != "\${TELEPROXY_LATEST_VERSION}" ]; then
        echo "New version available: \${TELEPROXY_LATEST_VERSION} (Current: \${TELEPROXY_CURRENT_VERSION}). Downloading..."
        if wget -O "\${TELEPROXY_BIN}.new" "\${TELEPROXY_URL}"; then
            chmod +x "\${TELEPROXY_BIN}.new"
            if "\${TELEPROXY_BIN}.new" null 2>&1 | grep -q "Invoking engine teleproxy-"; then
                mv "\${TELEPROXY_BIN}.new" "\${TELEPROXY_BIN}"
                echo "Teleproxy successfully updated to \${TELEPROXY_LATEST_VERSION}!"
                tg_message "\${MSG_PREFIX} Teleproxy updated. \${TELEPROXY_CURRENT_VERSION} > \${TELEPROXY_LATEST_VERSION}"
            else
                echo "Downloaded file is not a valid teleproxy binary."
                rm -f "\${TELEPROXY_BIN}.new"
                tg_message "\${MSG_PREFIX} Teleproxy update failed. Downloaded file is not a valid Teleproxy binary."
            fi
        else
            echo "WARNING: Failed to download teleproxy update. Keeping current version."
            tg_message "\${MSG_PREFIX}  Download failed. Latest: \${TELEPROXY_LATEST_VERSION}. Current: \${TELEPROXY_CURRENT_VERSION}."
            rm -f "\${TELEPROXY_BIN}.new"
        fi
    else
        echo "Teleproxy is up to date (\${TELEPROXY_CURRENT_VERSION})."
    fi
fi

echo "======================================================================"
echo "Telegram MTProto Proxy Link:"
echo "\${TG_LINK}"
echo "======================================================================"

\${TELEPROXY_BIN} -u nobody -H 443 -M 0 -S \${PROXY_SECRET} -D \${DOMAIN}:8443 --direct
EOF

chmod +x /start.sh

echo "Done."
echo "Run /start.sh or use it as your RouterOS Container CMD / Entrypoint"

# Self-destruction
rm -- "$INSTALLER_FULL_PATH"
