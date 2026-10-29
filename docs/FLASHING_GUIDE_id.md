# Tanzanite Halium 12 Panduan Flashing & Instalasi Dual-Boot

> **Perangkat**: Redmi Note 14 4G (`tanzanite`, MediaTek Helio G99 MT6789), dual-boot HyperOS + Ubuntu Touch 20.04 (Halium 12), partisi `/data` ext4 tanpa enkripsi.
> 
> **Bahasa lain / Other languages**: [English (FLASHING_GUIDE_en.md)](FLASHING_GUIDE_en.md)

---

Panduan langkah demi langkah untuk menginstal **Ubuntu Touch 20.04 (Focal Fossa)** secara dual-boot bersama **HyperOS / Android** pada **Redmi Note 14 4G (`tanzanite`)**.

---

## 1. Prasyarat dan File yang Dibutuhkan

### Persyaratan Perangkat
- **Perangkat**: Redmi Note 14 4G (`tanzanite`, MediaTek Helio G99 MT6789).
- **Bootloader**: Sudah di-unlock (UBL).
- **Custom Recovery**: Terpasang OrangeFox Recovery atau TWRP dengan dukungan partisi A/B dan terminal.
- **Root di Android (HyperOS)**: Terpasang KernelSU (direkomendasikan) atau Magisk agar aplikasi switcher dapat berjalan.

### File yang Dibutuhkan
1. **`Format-Data-Ext4-Tanzanite.zip`**: File flashable recovery untuk memformat partisi `userdata` ke ext4 tanpa enkripsi (mengatasi kendala bawaan GUI OrangeFox).
2. **`tanzanite-halium.zip`**: File installer recovery utama (berisi kernel Halium, patch vendor, patch AVB, rootfs Ubuntu Touch, dan overlay driver).
3. **`TanzaniteSwitcher-v1.0.0.apk`**: Aplikasi Android untuk berpindah sistem operasi secara instan.
4. Kartu MicroSD atau flashdisk OTG (atau komputer dengan kabel data untuk ADB sideload / push).

> [!CAUTION]
> Format data akan menghapus seluruh isi penyimpanan internal. Karena Ubuntu Touch memerlukan partisi `userdata` berformat ext4 tanpa enkripsi, salin semua data penting ke komputer atau MicroSD sebelum melanjutkan.

---

## 2. Langkah Instalasi

### Langkah 1: Masuk ke Custom Recovery
1. Matikan perangkat.
2. Tahan tombol **Power + Volume Up** secara bersamaan hingga logo recovery (OrangeFox atau TWRP) muncul.

### Langkah 2: Format Data ke ext4 Tanpa Enkripsi
> [!TIP]
> OrangeFox versi Tanzanite sering gagal atau tertahan saat memformat `/data` atau mengubah filesystem ke ext4 lewat antarmuka bawaan. Gunakan **Metode A** dengan file zip yang telah disediakan agar proses format bersih dan tuntas.

#### Metode A: Menggunakan Flashable Zip (Direkomendasikan)
1. Salin `Format-Data-Ext4-Tanzanite.zip` ke MicroSD atau flashdisk OTG (atau gunakan menu **Advanced > ADB Sideload**).
2. Di recovery, buka menu **Install** (atau jalankan `adb sideload Format-Data-Ext4-Tanzanite.zip`).
3. Geser penggeser konfirmasi untuk mem-flash. Script akan otomatis:
   - Melepaskan kuncian proses dan melakukan unmount paksa pada `/data` dan `/sdcard`.
   - Mengosongkan header dan footer partisi untuk membersihkan signature F2FS dan token enkripsi FBE lama.
   - Memformat partisi `userdata` ke ext4 ukuran blok 4K (`-b 4096`) dengan alokasi cadangan 1%.
   - Menginisialisasi kerangka folder penyimpanan internal `/data/media/0` dengan izin akses `media_rw`.
4. Reboot ke recovery (wajib):
   - Pilih menu **Reboot** > **Recovery**.
   - Langkah ini diperlukan agar kernel recovery mengenali tabel partisi ext4 yang baru.

#### Metode B: Manual Melalui Menu Recovery
1. Pada menu utama recovery, masuk ke **Wipe** > pilih **Format Data**.
2. Ketik `yes` lalu konfirmasi.
3. Masuk ke **Manage Partitions** / **Partition Options**:
   - Pilih partisi **Data** > ketuk **Change FS** > pilih **ext4** > geser konfirmasi.
   - Jika tersedia di menu, lakukan hal yang sama pada partisi **Metadata** ke format **ext4**.
4. Reboot ke recovery (wajib):
   - Pilih **Reboot** > **Recovery**.

### Langkah 3: Pastikan Slot Aktif Berada di Slot A
1. Buka menu **Reboot** di recovery.
2. Pastikan slot aktif saat ini adalah **Slot A**:
   - Jika saat ini berada di Slot B, ubah ke Slot A lalu reboot kembali ke recovery.
   - Slot B dibiarkan utuh sebagai cadangan darurat (fallback) HyperOS bawaan.

### Langkah 4: Flash Installer `tanzanite-halium.zip`
1. Hubungkan ponsel ke komputer menggunakan kabel data atau pasang MicroSD / OTG.
2. Kirim file `tanzanite-halium.zip` ke perangkat:
   ```bash
   adb push tanzanite-halium.zip /sdcard/
   # atau jika storage belum ter-mount:
   adb push tanzanite-halium.zip /tmp/
   ```
3. Di recovery, buka menu **Install** / **Files**.
4. Pilih file `tanzanite-halium.zip` lalu geser konfirmasi pemasangan.
5. Proses instalasi akan berjalan secara otomatis:
   - Mem-patch `/vendor/etc/fstab.mt6789` untuk mengarahkan userdata ke ext4 tanpa enkripsi.
   - Menonaktifkan verifikasi AVB dan dm-verity pada `vbmeta`, `vbmeta_system`, dan `vbmeta_vendor`.
   - Membuat cadangan partisi `boot`, `vendor_boot`, dan `dtbo` bawaan ke `/sdcard/.backup/`.
   - Mengekstrak rootfs Ubuntu Touch dan container Halium ke `/data/ubuntu`.
   - Memasang driver tampilan HWC2, konfigurasi audio, udev rules, dan pengaturan sandboxing `apt`.
   - Mem-flash image kernel Halium (`boot`, `vendor_boot`, `dtbo`) ke Slot A.

### Langkah 5: Booting Pertama ke Ubuntu Touch
1. Setelah pesan `Patching completed successfully!` muncul, pilih **Reboot System**.
2. Perangkat akan langsung booting ke antarmuka Ubuntu Touch (Lomiri).
3. Selesaikan panduan pengaturan awal di layar (pilihan bahasa, Wi-Fi, dan sandi kunci).
   - Pengguna default: `phablet`
   - Akses root terminal: perintah utilitas tertentu dapat dijalankan menggunakan `sudo` tanpa memerlukan kata sandi.

---

## 3. Fitur Dual-Boot

### Beralih dari Ubuntu Touch ke HyperOS (Android)
1. Buka aplikasi **Terminal** di Ubuntu Touch.
2. Jalankan perintah:
   ```bash
   sudo boot-to-android
   ```
3. Script akan memulihkan kernel Android bawaan dan me-reboot ponsel ke HyperOS.

### Beralih dari HyperOS ke Ubuntu Touch
1. Setelah masuk ke HyperOS, pasang aplikasi switcher:
   - Pasang berkas [TanzaniteSwitcher-v1.0.0.apk](file:///home/fxxyz73/tanzanite-halium/TanzaniteSwitcher-v1.0.0.apk).
2. Buka aplikasi **Tanzanite Switcher**.
3. Berikan izin root saat jendela KernelSU atau Magisk muncul.
4. Pada tampilan aplikasi, ketuk tombol **Switch to Ubuntu Touch**.
5. Aplikasi akan menulis image kernel Halium dari cadangan lokal dan me-reboot perangkat kembali ke Ubuntu Touch.

---

## 4. Pemecahan Masalah

### Akses Penyimpanan Internal (`/sdcard`) Tertolak di HyperOS
Jika aplikasi di HyperOS tidak dapat membaca galeri, folder unduhan, atau `/sdcard`:
- **Penyebab**: FUSE-BPF pada kernel MT6789 memblokir akses ketika folder `/data/media/0` belum memiliki izin kepemilikan `media_rw` pada userdata ext4 yang didekripsi.
- **Solusi**:
  1. Pasang modul terpisah [Tanzanite-HyperOS-SDCard-Fix-KSU.zip](file:///home/fxxyz73/tanzanite-halium/out/Tanzanite-HyperOS-SDCard-Fix-KSU.zip) langsung lewat aplikasi **KernelSU** / **Magisk** di HyperOS, atau flash zip tersebut di OrangeFox Recovery.
  2. Modul ini secara otomatis mengatur properti `ro.fuse.bpf.enabled=false`, `ro.fuse.bpf.is_running=false`, `persist.sys.fuse.bpf.override=false`, dan `persist.sys.fuse.passthrough.enable=false` pada tahap `post-fs-data`.
  3. Jika diperlukan, buka terminal root di Android lalu perbaiki izin direktori:
     ```sh
     chown -R 1023:1023 /data/media
     chmod 770 /data/media
     chmod 2770 /data/media/0
     ```

### Kendala Dependensi Paket `apt install` di Ubuntu Touch
- **Penyebab**: Mekanisme sandbox user `_apt` tidak didukung pada container Halium, dan paket metapackage lama merujuk ke driver HWC1 yang sudah tidak digunakan.
- **Solusi**: File installer `tanzanite-halium.zip` sudah mengatur konfigurasi ini secara default. Jika memperbaiki instalasi manual, pastikan baris berikut tersimpan di `/etc/apt/apt.conf.d/90-android-sandbox.conf`:
  ```text
  APT::Sandbox::User "root";
  ```
- Pembahasan teknis mendalam dapat dibaca pada [TROUBLESHOOTING_SDCARD_APT.md](file:///home/fxxyz73/tanzanite-halium/docs/TROUBLESHOOTING_SDCARD_APT.md).

---

## 5. Komunitas dan Kontak

- Repositori: [https://github.com/iprjkt/tanzanite-halium](https://github.com/iprjkt/tanzanite-halium)
- Grup Diskusi Telegram: [https://t.me/idiscuss1](https://t.me/idiscuss1)
- Kontak Maintainer Telegram: [https://t.me/anotherside551](https://t.me/anotherside551)
- Donasi dan Dukungan: [https://sociabuzz.com/fxxyz73/tribe](https://sociabuzz.com/fxxyz73/tribe)
