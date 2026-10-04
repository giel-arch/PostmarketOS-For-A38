# postmarketOS (Nura) untuk OPPO A38

Port **postmarketOS** (yang kini bernama **Nura**) untuk **OPPO A38 / CPH2579**
(codename vendor: `ossi`) — MediaTek Helio G85 (MT6769V/CZ, platform `mt6768`,
board `k69v1_64`), Android 15, slot **B**, eMMC 128GB.

**Repo ini membangun SEMUA di GitHub Actions** — kernel, rootfs, sampai
boot image jadi. Cukup trigger workflow `Build postmarketOS (OPPO A38)`,
lalu unduh artifact `pmOS-oppo-a38` dan flash.

## Repositori terkait

| Repo | Isi |
|---|---|
| [giel-arch/kernel-mt6769-a38](https://github.com/giel-arch/kernel-mt6769-a38) | Source kernel (GKI 6.6.30, `oppo_a38_defconfig`) |
| [giel-arch/Kernel-mt6769-a38-PMOS](https://github.com/giel-arch/Kernel-mt6769-a38-PMOS) | Fragmen config pmOS + workflow build kernel + `boot-pmos.img` |
| **giel-arch/PostmarketOS-For-A38** (repo ini) | Device package pmOS + workflow build image lengkap |

## Mengapa percobaan lama gagal (dan apa yang diperbaiki)

1. **`CONFIG_DEVTMPFS` tidak aktif** di kernel sebelumnya. Initramfs pmOS
   menjalankan `mount -t devtmpfs dev /dev` — tanpa itu `/dev` kosong dan
   init tidak pernah menemukan partisi. Sekarang `pmos.fragment` memaksa
   `DEVTMPFS=y`.
2. **Partisi dicari lewat nama/label** yang dibuat ueventd Android
   (`/dev/disk/by-partlabel/...` — tidak ada di pmOS). Sekarang rootfs
   dituju **eksplisit lewat path mmcblk**: `root_path=/dev/mmcblk0p59`
   (userdata) diinjeksi ke initramfs, plus fallback label `pmOS_root`.
3. **`initramfs-extra` tidak dimuat** (butuh partisi boot yang tidak kita
   punya). Sekarang initramfs + initramfs-extra **digabung** sehingga
   `jump_init_2nd` langsung ke stage 2 tanpa partisi boot.
4. **Modul vendor MTK tidak bisa dimuat** (vermagic beda). Sekarang
   dimuat paksa via `force_insmod` (`finit_module` +
   `MODULE_INIT_IGNORE_VERMAGIC/MODVERSIONS`), baik di initramfs
   (dari vendor_boot ramdisk) maupun di rootfs (paket
   `mtk-vendor-modules`).
5. Kompresi ramdisk **tetap lz4_legacy** (kernel gagal membaca gzip yang
   mengikuti ramdisk lz4_legacy vendor_boot) — magiskboot repack menjaga
   format aslinya.

## Cara pakai (GitHub Actions)

1. Buka tab **Actions** → **Build postmarketOS (OPPO A38)** → **Run workflow**.
2. Tunggu (~40-60 menit: build kernel + pmbootstrap + repack).
3. Unduh artifact `pmOS-oppo-a38` → berisi:
   - `boot-pmos.img` — kernel pmOS (ditempel ke boot_b stok)
   - `init_boot-pmos.img` — initramfs pmOS (ditempel ke init_boot_b bersih)
   - `oppo-a38.img` — rootfs (diflash ke userdata)
   - `vbmeta_b.bin` + `FLASH.txt`

### Flashing (slot B, dari fastboot/bootloader)

```
adb reboot bootloader
fastboot flash boot_b boot-pmos.img
fastboot flash init_boot_b init_boot-pmos.img
fastboot flash userdata oppo-a38.img        # MENGHAPUS data Android!
fastboot flash vbmeta_b --disable-verity --disable-verification vbmeta_b.bin
fastboot reboot
```

> `vendor_boot_b` **tidak disentuh** — DTB + modul vendor tetap dari situ
> (yang terpasang sekarang sudah versi OrangeFox, hanya `recovery.cpio`
> yang beda). `super` juga tidak disentuh.

### Masuk ke sistem

- **SSH via USB** (layar belum jalan): di komputer set IP statis
  `172.16.42.2/24` pada interface USB, lalu `ssh root@172.16.42.1`
  (password `147147` — ubah sesudah login).
- Konsol serial/UART: `8250_mtk.ko` dimuat via `vendor-force`.

## Status

| Fitur | Status |
|---|---|
| Boot kernel + initramfs | ✅ dirancang (butuh diuji) |
| eMMC (`mtk-mmc` force-load) | ✅ boot-kritis |
| USB gadget MUSB + SSH | ✅ boot-kritis |
| Layar (mediatek-drm + panel ili7807s + ocp2130) | ⚠️ modul ada, belum diuji |
| Sentuh (ilitek7807s) | ⚠️ modul ada, belum diuji |
| WiFi/BT/audio/modem | ❌ WIP |

## Build lokal (tanpa CI)

`pmbootstrap` (install: `pipx install git+https://gitlab.postmarketos.org/postmarketOS/pmbootstrap.git`),
lalu salin `device/testing/*` ke `$HOME/.local/var/pmbootstrap/cache_git/pmaports/device/testing/`,
`pmbootstrap config device oppo-a38`, build paket, `pmbootstrap install`, dan jalankan
`scripts/repack-initboot.sh`.

## Memulihkan Android

Dump lengkap ada di `~/WorkSpace/OPPO A38/` — flash ulang `boot_b.bin`,
`init_boot_b.bin`, `vbmeta_b.bin`, dan (jika userdata hilang) reflashing
super + userdata dari dump/OTA.
