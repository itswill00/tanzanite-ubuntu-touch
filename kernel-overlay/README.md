# kernel-overlay

Device-specific pieces added on top of the upstream kernel tree.

The kernel source is the official Google **Android Common Kernel (ACK)**,
`android12-5.10-lts` (GKI 5.10), cloned by `scripts/build-all.sh`. ACK has no
Redmi Note 14 4G definition, so the files here are copied into the tree before
the kernel is configured:

| File | Destination in the kernel tree |
| --- | --- |
| `configs/tanzanite_defconfig` | `arch/arm64/configs/tanzanite_defconfig` |
| `dts/tanzanite.dts` | `arch/arm64/boot/dts/mediatek/tanzanite.dts` |
| `dts/tanzanite-overlay.dts` | `arch/arm64/boot/dts/mediatek/tanzanite-overlay.dts` |

`scripts/apply_kernel_overlay.sh` also appends the two `dtb-y` lines to
`arch/arm64/boot/dts/mediatek/Makefile`.

## Provenance and license

The device tree sources carry `SPDX-License-Identifier: GPL-2.0` and come from
the community GKI work [`iprjkt/evernight-gki`](https://github.com/iprjkt/evernight-gki),
the only public source of a tanzanite kernel definition (Xiaomi has not released
one). They stay GPL-2.0 and are **not** covered by this repository's Apache-2.0
`LICENSE`.

Some options in `tanzanite_defconfig` come from that fork's out-of-tree patches
(e.g. `CONFIG_TCP_CONG_BBR3`, `CONFIG_CPU_FREQ_GOV_REFLEX`,
`CONFIG_CPU_FREQ_GOV_SCHEDHORIZON`, `CONFIG_PELT_UTIL_HALFLIFE_12`). A plain ACK
tree has no such Kconfig symbols, so `make tanzanite_defconfig` drops them with
a warning; the build still succeeds but those features are absent.
