/*
 * tanzanite-flashlight-bridge
 *
 * Exposes the MTK torch control as a stable, writable file so that
 * ayatana-indicator-power can toggle the flashlight through a plain path
 * (deviceinfo FlashlightSysfsPath=/run/flashlight_bridge) instead of needing to
 * know about the MediaTek flashlight class layout.
 *
 * ayatana-indicator-power writes "1\n" or "0\n" to /run/flashlight_bridge; this
 * daemon watches that file and forwards the value to the kernel torch node.
 *
 * The kernel node name differs between MTK kernels, so the daemon probes a list
 * of candidates at start-up and at each toggle. The write format is also probed:
 * mtk flashlight_core expects four space-separated fields ("0 0 0 1"), while the
 * generic leds-class torch takes a bare "1". Both are attempted.
 *
 * Every failure is logged to stderr (captured by the systemd unit), so a missing
 * driver shows up as a clear message instead of silently doing nothing - which
 * is how the original version behaved.
 */

#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <fcntl.h>
#include <errno.h>
#include <sys/stat.h>
#include <sys/inotify.h>
#include <syslog.h>

#define BRIDGE_FILE "/run/flashlight_bridge"
#define DEFAULT_TIMEOUT_MS 1000

/* Candidate kernel nodes, most specific first. */
static const char *torch_candidates[] = {
    "/sys/class/flashlight_core/flashlight/flashlight_torch",
    "/sys/class/flashlight/flashlight_torch",
    "/sys/class/leds/flashlight/brightness",
    "/sys/class/leds/torch/brightness",
    "/sys/class/leds/flash/brightness",
    NULL
};

/* Write formats to try, most specific first. */
static const char *torch_formats[] = {
    "0 0 0 %d\n",   /* mtk flashlight_core: <flash> <torch> ... <on> */
    "%d\n",         /* generic leds brightness / timed_output enable */
    NULL
};

static const char *find_torch_node(void) {
    for (int i = 0; torch_candidates[i]; i++) {
        if (access(torch_candidates[i], W_OK) == 0)
            return torch_candidates[i];
    }
    return NULL;
}

static int set_torch(int on) {
    const char *node = find_torch_node();
    if (!node) {
        syslog(LOG_WARNING,
               "no writable torch node found; is the flashlight kernel module loaded? "
               "(tried flashlight_core, flashlight, leds/flashlight, leds/torch, leds/flash)");
        return -1;
    }

    for (int i = 0; torch_formats[i]; i++) {
        FILE *tf = fopen(node, "w");
        if (!tf) {
            syslog(LOG_WARNING, "cannot open %s: %s", node, strerror(errno));
            return -1;
        }
        fprintf(tf, torch_formats[i], on ? 1 : 0);
        if (fclose(tf) == 0)
            return 0;
        syslog(LOG_WARNING, "write failed on %s: %s", node, strerror(errno));
    }
    return -1;
}

static void sync_torch(void) {
    FILE *bf = fopen(BRIDGE_FILE, "r");
    if (!bf) {
        syslog(LOG_WARNING, "cannot read %s: %s", BRIDGE_FILE, strerror(errno));
        return;
    }
    char buf[32] = {0};
    if (fgets(buf, sizeof(buf), bf)) {
        int val = 0;
        if (sscanf(buf, "%d", &val) == 1) {
            if (set_torch(val > 0) == 0)
                syslog(LOG_INFO, "torch -> %s", val > 0 ? "on" : "off");
        }
    }
    fclose(bf);
    /* ayatana writes as the desktop user; keep the node world-writable so the
     * next toggle works without a permission error. */
    chmod(BRIDGE_FILE, 0666);
}

int main(void) {
    openlog("tanzanite-flashlight", LOG_PID, LOG_DAEMON);

    int fd = open(BRIDGE_FILE, O_CREAT | O_RDWR, 0666);
    if (fd < 0) {
        syslog(LOG_ERR, "cannot create %s: %s", BRIDGE_FILE, strerror(errno));
        return 1;
    }
    if (write(fd, "0\n", 2) < 0)
        syslog(LOG_WARNING, "cannot initialise %s: %s", BRIDGE_FILE, strerror(errno));
    close(fd);
    chmod(BRIDGE_FILE, 0666);

    if (!find_torch_node())
        syslog(LOG_WARNING,
               "torch node missing at start-up; the flashlight driver is probably not loaded. "
               "The bridge will keep watching and retry on each toggle.");

    int inotify_fd = inotify_init();
    if (inotify_fd < 0) {
        syslog(LOG_ERR, "inotify_init failed: %s", strerror(errno));
        return 1;
    }

    inotify_add_watch(inotify_fd, "/run", IN_CLOSE_WRITE | IN_MOVED_TO);
    inotify_add_watch(inotify_fd, BRIDGE_FILE, IN_CLOSE_WRITE | IN_MODIFY);

    sync_torch();

    char buf[4096] __attribute__ ((aligned(__alignof__(struct inotify_event))));
    for (;;) {
        ssize_t len = read(inotify_fd, buf, sizeof(buf));
        if (len <= 0) {
            if (len < 0 && errno == EINTR) continue;
            syslog(LOG_ERR, "inotify read failed: %s", strerror(errno));
            break;
        }
        sync_torch();
    }

    close(inotify_fd);
    closelog();
    return 0;
}
