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
	# Urutan DIHASILKAN dari graf depends modinfo (topological sort,
	# 39 modul, siklus=0): cqhci-mtk_mmc-dbg dsb. sebelum mtk-mmc.
	# Fase initramfs = closure boot-kritis (eMMC + pmic + clk + iommu).
	MODS="aee_aed.ko buildvariant.ko emicen.ko iommu_secure.ko irq-dbg.ko \
mrdump.ko mt6358-regulator.ko mt635x-auxadc.ko mt6397.ko mt6577_auxadc.ko \
mtk_boot_common.ko mtk_iommu_util.ko mtk-mmc-wp.ko mtk-scpsys-mt6768.ko \
oplusboot.ko pinctrl-mtk-v2.ko rpmb.ko timer-mediatek.ko clk-common.ko \
mtk-pmic-wrap.ko mtk-smi.ko blocktag.ko iommu_debug.ko \
oplus_bsp_boot_projectinfo.ko pinctrl-mtk-common-v2_debug.ko rpmb-mtk.ko \
clk-fmeter-mt6768.ko clk-mt6768.ko clk-mt6768-pg.ko clkchk-mt6768.ko \
clkdbg-mt6768.ko mtk-smi-dbg.ko cqhci.ko device_info.ko i2c-mt65xx.ko \
mtk-mmc-dbg.ko pd-chk-mt6768.ko mtk_iommu.ko mtk-mmc.ko"
	# 3 pass: modul yang gagal karena dependensinya belum ke-load di
	# pass sebelumnya berpeluang sukses di pass berikutnya.
	for pass in 1 2 3; do
		for mod in $MODS; do
			f=$(find /lib/modules -name "$mod" 2>/dev/null | head -n 1)
			[ -n "$f" ] || continue
			if ! /usr/bin/force_insmod "$f" >/dev/null 2>&1; then
				[ "$pass" = "3" ] && echo "  ossi: GAGAL load $mod"
			fi
		done
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
