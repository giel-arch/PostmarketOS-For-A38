#!/bin/bash
# Repack init_boot OPPO A38 (ossi) untuk postmarketOS/Nura.
#
#   $1 = root repo PostmarketOS-For-A38
#   $2 = direktori export pmbootstrap (berisi initramfs, initramfs-extra)
#   $3 = path output init_boot-pmos.img
#
# Batasan keras: partisi init_boot perangkat hanya 8MB, jadi HANYA
# initramfs utama yang masuk ke sini (bukan gabungan dengan -extra).
#
# Apa yang dilakukan:
#   1. Perbaiki tabrakan /lib: vendor_boot ramdisk menyediakan /lib
#      (dir berisi modul vendor), initramfs pmOS punya /lib ->
#      usr/lib (symlink). /lib jadi dir sungguhan berisi isi usr/lib.
#   2. force_insmod + daftar modul vendor boot-kritis dimuat lebih
#      awal (vermagic modul vendor != build kita).
#   3. Default runtime diinjeksi (cmdline boot kita kosong karena
#      repack magiskboot mempertahankan header stok):
#        - root_path=/dev/mmcblk0p59  (userdata, ext4 murni hasil
#          postprocess-rootfs.sh)
#        - stowaway=y  (mode pmOS "boot di rootfs": initramfs-extra
#          diambil dari /boot di dalam rootfs)
#   4. cpio mentah -> magiskboot repack (kompres lz4_legacy, format
#      asli init_boot; gzip setelah lz4_legacy vendor TIDAK bisa
#      dibaca kernel).
set -euo pipefail

REPO="$1"; EXPORT="$2"; OUT="$3"
WORK="$(mktemp -d)"
cd "$WORK"
echo "[ossi] work dir: $WORK"

# --- magiskboot ---
curl -sL -o magisk.apk \
	https://github.com/topjohnwu/Magisk/releases/download/v28.1/Magisk-v28.1.apk
python3 -c "import zipfile; zipfile.ZipFile('magisk.apk').extract('lib/x86_64/libmagiskboot.so')"
cp lib/x86_64/libmagiskboot.so magiskboot && chmod +x magiskboot

# --- force_insmod untuk initramfs (aarch64, static) ---
aarch64-linux-gnu-gcc -static -O2 "$REPO/scripts/force_insmod.c" -o force_insmod

# --- unpack init_boot bersih (tanpa KernelSU) ---
cp "$REPO/assets/init_boot_b-clean.bin" .
./magiskboot unpack init_boot_b-clean.bin

# --- ekstrak initramfs utama SAJA ---
mkdir rd
cd rd
gzip -dc "$EXPORT/initramfs" | cpio -id --no-absolute-filenames 2>/dev/null

# --- perbaikan /lib (vendor_boot = dir /lib; pmOS = symlink) ---
rm -f lib
mv usr/lib lib
ln -s ../lib usr/lib
rm -rf lib/modules

# --- force_insmod ke initramfs ---
cp ../force_insmod usr/bin/force_insmod
chmod +x usr/bin/force_insmod

# --- patch init_functions.sh: default runtime + helper ---
cat >> init_functions.sh <<'OSSI_EOF'

# === OPPO A38 (ossi) pmOS port patches ===
# Mode stowaway: /boot ada DI DALAM rootfs (partisi userdata diekstrak
# menjadi ext4 murni oleh postprocess-rootfs.sh, tanpa GPT nested).
stowaway="${stowaway:-y}"
force_load_mtk_modules() {
	echo "  ossi: force-loading MTK vendor modules..."
	# URUTAN RESMI VENDOR: modules.load.recovery dari vendor_boot
	# vendor_ramdisk (Android recovery memuatnya via modprobe urutan
	# yang sama; kita pakai force_insmod). 3 pass meniru resolusi
	# dependensi modprobe. Modul termuat dicatat di /lib/modules/.loaded
	# (EEXIST bukan kegagalan).
	LOADFILE=/lib/modules/modules.load.recovery
	load_one() {
		mod="$1"
		printf '.'   # penanda posisi urutan: modul ke-N titik = modul ke-N di daftar
		grep -qxF "$mod" /lib/modules/.loaded 2>/dev/null && return 0
		f=$(find /lib/modules -name "$mod" 2>/dev/null | head -n 1)
		[ -n "$f" ] || return 0
		if /usr/bin/force_insmod "$f" >/dev/null 2>&1; then
			echo "$mod" >> /lib/modules/.loaded
		elif [ "$pass" = "3" ]; then
			echo ""
			echo "  ossi: GAGAL load $mod (titik ke-$(grep -c . /lib/modules/.loaded 2>/dev/null))"
		fi
	}
	msdc_diag() {
		# Diagnostik status eMMC/msdc -> console (terbaca via pstore
		# pada boot berikutnya).
		echo "  ossi: diag mtk-msdc:"
		grep mtk_mmc /proc/modules 2>/dev/null || echo "  ossi: mtk_mmc TIDAK termuat"
		if [ -d /sys/bus/platform/drivers/mtk-msdc ]; then
			echo "  ossi: driver mtk-msdc terdaftar"
			for d in 11230000.mmc 11240000.mmc; do
				if [ -e "/sys/bus/platform/devices/$d" ] && \
				   [ ! -e "/sys/bus/platform/drivers/mtk-msdc/$d" ]; then
					echo "  ossi: bind paksa $d"
					echo "$d" > /sys/bus/platform/drivers/mtk-msdc/bind 2>/dev/null
				fi
			done
		else
			echo "  ossi: driver mtk-msdc TIDAK terdaftar!"
		fi
		ls /dev/mmcblk* 2>/dev/null || echo "  ossi: tidak ada /dev/mmcblk*"
		dmesg 2>/dev/null | grep -iE 'msdc|mmc' | tail -12
	}
	for pass in 1 2 3; do
		if [ -f "$LOADFILE" ]; then
			while read -r mod; do
				case "$mod" in *.ko) load_one "$mod";; esac
			done < "$LOADFILE"
			echo ""
			echo "  ossi: pass $pass selesai ($(grep -c . /lib/modules/.loaded 2>/dev/null || echo 0) modul termuat)"
		else
			# fallback: daftar statis (bila file vendor tidak ada)
			for mod in clk-common.ko clk-mt6768.ko clk-mt6768-pg.ko \
			           mtk-pmic-wrap.ko mt6397.ko mt6358-regulator.ko \
			           mtk-scpsys.ko mtk-scpsys-mt6768.ko mcDrvModule.ko \
			           device_info.ko mtk-mmc-dbg.ko cqhci.ko \
			           rpmb-mtk.ko mtk-mmc.ko timer-mediatek.ko; do
				load_one "$mod"
			done
		fi
	done
	sleep 1
}
root_path_default() {
	# Rootfs pmOS = partisi userdata (mmcblk0p59). Path mmcblk
	# eksplisit, bukan by-name/by-partlabel (symlinks itu buatan
	# ueventd Android, tidak ada di pmOS).
	[ -z "$PMOS_ROOT" ] && [ -z "$root_uuid" ] && [ -z "$root_path" ] && \
		root_path="/dev/mmcblk0p59"
}
# === end ossi patches ===
OSSI_EOF

sed -i 's|^find_root_partition() {|find_root_partition() {\n\troot_path_default|' init_functions.sh
sed -i 's|^jump_init_2nd$|force_load_mtk_modules\njump_init_2nd|' init

# --- repack: cpio mentah, magiskboot kompres lz4_legacy ---
find . -print0 | cpio --null -o -H newc 2>/dev/null > ../ramdisk.cpio
cd ..
./magiskboot repack init_boot_b-clean.bin "$OUT"
SZ=$(stat -c%s "$OUT")
echo "[ossi] selesai: $OUT ($SZ byte)"
if [ "$SZ" -gt 8388608 ]; then
	echo "[ossi] PERINGATAN: melebihi 8MB partisi init_boot!"
	exit 1
fi
