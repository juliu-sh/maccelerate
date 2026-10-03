#include <ApplicationServices/ApplicationServices.h>
#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
#include "../Sources/ISS/event_serialize.h"

static unsigned posted_events;
static unsigned cleanup_events;
static CGEventRef last_posted;
static void capture(CGEventRef event) {
    if (iss_is_neutral_gesture_terminal(event)) {
        assert(CGEventGetDoubleValueField(event, (CGEventField)124) == 0);
        assert(CGEventGetDoubleValueField(event, (CGEventField)129) == 0);
        assert(CGEventGetDoubleValueField(event, (CGEventField)130) == 0);
        cleanup_events++;
    } else posted_events++;
    if (last_posted) CFRelease(last_posted);
    last_posted = CGEventCreateCopy(event);
    assert(last_posted);
}
static void capture_post(CGEventTapLocation location, CGEventRef event) {
    (void)location; capture(event);
}
static void capture_tap_post(CGEventTapProxy proxy, CGEventRef event) {
    (void)proxy; capture(event);
}
// Exercise the real private callback without installing an event tap or
// delivering any synthetic input to the desktop.
static bool fixture_trusted(void) { return true; }
#define AXIsProcessTrusted fixture_trusted
#define CGPreflightPostEventAccess fixture_trusted
#define CGEventPost capture_post
#define CGEventTapPostEvent capture_tap_post
#include "../Sources/ISS/ISS.c"
#undef CGEventPost
#undef CGEventTapPostEvent

static CGEventRef gesture(int type, int motion, int phase) {
    CGEventRef event = CGEventCreate(NULL);
    assert(event);
    CGEventSetType(event, (CGEventType)type);
    CGEventSetIntegerValueField(event, (CGEventField)55, type);
    CGEventSetIntegerValueField(event, (CGEventField)110, 23);
    CGEventSetIntegerValueField(event, (CGEventField)123, motion);
    CGEventSetIntegerValueField(event, (CGEventField)132, phase);
    CGEventSetIntegerValueField(event, kCGEventSourceUnixProcessID, 0);
    return event;
}

static CGEventRef deliver(CGEventRef event) {
    return eventTapCallback(NULL, CGEventGetType(event), event, NULL);
}

static void assert_unchanged(CGEventRef event) {
    CFDataRef before = CGEventCreateData(NULL, event);
    const unsigned posts_before = posted_events + cleanup_events;
    assert(deliver(event) == event);
    CFDataRef after = CGEventCreateData(NULL, event);
    assert(before && after && CFEqual(before, after));
    assert(posted_events + cleanup_events == posts_before);
    CFRelease(before);
    CFRelease(after);
}

static void begin_tracking(bool already_fired) {
    iss_set_swipe_override(false);
    iss_set_swipe_override(true);
    CGEventRef begin = gesture(30, 1, 1);
    assert(deliver(begin) == NULL);
    assert(swipeTracking);
    // Model a completed switch without asking WindowServer to switch Spaces.
    swipeFired = already_fired;
    CFRelease(begin);
}

int main(int argc, char **argv) {
    assert(setenv("ISS_FORCE_EVENT_AUGMENTATION", argc > 1 ? argv[1] : "0", 1) == 0);
    const CGEventType interruptions[] = {
        kCGEventTapDisabledByTimeout
    };
    unsigned scenarios = 0;
    for (unsigned i = 0; i < sizeof(interruptions) / sizeof(interruptions[0]); i++) {
        iss_set_swipe_override(false);
        iss_set_swipe_override(true);
        eventTapCallback(NULL, interruptions[i], NULL, NULL);
        CGEventRef idle_tail = gesture(30, 1, 2);
        assert_unchanged(idle_tail);
        CFRelease(idle_tail);
        scenarios++;
        for (int fired = 0; fired <= 1; fired++) {
            for (int terminal = 4; terminal <= 8; terminal += 4) {
                begin_tracking(fired);
                eventTapCallback(NULL, interruptions[i], NULL, NULL);
                eventTapCallback(NULL, interruptions[i], NULL, NULL);
                assert(!swipeTracking && !swipeFired);
                CGEventRef general = gesture(29, 0, 2);
                assert_unchanged(general);
                CGEventRef tail = gesture(30, 1, 2);
                CGEventSetDoubleValueField(tail, (CGEventField)124, 0.25);
                assert(deliver(tail) == NULL);
                // Synthetic gestures from other applications are not drained.
                CGEventSetIntegerValueField(tail, kCGEventSourceUnixProcessID, 12345);
                assert_unchanged(tail);
                CGEventSetIntegerValueField(tail, kCGEventSourceUnixProcessID, 0);
                assert(deliver(tail) == NULL);
                CGEventRef end = gesture(30, 1, terminal);
                CGEventSetDoubleValueField(end, (CGEventField)129, 100);
                assert(deliver(end) == NULL);
                assert_unchanged(general);
                // End/Cancel releases the drain state.
                assert_unchanged(tail);
                assert(posted_events == 0);
                CFRelease(general); CFRelease(tail); CFRelease(end);
                scenarios++;
            }
            // A new Begin also supersedes an interrupted, unterminated swipe.
            begin_tracking(fired);
            eventTapCallback(NULL, interruptions[i], NULL, NULL);
            CGEventRef begin = gesture(30, 1, 1);
            assert(deliver(begin) == NULL);
            assert(swipeTracking && !swipeFired);
            CGEventRef end = gesture(30, 1, 4);
            assert(deliver(end) == NULL);
            assert(!swipeTracking && !swipeFired);
            CFRelease(begin); CFRelease(end);
            scenarios++;

            // Disabling or destroying clears recovery as well as active state.
            for (int destroy = 0; destroy <= 1; destroy++) {
                begin_tracking(fired);
                eventTapCallback(NULL, interruptions[i], NULL, NULL);
                if (destroy) iss_destroy();
                else iss_set_swipe_override(false);
                iss_set_swipe_override(true);
                CGEventRef tail = gesture(30, 1, 2);
                assert_unchanged(tail);
                assert(!swipeTracking && !swipeFired);
                CFRelease(tail);
                scenarios++;
            }
        }
    }

    // Recovery must neither intercept vertical sequences nor reinterpret Cmd-W.
    begin_tracking(true);
    eventTapCallback(NULL, kCGEventTapDisabledByTimeout, NULL, NULL);
    iss_set_overlay_hotkey(ISSOverlayModeMissionControl, 126, kCGEventFlagMaskControl, true);
    iss_set_overlay_hotkey(ISSOverlayModeAppExpose, 125, kCGEventFlagMaskControl, true);
    const int phases[] = {128, 1, 2, 4, 8};
    for (int direction = -1; direction <= 1; direction += 2) {
        for (unsigned p = 0; p < 5; p++) {
            CGEventRef vertical = gesture(30, 2, phases[p]);
            CGEventSetDoubleValueField(vertical, (CGEventField)124, direction * 0.1);
            CGEventSetDoubleValueField(vertical, (CGEventField)130, direction * 0.25);
            CGEventRef prepared = iss_prepare_dock_swipe_event_for_current_os(vertical);
            CFRelease(vertical);
            assert(prepared);
            CGEventSetIntegerValueField(prepared, kCGEventSourceUnixProcessID, 0);
            const unsigned before = posted_events;
            CGEventRef result = deliver(prepared);
            const bool replaced = iss_requires_event_augmentation() &&
                (phases[p] == 2 || phases[p] == 4);
            assert(replaced ? result == NULL : result == prepared);
            assert(posted_events == before + (replaced ? 1u : 0u));
            CGEventRef observed = replaced ? last_posted : result;
            assert(CGEventGetType(observed) == (CGEventType)30);
            assert(CGEventGetIntegerValueField(observed, (CGEventField)123) == 2);
            assert(CGEventGetIntegerValueField(observed, (CGEventField)132) == phases[p]);
            assert(CGEventGetDoubleValueField(observed, (CGEventField)124) * direction > 0);
            if (phases[p] == 4) {
                const double velocity = iss_requires_event_augmentation() ? 100.0 : 1000.0;
                assert(CGEventGetDoubleValueField(observed, (CGEventField)130) == direction * velocity);
            }
            CFRelease(prepared);
            scenarios++;
        }
    }
    CGEventRef key_during_recovery = CGEventCreateKeyboardEvent(NULL, 13, true);
    CGEventSetFlags(key_during_recovery, kCGEventFlagMaskCommand);
    CGEventSetIntegerValueField(key_during_recovery, kCGEventSourceUnixProcessID, 0);
    assert_unchanged(key_during_recovery);
    CFRelease(key_during_recovery);
    scenarios++;
    for (int enabled = 0; enabled <= 1; enabled++) {
        iss_set_swipe_override(enabled);
        for (int source = 0; source <= 1; source++) {
            for (int down = 0; down <= 1; down++) {
                CGEventRef key = CGEventCreateKeyboardEvent(NULL, 13, down);
                CGEventSetFlags(key, kCGEventFlagMaskCommand);
                CGEventSetIntegerValueField(key, kCGEventSourceUnixProcessID, source ? 12345 : 0);
                assert_unchanged(key);
                CFRelease(key);
                scenarios++;
            }
        }
    }
    iss_set_swipe_override(false);
    for (int type = 29; type <= 30; type++) {
        for (unsigned p = 0; p < 5; p++) {
            CGEventRef event = gesture(type, 1, phases[p]);
            assert_unchanged(event);
            CFRelease(event);
            scenarios++;
        }
    }
    assert(posted_events == (iss_requires_event_augmentation() ? 4u : 0u));
    if (last_posted) CFRelease(last_posted);
    printf("PASS: %u gesture recovery scenarios (augmentation=%s), no desktop input delivered\n",
           scenarios, argc > 1 ? argv[1] : "0");
    return 0;
}
