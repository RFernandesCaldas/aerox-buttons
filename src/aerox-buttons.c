/* aerox-buttons - extra mouse buttons -> macOS actions.
 *
 *   F3 (page 0x07 usage 0x3c) -> Mission Control
 *   F4 (page 0x07 usage 0x3d) -> Applications launcher
 *
 * Configure the buttons on the mouse itself (e.g. with rivalcfg) to emit F3
 * and F4; this daemon turns those keystrokes into macOS actions.
 *
 * Matches vendor 0x1038 (USB) and 0x0111 (Bluetooth): the Aerox 5 Wireless
 * reports a different vendor ID depending on the transport, and over
 * Bluetooth it exposes a single composite interface, so the match is done on
 * vendor only - filtering on PrimaryUsage would miss the buttons entirely.
 *
 * Mission Control via com.apple.exposelauncher is a toggle, exactly like the
 * keyboard's own F3 key, so no window-state guessing is done here.
 */
#include <IOKit/hid/IOHIDManager.h>
#include <IOKit/hid/IOHIDKeys.h>
#include <ApplicationServices/ApplicationServices.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>
#include <time.h>
#include <fcntl.h>
#include <sys/wait.h>

#define USAGE_F3 0x3c
#define USAGE_F4 0x3d
#define DEBOUNCE 0.40

static double last_fire[2] = { 0, 0 };
static const char *LOG = "/tmp/aerox-buttons.log";

static void logmsg(const char *m) {
    FILE *f = fopen(LOG, "a");
    if (!f) return;
    time_t t = time(NULL);
    struct tm tv;
    localtime_r(&t, &tv);
    fprintf(f, "%02d:%02d:%02d %s\n", tv.tm_hour, tv.tm_min, tv.tm_sec, m);
    fclose(f);
}

static void run(const char *const argv[]) {
    pid_t p = fork();
    if (p == 0) {
        setsid();
        int dn = open("/dev/null", O_WRONLY);
        if (dn >= 0) { dup2(dn, 1); dup2(dn, 2); }
        execvp(argv[0], (char *const *)argv);
        _exit(127);
    }
    if (p > 0) waitpid(p, NULL, 0);
}

static void cb(void *ctx __attribute__((unused)),
               IOReturn res __attribute__((unused)),
               void *sender __attribute__((unused)),
               IOHIDValueRef value) {
    IOHIDElementRef el = IOHIDValueGetElement(value);
    if (!el) return;
    if (IOHIDElementGetUsagePage(el) != 0x07) return;
    uint32_t usage = IOHIDElementGetUsage(el);
    if (IOHIDValueGetIntegerValue(value) == 0) return;
    if (usage != USAGE_F3 && usage != USAGE_F4) return;

    int idx = (usage == USAGE_F3) ? 0 : 1;
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    double now = ts.tv_sec + ts.tv_nsec / 1e9;
    if (now - last_fire[idx] < DEBOUNCE) return;
    last_fire[idx] = now;

    if (idx == 0) {
        /* The keyboard's own F3 is a toggle; mirror that exactly. */
        logmsg("F3 -> Mission Control (toggle)");
        run((const char *const[]){ "/usr/bin/open", "-b", "com.apple.exposelauncher", NULL });
    } else {
        logmsg("F4 -> Applications");
        run((const char *const[]){ "/usr/bin/open", "-b", "com.apple.apps.launcher", NULL });
    }
}

static void device_added(void *ctx __attribute__((unused)),
                         IOReturn res __attribute__((unused)),
                         void *sender __attribute__((unused)),
                         IOHIDDeviceRef dev __attribute__((unused))) {
    logmsg("device added");
}

int main(void) {
    IOHIDManagerRef mgr = IOHIDManagerCreate(kCFAllocatorDefault, kIOHIDOptionsTypeNone);

    /* Match on vendor only: over Bluetooth the mouse exposes a single
     * composite interface, so a PrimaryUsage filter would miss the buttons. */
    int vendors[2] = { 0x1038, 0x0111 };
    CFMutableDictionaryRef matches[2];
    for (int i = 0; i < 2; i++) {
        CFNumberRef vN = CFNumberCreate(NULL, kCFNumberIntType, &vendors[i]);
        CFMutableDictionaryRef d = CFDictionaryCreateMutable(NULL, 0, NULL, NULL);
        CFDictionarySetValue(d, CFSTR(kIOHIDVendorIDKey), vN);
        matches[i] = d;
        CFRelease(vN);
    }
    CFTypeRef arrv[2] = { matches[0], matches[1] };
    CFArrayRef arr = CFArrayCreate(NULL, arrv, 2, &kCFTypeArrayCallBacks);

    IOHIDManagerSetDeviceMatchingMultiple(mgr, arr);
    IOHIDManagerRegisterInputValueCallback(mgr, cb, NULL);
    IOHIDManagerRegisterDeviceMatchingCallback(mgr, device_added, NULL);
    IOHIDManagerScheduleWithRunLoop(mgr, CFRunLoopGetCurrent(), kCFRunLoopDefaultMode);
    IOReturn r = IOHIDManagerOpen(mgr, kIOHIDOptionsTypeNone);
    logmsg(r == kIOReturnSuccess ? "started OK" : "FAILED to open HID manager");
    CFRunLoopRun();
    return 0;
}
