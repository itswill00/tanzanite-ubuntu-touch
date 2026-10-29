#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <fcntl.h>
#include <sys/stat.h>
#include <sys/inotify.h>
#include <errno.h>

#define BRIDGE_FILE "/run/flashlight_bridge"
#define SYSFS_TORCH "/sys/class/flashlight_core/flashlight/flashlight_torch"

static void sync_torch(void) {
    FILE *bf = fopen(BRIDGE_FILE, "r");
    if (!bf) return;
    char buf[32] = {0};
    if (fgets(buf, sizeof(buf), bf)) {
        int val = 0;
        if (sscanf(buf, "%d", &val) == 1) {
            FILE *tf = fopen(SYSFS_TORCH, "w");
            if (tf) {
                if (val > 0) {
                    fprintf(tf, "0 0 0 1\n");
                } else {
                    fprintf(tf, "0 0 0 0\n");
                }
                fclose(tf);
            }
        }
    }
    fclose(bf);
    chmod(BRIDGE_FILE, 0666);
}

int main(void) {
    int fd = open(BRIDGE_FILE, O_CREAT | O_RDWR, 0666);
    if (fd >= 0) {
        write(fd, "0\n", 2);
        close(fd);
    }
    chmod(BRIDGE_FILE, 0666);

    int inotify_fd = inotify_init();
    if (inotify_fd < 0) return 1;

    inotify_add_watch(inotify_fd, "/run", IN_CLOSE_WRITE | IN_MOVED_TO);
    inotify_add_watch(inotify_fd, BRIDGE_FILE, IN_CLOSE_WRITE | IN_MODIFY);

    sync_torch();

    char buf[4096] __attribute__ ((aligned(__alignof__(struct inotify_event))));
    while (1) {
        ssize_t len = read(inotify_fd, buf, sizeof(buf));
        if (len <= 0) {
            if (len < 0 && errno == EINTR) continue;
            break;
        }
        sync_torch();
    }
    close(inotify_fd);
    return 0;
}
