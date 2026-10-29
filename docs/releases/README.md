# Release notes archive

One file per release, written at release time and committed so the reasoning behind a release is
versioned with the code that implements it. The same text is used as the GitHub release body.

| Version | Date | Summary | Notes |
| --- | --- | --- | --- |
| 1.1.0 | 2026-10-29 | Audio, torch, vibration and camera fixed | [v1.1.0.md](v1.1.0.md) |

## Older, unversioned builds

Before 1.1.0 the port had no version scheme and two installer zips were produced during development.
Both are superseded and should not be used.

| Build | Size | SHA-256 (prefix) | Superseded because |
| --- | --- | --- | --- |
| `tanzanite-halium.zip` | 962,716,095 B | `18393dd1…c402` | First successful build; before any bug fixes |
| `tanzanite-halium.zip` | 963,251,086 B | `e2b6dbf4…b3b4` | Rebuilt with module-list and udev fixes, before the missing drivers were recovered |

## Naming

```
tanzanite-ut20.04-halium12-v1.1.0-20261029-b4e45b1.zip
│         │       │          │      │        └─ commit the artifact was built from
│         │       │          │      └────────── build date, UTC
│         │       │          └───────────────── port version, from VERSION
│         │       └──────────────────────────── Halium version
│         └──────────────────────────────────── Ubuntu Touch rootfs release
└────────────────────────────────────────────── device codename
```

Full scheme and bump rules: [`../VERSIONING.md`](../VERSIONING.md).

## Verifying a download

```bash
git verify-tag v1.1.0
sha256sum -c tanzanite-ut20.04-halium12-v1.1.0-*.zip.sha256
```

Tags are GPG-signed by the same identity as the commit author.
