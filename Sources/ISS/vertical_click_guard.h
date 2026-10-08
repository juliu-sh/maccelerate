#include <math.h>
#include <limits.h>

// Correlate synthesized middle clicks with an accelerated physical overview
// swipe. Main-runloop state only; never change the native vertical gesture.
enum { kVerticalClickSourceCount = 8 };
static struct {
    bool tracking, moved;
    double activityDeadline, releaseDeadline;
    struct { pid_t pid; unsigned pending; } blockedClicks[kVerticalClickSourceCount];
    CGEventTimestamp endedTimestamp;
} verticalClickGuard;
static const double kVerticalClickIdleTimeout = 1.0;
static const double kVerticalClickReleaseWindow = 0.15;

static double vertical_click_now(void) {
    struct timespec time;
    clock_gettime(CLOCK_MONOTONIC, &time);
    return (double)time.tv_sec + (double)time.tv_nsec / 1e9;
}
static void vertical_click_reset(void) {
    memset(&verticalClickGuard, 0, sizeof(verticalClickGuard));
}
static void vertical_click_expire(double now) {
    if (verticalClickGuard.tracking && now >= verticalClickGuard.activityDeadline) {
        verticalClickGuard.tracking = false;
        verticalClickGuard.moved = false;
    }
}
static void vertical_click_observe(CGEventRef event, bool accelerated) {
    const double now = vertical_click_now();
    vertical_click_expire(now);
    const int64_t phase = CGEventGetIntegerValueField(event, kCGEventGesturePhase);
    if (phase == kCGSGesturePhaseBegan) {
        verticalClickGuard.tracking = true;
        verticalClickGuard.moved = false;
        verticalClickGuard.releaseDeadline = 0;
        verticalClickGuard.activityDeadline = now + kVerticalClickIdleTimeout;
    } else if (verticalClickGuard.tracking &&
        (phase == kCGSGesturePhaseChanged || phase == kCGSGesturePhaseEnded)) {
        // A Begin/End without movement remains an intentional tap.
        const double progress = CGEventGetDoubleValueField(event, kCGEventGestureSwipeProgress);
        const double position = CGEventGetDoubleValueField(event, kCGEventGestureSwipePositionY);
        const double velocity = CGEventGetDoubleValueField(event, kCGEventGestureSwipeVelocityY);
        if (accelerated && ((isfinite(progress) && progress != 0) || (isfinite(position) && position != 0)
            || (phase == kCGSGesturePhaseEnded && isfinite(velocity) && velocity != 0))) {
            verticalClickGuard.moved = true;
        }
        verticalClickGuard.activityDeadline = now + kVerticalClickIdleTimeout;
    }
    if (phase == kCGSGesturePhaseEnded || phase == kCGSGesturePhaseCancelled) {
        if (verticalClickGuard.tracking && verticalClickGuard.moved) {
            verticalClickGuard.releaseDeadline = now + kVerticalClickReleaseWindow;
            verticalClickGuard.endedTimestamp = CGEventGetTimestamp(event);
        }
        verticalClickGuard.tracking = false;
        verticalClickGuard.moved = false;
    }
}
static void vertical_click_companion(CGEventRef event) {
    // A new physical contact sequence is a new intentional gesture. Do not
    // carry the previous swipe's release window into a genuine tap.
    if (!verticalClickGuard.tracking &&
        CGEventGetIntegerValueField(event, kCGEventGesturePhase) == kCGSGesturePhaseBegan) {
        const CGEventTimestamp timestamp = CGEventGetTimestamp(event);
        if (!verticalClickGuard.endedTimestamp || timestamp > verticalClickGuard.endedTimestamp)
            verticalClickGuard.releaseDeadline = 0;
    }
}
static bool vertical_click_should_suppress(CGEventType type, CGEventRef event) {
    if (type != kCGEventOtherMouseDown && type != kCGEventOtherMouseUp
        && type != kCGEventOtherMouseDragged) return false;
    if (CGEventGetIntegerValueField(event, kCGMouseEventButtonNumber) != kCGMouseButtonCenter) return false;
    const pid_t pid = (pid_t)CGEventGetIntegerValueField(event, kCGEventSourceUnixProcessID);
    if (pid <= 0) return false; // Physical mice keep their normal middle button.
    const double now = vertical_click_now();
    vertical_click_expire(now);
    size_t slot = kVerticalClickSourceCount, freeSlot = kVerticalClickSourceCount;
    for (size_t i = 0; i < kVerticalClickSourceCount; i++) {
        if (verticalClickGuard.blockedClicks[i].pid == pid) slot = i;
        else if (!verticalClickGuard.blockedClicks[i].pid && freeSlot == kVerticalClickSourceCount) freeSlot = i;
    }
    if (type == kCGEventOtherMouseDown) {
        const bool swipe = verticalClickGuard.tracking && verticalClickGuard.moved;
        if (swipe || now < verticalClickGuard.releaseDeadline) {
            if (slot == kVerticalClickSourceCount) slot = freeSlot;
            // Do not consume a Down unless its matching Up can be tracked.
            if (slot == kVerticalClickSourceCount || verticalClickGuard.blockedClicks[slot].pending == UINT_MAX) return false;
            verticalClickGuard.blockedClicks[slot].pid = pid;
            verticalClickGuard.blockedClicks[slot].pending++;
            return true;
        }
        // A new valid Down starts a new click, including after a lost Up.
        if (slot < kVerticalClickSourceCount) memset(&verticalClickGuard.blockedClicks[slot], 0,
                            sizeof(verticalClickGuard.blockedClicks[slot]));
    } else if (slot < kVerticalClickSourceCount) {
        // Keep the suppressed-Up marker beyond the swipe timeout. It does
        // not block later complete clicks: their new Down clears it above.
        if (type == kCGEventOtherMouseUp && --verticalClickGuard.blockedClicks[slot].pending == 0)
            memset(&verticalClickGuard.blockedClicks[slot], 0, sizeof(verticalClickGuard.blockedClicks[slot]));
        return true;
    }
    return false;
}
