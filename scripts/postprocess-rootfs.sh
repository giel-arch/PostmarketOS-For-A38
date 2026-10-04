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

# Hasil pmbootstrap export milik root — samakan akses agar dd bisa jalan
sudo chmod a+rw "$IMG" "$EXPORT"/initramfs "$EXPORT"/initramfs-extra \
	"$EXPORT"/vmlinuz-* 2>/dev/null || true

# Offset & ukuran p2 (sektor 512B) dari tabel GPT
LINE=$(sfdisk -d "$IMG" | grep 'img2')
START=$(echo "$LINE" | sed 's/.*start= *\([0-9]*\).*/\1/')
SIZE=$(echo "$LINE" | sed 's/.*size= *\([0-9]*\).*/\1/')
echo "[ossi] p2: start=$START size=$SIZE (sektor 512B)"

# Ekstrak p2 dulu menjadi ext4 murni (debugfs tidak bisa buka GPT)
TMP="$EXPORT/oppo-a38-root.img"
dd if="$IMG" of="$TMP" bs=512 skip="$START" count="$SIZE" status=none
file "$TMP" | grep -q 'pmOS_root' || { echo "[ossi] label pmOS_root hilang!"; exit 1; }

# Suntik file /boot ke rootfs ekstraksi (debugfs, tanpa mount)
for f in vmlinuz-oppo-a38 initramfs initramfs-extra; do
	debugfs -w -R "write $EXPORT/$f /boot/$f" "$TMP" 2>&1 | grep -v 'debugfs 1\|Filesystem' || true
done
# pastikan benar-benar tertulis
for f in vmlinuz-oppo-a38 initramfs initramfs-extra; do
	debugfs -R "ls -l /boot" "$TMP" 2>/dev/null | grep -q "$f" || {
		echo "[ossi] GAGAL menulis /boot/$f"; exit 1; }
done

mv "$TMP" "$IMG"
echo "[ossi] rootfs tunggal siap: $IMG ($(stat -c%s "$IMG") byte)"
