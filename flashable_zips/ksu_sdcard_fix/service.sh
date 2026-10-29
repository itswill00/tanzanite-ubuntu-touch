#!/system/bin/sh
MODDIR=${0%/*}
LOGTAG="TanzaniteSDCardFix"

# Wait for boot completion before checking status
while [ "$(getprop sys.boot_completed)" != "1" ]; do
    sleep 2
done

# Re-enforce properties just in case Android init or vendor services reverted them
for prop in \
    ro.fuse.bpf.enabled \
    ro.fuse.bpf.is_running \
    persist.sys.fuse.bpf.override \
    persist.sys.fuse.passthrough.enable
do
    resetprop -n "$prop" false 2>/dev/null || resetprop "$prop" false 2>/dev/null
done

log -p i -t "$LOGTAG" "Service check completed. Current ro.fuse.bpf.enabled=$(getprop ro.fuse.bpf.enabled)" 2>/dev/null || true
