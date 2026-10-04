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

# Urutan DIHASILKAN dari graf depends modinfo (topological sort,
# 55 modul, siklus=0). Fase rootfs = closure USB (MUSB + phy) +
# display (mediatek-drm + panel ili7807s + ocp2130) + touch (ilitek).
for mod in \
aee_aed.ko buildvariant.ko clkbuf.ko drm_display_helper.ko drm_dma_helper.ko \
emicen.ko irq-dbg.ko leds-mtk.ko mrdump.ko mtk_boot_common.ko \
mtk_disp_notify.ko mtk_dramc.ko mtk-dvfsrc.ko mtk-icc-core.ko \
mtk-mmdebug-vcp-stub.ko mtk-mmdvfs-ftrace.ko mtk_panel_ext.ko mtk_sync.ko \
ocp2130_drv.ko olc.ko oplus_bsp_fw_update.ko oplus_bsp_mm_osvelte.ko \
oplus_bsp_tp_ilitek_common.ko oplus_bsp_tp_notify.ko oplusboot.ko \
pd_dbg_info.ko phy-generic.ko phy-mtk-tphy.ko pwm-mtk-disp.ko spi_slave.ko \
clk-common.ko mmprofile.ko mtk-smi.ko iommu_debug.ko mme.ko \
oplus_boost_pool_mtk.ko oplus_bsp_boot_projectinfo.ko tcpc_class.ko \
mtk-smi-dbg.ko system_heap.ko device_info.ko oplus_bsp_tp_custom.ko \
extcon-mtk-usb.ko musb_hdrc.ko mtk-cmdq-drv-ext.ko mtk-mmdvfs.ko \
oplus_bsp_tp_common.ko musb_main.ko mtk-mml.ko mtk-mmdvfs-debug.ko \
oplus_bsp_tp_ilitek7807s.ko mmqos-common.ko mediatek-drm.ko \
leds-mtk-disp.ko oplus24700_ili7807s_tm_fhdp_dsi_vdo.ko
do
	LOAD "$mod"
done

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
