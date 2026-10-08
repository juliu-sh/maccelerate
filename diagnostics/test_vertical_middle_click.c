#include <ApplicationServices/ApplicationServices.h>
#include <time.h>
#include <string.h>
static double test_now = 100;
static CGEventTimestamp native_timestamp = 100000000000;
static int test_clock(clockid_t clock, struct timespec *time) {
    (void)clock;
    time->tv_sec = (time_t)test_now;
    time->tv_nsec = (long)((test_now - (double)time->tv_sec) * 1e9);
    return 0;
}
static bool tap_enabled;
static CGEventMask subscribed;
static const char *product_version = "26.6";
int middle_fixture_sysctlbyname(const char *name, void *out, size_t *size, void *new_value, size_t new_size) {
    (void)new_value; (void)new_size;
    const char *value = !strcmp(name, "kern.osproductversion") ? product_version : "unknown";
    size_t length = strlen(value) + 1;
    if (!out) { *size = length; return 0; }
    if (*size < length) return -1;
    memcpy(out, value, length); *size = length; return 0;
}
static CFMachPortRef test_tap(CGEventTapLocation location, CGEventTapPlacement placement,
    CGEventTapOptions options, CGEventMask mask, CGEventTapCallBack callback, void *context) {
    (void)location; (void)placement; (void)options; (void)callback; (void)context;
    subscribed = mask;
    CFMachPortContext port = {0, NULL, NULL, NULL, NULL};
    return CFMachPortCreate(NULL, NULL, &port, NULL);
}
static void test_enable(CFMachPortRef port, bool enabled) { (void)port; tap_enabled = enabled; }
static bool test_enabled(CFMachPortRef port) { (void)port; return tap_enabled; }
#define clock_gettime test_clock
#define CGEventTapCreate test_tap
#define CGEventTapEnable test_enable
#define CGEventTapIsEnabled test_enabled
#define main retained_recovery_main
#include "test_gesture_recovery.c"
#undef main

static void vertical(int phase) {
    CGEventRef event = gesture(30, 2, phase);
    CGEventSetTimestamp(event, ++native_timestamp);
    if (phase == 2 || phase == 4) {
        CGEventSetDoubleValueField(event, (CGEventField)124, .1);
        CGEventSetDoubleValueField(event, (CGEventField)126, .15);
        CGEventSetDoubleValueField(event, (CGEventField)130, .25);
    }
    CGEventRef prepared = iss_prepare_dock_swipe_event_for_current_os(event);
    CFRelease(event);
    assert(prepared);
    CGEventSetIntegerValueField(prepared, kCGEventSourceUnixProcessID, 0);
    deliver(prepared);
    CFRelease(prepared);
}
static bool mouse(CGEventType type, unsigned button, int pid) {
    CGEventRef event = CGEventCreateMouseEvent(NULL, type, CGPointZero, (CGMouseButton)button);
    assert(event);
    CGEventSetIntegerValueField(event, kCGMouseEventButtonNumber, button);
    CGEventSetIntegerValueField(event, kCGEventSourceUnixProcessID, pid);
    CGEventRef result = deliver(event);
    assert(!result || result == event);
    CFRelease(event);
    return result != NULL;
}
static void reset(void) {
    iss_destroy();
    inputRequiresRestart = false;
    iss_set_swipe_override(true);
    iss_set_gesture_speed(1000);
    test_now = 100;
}
static void fresh_contact(void) {
    CGEventRef event = gesture(29, 0, 1);
    CGEventSetTimestamp(event, ++native_timestamp);
    assert(deliver(event) == event);
    CFRelease(event);
}
int main(int argc, char **argv) {
    if (argc > 1) product_version = argv[1];
    unsetenv("ISS_FORCE_EVENT_AUGMENTATION");
    reset();
    assert(mouse(kCGEventOtherMouseDown, 2, 4242));
    assert(mouse(kCGEventOtherMouseUp, 2, 4242));
    vertical(1); vertical(2); vertical(4);
    // A downstream Mission Control middle-click action must see no click
    // from the consumed/accelerated three-finger swipe's release.
    unsigned unexpected_app_closes = mouse(kCGEventOtherMouseDown, 2, 4242) ? 1 : 0;
    if (unexpected_app_closes) {
        puts("FAIL: synthesized middle click after vertical swipe reaches downstream app-close action");
        return 1;
    }
    assert(!mouse(kCGEventOtherMouseUp, 2, 4242));
    // Once a new physical contact begins, a deliberate tap is still usable.
    fresh_contact();
    assert(mouse(kCGEventOtherMouseDown, 2, 4242));
    assert(mouse(kCGEventOtherMouseUp, 2, 4242));

    reset(); vertical(1); vertical(2);
    assert(!mouse(kCGEventOtherMouseDown, 2, 4242));
    assert(!mouse(kCGEventOtherMouseDragged, 2, 4242));
    vertical(4); test_now += .3;
    assert(!mouse(kCGEventOtherMouseUp, 2, 4242)); // Matched release beyond the swipe window.
    assert(mouse(kCGEventOtherMouseDown, 2, 4242));
    assert(mouse(kCGEventOtherMouseUp, 2, 4242));

    // The same software can issue a new valid click even if an old Up was lost.
    reset(); vertical(1); vertical(2); vertical(4);
    assert(!mouse(kCGEventOtherMouseDown, 2, 4242));
    test_now += .3;
    assert(mouse(kCGEventOtherMouseDown, 2, 4242));
    assert(mouse(kCGEventOtherMouseUp, 2, 4242));

    // Lost terminal or mouse-Up events cannot latch the filter indefinitely.
    reset(); vertical(1); vertical(2); test_now += 1.1;
    assert(mouse(kCGEventOtherMouseDown, 2, 4242));
    reset(); vertical(1); vertical(2);
    assert(!mouse(kCGEventOtherMouseDown, 2, 4242));
    test_now += 1.1;
    assert(!mouse(kCGEventOtherMouseUp, 2, 4242));
    assert(mouse(kCGEventOtherMouseDown, 2, 4242));
    assert(mouse(kCGEventOtherMouseUp, 2, 4242));

    // A touch sequence without movement and orphan Changed/Ended are not swipes.
    reset(); vertical(1);
    CGEventRef zero_end = gesture(30, 2, 4);
    deliver(zero_end); CFRelease(zero_end);
    assert(mouse(kCGEventOtherMouseDown, 2, 4242));
    reset(); vertical(2); vertical(4);
    assert(mouse(kCGEventOtherMouseDown, 2, 4242));

    // Preserve hardware middle clicks, other buttons and different-source Up.
    reset(); vertical(1); vertical(2);
    assert(mouse(kCGEventOtherMouseDown, 2, 0));
    assert(mouse(kCGEventOtherMouseUp, 2, 0));
    assert(mouse(kCGEventLeftMouseDown, 0, 4242));
    assert(mouse(kCGEventLeftMouseUp, 0, 4242));
    assert(mouse(kCGEventRightMouseDown, 1, 4242));
    assert(mouse(kCGEventRightMouseUp, 1, 4242));
    assert(!mouse(kCGEventOtherMouseDown, 2, 4242));
    assert(mouse(kCGEventOtherMouseUp, 2, 9876));
    assert(!mouse(kCGEventOtherMouseUp, 2, 4242));

    // Overlapping software sources need independent Down/Up pairing.
    reset(); vertical(1); vertical(2);
    assert(!mouse(kCGEventOtherMouseDown, 2, 4242));
    assert(!mouse(kCGEventOtherMouseDown, 2, 9876));
    vertical(4); test_now += .3;
    assert(!mouse(kCGEventOtherMouseUp, 2, 4242));
    assert(!mouse(kCGEventOtherMouseUp, 2, 9876));
    assert(mouse(kCGEventOtherMouseDown, 2, 4242));
    assert(mouse(kCGEventOtherMouseUp, 2, 4242));

    // Duplicate Down and concurrent clients must not overwrite each other.
    reset(); vertical(1); vertical(2);
    assert(!mouse(kCGEventOtherMouseDown, 2, 4242));
    assert(!mouse(kCGEventOtherMouseDown, 2, 4242));
    assert(!mouse(kCGEventOtherMouseUp, 2, 4242));
    assert(!mouse(kCGEventOtherMouseUp, 2, 4242));
    reset(); vertical(1); vertical(2);
    for (int pid = 10000; pid < 10008; pid++) assert(!mouse(kCGEventOtherMouseDown, 2, pid));
    // At capacity, allow the complete extra click rather than dropping a Down
    // whose Up cannot be safely paired. Other sources remain protected.
    assert(mouse(kCGEventOtherMouseDown, 2, 10008));
    assert(mouse(kCGEventOtherMouseUp, 2, 10008));
    for (int pid = 10000; pid < 10008; pid++) assert(!mouse(kCGEventOtherMouseUp, 2, pid));

    // Long synthetic holds cannot leak a later Up-only close action.
    reset(); vertical(1); vertical(2); vertical(4);
    assert(!mouse(kCGEventOtherMouseDown, 2, 4242));
    test_now += 10;
    assert(!mouse(kCGEventOtherMouseDragged, 2, 4242));
    assert(!mouse(kCGEventOtherMouseUp, 2, 4242));
    assert(mouse(kCGEventOtherMouseDown, 2, 4242));
    assert(mouse(kCGEventOtherMouseUp, 2, 4242));

    // Release-time boundary and cancellation both close the physical swipe.
    reset(); vertical(1); vertical(2); vertical(8); test_now += .149;
    assert(!mouse(kCGEventOtherMouseDown, 2, 4242));
    assert(!mouse(kCGEventOtherMouseUp, 2, 4242));
    test_now += .002;
    assert(mouse(kCGEventOtherMouseDown, 2, 4242));

    // Late companion Begin from the same swipe must not clear the guard.
    reset(); vertical(1); vertical(2);
    CGEventRef late_begin = gesture(29, 0, 1);
    CGEventSetTimestamp(late_begin, ++native_timestamp);
    vertical(4);
    assert(deliver(late_begin) == late_begin);
    CFRelease(late_begin);
    assert(!mouse(kCGEventOtherMouseDown, 2, 4242));

    // Disable, destroy, timeout and permission suspension must fail open.
    for (unsigned stop = 0; stop < 4; stop++) {
        reset(); vertical(1); vertical(2);
        assert(!mouse(kCGEventOtherMouseDown, 2, 4242));
        switch (stop) {
        case 0: iss_set_swipe_override(false); break;
        case 1: iss_destroy(); break;
        case 2: eventTapCallback(NULL, kCGEventTapDisabledByTimeout, NULL, NULL); break;
        case 3: iss_suspend_for_permission_change(); break;
        }
        assert(mouse(kCGEventOtherMouseUp, 2, 4242));
        assert(mouse(kCGEventOtherMouseDown, 2, 4242));
    }

    reset(); iss_set_swipe_override(false); vertical(1); vertical(2); vertical(4);
    assert(mouse(kCGEventOtherMouseDown, 2, 4242));
    reset(); iss_set_gesture_speed(25); vertical(1); vertical(2); vertical(4);
    assert(mouse(kCGEventOtherMouseDown, 2, 4242));

    // Unknown raw payload on the modern path is passed through rather than
    // accelerated. It must not arm a filter for a gesture we left native.
    if (iss_requires_event_augmentation()) {
        reset(); vertical(1);
        CGEventRef malformed = gesture(30, 2, 2);
        CGEventSetDoubleValueField(malformed, (CGEventField)124, .1);
        assert(deliver(malformed) == malformed);
        CFRelease(malformed);
        assert(mouse(kCGEventOtherMouseDown, 2, 4242));
    }

    // The actual app subscribes to the guarded events, rather than just
    // passing an artificial event type into an otherwise unused callback.
    reset(); assert(iss_init());
    assert(subscribed & CGEventMaskBit(kCGEventOtherMouseDown));
    assert(subscribed & CGEventMaskBit(kCGEventOtherMouseUp));
    assert(subscribed & CGEventMaskBit(kCGEventOtherMouseDragged));
    printf("PASS: product=%s; middle-click action, deliberate taps, hardware, pairing, expiry and lifecycle; no desktop input\n", product_version);
    iss_destroy();
    if (last_posted) CFRelease(last_posted);
    return 0;
}
