ui_print "****************************************"
ui_print "  Tanzanite HyperOS SDCard Fix (KSU)    "
ui_print "  Redmi Note 14 4G (tanzanite / MT6789) "
ui_print "****************************************"
ui_print "- Disabling FUSE-BPF for decrypted EXT4 storage..."

# Set executable permissions
set_perm "$MODPATH/post-fs-data.sh" 0 0 0755
set_perm "$MODPATH/service.sh" 0 0 0755
set_perm "$MODPATH/system.prop" 0 0 0644

ui_print "- Module successfully installed!"
ui_print "- Reboot device to apply changes."
