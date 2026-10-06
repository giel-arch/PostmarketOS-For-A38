#!/bin/sh
# OPPO A38 (ossi): USB NCM gadget + muat modul vendor sisa
# Perangkat: 172.16.42.1 (ssh root@172.16.42.1 dari host 172.16.42.2)

LOAD() {
	f="/lib/modules/vendor-force/$1"
	name=$(echo "$1" | sed 's/\.ko$//; s/-/_/g')
	# sudah termuat? (EEXIST bukan kegagalan)
	grep -qE "^($name|${1%.ko}) " /proc/modules 2>/dev/null && return 0
	if [ -f "$f" ]; then
		/usr/bin/force_insmod "$f" >/dev/null 2>&1 || \
			logger -t usb-gadget "GAGAL load $1"
	fi
}

# URUTAN RESMI VENDOR: modules.load (daftar boot normal Android) dari
# vendor_boot — 196 modul, termasuk USB/display/touch.
if [ -f /lib/modules/vendor-force/modules.load ]; then
	while read -r mod; do
		case "$mod" in *.ko) LOAD "$mod";; esac
	done < /lib/modules/vendor-force/modules.load
else
	# fallback: rantai inti USB + tampilan + sentuh
	for m in extcon-mtk-usb phy-mtk-tphy phy-generic musb_hdrc musb_main \
	         i2c-mt65xx mediatek-drm drm_display_helper drm_dma_helper \
	         mtk_panel_ext pwm-mtk-disp leds-mtk-disp ocp2130_drv \
	         ac114_p_3_a0013_hd_dsi_vdo \
	         oplus_bsp_tp_custom oplus_bsp_tp_ilitek_common \
	         oplus_bsp_tp_ilitek7807s; do
		LOAD "$m.ko"
	done
fi

# Gadget NCM via configfs
[ -d /sys/kernel/config/usb_gadget ] || \
	mount -t configfs none /sys/kernel/config 2>/dev/null

G=/sys/kernel/config/usb_gadget/g1
mkdir -p "$G/functions/ncm.usb0" "$G/strings/0x409" "$G/configs/c.1" 2>/dev/null
echo "OPPO A38 (pmOS)" > "$G/strings/0x409/product" 2>/dev/null
echo "postmarketOS" > "$G/strings/0x409/manufacturer" 2>/dev/null
ln -sfn "$G/functions/ncm.usb0" "$G/configs/c.1/f1" 2>/dev/null

UDC=$(ls /sys/class/udc 2>/dev/null | head -n 1)
if [ -n "$UDC" ]; then
	echo "$UDC" > "$G/UDC" 2>/dev/null
fi

sleep 1
ip link set usb0 up 2>/dev/null
ip addr add 172.16.42.1/24 dev usb0 2>/dev/null
