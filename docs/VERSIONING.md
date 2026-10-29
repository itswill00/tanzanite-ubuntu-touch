# Versioning and release naming

## Port version

The port version lives in [`VERSION`](../VERSION) at the repository root, one line, semver:

```
1.1.0
```

`build_zip_local.sh` reads `PORT_VERSION` from the environment and falls back to a built-in default.
Keep the two in sync when cutting a release:

```bash
PORT_VERSION="$(cat VERSION)" ./scripts/build_zip_local.sh
```

### What the numbers mean

| Change | Bump |
| --- | --- |
| A feature that was broken now works (e.g. camera, torch, audio DSP) | **minor** |
| Fixes that make an existing feature behave correctly (udev rules, module load list, audio policy) | **patch** |
| Boot image format, kernel major, Halium version, rootfs release, or anything requiring a clean flash | **major** |

This port is not 1.0.0 in the "everything works" sense: the four repaired features are verified
structurally but not yet confirmed on hardware. 1.1.0 reflects that the module set and audio
configuration are now complete, not that the device is daily-driver ready.

## Artifact naming

```
tanzanite-ut20.04-halium12-v1.1.0-20261029-18297c7.zip
│         │       │          │      │        │
│         │       │          │      │        └─ short commit of this repo
│         │       │          │      └────────── build date, UTC
│         │       │          └───────────────── port version (VERSION)
│         │       └──────────────────────────── Halium version (vendor blobs)
│         └──────────────────────────────────── Ubuntu Touch rootfs release
└────────────────────────────────────────────── device codename
```

A `-dirty` suffix is appended to the commit if the working tree had uncommitted changes, so a build
from modified sources can never be mistaken for a clean one.

Every build produces three files in `dist/`:

| File | Contents |
| --- | --- |
| `tanzanite-ut20.04-halium12-v1.1.0-20261029-18297c7.zip` | the installer |
| `....zip.sha256` | checksum, in `sha256sum -c` format |
| `....buildinfo` | size, checksum, versions, commit, build time, kernel, module count |

## Build manifest inside the zip

The zip carries `META-INF/tanzanite/build.prop`:

```
tanzanite.build.version=1.1.0
tanzanite.build.device=tanzanite
tanzanite.build.ut_release=ut20.04
tanzanite.build.halium=halium12
tanzanite.build.date=2026-10-29T05:00:00Z
tanzanite.build.commit=18297c7
tanzanite.build.kernel=5.10.269-EvernightKernel-1.1
tanzanite.build.modules=385
tanzanite.build.installer=tanzanite-ut20.04-halium12-v1.1.0-20261029-18297c7.zip
```

The installer copies it to `/data/ubuntu/etc/tanzanite-build.prop` and prints the version during
flashing, so a device can always report which build it is running:

```bash
cat /etc/tanzanite-build.prop
```

## Release checklist

1. Update `VERSION` if the change warrants a bump, and commit it.
2. Rebuild the images: `./build.sh -b workdir`
3. Rebuild the installer: `PORT_VERSION="$(cat VERSION)" ./scripts/build_zip_local.sh`
4. Verify: `./scripts/check_modules.sh && ./scripts/check_device_config.sh`
5. Publish: `./scripts/publish_artifact.sh dist/<name>.zip`
   This uploads to gofile and rewrites `README.md`, `artifacts/README.md` and
   `artifacts/<name>.sha256` from the actual file.
6. Tag the release: `git tag -a v1.1.0 -m "..." && git push --tags`
