#include <ApplicationServices/ApplicationServices.h>
#include <assert.h>
#include <stdio.h>

// Mock TCC and CG tap operations: this executable never observes or posts
// real desktop input. Its Mach port is an ordinary, private CF test resource.
static bool enabled = false;
static unsigned posts;
static bool fake_trusted(void) { return true; }
static bool fake_post_access(void) { return true; }
static CFMachPortRef fake_create(CGEventTapLocation tap, CGEventTapPlacement place,
    CGEventTapOptions options, CGEventMask mask, CGEventTapCallBack callback, void *info) {
    (void)tap; (void)place; (void)options; (void)mask; (void)callback; (void)info;
    CFMachPortContext context = {0, NULL, NULL, NULL, NULL};
    return CFMachPortCreate(NULL, NULL, &context, NULL);
}
static void fake_enable(CFMachPortRef tap, bool value) { (void)tap; enabled = value; }
static bool fake_enabled(CFMachPortRef tap) { (void)tap; return enabled; }
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
#define CGEventPost fake_post
#define CGEventTapPostEvent fake_tap_post
#include "../Sources/ISS/ISS.c"

enum { kLeft = 123, kRight = 124, kUp = 126, kOne = 18 };
static const CGEventFlags kArrowFlags =
    kCGEventFlagMaskSecondaryFn | kCGEventFlagMaskNumericPad;

static int fired[ISSSystemShortcutCount];
static unsigned firedTotal;
static void record(ISSSystemShortcut shortcut) { fired[shortcut]++; firedTotal++; }

static CGEventRef key(CGKeyCode code, bool down, CGEventFlags flags,
                      pid_t source, bool repeat) {
    CGEventRef event = CGEventCreateKeyboardEvent(NULL, code, down);
    assert(event);
    CGEventSetFlags(event, flags);
    CGEventSetIntegerValueField(event, kCGEventSourceUnixProcessID, source);
    CGEventSetIntegerValueField(event, kCGKeyboardEventAutorepeat, repeat ? 1 : 0);
    return event;
}

// Returns true when the tap consumed the event.
static bool consumed(CGKeyCode code, bool down, CGEventFlags flags,
                     pid_t source, bool repeat) {
    CGEventRef event = key(code, down, flags, source, repeat);
    CGEventRef result = eventTapCallback(NULL, down ? kCGEventKeyDown : kCGEventKeyUp,
                                         event, NULL);
    assert(result == NULL || result == event);
    CFRelease(event);
    return result == NULL;
}

// Returns true when the tap accelerated the overlay itself or rewrote the key
// in place to macOS's native overlay key. code must differ from native.
static bool overlay_handled(CGKeyCode code, bool down, CGEventFlags flags,
                            CGKeyCode native) {
    CGEventRef event = key(code, down, flags, 0, false);
    CGEventRef result = eventTapCallback(NULL, down ? kCGEventKeyDown : kCGEventKeyUp,
                                         event, NULL);
    assert(result == NULL || result == event);
    const bool handled = result == NULL ||
        CGEventGetIntegerValueField(event, kCGKeyboardEventKeycode) == native;
    CFRelease(event);
    return handled;
}

static bool takeShiftClick;
static unsigned shiftClicks;
static CGPoint lastShiftClick;
static bool shift_click(CGPoint location) {
    shiftClicks++;
    lastShiftClick = location;
    return takeShiftClick;
}

// Returns true when the tap consumed the mouse event.
static bool click_consumed(bool down, CGEventFlags flags, pid_t source) {
    CGEventRef event = CGEventCreateMouseEvent(
        NULL, down ? kCGEventLeftMouseDown : kCGEventLeftMouseUp,
        CGPointMake(640, 1060), kCGMouseButtonLeft);
    assert(event);
    CGEventSetFlags(event, flags);
    CGEventSetIntegerValueField(event, kCGEventSourceUnixProcessID, source);
    CGEventRef result = eventTapCallback(
        NULL, down ? kCGEventLeftMouseDown : kCGEventLeftMouseUp, event, NULL);
    assert(result == NULL || result == event);
    CFRelease(event);
    return result == NULL;
}

static void reset(void) {
    iss_destroy();
    inputRequiresRestart = false;
    for (int i = 0; i < ISSSystemShortcutCount; i++) {
        iss_set_system_shortcut((ISSSystemShortcut)i, 0, 0, false);
        fired[i] = 0;
    }
    iss_set_overlay_hotkey(ISSOverlayModeMissionControl, 0, 0, false);
    iss_set_overlay_hotkey(ISSOverlayModeAppExpose, 0, 0, false);
    iss_set_system_overlay_hotkey(ISSOverlayModeMissionControl, 0, 0, false);
    iss_set_system_overlay_hotkey(ISSOverlayModeAppExpose, 0, 0, false);
    firedTotal = posts = 0;
    iss_set_system_shortcut_callback(record);
    assert(iss_init());
}

int main(void) {
    const CGEventFlags control = kCGEventFlagMaskControl;
    const CGEventFlags controlShift = control | kCGEventFlagMaskShift;

    // Disabled by default: the key combination keeps its native owner.
    reset();
    assert(!consumed(kRight, true, control | kArrowFlags, 0, false));
    assert(!consumed(kRight, false, control | kArrowFlags, 0, false));
    assert(firedTotal == 0);

    // A physical ⌃→ press, its repeats and its release are consumed once.
    reset();
    iss_set_system_shortcut(ISSSystemShortcutLeft, kLeft, control, true);
    iss_set_system_shortcut(ISSSystemShortcutRight, kRight, control, true);
    assert(consumed(kRight, true, control | kArrowFlags, 0, false));
    assert(fired[ISSSystemShortcutRight] == 1 && firedTotal == 1);
    for (int i = 0; i < 5; i++) assert(consumed(kRight, true, control | kArrowFlags, 0, true));
    assert(firedTotal == 1);
    // Releasing Control first still consumes the arrow key-up.
    assert(consumed(kRight, false, kArrowFlags, 0, false));
    assert(!consumed(kRight, false, kArrowFlags, 0, false));
    assert(consumed(kLeft, true, control | kArrowFlags, 0, false));
    assert(consumed(kLeft, false, control | kArrowFlags, 0, false));
    assert(fired[ISSSystemShortcutLeft] == 1 && firedTotal == 2);

    // Other modifiers, keys, synthetic events and stray repeats pass through.
    assert(!consumed(kRight, true, controlShift | kArrowFlags, 0, false));
    assert(!consumed(kRight, true, kCGEventFlagMaskCommand | control | kArrowFlags, 0, false));
    assert(!consumed(kRight, true, kArrowFlags, 0, false));
    assert(!consumed(kUp, true, control | kArrowFlags, 0, false));
    assert(!consumed(kRight, true, control | kArrowFlags, 4242, false));
    assert(!consumed(kRight, true, control | kArrowFlags, 0, true));
    assert(firedTotal == 2 && posts == 0);

    // Desktop shortcuts map to their own slot.
    iss_set_system_shortcut(ISSSystemShortcutDesktop1, kOne, control, true);
    assert(consumed(kOne, true, control, 0, false));
    assert(consumed(kOne, false, control, 0, false));
    assert(fired[ISSSystemShortcutDesktop1] == 1);

    // Disabling a binding or clearing the callback restores pass-through.
    iss_set_system_shortcut(ISSSystemShortcutRight, kRight, control, false);
    assert(!consumed(kRight, true, control | kArrowFlags, 0, false));
    iss_set_system_shortcut_callback(NULL);
    assert(!consumed(kLeft, true, control | kArrowFlags, 0, false));
    iss_set_system_shortcut_callback(record);

    // A timeout or teardown never leaves a stale consumed key behind.
    reset();
    iss_set_system_shortcut(ISSSystemShortcutRight, kRight, control, true);
    assert(consumed(kRight, true, control | kArrowFlags, 0, false));
    eventTapCallback(NULL, kCGEventTapDisabledByTimeout, NULL, NULL);
    assert(!consumed(kRight, false, control | kArrowFlags, 0, false));
    assert(consumed(kRight, true, control | kArrowFlags, 0, false));
    iss_destroy();
    inputRequiresRestart = false;
    assert(iss_init());
    assert(!consumed(kRight, false, control | kArrowFlags, 0, false));

    // Out-of-range slots are ignored.
    iss_set_system_shortcut(ISSSystemShortcutCount, kUp, control, true);
    iss_set_system_shortcut((ISSSystemShortcut)-1, kUp, control, true);
    assert(!consumed(kUp, true, control | kArrowFlags, 0, false));

    // macOS's Mission Control shortcut works alongside an additional one; both
    // are handled, and the release follows whichever key started it.
    reset();
    const CGKeyCode kM = 46;
    const CGEventFlags hyper = control | kCGEventFlagMaskAlternate | kCGEventFlagMaskCommand;
    iss_set_overlay_hotkey(ISSOverlayModeMissionControl, kM, hyper, true);
    iss_set_system_overlay_hotkey(ISSOverlayModeMissionControl, kM, control, true);
    assert(overlay_handled(kM, true, hyper, kUp));
    assert(overlay_handled(kM, false, hyper, kUp));
    assert(overlay_handled(kM, true, control, kUp));
    assert(overlay_handled(kM, false, control, kUp));
    assert(!overlay_handled(kM, true, controlShift, kUp));
    assert(firedTotal == 0);
    // Disabling the macOS binding leaves the additional one working.
    iss_set_system_overlay_hotkey(ISSOverlayModeMissionControl, kM, control, false);
    assert(!overlay_handled(kM, true, control, kUp));
    assert(overlay_handled(kM, true, hyper, kUp));
    assert(overlay_handled(kM, false, hyper, kUp));
    // An App Exposé-only macOS binding still enables the tap path.
    iss_set_overlay_hotkey(ISSOverlayModeMissionControl, 0, 0, false);
    iss_set_system_overlay_hotkey(ISSOverlayModeAppExpose, kM, control, true);
    assert(overlay_handled(kM, true, control, 125));
    assert(overlay_handled(kM, false, control, 125));
    iss_set_system_overlay_hotkey((ISSOverlayMode)7, kM, hyper, true);
    assert(!overlay_handled(kM, true, hyper, kUp));

    // Shift-clicks reach the app; only a click it takes is consumed, with its
    // release. Other modifiers, synthetic clicks and plain clicks pass.
    reset();
    const CGEventFlags shift = kCGEventFlagMaskShift;
    assert(!click_consumed(true, shift, 0) && !click_consumed(false, shift, 0));
    iss_set_shift_click_callback(shift_click);
    takeShiftClick = false;
    assert(!click_consumed(true, shift, 0) && !click_consumed(false, shift, 0));
    assert(shiftClicks == 1);
    takeShiftClick = true;
    assert(click_consumed(true, shift, 0));
    assert(lastShiftClick.x == 640 && lastShiftClick.y == 1060);
    // Releasing Shift before the button still consumes the release, once.
    assert(click_consumed(false, 0, 0));
    assert(!click_consumed(false, 0, 0));
    assert(!click_consumed(true, 0, 0) && !click_consumed(false, 0, 0));
    assert(!click_consumed(true, shift | kCGEventFlagMaskCommand, 0));
    assert(!click_consumed(true, shift | control, 0));
    assert(!click_consumed(true, shift, 4242));
    assert(shiftClicks == 2);
    // A timeout, teardown or cleared callback never strands a release.
    assert(click_consumed(true, shift, 0));
    eventTapCallback(NULL, kCGEventTapDisabledByTimeout, NULL, NULL);
    assert(!click_consumed(false, shift, 0));
    assert(click_consumed(true, shift, 0));
    iss_set_shift_click_callback(NULL);
    assert(!click_consumed(false, shift, 0));
    assert(!click_consumed(true, shift, 0));
    iss_set_shift_click_callback(shift_click);
    assert(click_consumed(true, shift, 0));
    iss_destroy();
    inputRequiresRestart = false;
    assert(iss_init());
    assert(!click_consumed(false, shift, 0));
    iss_set_shift_click_callback(NULL);
    assert(posts == 0);

    iss_destroy();
    puts("PASS: macOS Space and overlay shortcuts consumed once per physical press; Shift-clicks only when taken; other input passes through; no desktop input");
    return 0;
}
