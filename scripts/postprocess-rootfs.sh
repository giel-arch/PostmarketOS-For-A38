#!/bin/bash
# Post-process rootfs image OPPO A38 (ossi).
#
#   $1 = direktori export pmbootstrap (berisi oppo-a38.img GPT berisi
#        p1 pmOS_boot + p2 pmOS_root, plus initramfs/initramfs-extra/
#        vmlinuz-oppo-a38)
#
# Hasil: oppo-a38.img DIGANTI menjadi partisi root SAJA (ext4 murni,
# label pmOS_root) yang sudah berisi /boot/{vmlinuz,initramfs,initramfs-extra}.
# Diflash ke userdata (mmcblk0p59) -> root langsung ter-mount lewat
# path mmcblk eksplisit + mode stowaway initramfs (initramfs-extra
# diambil dari /boot di dalam rootfs).
set -euo pipefail

EXPORT="$1"
IMG="$EXPORT/oppo-a38.img"

# Hasil pmbootstrap export milik root — samakan akses agar debugfs/dd
# bisa jalan sebagai user CI
sudo chmod a+rw "$IMG" "$EXPORT"/initramfs "$EXPORT"/initramfs-extra \
	"$EXPORT"/vmlinuz-* 2>/dev/null || true

# Offset & ukuran p2 (sektor 512B) dari tabel GPT
LINE=$(sfdisk -d "$IMG" | grep 'img2')
START=$(echo "$LINE" | sed 's/.*start= *\([0-9]*\).*/\1/')
SIZE=$(echo "$LINE" | sed 's/.*size= *\([0-9]*\).*/\1/')
echo "[ossi] p2: start=$START size=$SIZE (sektor 512B)"

# Suntik file /boot ke partisi root (debugfs, tanpa mount)
for f in vmlinuz-oppo-a38 initramfs initramfs-extra; do
	debugfs -w -R "write $EXPORT/$f /boot/$f" "$IMG" 2>&1 | grep -v 'Filesystem' || true
done
# pastikan benar-benar tertulis
for f in vmlinuz-oppo-a38 initramfs initramfs-extra; do
	debugfs -R "ls -l /boot" "$IMG" 2>/dev/null | grep -q "$f" || {
		echo "[ossi] GAGAL menulis /boot/$f"; exit 1; }
done

# Ekstrak p2 menjadi image rootfs tunggal
TMP="$EXPORT/oppo-a38-root.img"
dd if="$IMG" of="$TMP" bs=512 skip="$START" count="$SIZE" status=none
mv "$TMP" "$IMG"

# Sanity: label tetap pmOS_root
file "$IMG" | grep -q 'pmOS_root' || { echo "[ossi] label pmOS_root hilang!"; exit 1; }
echo "[ossi] rootfs tunggal siap: $IMG ($(stat -c%s "$IMG") byte)"
