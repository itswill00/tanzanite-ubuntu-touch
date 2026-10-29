# Security policy

## Reporting a vulnerability

This is a community port, not a product. If you find something security-relevant, open a
[private security advisory](https://github.com/itswill00/tanzanite-ubuntu-touch/security/advisories/new)
rather than a public issue.

Please include: what the issue is, how to reproduce it, which build version
(`cat /etc/tanzanite-build.prop`) and the impact you believe it has.

Expect a best-effort response. There is no SLA and no bounty.

## Scope

**In scope for this repository:**

- The installer logic in `flashable_zips/update-binary.template.sh` — it runs as root in recovery,
  writes to block devices, and disables Android Verified Boot. A bug here can brick a device or
  leave it in a less secure state than intended.
- The helper scripts in `scripts/` — they download and unpack firmware, handle untrusted archives,
  and upload artifacts.
- The rootfs overlay — udev rules, systemd units, sudoers fragments, AppArmor profiles.
- Anything that would cause a build to ship a wrong or unexpected binary.

**Out of scope:**

- Vulnerabilities in the vendor binaries under `vendor-ramdisk-overlay/` and
  `overlay/system/usr/share/halium-overlay/vendor/`. These are MediaTek and Xiaomi binaries
  redistributed unmodified from stock firmware. Report those to the vendor. See
  [`docs/BINARIES.md`](docs/BINARIES.md) for provenance.
- Vulnerabilities in the kernel (`iprjkt/evernight-gki`) or in Ubuntu Touch / Halium / libhybris.
  Report upstream.
- The fact that the installer disables AVB. That is deliberate and documented; it is required for
  the port to boot. What *is* in scope is the installer failing to do it correctly, or doing it to
  the wrong slot.
- Anything requiring an already-compromised device.

## Known and accepted design decisions

These are documented so they are not reported as findings:

| Decision | Why | Mitigation |
| --- | --- | --- |
| Android Verified Boot is disabled (`vbmeta` flags set to `0x03`) | Unsigned `boot.img`/`vendor_boot.img` cannot boot otherwise | Only the active slot is touched; the other slot and its `vbmeta` are left intact for rollback |
| `/data` must be unencrypted ext4 | Halium's initramfs cannot unlock FBE, and Ubuntu Touch has no equivalent | Documented as a hard prerequisite; `FilesystemEncryption: false` in the deviceinfo YAML |
| `adbd` runs with `ADBD_SECURE=0` in devel builds | Needed for debugging a port that cannot be debugged otherwise | Only set by `prepare-fake-ota.sh`, not in the recovery installer |
| SSH with empty password enabled in devel builds | Same reason | Only in devel-flashable builds, not in released installers |
| Prebuilt vendor kernel modules | Cannot be rebuilt without vendor source, which Xiaomi has not released | Provenance and hashes documented in `docs/BINARIES.md` |

## Verifying a release

Releases are GPG-signed tags and each artifact ships a checksum:

```bash
git verify-tag v1.1.0
sha256sum -c tanzanite-ut20.04-halium12-v1.1.0-*.zip.sha256
```

The tag signature must be from the same identity as the commit author. Every commit carries
`Signed-off-by`.

## What this port does not protect against

Be clear-eyed about the threat model:

- **An unlocked bootloader means the device is not verifiably secure.** Anything with physical
  access can flash anything. That is inherent to installing a custom OS, not a bug in this port.
- **The vendor binaries are unauditable.** They run with high privilege in the Android container.
- **There is no secure boot chain.** The port intentionally breaks it.
- **Ubuntu Touch 20.04 is past standard support.** Security updates come from UBports, on their
  schedule, not Canonical's.

If you need a device whose boot chain you can trust, do not install this.
