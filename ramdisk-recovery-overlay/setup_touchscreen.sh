#!/system/bin/sh
# Xiaomi Tanzanite touch modules (if available in ramdisk)
for mod in /lib/modules/xiaomi.ko /lib/modules/lct_tp.ko /lib/modules/ft3519t.ko; do
    [ -f "$mod" ] && insmod "$mod"
done
exit 0
