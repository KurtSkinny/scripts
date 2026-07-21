### [install_chr.sh](https://github.com)
Automated script to reinstall a Debian/Ubuntu server into MikroTik RouterOS (CHR) by downloading a disk image and writing it directly to the system disk.

```sh
apt-get update && apt-get install -y wget unzip
wget -O install_chr.sh https://githubusercontent.com
chmod +x install_chr.sh
./install_chr.sh https://mikrotik.com
```

---

### [teleproxy-alpine-ssl.sh](https://github.com)
Automated installer for MTProto proxy ([Teleproxy](https://github.com/teleproxy/teleproxy)) with a Let's Encrypt SSL certificate inside an Alpine Linux container (optimized for MikroTik RouterOS). 
* **Note:** `cron` is not used. **Restart the container weekly** to trigger automatic SSL renewal on boot.

```sh
wget -O setup.sh https://githubusercontent.com
chmod +x setup.sh
export DOMAIN="yourdomain.com"
export TG_SECRET="____YOUR_16-byte_hex_secret_____" # Or leave empty for auto-generation
. ./setup.sh
# Run /start.sh or use it as your RouterOS Container CMD / Entrypoint
```

---

### [index.html](https://github.com) 
Simple index page template.

```sh
wget https://githubusercontent.com -O index.html
sed -i "s/YOUR_DOMAIN_NAME/yourdomain.com/g" index.html
```

Enable SSI (Server Side Includes) for this page in your Nginx configuration:
```conf
location = /index.html {
    ssi on;
}
```
