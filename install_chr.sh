#!/bin/bash

# Проверка типа загрузчика (UEFI vs BIOS)
if [ -d /sys/firmware/efi ]; then
    echo "ОШИБКА: Обнаружен загрузчик UEFI."
    echo "Данный скрипт предназначен только для Legacy BIOS."
    echo "Для установки на UEFI обратитесь к поиску (требуется другой метод разметки)."
    exit 1
fi

# Проверка наличия аргумента
if [ -z "$1" ]; then
    echo "Usage: $0 <CHR_IMAGE_ZIP>"
    echo "Example: $0 chr-7.22.1-arm64.img.zip"
    echo "Go to https://mikrotik.com/download/chr and copy url to img.zip"
    exit 1
fi

URL=$1
IMG_ZIP="chr_image.zip"

cd /tmp || exit 1

echo "--- Подготовка системы ---"
apt-get update
apt-get install -y wget unzip

echo "--- Скачивание образа ---"
wget -O "$IMG_ZIP" "$URL"

echo "--- Распаковка ---"
# Распаковываем и берем первый попавшийся .img файл
unzip "$IMG_ZIP"
IMG_FILE=$(ls *.img | head -n 1)

if [ -z "$IMG_FILE" ]; then
    echo "Ошибка: .img файл не найден в архиве."
    exit 1
fi

echo "--- Определение системного диска ---"
# Берем диск, на котором смонтирован корень /
DISK=$(lsblk -no pkname $(findmnt -nvo source /))
if [ -z "$DISK" ]; then
    # Если lsblk не отдал имя (бывает на старых ядрах), ищем через fdisk
    DISK=$(fdisk -l | grep "Disk /dev/" | head -n 1 | awk '{print $2}' | cut -d: -f1)
fi

echo "Обнаружен системный диск: /dev/$DISK"

# Подтверждение (опционально, можно закомментировать для полной автоматизации)
echo "ВНИМАНИЕ: Все данные на /dev/$DISK будут уничтожены. Нажмите Enter для продолжения или Ctrl+C для отмены."
read

echo "--- Запись образа на диск ---"
# Монтируем диск в режим "только чтение", чтобы минимизировать ошибки при затирании живой системы
echo u > /proc/sysrq-trigger
dd if="$IMG_FILE" of="/dev/$DISK" bs=4M oflag=sync

echo "--- Перезагрузка ---"
echo "Установка завершена. Сервер будет перезагружен через 3 секунды."
sleep 3
echo 1 > /proc/sys/kernel/sysrq
echo b > /proc/sysrq-trigger
