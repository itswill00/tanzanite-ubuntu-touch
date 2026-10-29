#define _GNU_SOURCE
#include <dlfcn.h>
#include <string.h>
#include <stdio.h>
#include <stdlib.h>

typedef struct _GList GList;
struct _GList {
    void *data;
    GList *next;
    GList *prev;
};

typedef void* GUdevDevice;
typedef void* GUdevClient;

static const char* (*real_g_udev_device_get_name)(GUdevDevice *device) = NULL;
static const char* (*real_g_udev_device_get_subsystem)(GUdevDevice *device) = NULL;
static GList* (*real_g_udev_client_query_by_subsystem)(GUdevClient *client, const char *subsystem) = NULL;
static void (*real_g_object_unref)(void *object) = NULL;
static GList* (*real_g_list_delete_link)(GList *list, GList *link) = NULL;
static double (*real_g_udev_device_get_sysfs_attr_as_double_uncached)(GUdevDevice *device, const char *attribute) = NULL;
static const char* (*real_g_udev_device_get_sysfs_attr_uncached)(GUdevDevice *device, const char *attribute) = NULL;
static const char* (*real_g_udev_device_get_sysfs_attr)(GUdevDevice *device, const char *attribute) = NULL;

static int is_ignored_device(const char *name) {
    if (!name) return 0;
    if (strcmp(name, "bms") == 0) return 1;
    if (strcmp(name, "mtk-gauge") == 0) return 1;
    if (strcmp(name, "sc-cp-master") == 0) return 1;
    return 0;
}

const char* g_udev_device_get_name(GUdevDevice *device) {
    if (!real_g_udev_device_get_name)
        real_g_udev_device_get_name = dlsym(RTLD_NEXT, "g_udev_device_get_name");
    return real_g_udev_device_get_name ? real_g_udev_device_get_name(device) : NULL;
}

const char* g_udev_device_get_subsystem(GUdevDevice *device) {
    if (!real_g_udev_device_get_subsystem)
        real_g_udev_device_get_subsystem = dlsym(RTLD_NEXT, "g_udev_device_get_subsystem");
    if (!real_g_udev_device_get_name)
        real_g_udev_device_get_name = dlsym(RTLD_NEXT, "g_udev_device_get_name");

    const char *name = real_g_udev_device_get_name ? real_g_udev_device_get_name(device) : NULL;
    if (is_ignored_device(name)) {
        return "ignored";
    }
    return real_g_udev_device_get_subsystem ? real_g_udev_device_get_subsystem(device) : NULL;
}

GList* g_udev_client_query_by_subsystem(GUdevClient *client, const char *subsystem) {
    if (!real_g_udev_client_query_by_subsystem)
        real_g_udev_client_query_by_subsystem = dlsym(RTLD_NEXT, "g_udev_client_query_by_subsystem");
    if (!real_g_udev_device_get_name)
        real_g_udev_device_get_name = dlsym(RTLD_NEXT, "g_udev_device_get_name");
    if (!real_g_object_unref)
        real_g_object_unref = dlsym(RTLD_NEXT, "g_object_unref");
    if (!real_g_list_delete_link)
        real_g_list_delete_link = dlsym(RTLD_NEXT, "g_list_delete_link");

    if (!real_g_udev_client_query_by_subsystem) return NULL;
    GList *list = real_g_udev_client_query_by_subsystem(client, subsystem);
    if (subsystem && strcmp(subsystem, "power_supply") == 0 && list) {
        GList *curr = list;
        while (curr) {
            GList *next = curr->next;
            GUdevDevice *dev = curr->data;
            const char *name = real_g_udev_device_get_name ? real_g_udev_device_get_name(dev) : NULL;
            if (is_ignored_device(name)) {
                if (real_g_object_unref)
                    real_g_object_unref(dev);
                if (real_g_list_delete_link)
                    list = real_g_list_delete_link(list, curr);
            }
            curr = next;
        }
    }
    return list;
}

static double get_sanitized_capacity(GUdevDevice *device, double orig_cap) {
    if (orig_cap > 2.0)
        return orig_cap;

    if (!real_g_udev_device_get_sysfs_attr_as_double_uncached)
        real_g_udev_device_get_sysfs_attr_as_double_uncached = dlsym(RTLD_NEXT, "g_udev_device_get_sysfs_attr_as_double_uncached");

    double volt = real_g_udev_device_get_sysfs_attr_as_double_uncached ?
                  real_g_udev_device_get_sysfs_attr_as_double_uncached(device, "voltage_now") : 0.0;

    /* If cell voltage is > 3.5V, battery is healthy and has substantial charge */
    if (volt > 3500000.0) {
        /* 1. Try reading bms hardware capacity directly */
        FILE *f = fopen("/sys/class/power_supply/bms/capacity", "r");
        if (f) {
            double bms_cap = 0.0;
            if (fscanf(f, "%lf", &bms_cap) == 1 && bms_cap > 2.0) {
                fclose(f);
                return bms_cap;
            }
            fclose(f);
        }

        /* 2. Fallback to Open Circuit Voltage estimation table for 4.4V cell */
        if (volt >= 4350000.0) return 98.0;
        if (volt >= 4200000.0) return 85.0;
        if (volt >= 4050000.0) return 70.0;
        if (volt >= 3900000.0) return 50.0;
        if (volt >= 3800000.0) return 35.0;
        if (volt >= 3700000.0) return 20.0;
        return 15.0;
    }

    /* Genuinely dead battery (<= 3.5V), pass through real reading for safe shutdown */
    return orig_cap;
}

double g_udev_device_get_sysfs_attr_as_double_uncached(GUdevDevice *device, const char *attribute) {
    if (!real_g_udev_device_get_sysfs_attr_as_double_uncached)
        real_g_udev_device_get_sysfs_attr_as_double_uncached = dlsym(RTLD_NEXT, "g_udev_device_get_sysfs_attr_as_double_uncached");

    double val = real_g_udev_device_get_sysfs_attr_as_double_uncached ?
                 real_g_udev_device_get_sysfs_attr_as_double_uncached(device, attribute) : 0.0;

    if (attribute && strcmp(attribute, "capacity") == 0) {
        return get_sanitized_capacity(device, val);
    }
    return val;
}

const char* g_udev_device_get_sysfs_attr_uncached(GUdevDevice *device, const char *attribute) {
    if (!real_g_udev_device_get_sysfs_attr_uncached)
        real_g_udev_device_get_sysfs_attr_uncached = dlsym(RTLD_NEXT, "g_udev_device_get_sysfs_attr_uncached");

    const char *val = real_g_udev_device_get_sysfs_attr_uncached ?
                      real_g_udev_device_get_sysfs_attr_uncached(device, attribute) : NULL;

    if (attribute && strcmp(attribute, "capacity") == 0 && val) {
        int cap = atoi(val);
        if (cap <= 2) {
            double safe = get_sanitized_capacity(device, (double)cap);
            if (safe > 2.0) {
                static __thread char buf[16];
                snprintf(buf, sizeof(buf), "%d", (int)safe);
                return buf;
            }
        }
    }
    return val;
}

const char* g_udev_device_get_sysfs_attr(GUdevDevice *device, const char *attribute) {
    if (!real_g_udev_device_get_sysfs_attr)
        real_g_udev_device_get_sysfs_attr = dlsym(RTLD_NEXT, "g_udev_device_get_sysfs_attr");

    const char *val = real_g_udev_device_get_sysfs_attr ?
                      real_g_udev_device_get_sysfs_attr(device, attribute) : NULL;

    if (attribute && strcmp(attribute, "capacity") == 0 && val) {
        int cap = atoi(val);
        if (cap <= 2) {
            double safe = get_sanitized_capacity(device, (double)cap);
            if (safe > 2.0) {
                static __thread char buf[16];
                snprintf(buf, sizeof(buf), "%d", (int)safe);
                return buf;
            }
        }
    }
    return val;
}
