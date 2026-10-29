# Tanzanite Halium 12 Dual-Boot Flashing & Installation Guide

> **Device**: Redmi Note 14 4G (`tanzanite`, MediaTek Helio G99 MT6789), dual-boot HyperOS + Ubuntu Touch 20.04 (Halium 12), unencrypted ext4 `/data`.
> 
> **Other languages / Bahasa lain**: [Bahasa Indonesia (FLASHING_GUIDE_id.md)](FLASHING_GUIDE_id.md)

---

Step-by-step installation guide for setting up **Ubuntu Touch 20.04 (Focal Fossa)** in a dual-boot configuration alongside **HyperOS / Android** on the **Redmi Note 14 4G (`tanzanite`)**.

---

## 1. Prerequisites and Required Files

### Device Requirements
- **Device**: Redmi Note 14 4G (`tanzanite`, MediaTek Helio G99 MT6789).
- **Bootloader**: Unlocked (UBL).
- **Custom Recovery**: OrangeFox Recovery or TWRP installed with A/B slot and terminal support.
- **Android Root (HyperOS)**: KernelSU installed (recommended) or Magisk to allow the switcher app to manage boot partitions.

### Required Files
1. **`Format-Data-Ext4-Tanzanite.zip`**: Flashable recovery utility to format the `userdata` partition to clean unencrypted ext4 (fixes OrangeFox GUI format bugs).
2. **`tanzanite-halium.zip`**: Main flashable recovery installer package (contains Halium kernel, vendor fstab patch, AVB patch, Ubuntu Touch rootfs, and device overlay).
3. **`TanzaniteSwitcher-v1.0.0.apk`**: Native Android companion app for 1-tap switching.
4. MicroSD card or USB OTG flash drive (or a computer with ADB cable for ADB sideload / push).

> [!CAUTION]
> Formatting userdata will erase all files on internal storage. Ubuntu Touch requires an unencrypted ext4 partition for `/data`. Back up important files to a computer or MicroSD card before proceeding.

---

## 2. Step-by-Step Installation

### Step 1: Boot into Custom Recovery
1. Power off the device completely.
2. Press and hold **Power + Volume Up** buttons simultaneously until the recovery splash screen (OrangeFox or TWRP) appears.

### Step 2: Format Data to Unencrypted ext4
> [!TIP]
> OrangeFox on Tanzanite frequently encounters errors or fails to completely strip FBE/F2FS metadata when formatting `/data` through the recovery touch menu. Use **Method A** with the provided flashable zip for a clean, reliable format.

#### Method A: Flashable Zip Utility (Recommended)
1. Copy `Format-Data-Ext4-Tanzanite.zip` to a MicroSD / USB OTG drive (or use **Advanced > ADB Sideload**).
2. In recovery, select **Install** (or run `adb sideload Format-Data-Ext4-Tanzanite.zip`).
3. Swipe the slider to confirm flash. The script will automatically:
   - Terminate active process locks and forcefully unmount `/data` and `/sdcard`.
   - Zero out partition headers and footers to erase old F2FS signatures and FBE crypto tokens.
   - Format `userdata` to 4K ext4 (`-b 4096`) with a 1% reservation ratio.
   - Initialize the `/data/media/0` internal storage directory structure with `media_rw` permissions.
4. Reboot to recovery (required):
   - Go to **Reboot** > select **Recovery**.
   - This step is necessary so the recovery kernel refreshes its partition table with the new ext4 filesystem.

#### Method B: Manual via Recovery Menu
1. From the recovery main menu, navigate to **Wipe** > select **Format Data**.
2. Type `yes` and confirm.
3. Open **Manage Partitions** / **Partition Options**:
   - Select the **Data** partition > tap **Change FS** > choose **ext4** > swipe to confirm.
   - If accessible in the recovery menu, perform the same step for the **Metadata** partition to format it to **ext4**.
4. Reboot to recovery (required):
   - Go to **Reboot** > select **Recovery**.

### Step 3: Verify Active Slot is Slot A
1. Navigate to the **Reboot** menu in recovery.
2. Verify that the active slot is **Slot A**:
   - If currently set to Slot B, switch to Slot A and reboot into recovery once more.
   - Slot B is kept untouched as a clean stock HyperOS fallback slot.

### Step 4: Flash `tanzanite-halium.zip`
1. Connect the phone to your computer or insert your MicroSD/OTG drive.
2. Push or copy `tanzanite-halium.zip` to the device:
   ```bash
   adb push tanzanite-halium.zip /sdcard/
   # or if storage is not mounted yet:
   adb push tanzanite-halium.zip /tmp/
   ```
3. In recovery, go to **Install** / **Files**.
4. Select `tanzanite-halium.zip` and swipe to confirm.
5. The installer will execute the following steps automatically:
   - Patches `/vendor/etc/fstab.mt6789` to mount userdata as unencrypted ext4.
   - Disables AVB verification and dm-verity on `vbmeta`, `vbmeta_system`, and `vbmeta_vendor`.
   - Backs up stock `boot`, `vendor_boot`, and `dtbo` partitions to `/sdcard/.backup/`.
   - Extracts Ubuntu Touch rootfs and the Halium container into `/data/ubuntu`.
   - Deploys HWC2 display platform drivers (`mir-android2`), audio routing, udev rules, and `apt` sandboxing configuration.
   - Flashes the Halium kernel (`boot`, `vendor_boot`, `dtbo`) into Slot A.

### Step 5: Initial Boot into Ubuntu Touch
1. Once the terminal displays `Patching completed successfully!`, select **Reboot System**.
2. The device will boot straight into the Ubuntu Touch (Lomiri) environment.
3. Complete the initial setup wizard on screen (language, Wi-Fi, lockscreen passcode).
   - Default user: `phablet`
   - Terminal access: predefined utility commands can be executed via `sudo` without entering a password.

---

## 3. Dual-Boot Switching

### Switching from Ubuntu Touch to HyperOS (Android)
1. Open the **Terminal** app on Ubuntu Touch.
2. Run:
   ```bash
   sudo boot-to-android
   ```
3. The script will restore the stock Android boot kernel and reboot your phone into HyperOS.

### Switching from HyperOS to Ubuntu Touch
1. Once booted into HyperOS, install the switcher companion app:
   - Install [TanzaniteSwitcher-v1.0.0.apk](file:///home/fxxyz73/tanzanite-halium/TanzaniteSwitcher-v1.0.0.apk).
2. Launch the **Tanzanite Switcher** app.
3. Grant root permissions when prompted by KernelSU or Magisk.
4. On the main dashboard, tap **Switch to Ubuntu Touch**.
5. The app writes the Halium boot partition from local backup and automatically reboots the phone into Ubuntu Touch.

---

## 4. Technical Notes and Troubleshooting

### Internal Storage (`/sdcard`) Permission Denied on HyperOS
If HyperOS apps cannot access photos, downloads, or internal storage:
- **Cause**: FUSE-BPF on the MT6789 kernel enforces strict lower-inode credential checks. If `/data/media/0` lacks `media_rw` group ownership on decrypted ext4 userdata, apps are denied access.
- **Fix**:
  1. Install the standalone module [Tanzanite-HyperOS-SDCard-Fix-KSU.zip](file:///home/fxxyz73/tanzanite-halium/out/Tanzanite-HyperOS-SDCard-Fix-KSU.zip) via the **KernelSU** or **Magisk** app in HyperOS, or flash it in OrangeFox Recovery.
  2. The module disables FUSE-BPF during early `post-fs-data` by applying `ro.fuse.bpf.enabled=false`, `ro.fuse.bpf.is_running=false`, `persist.sys.fuse.bpf.override=false`, and `persist.sys.fuse.passthrough.enable=false`.
  3. If needed, open a root terminal in Android and restore directory permissions:
     ```sh
     chown -R 1023:1023 /data/media
     chmod 770 /data/media
     chmod 2770 /data/media/0
     ```

### `apt install` Package Dependency Errors in Ubuntu Touch
- **Cause**: Sandboxing for the `_apt` user fails inside Halium LXC containers, and obsolete metapackages depend on deprecated HWC1 drivers.
- **Fix**: The `tanzanite-halium.zip` installer configures this automatically. For manual recovery, verify `/etc/apt/apt.conf.d/90-android-sandbox.conf` contains:
  ```text
  APT::Sandbox::User "root";
  ```
- Refer to [TROUBLESHOOTING_SDCARD_APT.md](file:///home/fxxyz73/tanzanite-halium/docs/TROUBLESHOOTING_SDCARD_APT.md) for deeper technical analysis.

---

## 5. Community and Support

- Repository: [https://github.com/iprjkt/tanzanite-halium](https://github.com/iprjkt/tanzanite-halium)
- Telegram Discussion Group: [https://t.me/idiscuss1](https://t.me/idiscuss1)
- Telegram Maintainer Contact: [https://t.me/anotherside551](https://t.me/anotherside551)
- Donation and Support: [https://sociabuzz.com/fxxyz73/tribe](https://sociabuzz.com/fxxyz73/tribe)
