# Bootloader, AVB, and the "you must flash fenrir/lkpatcher first" advice

There is a persistent claim in tanzanite communities that Ubuntu Touch can only boot after patching
the bootloader with **fenrir** or **lkpatcher**. This document explains what those tools do, why the
claim does not apply to this device, and what to actually check if a boot fails before the kernel
runs.

**Short version:** you should not need an LK patch. The installer already disables Android Verified
Boot through `vbmeta`, which is the mechanism that matters here. `lkpatcher` cannot patch tanzanite
anyway — the tool only speaks ARM32 Thumb-2 and tanzanite's LK is AArch64.

---

## What fenrir and lkpatcher actually do

### fenrir

[`R0rt1z2/fenrir`](https://github.com/R0rt1z2/fenrir) is a proof-of-concept exploit for a logic flaw
in the MediaTek boot chain. Normal order:

```
BootROM -> Preloader -> bl2_ext (EL3, verified) -> TEE -> GenieZone -> LK/AEE -> Linux kernel
```

`bl2_ext` runs at **EL3**, the highest privilege level, and is responsible for verifying everything
after it. On affected devices, when seccfg is set to *unlocked*, the Preloader **skips verifying
`bl2_ext`**. So an attacker-controlled `bl2_ext` runs at EL3 and can patch
`sec_get_vfy_policy()` to always return 0, after which every downstream image is accepted
unverified. The entire chain of trust collapses.

**The repository is archived and deprecated.** The author states the code is "pretty much a
glorified Python framework for applying binary patches", kept the AArch64 version private, and
stopped maintaining it.

### lkpatcher

[`R0rt1z2/lkpatcher`](https://github.com/R0rt1z2/lkpatcher) is the maintained successor: a tool for
patching `lk.img` sub-partitions. Its default patch categories are:

| Category | Purpose |
| --- | --- |
| `fastboot` | Force the function checking the unlock bit to return 0 (unlocked) |
| `dm_verity` | Suppress the warning shown when vbmeta state is unexpected |
| `orange_state` | Suppress the "orange state" boot warning |
| `red_state` | Force the device-verification warning to return immediately |

Every needle in `DEFAULT_PATCHES` is ARM32 Thumb-2, and every replacement is `00207047`, which in
Thumb-2 assembles to `movs r0, #0; bx lr` — "return 0 immediately".

---

## Why this does not apply to tanzanite

### 1. The LK is AArch64, and lkpatcher is ARM32-only

Analysed against stock `lk.img` from firmware `OS2.0.214.0.VOGEUXM`:

```
lk.img (2,856,656 bytes) contains 4 partitions:
  1. lk           812,064 bytes
  2. bl2_ext    1,018,656 bytes
  3. aee          830,296 bytes
  4. lk_main_dtb  178,601 bytes
```

That is the same layout fenrir targets, and `sec_get_vfy_policy` **is** present as a string inside
the `lk` partition — so the underlying flaw may well be present. But the code is AArch64:

| Indicator | Count in `lk` partition |
| --- | --- |
| AArch64 `stp x29, x30` prologue (`fd7bbea9`) | **243** |
| Thumb-2 `push {r4-r7, lr}` (`2de9f0`) | 0 |
| ARM32 `push {r4, lr}` (`e92d4`) | 0 |

Running lkpatcher on the real image:

```
[INFO] Patching summary: 0/6 patches applied, 6 skipped
```

Nothing was patched because none of the ARM32 patterns exist in the binary. Note that `--dry-run`
reports `6/6 applied` — that is a bug in lkpatcher's dry-run mode, which does not actually verify
needle presence. Do not trust it.

### 2. AVB is the mechanism that matters, and it is already handled

Verified boot on this device is enforced through **Android Verified Boot** metadata in `vbmeta`,
`vbmeta_system` and `vbmeta_vendor`. The AVB header carries a flags field at byte offset 120:

| Flag | Meaning |
| --- | --- |
| `0x01` | verification disabled |
| `0x02` | verity disabled |
| `0x03` | both disabled |

Stock firmware ships these **all zero**, i.e. enforcement enabled:

```
vbmeta.img         8192 B  AVB0  flags = 0x00000000
vbmeta_system.img  4096 B  AVB0  flags = 0x00000000
vbmeta_vendor.img  4096 B  AVB0  flags = 0x00000000
```

The installer (`flashable_zips/update-binary.template.sh`, stage 8) writes `0x03` into byte 123 of
each of the three partitions on the active slot, then reads it back to confirm. That is what allows
the unsigned `boot.img` and `vendor_boot.img` built here to boot. No LK modification is involved.

### 3. The warnings are cosmetic

"Orange state" and "red state" are **text printed to the screen**. They do not block boot. Patching
LK to remove them changes nothing functional and carries real risk.

### 4. The risk is asymmetric

`bl2_ext` executes at EL3. A wrong offset there bricks the device until it is recovered through
EDL/DA or test points. The benefit is removing a warning and a check that the installer already
bypasses through a safer mechanism.

---

## What to do instead

### Just try flashing normally

Flash the v1.1.0 installer and see what happens. If it boots, you are done.

### If it fails before the kernel runs

Diagnose in this order:

```bash
# 1. Is the bootloader actually unlocked?
fastboot getvar unlocked            # expect: unlocked: yes

# 2. Which slot is active?
fastboot getvar current-slot        # _a or _b

# 3. Did the installer actually disable AVB?
#    flags must read 03000000 (little-endian 0x03)
adb shell 'dd if=/dev/block/by-name/vbmeta_a bs=1 skip=120 count=4 2>/dev/null | xxd'

# 4. Is the Halium kernel actually on the boot partition?
fastboot getvar 2>/dev/null | head -0
adb shell 'dd if=/dev/block/by-name/boot_a bs=64 count=1 2>/dev/null | xxd'   # expect ANDROID!
```

If the vbmeta flags are not `0x03`, the AVB step of the installer failed — that is an installer
problem, not a bootloader problem, and patching LK would not fix it.

### If the kernel starts but the rootfs does not

That is a different failure class entirely, and LK patching is irrelevant to it. Check the console
(the cmdline now includes `console=tty0`), then:

```bash
# Halium initramfs reached?
# If you land in a shell, the kernel and vendor modules are fine and the problem
# is mount/udev/rootfs, not secure boot.
cat /proc/cmdline
ls /lib/modules
dmesg | tail -50
```

---

## If you decide to patch LK anyway

Understand what you are doing:

1. **Back up every partition first.** `lk`, `bl2_ext`, `boot`, `vendor_boot`, `dtbo`, and all three
   `vbmeta` partitions.
2. **lkpatcher cannot do it for tanzanite.** There is no AArch64 patch set. Producing one means
   reverse-engineering the AArch64 `sec_get_vfy_policy` yourself and writing custom JSON patches
   (`-j patches.json`), then validating with `--analyze-policies` and `--dry-run` — and remembering
   that dry-run lies.
3. **Test on hardware you can afford to lose.** An EL3 mistake is not recoverable from fastboot.
4. Consider whether the goal is worth it. If the goal is booting Ubuntu Touch, `vbmeta` is the
   right lever. If the goal is removing a boot warning, accept the warning.

---

## References

- [R0rt1z2/fenrir](https://github.com/R0rt1z2/fenrir) — archived PoC, MTK `bl2_ext` EL3 bypass
- [R0rt1z2/lkpatcher](https://github.com/R0rt1z2/lkpatcher) — LK image patcher, ARM32 patch set
- [Reverse Engineering MediaTek Bootloaders](https://blog.r0rt1z2.com/posts/reverse-engineering-mediatek-lk)
- [HackTricks: MediaTek bl2_ext secure-boot bypass](https://hacktricks.wiki/en/hardware-physical-access/firmware-analysis/android-mediatek-secure-boot-bl2_ext-bypass-el3.html)
- [Android Verified Boot](https://source.android.com/docs/security/features/verifiedboot)
- [`docs/MODULE_AUDIT.md`](MODULE_AUDIT.md) — the other half of boot debugging on this port
