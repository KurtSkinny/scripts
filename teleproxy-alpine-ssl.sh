#!/bin/sh

### REQUIRED ###
# export DOMAIN=""
# export TG_SECRET=""

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
    aarch64|arm64) TELEPROXY_ARCH="arm64" ;;
    *) fatal "Unsupported architecture: ${ARCH}. Only x86_64 (amd64) and aarch64 (arm64) are supported." ;;
esac

if [ -z "${DOMAIN}" ]; then
    fatal "The DOMAIN environment variable is not set or empty. Please run: export DOMAIN=\"yourdomain.com\""
fi

if [ -z "${TG_SECRET}" ]; then
    GENERATED_SECRET=$(head -c 16 /dev/urandom | od -An -tx1 | tr -d '\n ')
    echo "--------------------------------------------------------------" >&2
    echo "ERROR: The TG_SECRET environment variable is empty or not set." >&2
    echo "Please provide your own secret or use the newly generated:" >&2
    echo "" >&2
    echo "export TG_SECRET=\"${GENERATED_SECRET}\"" >&2
    echo "--------------------------------------------------------------" >&2
    fatal "TG_SECRET is missing. Set the variable and rerun the script."
fi

# ==========================================
# ENVIRONMENT & DEPENDENCIES SETUP
# ==========================================

apk update || fatal "apk update failed."
apk add nginx openssl curl wget ca-certificates || fatal "Failed to install required packages."

TELEPROXY_URL=$(echo "$TELEPROXY_URL" | sed "s/{TELEPROXY_ARCH}/$TELEPROXY_ARCH/")
wget -O "${TELEPROXY_BIN}" "${TELEPROXY_URL}" || fatal "Failed to download teleproxy."
chmod +x "${TELEPROXY_BIN}"

cat << EOF > /etc/nginx/http.d/default.conf
server {
    listen 80 default_server;
    root /var/www/${DOMAIN};
}
EOF

mkdir -p /etc/nginx/ssl
mkdir -p /var/www/${DOMAIN}

wget -O /var/www/${DOMAIN}/index.html ${PURE_INDEX_URL} || fatal "Failed to download index.html."

sed -i "s/YOUR_DOMAIN_NAME/${DOMAIN}/g" /var/www/${DOMAIN}/index.html

# ==========================================
# INITIAL SSL CERTIFICATE ISSUANCE
# ==========================================

/usr/sbin/nginx

wget -O - https://get.acme.sh | sh -s email=my@${DOMAIN} --home ${ACME_DIR} --no-cron \
|| fatal "Failed to install acme.sh."

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

TG_SECRET="${TG_SECRET}"

TG_BOT_TOKEN="${TG_BOT_TOKEN}"
TG_CHAT_ID="${TG_CHAT_ID}"

DOMAIN="${DOMAIN}"
ACME_DIR="${ACME_DIR}"
TELEPROXY_BIN="${TELEPROXY_BIN}"
TELEPROXY_URL="${TELEPROXY_URL}"

DOMAIN_HEX=\$(echo -n "\${DOMAIN}" | od -An -tx1 | tr -d '\n ')
TG_LINK="tg://proxy?server=\${DOMAIN}&port=443&secret=ee\${TG_SECRET}\${DOMAIN_HEX}"

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

\${TELEPROXY_BIN} -u nobody -H 443 -M 0 -S \${TG_SECRET} -D \${DOMAIN}:8443 --direct
EOF

chmod +x /start.sh

echo "Done."
echo "Run /start.sh or use it as your RouterOS Container CMD / Entrypoint"

# Self-destruction
rm -- "$INSTALLER_FULL_PATH"
