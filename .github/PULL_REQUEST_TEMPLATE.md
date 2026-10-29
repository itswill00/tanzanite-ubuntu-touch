## What this changes

<!-- One or two sentences. If it fixes a symptom, name the symptom and the mechanism. -->

## Why

<!--
The diff says what. This section says why it is needed and what you ruled out.
If an assumption turned out to be wrong, say which one and what disproved it —
several entries in CHANGELOG.md exist because that was written down properly.
-->

## How it was verified

- [ ] `make check` passes (shellcheck, module lists, device config)
- [ ] Shell syntax: `bash -n` on every script touched
- [ ] If it changes the module set: `./scripts/sync_modules_load.sh` run and committed
- [ ] If it changes the audio config: file is byte-identical to stock `OS2.0.214.0.VOGEUXM`
- [ ] If it touches the installer: reviewed the recovery-time behaviour by hand
- [ ] Tested on device (state what you saw, or say "not tested")

## Affected area

<!-- modules / audio / camera / udev / deviceinfo / flashlight / boot / scripts / docs / ci -->

## Checklist

- [ ] Commit messages follow the convention in CONTRIBUTING.md
- [ ] Commits are signed off (`git commit -s`)
- [ ] Generated files were regenerated, not hand-edited
- [ ] No build products, zips or `dist/` contents included
- [ ] I read docs/MODULE_AUDIT.md and docs/BOOTLOADER.md if this touches boot or hardware

## Related

<!-- Issue numbers, upstream commits, firmware versions -->
