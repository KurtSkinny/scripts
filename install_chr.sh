#!/bin/bash

# This script is used to automatically reinstall a Debian/Ubuntu server into MikroTik RouterOS (CHR) by downloading a disk image and writing it directly to the system disk.

# Usage example:
# apt-get update && apt-get install -y wget unzip
# wget -O install_chr.sh https://raw.githubusercontent.com/KurtSkinny/scripts/refs/heads/main/install_chr.sh
# chmod +x install_chr.sh
# ./install_chr.sh https://download.mikrotik.com/routeros/7.23.2/chr-7.23.2.img.zip

if [ "$(id -u)" -ne 0 ]; then
    echo "ERROR: This script must be run as root."
    exit 1
fi

# Check bootloader type (UEFI vs BIOS)
if [ -d /sys/firmware/efi ]; then
    echo "ERROR: UEFI bootloader detected."
    echo "This script is designed for Legacy BIOS only."
    echo "For UEFI installation, please search for an alternative method (requires manual partitioning)."
    exit 1
fi

if [ -z "$1" ]; then
    echo "Usage: $0 <CHR_IMAGE_ZIP_URL>"
    echo "Example: $0 https://download.mikrotik.com/routeros/7.22.1/chr-7.22.1.img.zip"
    echo "Go to https://mikrotik.com/download/chr and copy url to img.zip"
    exit 1
fi

URL=$1
# Switch to /tmp for all operations
IMG_ZIP="chr_image.zip"

cd /tmp || exit 1

WGET_BIN=$(command -v wget 2>/dev/null)
UNZIP_BIN=$(command -v unzip 2>/dev/null)

echo "--- Checking Dependencies ---"
TO_INSTALL=""
[ -z "$WGET_BIN" ] && TO_INSTALL="wget"
[ -z "$UNZIP_BIN" ] && TO_INSTALL="${TO_INSTALL:+$TO_INSTALL }unzip"

if [ -n "$TO_INSTALL" ]; then
    echo "Installing missing packages: $TO_INSTALL"
    apt-get update && apt-get install -yq $TO_INSTALL
    WGET_BIN=$(command -v wget 2>/dev/null)
    UNZIP_BIN=$(command -v unzip 2>/dev/null)
    if [ -z "$WGET_BIN" ] || [ -z "$UNZIP_BIN" ]; then
        echo "Error installing packages. Please install the required packages manually: $TO_INSTALL"
        exit 1
    else
        echo "Done."
    fi
fi

echo "--- Gathering Network Information ---"
# Detect primary interface, IP with mask (CIDR), and default gateway
INTERFACE=$(ip route show default | awk '{print $5}' | head -n1)
IP_ADDR=$(ip -4 addr show "$INTERFACE" | awk '/inet / {print $2}' | head -n1)
GATEWAY=$(ip route show default | awk '{print $3}' | head -n1)

echo "------------------------------------------"
echo "SAVE THIS DATA (required for RouterOS setup):"
echo ""
echo "IP/Mask: $IP_ADDR"
echo "Gateway: $GATEWAY"
echo ""
echo "------------------------------------------"
echo "Press ENTER to proceed, or Ctrl+C to cancel."
read

echo "--- Downloading and Unpacking Image ---"
$WGET_BIN -O "$IMG_ZIP" "$URL" || { echo "Download failed"; exit 1; }
$UNZIP_BIN "$IMG_ZIP" || { echo "Unzip failed"; exit 1; }
IMG_FILE=$(ls *.img 2>/dev/null | head -n 1)
[ -z "$IMG_FILE" ] && { echo "Error: .img file not found in the archive."; exit 1; }

echo "--- Identifying System Disk ---"
# Find the parent device for the root partition /
DISK=$(lsblk -no pkname $(findmnt -nvo source /))
if [ -z "$DISK" ]; then
    # Fallback if partition name is empty
    DISK=$(fdisk -l | grep "Disk /dev/" | head -n 1 | awk '{print $2}' | cut -d: -f1)
fi

# Check if DISK is still empty
if [ -z "$DISK" ]; then
    echo "ERROR: Could not determine the system disk."
    echo "Please check 'lsblk' or 'fdisk -l' manually."
    exit 1
fi

echo ""
echo "!!! WARNING !!!"
echo "The script will overwrite the disk: /dev/$DISK"
echo "All current data will be PERMANENTLY DELETED."
echo "Press ENTER to proceed, or Ctrl+C to cancel."
read

echo "--- Writing Image to Disk ---"
# Force filesystem to Read-Only mode to avoid conflicts
sync
sleep 1
echo u > /proc/sysrq-trigger
# Write the image
sleep 1
dd if="$IMG_FILE" of="/dev/$DISK" bs=1M oflag=sync || { echo "Disk write failed"; exit 1; }

echo "--- Done! ---"
echo "The server will reboot in 5 seconds."
echo "Use your VNC console to log in (User: admin, No Password)."
sleep 5

# Trigger immediate hardware reboot
echo 1 > /proc/sys/kernel/sysrq
echo b > /proc/sysrq-trigger
