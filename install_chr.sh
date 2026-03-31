#!/bin/bash

# Usage example for RouterOS v7.22.1

# wget -O install_chr.sh https://raw.githubusercontent.com/KurtSkinny/scripts/refs/heads/main/install_chr.sh
# chmod +x install_chr.sh
# ./install_chr.sh https://download.mikrotik.com/routeros/7.22.1/chr-7.22.1-arm64.img.zip

# Check bootloader type (UEFI vs BIOS)
if [ -d /sys/firmware/efi ]; then
    echo "ERROR: UEFI bootloader detected."
    echo "This script is designed for Legacy BIOS only."
    echo "For UEFI installation, please search for an alternative method (requires manual partitioning)."    exit 1
fi

# Проверка наличия аргумента
if [ -z "$1" ]; then
    echo "Usage: $0 <CHR_IMAGE_ZIP_URL>"
    echo "Example: $0 https://download.mikrotik.com/routeros/7.22.1/chr-7.22.1-arm64.img.zip"
    echo "Go to https://mikrotik.com/download/chr and copy url to img.zip"
    exit 1
fi

URL=$1
# Switch to /tmp for all operations
IMG_ZIP="chr_image.zip"

cd /tmp || exit 1

echo "--- Gathering Network Information ---"
echo "--- Gathering Network Information ---"

# Detect primary interface, IP with mask (CIDR), and default gateway
ip route
ip -4 addr show
INTERFACE=$(ip route | grep default | awk '{print $5}' | head -n1)
IP_ADDR=$(ip -4 addr show "$INTERFACE" | grep inet | awk '{print $2}' | head -n1)
GATEWAY=$(ip route | grep default | awk '{print $3}' | head -n1)

echo "------------------------------------------"
echo "SAVE THIS DATA (required for RouterOS setup):"
echo "IP/Mask: $IP_ADDR"
echo "Gateway: $GATEWAY"
echo "------------------------------------------"
echo "Press ENTER to proceed, or Ctrl+C to cancel."
read

echo "--- Installing Dependencies ---"
apt-get update && apt-get install -y wget unzip

echo "--- Downloading and Unpacking Image ---"
wget -O "$IMG_ZIP" "$URL"
unzip "$IMG_ZIP"
IMG_FILE=$(ls *.img | head -n 1)

if [ -z "$IMG_FILE" ]; then
    echo "Error: .img file not found in the archive."
    exit 1
fi

echo "--- Identifying System Disk ---"
# Find the parent device for the root partition /
DISK=$(lsblk -no pkname $(findmnt -nvo source /))
if [ -z "$DISK" ]; then
    # Fallback if partition name is empty
    DISK=$(fdisk -l | grep "Disk /dev/" | head -n 1 | awk '{print $2}' | cut -d: -f1)
fi

echo ""
echo "!!! WARNING !!!"
echo "The script will overwrite the disk: $TARGET_DISK"
echo "All current data on Debian 11 will be PERMANENTLY DELETED."
echo "Press ENTER to proceed, or Ctrl+C to cancel."
read

echo "--- Writing Image to Disk ---"
# Force filesystem to Read-Only mode to avoid conflicts
sync
echo u > /proc/sysrq-trigger
# Write the image
dd if="$IMG_FILE" of="/dev/$DISK" bs=4M oflag=sync

echo "--- Done! ---"
echo "The server will reboot in 5 seconds."
echo "Use your VNC console to log in (User: admin, No Password)."
sleep 5

# Trigger immediate hardware reboot
echo 1 > /proc/sys/kernel/sysrq
echo b > /proc/sysrq-trigger
