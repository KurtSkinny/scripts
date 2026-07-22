#!/bin/sh
# export DOMAIN=""
# export TG_SECRET=""

TELEPROXY_BIN="/usr/sbin/teleproxy"
ACME_DIR="/root/acme.sh"
PURE_INDEX_HTML="https://raw.githubusercontent.com/KurtSkinny/scripts/master/index.html"

export LE_WORKING_DIR="$ACME_DIR"

###

fatal() {
    echo "ERROR: $1" >&2
    exit 1
}

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

[ "$(id -u)" -eq 0 ] || fatal "Run as root."

apk update
apk add nginx openssl curl

curl -Lo ${TELEPROXY_BIN} https://github.com/teleproxy/teleproxy/releases/latest/download/teleproxy-linux-amd64
chmod +x ${TELEPROXY_BIN}

cat << EOF > /etc/nginx/http.d/default.conf
server {
    listen 80 default_server;
    root /var/www/${DOMAIN};
}
EOF

mkdir -p /etc/nginx/ssl
mkdir -p /var/www/${DOMAIN}

wget ${PURE_INDEX_HTML} -O /var/www/${DOMAIN}/index.html

sed -i "s/YOUR_DOMAIN_NAME/${DOMAIN}/g" /var/www/${DOMAIN}/index.html

/usr/sbin/nginx

curl https://get.acme.sh | sh -s email=my@${DOMAIN} --home ${ACME_DIR} --no-cron

cd ${ACME_DIR}

./acme.sh --set-default-ca --server letsencrypt

./acme.sh --issue -d ${DOMAIN} -w /var/www/${DOMAIN}

./acme.sh --install-cert \
  -d ${DOMAIN} \
  --key-file       /etc/nginx/ssl/${DOMAIN}_privkey.pem \
  --fullchain-file /etc/nginx/ssl/${DOMAIN}_fullchain.pem

cat << EOF > /etc/nginx/http.d/default.conf
server {
    listen 80 default_server;
    return 301 https://\$host\$request_uri;
}

server {
    listen 127.0.0.1:8443 ssl default_server;
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

DOMAIN_HEX=$(echo -n "${DOMAIN}" | od -An -tx1 | tr -d '\n ')
TG_LINK="tg://proxy?server=${DOMAIN}&port=443&secret=ee${TG_SECRET}${DOMAIN_HEX}"

cat << EOF > /start.sh
#!/bin/sh

echo -e "\n127.0.0.1 ${DOMAIN}" >> /etc/hosts

/usr/sbin/nginx

export LE_WORKING_DIR="$ACME_DIR"

${ACME_DIR}/acme.sh --cron

/usr/sbin/nginx -s reload

echo "======================================================================"
echo "Telegram MTProto Proxy Link:"
echo "${TG_LINK}"
echo "======================================================================"

${TELEPROXY_BIN} -u nobody -H 443 -M 1 -S ${TG_SECRET} -D ${DOMAIN}:8443 --direct
EOF

chmod +x /start.sh

echo "Done."
echo "Run /start.sh or use it as your RouterOS Container CMD / Entrypoint"

# Self-destruction
rm -- "$0"
