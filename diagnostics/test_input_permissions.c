#include <ApplicationServices/ApplicationServices.h>
#include <assert.h>
#include <stdio.h>

// Mock TCC and CG tap operations: this executable never observes or posts
// real desktop input. Its Mach port is an ordinary, private CF test resource.
static bool trusted = true, mayPost = true, enabled = false, failSource = false;
static unsigned creates, enables, posts;
static bool fake_trusted(void) { return trusted; }
static bool fake_post_access(void) { return mayPost; }
static CFMachPortRef fake_create(CGEventTapLocation tap, CGEventTapPlacement place,
    CGEventTapOptions options, CGEventMask mask, CGEventTapCallBack callback, void *info) {
    (void)tap; (void)place; (void)options; (void)mask; (void)callback; (void)info;
    creates++;
    CFMachPortContext context = {0, NULL, NULL, NULL, NULL};
    return CFMachPortCreate(NULL, NULL, &context, NULL);
}
static void fake_enable(CFMachPortRef tap, bool value) {
    (void)tap; enabled = value; if (value) enables++;
}
static bool fake_enabled(CFMachPortRef tap) { (void)tap; return enabled; }
static CFRunLoopSourceRef fake_source(CFAllocatorRef allocator, CFMachPortRef tap, CFIndex order) {
    return failSource ? NULL : CFMachPortCreateRunLoopSource(allocator, tap, order);
}
static void fake_post(CGEventTapLocation location, CGEventRef event) {
    (void)location; (void)event; posts++;
}
static void fake_tap_post(CGEventTapProxy proxy, CGEventRef event) {
    (void)proxy; (void)event; posts++;
}
#define AXIsProcessTrusted fake_trusted
#define CGPreflightPostEventAccess fake_post_access
#define CGEventTapCreate fake_create
#define CGEventTapEnable fake_enable
#define CGEventTapIsEnabled fake_enabled
#define CFMachPortCreateRunLoopSource fake_source
#define CGEventPost fake_post
#define CGEventTapPostEvent fake_tap_post
#include "../Sources/ISS/ISS.c"

static void reset(void) {
    iss_destroy(); inputRequiresRestart = false;
    tapTimeoutCount = 0; tapTimeoutWindow = 0;
    trusted = mayPost = true; enabled = failSource = false;
    creates = enables = posts = 0;
}
int main(void) {
    reset(); trusted = false;
    assert(!iss_init() && creates == 0 && !iss_input_requires_restart());
    trusted = true; mayPost = false;
    assert(!iss_init() && creates == 0);
    mayPost = true;
    assert(iss_init() && creates == 1 && enables == 1 && iss_is_active());
    assert(iss_init() && creates == 1); // No duplicate tap.

    // A user/system disable is final even if AX trust is temporarily stale.
    eventTapCallback(NULL, kCGEventTapDisabledByUserInput, NULL, NULL);
    assert(!globalTap && !globalSource && !iss_is_active() && iss_input_requires_restart());
    assert(enables == 1 && posts == 0);
    for (int i = 0; i < 20; i++) {
        eventTapCallback(NULL, kCGEventTapDisabledByUserInput, NULL, NULL);
        assert(!iss_init());
    }
    assert(enables == 1 && creates == 1 && posts == 0);
    CGEventRef click = CGEventCreateMouseEvent(NULL, kCGEventLeftMouseDown, CGPointZero, kCGMouseButtonLeft);
    CGEventRef key = CGEventCreateKeyboardEvent(NULL, 123, true);
    assert(eventTapCallback(NULL, kCGEventLeftMouseDown, click, NULL) == click);
    assert(eventTapCallback(NULL, kCGEventKeyDown, key, NULL) == key);
    CFRelease(click); CFRelease(key);

    reset(); assert(iss_init()); trusted = false;
    eventTapCallback(NULL, kCGEventTapDisabledByTimeout, NULL, NULL);
    assert(enables == 1 && !iss_is_active() && inputRequiresRestart);
    trusted = true; assert(!iss_init()); // Never re-arm after revocation.

    // Bound timeout recovery instead of retrying an unhealthy filter forever.
    reset(); assert(iss_init());
    for (int i = 0; i < 3; i++) eventTapCallback(NULL, kCGEventTapDisabledByTimeout, NULL, NULL);
    assert(iss_is_active() && enables == 4);
    eventTapCallback(NULL, kCGEventTapDisabledByTimeout, NULL, NULL);
    assert(!iss_is_active() && inputRequiresRestart && enables == 4);
    for (int i = 0; i < 20; i++) eventTapCallback(NULL, kCGEventTapDisabledByTimeout, NULL, NULL);
    assert(enables == 4 && posts == 0);

    reset(); failSource = true;
    assert(!iss_init() && !globalTap && !globalSource && enables == 0);
    reset(); assert(iss_init()); mayPost = false;
    assert(!iss_init() && !globalTap && inputRequiresRestart);
    reset(); assert(iss_init()); enabled = false;
    assert(!iss_init() && inputRequiresRestart && enables == 1);
    reset(); trusted = false;
    assert(!iss_trigger_overlay_from_event(ISSOverlayModeMissionControl, NULL));
    assert(!iss_post_dock_swipe(kCGSGesturePhaseBegan, ISSDirectionRight, 100));
    assert(posts == 0);
    // A revoked permission between a vertical gesture and a synthesized
    // middle click must pass the click through and tear down the filter.
    reset(); assert(iss_init()); iss_set_swipe_override(true);
    for (int phase = 1; phase <= 2; phase++) {
        CGEventRef native = CGEventCreate(NULL);
        CGEventSetType(native, (CGEventType)30);
        CGEventSetIntegerValueField(native, (CGEventField)55, 30);
        CGEventSetIntegerValueField(native, (CGEventField)110, 23);
        CGEventSetIntegerValueField(native, (CGEventField)123, 2);
        CGEventSetIntegerValueField(native, (CGEventField)132, phase);
        CGEventSetIntegerValueField(native, kCGEventSourceUnixProcessID, 0);
        if (phase == 2) CGEventSetDoubleValueField(native, (CGEventField)124, .1);
        CGEventRef prepared = iss_prepare_dock_swipe_event_for_current_os(native);
        CFRelease(native);
        assert(prepared);
        CGEventSetIntegerValueField(prepared, kCGEventSourceUnixProcessID, 0);
        eventTapCallback(NULL, (CGEventType)30, prepared, NULL);
        CFRelease(prepared);
    }
    CGEventRef middle = CGEventCreateMouseEvent(NULL, kCGEventOtherMouseDown, CGPointZero, kCGMouseButtonCenter);
    CGEventSetIntegerValueField(middle, kCGEventSourceUnixProcessID, 4242);
    trusted = false;
    assert(eventTapCallback(NULL, kCGEventOtherMouseDown, middle, NULL) == middle);
    assert(inputRequiresRestart && !globalTap && !verticalClickGuard.blockedClickPID);
    CFRelease(middle);
    iss_destroy();
    puts("PASS: permission grant, revoke, stale trust, timeout storm, failed connection and pass-through; no desktop input");
    return 0;
}
