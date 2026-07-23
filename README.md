### [install_chr.sh](https://github.com/KurtSkinny/scripts/blob/main/install_chr.sh)
Automated script to reinstall a Debian/Ubuntu server into MikroTik RouterOS (CHR) by downloading a disk image and writing it directly to the system disk.

```sh
apt-get update && apt-get install -y wget unzip
wget -O install_chr.sh https://raw.githubusercontent.com/KurtSkinny/scripts/master/install_chr.sh
chmod +x install_chr.sh
./install_chr.sh https://download.mikrotik.com/routeros/7.23.2/chr-7.23.2.img.zip
```

---

### [teleproxy-alpine-ssl.sh](https://github.com/KurtSkinny/scripts/blob/main/teleproxy-alpine-ssl.sh)
Automated installer for MTProto proxy ([Teleproxy](https://github.com/teleproxy/teleproxy)) masked behind a legitimate, fully functional HTTPS website with a valid Let's Encrypt SSL certificate using an Alpine Linux container (optimized for MikroTik RouterOS). 

#### Prerequisites:
* A public IP address on your server/router.
* A registered **domain name** with DNS A-records already pointing to your server's public IP.
* Ports **80** and **443** must be forwarded and open on your firewall.
* A supported CPU architecture: **x86_64 (amd64)** or **aarch64 (arm64)**.

> **Note:** `cron` is not used. **Restart the container weekly** to trigger automatic SSL renewal on boot.

```sh
wget -O setup.sh https://raw.githubusercontent.com/KurtSkinny/scripts/master/teleproxy-alpine-ssl.sh
chmod +x setup.sh

export DOMAIN="yourdomain.com"
export TG_SECRET="" # 16-byte hex secret key, or leave empty for auto-generation
export TG_BOT_TOKEN="123456789:ABCdefGhIJKlmNoPQRsTUVwxyZ" # Optional: Telegram Bot Token for notifications
export TG_CHAT_ID="123456789" # Optional: Telegram Chat/User ID for notifications

./setup.sh

# Run /start.sh or use it as your RouterOS Container CMD / Entrypoint
```

---

### [index.html](https://github.com/KurtSkinny/scripts/blob/main/index.html)
Simple index page template.

```sh
wget https://raw.githubusercontent.com/KurtSkinny/scripts/master/index.html -O index.html
sed -i "s/YOUR_DOMAIN_NAME/yourdomain.com/g" index.html
```

Enable SSI (Server Side Includes) for this page in your Nginx configuration:
```conf
location = /index.html {
    ssi on;
}
```
