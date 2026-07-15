
[install_chr.sh](https://github.com/KurtSkinny/scripts/blob/main/install_chr.sh) - This script is used to automatically reinstall a Debian/Ubuntu server into MikroTik RouterOS (CHR) by downloading a disk image and writing it directly to the system disk.

- Usage example:
```bash
apt-get update && apt-get install -y wget unzip
wget -O install_chr.sh https://raw.githubusercontent.com/KurtSkinny/scripts/refs/heads/main/install_chr.sh
chmod +x install_chr.sh
./install_chr.sh https://download.mikrotik.com/routeros/7.23.2/chr-7.23.2.img.zip
```
