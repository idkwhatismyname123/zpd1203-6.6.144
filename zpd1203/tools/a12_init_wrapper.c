#define _GNU_SOURCE
#include <dirent.h>
#include <errno.h>
#include <fcntl.h>
#include <linux/reboot.h>
#include <poll.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mount.h>
#include <sys/stat.h>
#include <sys/syscall.h>
#include <sys/sysmacros.h>
#include <termios.h>
#include <unistd.h>

static const char *const zpd_module_order[] = {
    "mali_mgm_mt6768.ko",
    "mali_kbase_mt6768.ko",
    "rfkill.ko",
    "cfg80211.ko",
    "btif_drv.ko",
    "conn_md_drv.ko",
    "connfem.ko",
    "wmt_drv.ko",
    "wmt_chrdev_wifi.ko",
    "bt_drv_connac1x.ko",
    "wlan_drv_gen4m.ko",
};

#define ZPD_MOD_COUNT ((int)(sizeof(zpd_module_order) / sizeof(zpd_module_order[0])))
#define ZPD_EARLY_CFGFS "/dev/.zpd_cfgfs"
#define ZPD_EARLY_GADGET "/dev/.zpd_cfgfs/usb_gadget/zpd_com"

static int write_sys(const char *path, const char *val) {
    int fd = open(path, O_WRONLY | O_TRUNC);
    if (fd < 0) return -1;
    ssize_t n = write(fd, val, strlen(val));
    close(fd);
    return n < 0 ? -1 : 0;
}

static void klog_note(const char *msg) {
    int fd = open("/dev/kmsg", O_WRONLY);
    if (fd >= 0) {
        (void)!write(fd, msg, strlen(msg));
        close(fd);
    }
}

static void klog_stage(int stage, const char *detail) {
    char buf[384];
    snprintf(buf, sizeof(buf), "<6>[ZPD1203-6.6] STAGE %d: %s\n", stage, detail);
    klog_note(buf);
}

static ssize_t copy_fd_to_path(int src_fd, const char *dst_path, mode_t mode) {
    int dfd = open(dst_path, O_CREAT | O_WRONLY | O_TRUNC, mode);
    char buf[4096];
    size_t total = 0;

    if (dfd < 0) return -1;
    if (lseek(src_fd, 0, SEEK_SET) < 0) {
        close(dfd);
        return -1;
    }

    for (;;) {
        ssize_t r = read(src_fd, buf, sizeof(buf));
        if (r == 0) break;
        if (r < 0) {
            if (errno == EINTR) continue;
            close(dfd);
            return -1;
        }
        size_t off = 0;
        while (off < (size_t)r) {
            ssize_t w = write(dfd, buf + off, (size_t)r - off);
            if (w <= 0) {
                if (w < 0 && errno == EINTR) continue;
                close(dfd);
                return -1;
            }
            off += (size_t)w;
        }
        total += (size_t)r;
    }

    close(dfd);
    chmod(dst_path, mode);
    return (ssize_t)total;
}

static void open_zpd_modules(int mod_fds[ZPD_MOD_COUNT], int mod_loaded[ZPD_MOD_COUNT]) {
    for (int i = 0; i < ZPD_MOD_COUNT; i++) {
        char mpath[256];
        snprintf(mpath, sizeof(mpath), "/zpd_modules/%s", zpd_module_order[i]);
        mod_fds[i] = open(mpath, O_RDONLY);
        mod_loaded[i] = 0;
    }
}

static void close_zpd_modules(int mod_fds[ZPD_MOD_COUNT]) {
    for (int i = 0; i < ZPD_MOD_COUNT; i++) {
        if (mod_fds[i] >= 0) {
            close(mod_fds[i]);
            mod_fds[i] = -1;
        }
    }
}

static void load_zpd_modules(int mod_fds[ZPD_MOD_COUNT], int mod_loaded[ZPD_MOD_COUNT],
                             const char *phase) {
    int present = 0;
    for (int i = 0; i < ZPD_MOD_COUNT; i++) {
        if (mod_fds[i] >= 0) present++;
    }
    if (present == 0) return;

    for (int i = 0; i < ZPD_MOD_COUNT; i++) {
        char note[320];
        if (mod_fds[i] < 0 || mod_loaded[i]) continue;
        lseek(mod_fds[i], 0, SEEK_SET);
        long rc = syscall(__NR_finit_module, mod_fds[i], "", 0);
        if (rc == 0) {
            mod_loaded[i] = 1;
            snprintf(note, sizeof(note), "<6>[ZPD1203-6.6] mod (%s): loaded %s\n",
                     phase, zpd_module_order[i]);
            klog_note(note);
        } else if (errno == EEXIST) {
            mod_loaded[i] = 1;
            snprintf(note, sizeof(note), "<6>[ZPD1203-6.6] mod (%s): %s already loaded\n",
                     phase, zpd_module_order[i]);
            klog_note(note);
        } else {
            snprintf(note, sizeof(note),
                     "<4>[ZPD1203-6.6] mod (%s): finit_module %s failed errno=%d (%s)\n",
                     phase, zpd_module_order[i], errno, strerror(errno));
            klog_note(note);
        }
    }
}

static void stage_vendor_module_overrides(int mod_fds[ZPD_MOD_COUNT]) {
    mkdir("/dev/.zpd_modules", 0755);
    for (int i = 0; i < ZPD_MOD_COUNT; i++) {
        char vpath[256];
        char dpath[256];
        char note[384];
        if (mod_fds[i] < 0) continue;

        snprintf(vpath, sizeof(vpath), "/vendor/lib/modules/%s", zpd_module_order[i]);
        if (access(vpath, F_OK) != 0) continue;

        snprintf(dpath, sizeof(dpath), "/dev/.zpd_modules/%s", zpd_module_order[i]);
        ssize_t nbytes = copy_fd_to_path(mod_fds[i], dpath, 0644);
        if (nbytes > 0) {
            if (mount(dpath, vpath, "none", MS_BIND, NULL) == 0) {
                snprintf(note, sizeof(note),
                         "<6>[ZPD1203-6.6] a12-wrap: bind-mounted 6.6 %s over %s (%zd B)\n",
                         zpd_module_order[i], vpath, nbytes);
                klog_note(note);
            } else {
                snprintf(note, sizeof(note),
                         "<4>[ZPD1203-6.6] a12-wrap: bind-mount %s failed errno=%d (%s)\n",
                         vpath, errno, strerror(errno));
                klog_note(note);
            }
        }
    }
}

static void ensure_dev_perms(int *fb_chmed, int *mali_chmed, int *ion_chmed) {
    if (!*fb_chmed && access("/dev/graphics/fb0", F_OK) == 0) {
        chmod("/dev/graphics/fb0", 0666);
        *fb_chmed = 1;
        klog_stage(6, "/dev/graphics/fb0 ready (0666)");
    }
    if (!*mali_chmed && access("/dev/mali0", F_OK) == 0) {
        chmod("/dev/mali0", 0666);
        *mali_chmed = 1;
        klog_note("<6>[ZPD1203-6.6] a12-wrap: /dev/mali0 ready (0666)\n");
    }
    if (!*ion_chmed && access("/dev/ion", F_OK) == 0) {
        chmod("/dev/ion", 0666);
        *ion_chmed = 1;
        klog_note("<6>[ZPD1203-6.6] a12-wrap: /dev/ion ready (0666)\n");
    }
}

static void dump_pstore_early(void) {
    mkdir("/sys/fs/pstore", 0755);
    if (mount("pstore", "/sys/fs/pstore", "pstore", 0, NULL) != 0) {
        char msg[192];
        snprintf(msg, sizeof(msg),
                 "<6>[ZPD1203-6.6] STAGE 2: pstore mount skipped errno=%d (%s)\n",
                 errno, strerror(errno));
        klog_note(msg);
        return;
    }

    DIR *d = opendir("/sys/fs/pstore");
    if (!d) {
        klog_note("<4>[ZPD1203-6.6] STAGE 2: opendir(/sys/fs/pstore) failed\n");
        umount2("/sys/fs/pstore", MNT_DETACH);
        return;
    }

    int dump_fd = open("/dev/.pstore_dump.log", O_CREAT | O_WRONLY | O_TRUNC, 0644);
    int files_found = 0;
    struct dirent *de;
    while ((de = readdir(d)) != NULL) {
        if (de->d_name[0] == '.') continue;
        char ppath[320];
        struct stat st;
        snprintf(ppath, sizeof(ppath), "/sys/fs/pstore/%s", de->d_name);
        if (stat(ppath, &st) != 0 || !S_ISREG(st.st_mode)) continue;
        files_found++;

        char hdr[384];
        snprintf(hdr, sizeof(hdr),
                 "<6>[ZPD1203-6.6] STAGE 2: pstore entry %s (%lld bytes)\n",
                 de->d_name, (long long)st.st_size);
        klog_note(hdr);

        int pfd = open(ppath, O_RDONLY);
        if (pfd >= 0) {
            if (dump_fd >= 0) {
                char sec[320];
                int slen = snprintf(sec, sizeof(sec), "\n=== pstore: %s (%lld bytes) ===\n",
                                    de->d_name, (long long)st.st_size);
                (void)!write(dump_fd, sec, (size_t)slen);
                char buf[4096];
                ssize_t r;
                while ((r = read(pfd, buf, sizeof(buf))) > 0) {
                    (void)!write(dump_fd, buf, (size_t)r);
                }
            }
            if (strncmp(de->d_name, "console-ramoops", 15) == 0 ||
                strncmp(de->d_name, "dmesg-ramoops", 13) == 0) {
                off_t tail_off = (st.st_size > 1024) ? (st.st_size - 1024) : 0;
                if (lseek(pfd, tail_off, SEEK_SET) >= 0) {
                    char tail[1025];
                    ssize_t tr = read(pfd, tail, sizeof(tail) - 1);
                    if (tr > 0) {
                        tail[tr] = '\0';
                        char kbuf[1408];
                        snprintf(kbuf, sizeof(kbuf),
                                 "<6>[ZPD1203-6.6] pstore tail (%s):\n%s\n",
                                 de->d_name, tail);
                        klog_note(kbuf);
                    }
                }
            }
            close(pfd);
        }
    }
    closedir(d);
    if (dump_fd >= 0) close(dump_fd);

    if (files_found == 0) {
        klog_stage(2, "pstore mounted cleanly, no prior crash dumps present");
    } else {
        char msg[192];
        snprintf(msg, sizeof(msg),
                 "<6>[ZPD1203-6.6] STAGE 2: archived %d pstore file(s) to /dev/.pstore_dump.log\n",
                 files_found);
        klog_note(msg);
    }
    umount2("/sys/fs/pstore", MNT_DETACH);
}

static int read_sys_str(const char *path, char *buf, size_t sz) {
    int fd = open(path, O_RDONLY);
    if (fd < 0) return -1;
    ssize_t n = read(fd, buf, sz - 1);
    close(fd);
    if (n <= 0) {
        buf[0] = '\0';
        return -1;
    }
    buf[n] = '\0';
    while (n > 0 && (buf[n - 1] == '\n' || buf[n - 1] == '\r')) {
        buf[--n] = '\0';
    }
    return 0;
}

static void ensure_sysfs_available(void) {
    if (access("/sys/class/udc", F_OK) != 0) {
        mkdir("/sys", 0755);
        (void)mount("sysfs", "/sys", "sysfs", 0, NULL);
    }
}

static void enable_musb_init_done(void) {
    ensure_sysfs_available();
    (void)write_sys("/sys/module/musb_hdrc/parameters/kernel_init_done", "1\n");
}

static int find_hw_udc(char *udc, size_t sz, int retries) {
    ensure_sysfs_available();
    udc[0] = '\0';
    for (int attempt = 0; attempt < retries && !udc[0]; attempt++) {
        DIR *d = opendir("/sys/class/udc");
        if (d) {
            struct dirent *de;
            while ((de = readdir(d)) != NULL) {
                if (de->d_name[0] == '.') continue;
                if (strncmp(de->d_name, "dummy_udc", 9) == 0) continue;
                snprintf(udc, sz, "%s", de->d_name);
                break;
            }
            closedir(d);
        }
        if (!udc[0] && attempt + 1 < retries) usleep(200000);
    }
    return udc[0] ? 0 : -1;
}

static void ensure_tty_node(const char *tty_path, int port_num) {
    if (access(tty_path, F_OK) == 0) return;

    char sys_dev[96];
    char dev_buf[32];
    snprintf(sys_dev, sizeof(sys_dev), "/sys/class/tty/ttyGS%d/dev", port_num);

    for (int attempt = 0; attempt < 20; attempt++) {
        if (read_sys_str(sys_dev, dev_buf, sizeof(dev_buf)) == 0) {
            unsigned int maj = 0, min = 0;
            if (sscanf(dev_buf, "%u:%u", &maj, &min) == 2 && maj > 0) {
                if (mknod(tty_path, S_IFCHR | 0660, makedev(maj, min)) == 0 ||
                    errno == EEXIST) {
                    chmod(tty_path, 0660);
                    return;
                }
            }
        }
        usleep(25000);
    }
}

static int open_tty_raw(const char *devpath) {
    int fd = open(devpath, O_RDWR | O_NOCTTY | O_NONBLOCK);
    if (fd >= 0) {
        struct termios tio;
        if (tcgetattr(fd, &tio) == 0) {
            cfmakeraw(&tio);
            cfsetispeed(&tio, B115200);
            cfsetospeed(&tio, B115200);
            tcsetattr(fd, TCSANOW, &tio);
        }
    }
    return fd;
}

static void setup_hwc_fb_fallback(int *hwc_bound, int *bridge_fd) {
    char msg[256];
    int lfd = open("/dev/.fb0_bridge.log", O_CREAT | O_WRONLY | O_TRUNC, 0666);
    if (lfd >= 0) close(lfd);
    chmod("/dev/.fb0_bridge.log", 0666);
    int efd = open("/dev/.empty_hwc", O_CREAT | O_WRONLY | O_TRUNC, 0644);
    if (efd >= 0) close(efd);
    chmod("/dev/.empty_hwc", 0644);
    if (mount("/dev/.empty_hwc", "/vendor/lib64/hw/hwcomposer.mt6768.so",
              "none", MS_BIND, NULL) == 0) {
        *hwc_bound = 1;
        klog_note("<6>[ZPD1203-6.6] a12-wrap: bind-mounted /dev/.empty_hwc over hwcomposer.mt6768.so\n");
    } else {
        snprintf(msg, sizeof(msg),
                 "<4>[ZPD1203-6.6] a12-wrap: bind-mount hwcomposer.mt6768.so failed errno=%d (%s)\n",
                 errno, strerror(errno));
        klog_note(msg);
    }

    if (bridge_fd && *bridge_fd >= 0) {
        ssize_t total = copy_fd_to_path(*bridge_fd, "/dev/.gralloc_fb0_bridge.so", 0755);
        close(*bridge_fd);
        *bridge_fd = -1;

        if (total > 0) {
            if (mount("/dev/.gralloc_fb0_bridge.so", "/vendor/lib64/hw/gralloc.default.so",
                      "none", MS_BIND, NULL) == 0) {
                snprintf(msg, sizeof(msg),
                         "<6>[ZPD1203-6.6] a12-wrap: bind-mounted /dev/.gralloc_fb0_bridge.so over gralloc.default.so (%zd bytes)\n",
                         total);
                klog_note(msg);
            } else {
                snprintf(msg, sizeof(msg),
                         "<4>[ZPD1203-6.6] a12-wrap: bind-mount gralloc.default.so failed errno=%d (%s)\n",
                         errno, strerror(errno));
                klog_note(msg);
            }
        } else {
            snprintf(msg, sizeof(msg),
                     "<4>[ZPD1203-6.6] a12-wrap: copy gralloc.fb0_bridge.so failed errno=%d (%s)\n",
                     errno, strerror(errno));
            klog_note(msg);
        }
    }
}

static int bind_early_acm(int *tty_fd, const char *hw_udc) {
    char note[384];
    char udc[256];

    enable_musb_init_done();
    snprintf(udc, sizeof(udc), "%s", hw_udc);
    if (!udc[0]) find_hw_udc(udc, sizeof(udc), 5);
    if (!udc[0]) snprintf(udc, sizeof(udc), "musb-hdrc");

    mkdir(ZPD_EARLY_CFGFS, 0755);
    if (access(ZPD_EARLY_CFGFS "/usb_gadget", F_OK) != 0) {
        if (mount("configfs", ZPD_EARLY_CFGFS, "configfs", 0, NULL) != 0 && errno != EBUSY) {
            snprintf(note, sizeof(note),
                     "<4>[ZPD1203-6.6] STAGE 7-early: mount configfs failed errno=%d (%s)\n",
                     errno, strerror(errno));
            klog_note(note);
            return -1;
        }
    }

    mkdir(ZPD_EARLY_GADGET, 0755);
    write_sys(ZPD_EARLY_GADGET "/os_desc/use", "0\n");
    write_sys(ZPD_EARLY_GADGET "/bDeviceClass", "0x02\n");
    write_sys(ZPD_EARLY_GADGET "/bDeviceSubClass", "0x00\n");
    write_sys(ZPD_EARLY_GADGET "/bDeviceProtocol", "0x00\n");
    write_sys(ZPD_EARLY_GADGET "/idVendor", "0x1d6b\n");
    write_sys(ZPD_EARLY_GADGET "/idProduct", "0x0104\n");

    mkdir(ZPD_EARLY_GADGET "/strings/0x409", 0755);
    write_sys(ZPD_EARLY_GADGET "/strings/0x409/manufacturer", "ZPD1203\n");
    write_sys(ZPD_EARLY_GADGET "/strings/0x409/product", "ZPD1203 Linux 6.6 COM\n");
    write_sys(ZPD_EARLY_GADGET "/strings/0x409/serialnumber", "ZPD1203-66\n");

    mkdir(ZPD_EARLY_GADGET "/functions/acm.gs0", 0755);
    mkdir(ZPD_EARLY_GADGET "/configs/c.1", 0755);
    mkdir(ZPD_EARLY_GADGET "/configs/c.1/strings/0x409", 0755);
    write_sys(ZPD_EARLY_GADGET "/configs/c.1/strings/0x409/configuration", "early_acm\n");
    write_sys(ZPD_EARLY_GADGET "/configs/c.1/MaxPower", "500\n");

    if (symlink(ZPD_EARLY_GADGET "/functions/acm.gs0",
                ZPD_EARLY_GADGET "/configs/c.1/acm.gs0") < 0 && errno != EEXIST) {
        snprintf(note, sizeof(note),
                 "<4>[ZPD1203-6.6] STAGE 7-early: symlink acm.gs0 failed errno=%d (%s)\n",
                 errno, strerror(errno));
        klog_note(note);
    }

    char udc_nl[280];
    snprintf(udc_nl, sizeof(udc_nl), "%s\n", udc);
    int bound = -1, last_err = 0;
    for (int i = 0; i < 5; i++) {
        if (write_sys(ZPD_EARLY_GADGET "/UDC", udc_nl) == 0) {
            bound = 0;
            break;
        }
        last_err = errno;
        usleep(100000);
    }

    if (bound != 0) {
        snprintf(note, sizeof(note),
                 "<4>[ZPD1203-6.6] STAGE 7-early: bind zpd_com/UDC (%s) failed errno=%d (%s)\n",
                 udc, last_err, strerror(last_err));
        klog_note(note);
        return -1;
    }

    char pbuf[32] = {0};
    int port_num = 0;
    if (read_sys_str(ZPD_EARLY_GADGET "/functions/acm.gs0/port_num", pbuf, sizeof(pbuf)) == 0) {
        port_num = atoi(pbuf);
    }
    char tty_path[64];
    snprintf(tty_path, sizeof(tty_path), "/dev/ttyGS%d", port_num);
    ensure_tty_node(tty_path, port_num);

    int new_tty = open_tty_raw(tty_path);
    if (new_tty >= 0) {
        if (*tty_fd >= 0) close(*tty_fd);
        *tty_fd = new_tty;
        snprintf(note, sizeof(note),
                 "<6>[ZPD1203-6.6] STAGE 7-early: COM logger live on %s (zpd_com %s)\n",
                 tty_path, udc);
        klog_note(note);
    } else {
        snprintf(note, sizeof(note),
                 "<4>[ZPD1203-6.6] STAGE 7-early: open %s failed errno=%d (%s)\n",
                 tty_path, errno, strerror(errno));
        klog_note(note);
    }
    return 0;
}

static void unbind_early_acm(int *tty_fd) {
    if (*tty_fd >= 0) {
        close(*tty_fd);
        *tty_fd = -1;
    }
    write_sys(ZPD_EARLY_GADGET "/UDC", "\n");
    usleep(100000);
    unlink(ZPD_EARLY_GADGET "/configs/c.1/acm.gs0");
    rmdir(ZPD_EARLY_GADGET "/configs/c.1/strings/0x409");
    rmdir(ZPD_EARLY_GADGET "/configs/c.1");
    rmdir(ZPD_EARLY_GADGET "/functions/acm.gs0");
    rmdir(ZPD_EARLY_GADGET "/strings/0x409");
    rmdir(ZPD_EARLY_GADGET);
    umount2(ZPD_EARLY_CFGFS, MNT_DETACH);
    rmdir(ZPD_EARLY_CFGFS);
    klog_note("<6>[ZPD1203-6.6] STAGE 7: released early zpd_com gadget for g1 handoff\n");
}

static int bind_composite_g1(int *tty_fd, const char *hw_udc, int with_adb) {
    char note[512];
    char udc[256];
    char cur_udc[256] = {0};

    enable_musb_init_done();
    snprintf(udc, sizeof(udc), "%s", hw_udc);
    if (!udc[0]) find_hw_udc(udc, sizeof(udc), 5);
    if (!udc[0]) snprintf(udc, sizeof(udc), "musb-hdrc");

    if (read_sys_str("/config/usb_gadget/g1/UDC", cur_udc, sizeof(cur_udc)) == 0 && cur_udc[0]) {
        write_sys("/config/usb_gadget/g1/UDC", "\n");
        usleep(100000);
    }

    const char *old_links[] = {
        "/config/usb_gadget/g1/configs/b.1/f0",
        "/config/usb_gadget/g1/configs/b.1/f1",
        "/config/usb_gadget/g1/configs/b.1/f2",
        "/config/usb_gadget/g1/configs/b.1/f3",
        "/config/usb_gadget/g1/configs/b.1/f4",
        "/config/usb_gadget/g1/configs/b.1/f5",
    };
    for (size_t i = 0; i < sizeof(old_links) / sizeof(old_links[0]); i++) {
        unlink(old_links[i]);
    }

    write_sys("/config/usb_gadget/g1/os_desc/use", "0\n");
    if (with_adb) {
        write_sys("/config/usb_gadget/g1/bDeviceClass", "0xef\n");
        write_sys("/config/usb_gadget/g1/bDeviceSubClass", "0x02\n");
        write_sys("/config/usb_gadget/g1/bDeviceProtocol", "0x01\n");
        write_sys("/config/usb_gadget/g1/idVendor", "0x0e8d\n");
        write_sys("/config/usb_gadget/g1/idProduct", "0x2006\n");
        write_sys("/config/usb_gadget/g1/configs/b.1/strings/0x409/configuration", "adb_acm\n");
    } else {
        write_sys("/config/usb_gadget/g1/bDeviceClass", "0x02\n");
        write_sys("/config/usb_gadget/g1/bDeviceSubClass", "0x00\n");
        write_sys("/config/usb_gadget/g1/bDeviceProtocol", "0x00\n");
        write_sys("/config/usb_gadget/g1/idVendor", "0x1d6b\n");
        write_sys("/config/usb_gadget/g1/idProduct", "0x0104\n");
        write_sys("/config/usb_gadget/g1/configs/b.1/strings/0x409/configuration", "acm_only\n");
    }

    mkdir("/config/usb_gadget/g1/functions/acm.gs1", 0755);
    if (with_adb) {
        mkdir("/config/usb_gadget/g1/functions/ffs.adb", 0755);
        if (symlink("/config/usb_gadget/g1/functions/ffs.adb",
                    "/config/usb_gadget/g1/configs/b.1/f1") < 0 && errno != EEXIST) {
            snprintf(note, sizeof(note), "<4>[ZPD1203-6.6] symlink g1/f1 ffs.adb failed errno=%d (%s)\n",
                     errno, strerror(errno));
            klog_note(note);
        }
        if (symlink("/config/usb_gadget/g1/functions/acm.gs1",
                    "/config/usb_gadget/g1/configs/b.1/f2") < 0 && errno != EEXIST) {
            snprintf(note, sizeof(note), "<4>[ZPD1203-6.6] symlink g1/f2 acm.gs1 failed errno=%d (%s)\n",
                     errno, strerror(errno));
            klog_note(note);
        }
    } else {
        if (symlink("/config/usb_gadget/g1/functions/acm.gs1",
                    "/config/usb_gadget/g1/configs/b.1/f1") < 0 && errno != EEXIST) {
            snprintf(note, sizeof(note), "<4>[ZPD1203-6.6] symlink g1/f1 acm.gs1 failed errno=%d (%s)\n",
                     errno, strerror(errno));
            klog_note(note);
        }
    }

    char udc_nl[280];
    snprintf(udc_nl, sizeof(udc_nl), "%s\n", udc);
    int bound = -1;
    int last_err = 0;
    for (int i = 0; i < 5; i++) {
        if (write_sys("/config/usb_gadget/g1/UDC", udc_nl) == 0) {
            bound = 0;
            break;
        }
        last_err = errno;
        usleep(100000);
    }

    if (bound == 0) {
        snprintf(note, sizeof(note),
                 "<6>[ZPD1203-6.6] STAGE 7: bound g1 (%s) to %s ok\n",
                 with_adb ? "ffs.adb+acm.gs1" : "acm.gs1-only", udc);
        klog_note(note);
    } else {
        snprintf(note, sizeof(note),
                 "<3>[ZPD1203-6.6] STAGE 7 FAIL: bind g1/UDC (%s) errno=%d (%s)\n",
                 udc, last_err, strerror(last_err));
        klog_note(note);
        return -1;
    }

    char pbuf[32] = {0};
    int port_num = 1;
    if (read_sys_str("/config/usb_gadget/g1/functions/acm.gs1/port_num", pbuf, sizeof(pbuf)) == 0) {
        port_num = atoi(pbuf);
    }
    char tty_path[64];
    snprintf(tty_path, sizeof(tty_path), "/dev/ttyGS%d", port_num);
    ensure_tty_node(tty_path, port_num);

    int new_tty = open_tty_raw(tty_path);
    if (new_tty >= 0) {
        if (*tty_fd >= 0) close(*tty_fd);
        *tty_fd = new_tty;
        snprintf(note, sizeof(note),
                 "<6>[ZPD1203-6.6] COM logger attached to %s (%s)\n",
                 tty_path, with_adb ? "composite ADB+ACM" : "ACM fallback");
        klog_note(note);
    } else {
        snprintf(note, sizeof(note),
                 "<4>[ZPD1203-6.6] open %s failed errno=%d (%s)\n",
                 tty_path, errno, strerror(errno));
        klog_note(note);
    }
    return 0;
}

static int g1_acm_link_intact(void) {
    char linkbuf[256];
    char udc_cur[128] = {0};
    ssize_t n = readlink("/config/usb_gadget/g1/configs/b.1/f2", linkbuf, sizeof(linkbuf) - 1);
    if (n <= 0) return 0;
    linkbuf[n] = '\0';
    if (!strstr(linkbuf, "acm.gs1")) return 0;
    if (read_sys_str("/config/usb_gadget/g1/UDC", udc_cur, sizeof(udc_cur)) != 0 || !udc_cur[0]) {
        return 0;
    }
    return 1;
}

static void send_pstore_to_tty(int tty_fd) {
    int dfd = open("/dev/.pstore_dump.log", O_RDONLY);
    if (dfd < 0) {
        const char *m = "\r\n[pstore] no /dev/.pstore_dump.log captured\r\n";
        (void)!write(tty_fd, m, strlen(m));
        return;
    }
    char buf[1024];
    ssize_t r;
    while ((r = read(dfd, buf, sizeof(buf))) > 0) {
        (void)!write(tty_fd, buf, (size_t)r);
    }
    close(dfd);
}

static void run_logger_child(int kmsg_fd, int proc_fd, int bridge_fd,
                             int mod_fds[ZPD_MOD_COUNT], int mod_loaded[ZPD_MOD_COUNT],
                             const char *hw_udc) {
    static char ring[524288];
    size_t fill = 0, sent = 0;
    char cmd[64];
    size_t clen = 0;
    int tty_fd = -1;
    int released = 0;
    int in_new_root = 0;
    int hwc_bound = 0;
    int fb_chmed = 0;
    int mali_chmed = 0;
    int ion_chmed = 0;
    int early_acm_bound = 0;
    int switched_to_g1 = 0;
    int g1_with_adb = 0;
    int rebind_count = 0;
    int loops = 0;
    int new_root_loops = 0;
    int early_acm_next_try = 300;
    int early_acm_tries = 0;
    int g1_next_try = 0;
    int g1_tries = 0;

    setsid();
    signal(SIGPIPE, SIG_IGN);
    signal(SIGHUP, SIG_IGN);

    static const char banner[] =
        "\r\n=== ZPD1203 Linux 6.6 Screen+COM Logger (cmds: status, pstore, help, unbind, reboot-fb) ===\r\n";
    memcpy(ring, banner, sizeof(banner) - 1);
    fill = sizeof(banner) - 1;

    while (!released) {
        if (kmsg_fd >= 0) {
            for (int iter = 0; iter < 64; iter++) {
                char kline[2048];
                ssize_t kr = read(kmsg_fd, kline, sizeof(kline) - 1);
                if (kr <= 0) break;
                for (ssize_t i = 0; i < kr; i++) {
                    char c = kline[i];
                    if (fill + 2 >= sizeof(ring)) {
                        if (sent > 0) {
                            size_t rem = fill - sent;
                            memmove(ring, ring + sent, rem);
                            fill = rem;
                            sent = 0;
                        }
                        if (fill + 2 >= sizeof(ring)) {
                            size_t drop = sizeof(ring) / 4;
                            memmove(ring, ring + drop, fill - drop);
                            fill -= drop;
                            sent = (sent > drop) ? (sent - drop) : 0;
                        }
                    }
                    if (c == '\n') {
                        ring[fill++] = '\r';
                        ring[fill++] = '\n';
                    } else {
                        ring[fill++] = c;
                    }
                }
            }
        }

        if (tty_fd >= 0 && sent < fill) {
            while (sent < fill) {
                size_t chunk = fill - sent;
                if (chunk > 512) chunk = 512;
                ssize_t w = write(tty_fd, ring + sent, chunk);
                if (w > 0) {
                    sent += (size_t)w;
                    continue;
                }
                break;
            }
            if (sent == fill) {
                sent = 0;
                fill = 0;
            }
        }

        if (tty_fd >= 0) {
            struct pollfd pfd;
            pfd.fd = tty_fd;
            pfd.events = POLLIN;
            int pr = poll(&pfd, 1, 50);
            if (pr > 0 && (pfd.revents & POLLIN)) {
                char rb[64];
                ssize_t nr = read(tty_fd, rb, sizeof(rb));
                if (nr > 0) {
                    for (ssize_t i = 0; i < nr; i++) {
                        char c = rb[i];
                        if (c == '\r' || c == '\n') {
                            cmd[clen] = '\0';
                            if (strcmp(cmd, "reboot-fb") == 0) {
                                const char *m = "\r\nRebooting to fastboot...\r\n";
                                (void)!write(tty_fd, m, strlen(m));
                                sync();
                                syscall(SYS_reboot, LINUX_REBOOT_MAGIC1, LINUX_REBOOT_MAGIC2,
                                        LINUX_REBOOT_CMD_RESTART2, "bootloader");
                            } else if (strcmp(cmd, "unbind") == 0) {
                                const char *m = "\r\nReleasing active UDC...\r\n";
                                (void)!write(tty_fd, m, strlen(m));
                                released = 1;
                            } else if (strcmp(cmd, "pstore") == 0) {
                                send_pstore_to_tty(tty_fd);
                            } else if (strcmp(cmd, "help") == 0) {
                                const char *h = "\r\nCommands: status | pstore | help | unbind | reboot-fb\r\n";
                                (void)!write(tty_fd, h, strlen(h));
                            } else if (strcmp(cmd, "status") == 0) {
                                char udc_cur[128] = "n/a";
                                char sbuf[448];
                                if (switched_to_g1) {
                                    read_sys_str("/config/usb_gadget/g1/UDC", udc_cur, sizeof(udc_cur));
                                } else if (early_acm_bound) {
                                    read_sys_str(ZPD_EARLY_GADGET "/UDC", udc_cur, sizeof(udc_cur));
                                }
                                int n = snprintf(
                                    sbuf, sizeof(sbuf),
                                    "\r\n[status] new_root=%d early_acm=%d g1_switched=%d rebinds=%d hwc_bound=%d ep1=%d dri=%d fb0=%d mali=%d ion=%d pstore=%d UDC='%s'\r\n",
                                    in_new_root, early_acm_bound, switched_to_g1, rebind_count,
                                    hwc_bound,
                                    access("/dev/usb-ffs/adb/ep1", F_OK) == 0,
                                    access("/dev/dri/card0", F_OK) == 0,
                                    access("/dev/graphics/fb0", F_OK) == 0,
                                    access("/dev/mali0", F_OK) == 0,
                                    access("/dev/ion", F_OK) == 0,
                                    access("/dev/.pstore_dump.log", F_OK) == 0,
                                    udc_cur);
                                if (n > 0) (void)!write(tty_fd, sbuf, (size_t)n);
                            }
                            clen = 0;
                        } else if ((unsigned char)c >= 0x20 && (unsigned char)c < 0x7f) {
                            if (clen + 1 < sizeof(cmd)) cmd[clen++] = c;
                        }
                    }
                }
            }
        } else {
            usleep(50000);
        }
        loops++;
        if (in_new_root) new_root_loops++;

        if (!in_new_root && proc_fd >= 0 &&
            faccessat(proc_fd, "1/root/vendor/lib64/hw/hwcomposer.mt6768.so", F_OK, 0) == 0) {
            int rfd = openat(proc_fd, "1/root", O_RDONLY | O_DIRECTORY);
            if (rfd >= 0) {
                if (fchdir(rfd) == 0 && chroot(".") == 0 && chdir("/") == 0) {
                    in_new_root = 1;
                    load_zpd_modules(mod_fds, mod_loaded, "post-switchroot");
                    stage_vendor_module_overrides(mod_fds);
                    close_zpd_modules(mod_fds);

                    int has_dri = (access("/dev/dri/card0", F_OK) == 0);
                    for (int w = 0; !has_dri && w < 10; w++) {
                        usleep(20000);
                        has_dri = (access("/dev/dri/card0", F_OK) == 0);
                    }
                    if (has_dri) {
                        klog_stage(5, "SwitchRoot complete; native DRM /dev/dri/card0 active (skipping simplefb HWC stub)");
                        if (bridge_fd >= 0) {
                            close(bridge_fd);
                            bridge_fd = -1;
                        }
                    } else {
                        klog_stage(5, "SwitchRoot complete; /dev/dri/card0 absent, binding HWC empty stub + gralloc.fb0_bridge.so");
                        setup_hwc_fb_fallback(&hwc_bound, &bridge_fd);
                    }
                }
                close(rfd);
            }
        }

        if (in_new_root && new_root_loops <= 1200 && (new_root_loops % 20 == 1)) {
            ensure_dev_perms(&fb_chmed, &mali_chmed, &ion_chmed);
        }

        if (!early_acm_bound && !switched_to_g1 && loops >= early_acm_next_try &&
            early_acm_tries < 15 &&
            (!in_new_root || access("/config/usb_gadget/g1/configs/b.1", F_OK) != 0)) {
            early_acm_tries++;
            if (bind_early_acm(&tty_fd, hw_udc) == 0) {
                early_acm_bound = 1;
            } else {
                early_acm_next_try = loops + 40;
            }
        }

        if (in_new_root && !switched_to_g1 && loops >= g1_next_try && g1_tries < 15 &&
            access("/config/usb_gadget/g1/configs/b.1", F_OK) == 0) {
            if (access("/dev/usb-ffs/adb/ep1", F_OK) == 0) {
                if (early_acm_bound) {
                    unbind_early_acm(&tty_fd);
                    early_acm_bound = 0;
                }
                g1_tries++;
                if (bind_composite_g1(&tty_fd, hw_udc, 1) == 0) {
                    switched_to_g1 = 1;
                    g1_with_adb = 1;
                } else {
                    g1_next_try = loops + 40;
                }
            } else if (new_root_loops >= 500) {
                klog_note("<4>[ZPD1203-6.6] STAGE 7: ep1 timeout (~25s post-SwitchRoot), binding ACM-only fallback on g1\n");
                if (early_acm_bound) {
                    unbind_early_acm(&tty_fd);
                    early_acm_bound = 0;
                }
                g1_tries++;
                if (bind_composite_g1(&tty_fd, hw_udc, 0) == 0) {
                    switched_to_g1 = 1;
                    g1_with_adb = 0;
                } else {
                    g1_next_try = loops + 40;
                }
            }
        } else if (in_new_root && switched_to_g1 && g1_with_adb &&
                   (loops % 40 == 0) && rebind_count < 6 &&
                   access("/dev/usb-ffs/adb/ep1", F_OK) == 0 &&
                   !g1_acm_link_intact()) {
            klog_note("<4>[ZPD1203-6.6] STAGE 7 watchdog: restoring g1 (ffs.adb+acm.gs1) after Android USB reset\n");
            if (bind_composite_g1(&tty_fd, hw_udc, 1) == 0) {
                rebind_count++;
            }
        }
    }

    if (switched_to_g1) {
        write_sys("/config/usb_gadget/g1/UDC", "\n");
    } else if (early_acm_bound) {
        unbind_early_acm(&tty_fd);
    }
    close_zpd_modules(mod_fds);
    if (bridge_fd >= 0) close(bridge_fd);
    if (proc_fd >= 0) close(proc_fd);
    if (tty_fd >= 0) close(tty_fd);
    if (kmsg_fd >= 0) close(kmsg_fd);
    _exit(0);
}

int main(int argc, char **argv) {
    struct stat st;
    int mounted_dev = 0;
    if (stat("/dev/kmsg", &st) != 0) {
        if (mount("devtmpfs", "/dev", "devtmpfs", 0, NULL) == 0) mounted_dev = 1;
    }
    int mounted_sys = (mount("sysfs", "/sys", "sysfs", 0, NULL) == 0);
    mkdir("/proc", 0755);
    int mounted_proc = (mount("proc", "/proc", "proc", 0, NULL) == 0);
    int proc_fd = open("/proc", O_RDONLY | O_DIRECTORY);

    klog_stage(1, "pre-init wrapper started (dev/sys/proc ready)");
    dump_pstore_early();

    int mod_fds[ZPD_MOD_COUNT];
    int mod_loaded[ZPD_MOD_COUNT];
    open_zpd_modules(mod_fds, mod_loaded);
    load_zpd_modules(mod_fds, mod_loaded, "pre-init");

    char hw_udc[256] = {0};
    if (find_hw_udc(hw_udc, sizeof(hw_udc), 25) < 0) {
        klog_stage(3, "no hardware UDC found early; will retry musb-hdrc after SwitchRoot");
    } else {
        char note[320];
        snprintf(note, sizeof(note),
                 "<6>[ZPD1203-6.6] STAGE 3: detected UDC %s (deferring first bind to g1/zpd_com)\n",
                 hw_udc);
        klog_note(note);
    }

    int bridge_fd = open("/gralloc.fb0_bridge.so", O_RDONLY);
    if (bridge_fd < 0) {
        klog_note("<4>[ZPD1203-6.6] warning: open /gralloc.fb0_bridge.so failed\n");
    }

    int kmsg_fd = open("/dev/kmsg", O_RDONLY | O_NONBLOCK);
    if (kmsg_fd >= 0 || proc_fd >= 0) {
        pid_t pid = fork();
        if (pid == 0) {
            run_logger_child(kmsg_fd, proc_fd, bridge_fd, mod_fds, mod_loaded, hw_udc);
        }
        usleep(50000);
    }

    close_zpd_modules(mod_fds);
    if (bridge_fd >= 0) close(bridge_fd);
    if (kmsg_fd >= 0) close(kmsg_fd);
    if (proc_fd >= 0) close(proc_fd);

    if (mounted_sys) umount2("/sys", MNT_DETACH);
    if (mounted_dev) umount2("/dev", MNT_DETACH);
    if (mounted_proc) umount2("/proc", MNT_DETACH);

    klog_stage(4, "chaining to /system/bin/init");
    (void)argc;
    execv("/system/bin/init", argv);
    klog_note("<3>[ZPD1203-6.6] STAGE 4 FAIL: execv(/system/bin/init) returned error\n");
    for (;;) sleep(1);
    return 1;
}
