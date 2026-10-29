#!/system/bin/sh
MODDIR=${0%/*}

# Log to Android logcat
LOGTAG="TanzaniteSDCardFix"
log -p i -t "$LOGTAG" "Applying FUSE-BPF disable properties for Tanzanite HyperOS..." 2>/dev/null || true

# Reset FUSE-BPF properties to ensure internal storage /sdcard mounts properly on decrypted EXT4
for prop in \
    ro.fuse.bpf.enabled \
    ro.fuse.bpf.is_running \
    persist.sys.fuse.bpf.override \
    persist.sys.fuse.passthrough.enable
do
    resetprop -n "$prop" false 2>/dev/null || resetprop "$prop" false 2>/dev/null || setprop "$prop" false 2>/dev/null
done

log -p i -t "$LOGTAG" "FUSE-BPF properties applied successfully." 2>/dev/null || true
