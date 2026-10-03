#include <errno.h>
#include <string.h>
#include <stddef.h>
int trackpad_fixture_sysctlbyname(const char *name, void *out, size_t *size,
                                 void *value, size_t value_size) {
    (void)value; (void)value_size;
    const char *text = !strcmp(name, "kern.osproductversion") ? "27.0"
        : !strcmp(name, "kern.osversion") ? "26A428" : NULL;
    if (!text) { errno = ENOENT; return -1; }
    size_t length = strlen(text) + 1;
    if (!out) { *size = length; return 0; }
    if (*size < length) { errno = ENOMEM; return -1; }
    memcpy(out, text, length); *size = length; return 0;
}
#define main original_async_main
#include "test_async_switch.c"
#undef main

static CGEventRef physical_event(int type, int phase, double progress) {
    CGEventRef event = CGEventCreate(NULL);
    assert(event);
    CGEventSetTimestamp(event, (CGEventTimestamp)((clock_now + 1) * 1e9));
    CGEventSetIntegerValueField(event, (CGEventField)55, type);
    CGEventSetIntegerValueField(event, (CGEventField)110, 23);
    CGEventSetIntegerValueField(event, (CGEventField)123, type == 30 ? 1 : 0);
    CGEventSetIntegerValueField(event, (CGEventField)132, phase);
    CGEventSetDoubleValueField(event, (CGEventField)124, progress);
    CGEventSetIntegerValueField(event, kCGEventSourceUnixProcessID, 0);
    return event;
}
static void phase(int value, double progress) {
    CGEventRef event = physical_event(30, value, progress);
    assert(eventTapCallback(NULL, (CGEventType)30, event, NULL) == NULL);
    CFRelease(event);
}
static void next_valid(void) {
    missing = false; reordered = false; overview = false; duplicate_space = false;
    fail_create_after = -1; cursor_display = 0; count = 5;
    actual[0] = 1; auto_confirm = true;
    unsigned before = post_count;
    deliver_swipe(); drain(); phase(4, 0.1);
    assert(actual[0] == 2 && post_count == before + 3);
    assert(!swipeTracking && !interruptedHorizontalSwipe && !trackpadRecovery.timer);
}
static void fire_watchdog(void) {
    assert(trackpadRecovery.timer);
    trackpad_timer_fired(trackpadRecovery.timer, (void *)trackpadTimerGeneration);
}
static unsigned recovery_matrix(void) {
    unsigned cases = 0;
    // A valid edge is a no-op, not a missing-display failure.
    reset(); actual[0] = count - 1; deliver_swipe();
    assert(trackpadRecovery.requestState == ISSTrackpadRequestBoundary && post_count == 0);
    phase(4, 0.1); next_valid(); cases++;

    // Ambiguous/no Spaces and a cursor display not present in the topology.
    for (int failure = 0; failure < 3; failure++) {
        reset();
        if (failure == 0) count = 0;
        else if (failure == 1) cursor_display = 5;
        else duplicate_space = true;
        deliver_swipe();
        assert(trackpadRecovery.requestState == ISSTrackpadRequestFailedBeforePost);
        assert(post_count == 0 && interruptedHorizontalSwipe);
        next_valid(); cases++;
    }
    reset(); asyncDelivering = true; deliver_swipe(); asyncDelivering = false;
    assert(trackpadRecovery.requestID == 0 &&
           trackpadRecovery.requestState == ISSTrackpadRequestFailedBeforePost);
    next_valid(); cases++;

    // Each post-allocation failure: before Begin, Changed, or Ended.
    for (int successful_phases = 0; successful_phases < 3; successful_phases++) {
        reset(); deliver_swipe();
        if (successful_phases == 0) fail_create_after = 1; // snapshot then Begin
        else {
            for (int i = 0; i < successful_phases; i++) fire();
            fail_create_after = 0;
        }
        fire();
        assert(post_count == (unsigned)successful_phases);
        assert(trackpadRecovery.requestState == (successful_phases
            ? ISSTrackpadRequestFailedAfterPost : ISSTrackpadRequestFailedBeforePost));
        assert(interruptedHorizontalSwipe && !swipeTracking);
        fail_create_after = -1; phase(4, 0.2);
        assert(post_count == (unsigned)successful_phases);
        next_valid(); cases++;
    }
    // Physical Ended can precede completion of the synthetic request.
    reset(); deliver_swipe(); phase(4, 0.1); drain();
    assert(trackpadRecovery.requestState == ISSTrackpadRequestFailedAfterPost);
    assert(post_count == 3 && !swipeTracking && !interruptedHorizontalSwipe);
    next_valid(); cases++;

    reset(); deliver_swipe(); fire(); cursor_display = 1; drain();
    assert(trackpadRecovery.requestState == ISSTrackpadRequestFailedAfterPost);
    assert(post_count == 3 && locations[2].x == 100);
    next_valid(); cases++;

    reset(); deliver_swipe();
    assert(iss_request_switch(ISSDirectionLeft, ISSSwitchSourceExplicit, NULL));
    assert(trackpadRecovery.requestState == ISSTrackpadRequestSuperseded);
    auto_confirm = true; drain(); next_valid(); cases++;

    // Old completion must not mutate a newer gesture, including inline Superseded.
    reset(); auto_confirm = true; deliver_swipe();
    uint64_t old_id = trackpadRecovery.requestID;
    deliver_swipe();
    uint64_t new_id = trackpadRecovery.requestID;
    assert(new_id && new_id != old_id && swipeTracking);
    trackpad_switch_completed(old_id, ISSSwitchResultPostFailed);
    assert(trackpadRecovery.requestID == new_id && swipeTracking);
    drain(); assert(actual[0] == 3 && post_count == 6);
    phase(4, 0.1); next_valid(); cases++;

    // A held gesture with real Changed phases stays alive beyond total timeout.
    reset(); iss_set_swipe_override(true); phase(1, 0);
    for (int i = 0; i < 8; i++) {
        clock_now += 0.75; phase(2, 0); fire_watchdog();
        assert(swipeTracking && post_count == 0 && cleanup_posts == 0);
    }
    clock_now += kTrackpadIdleTimeout + 0.01; fire_watchdog();
    assert(!swipeTracking && cleanup_posts == 1 && post_count == 0);
    next_valid(); cases++;

    // Cancel an unposted request on expiry; never replay it later.
    reset(); deliver_swipe();
    clock_now += kTrackpadIdleTimeout + 0.01; fire_watchdog();
    assert(!async_busy() && !asyncTimer && post_count == 0 && cleanup_posts == 1);
    next_valid(); cases++;
    // If Begin was posted, finish only that sequence; do not submit a retry.
    reset(); auto_confirm = true; deliver_swipe(); fire();
    uint64_t attempts = asyncNextID;
    clock_now += kTrackpadIdleTimeout + 0.01; fire_watchdog(); drain();
    assert(post_count == 3 && cleanup_posts == 1 && asyncNextID == attempts);
    next_valid(); cases++;

    // An old timer cannot expire the next gesture, even if its address is retained.
    reset(); iss_set_swipe_override(true); phase(1, 0);
    CFRunLoopTimerRef old_timer = trackpadRecovery.timer; CFRetain(old_timer);
    uintptr_t old_token = trackpadTimerGeneration;
    clock_now += 0.9; phase(1, 0);
    uint64_t generation = trackpadRecovery.generation;
    clock_now += 0.2;
    trackpad_timer_fired(old_timer, (void *)old_token);
    assert(swipeTracking && trackpadRecovery.generation == generation && cleanup_posts == 0);
    CFRelease(old_timer); phase(8, 0); next_valid(); cases++;

    // Wall-clock changes do not change the monotonic idle duration.
    reset(); iss_set_swipe_override(true); phase(1, 0);
    wall_clock_offset = 100000; clock_now += 0.99; fire_watchdog();
    assert(swipeTracking && cleanup_posts == 0);
    wall_clock_offset = -100000; clock_now += 0.02; fire_watchdog();
    assert(!swipeTracking && cleanup_posts == 1);
    wall_clock_offset = 0; next_valid(); cases++;

    // Old physical terminals and our own PID-0 cleanup cannot end a new gesture.
    reset(); iss_set_swipe_override(true); phase(1, 0);
    CGEventRef old_end = physical_event(30, 4, 0.2);
    CGEventSetTimestamp(old_end, 1);
    CGEventRef owned = iss_copy_neutral_gesture_terminal(old_end, 8);
    assert(owned); CGEventSetIntegerValueField(owned, kCGEventSourceUnixProcessID, 0);
    phase(1, 0);
    assert(eventTapCallback(NULL, (CGEventType)30, old_end, NULL) == NULL);
    assert(eventTapCallback(NULL, (CGEventType)30, owned, NULL) == owned);
    assert(swipeTracking && cleanup_posts == 0 && post_count == 0);
    CFRelease(old_end); CFRelease(owned); phase(8, 0); next_valid(); cases++;

    // Failed gestures still consume their companion motion until closure.
    reset(); missing = true; deliver_swipe();
    CGEventRef remaining = physical_event(29, 2, 0.4);
    assert(eventTapCallback(NULL, (CGEventType)29, remaining, NULL) == NULL);
    CFRelease(remaining); phase(4, 0); next_valid(); cases++;

    // A new unrelated companion gesture must not inherit a missing old tail.
    reset(); iss_set_swipe_override(true); phase(1, 0); phase(8, 0);
    CGEventRef unrelated = physical_event(29, 1, 0);
    assert(eventTapCallback(NULL, (CGEventType)29, unrelated, NULL) == unrelated);
    CGEventSetIntegerValueField(unrelated, (CGEventField)132, 4);
    assert(eventTapCallback(NULL, (CGEventType)29, unrelated, NULL) == unrelated);
    CFRelease(unrelated); next_valid(); cases++;

    // Ended fallback rejected synchronously must still clear the drain flag.
    reset(); iss_set_swipe_override(true); phase(1, 0); missing = true;
    CGEventRef end = physical_event(30, 4, 0);
    CGEventSetDoubleValueField(end, (CGEventField)129, 1);
    assert(eventTapCallback(NULL, (CGEventType)30, end, NULL) == NULL);
    assert(!swipeTracking && !interruptedHorizontalSwipe && !trackpadRecovery.timer);
    CFRelease(end); next_valid(); cases++;

    // Disable/teardown/revocation invalidate retained timer callbacks.
    for (int action = 0; action < 3; action++) {
        reset(); iss_set_swipe_override(true); phase(1, 0);
        CFRunLoopTimerRef timer = trackpadRecovery.timer; CFRetain(timer);
        uintptr_t token = trackpadTimerGeneration;
        if (action == 0) iss_set_swipe_override(false);
        else if (action == 1) iss_destroy();
        else fixture_access = false;
        clock_now += 3;
        trackpad_timer_fired(timer, (void *)token);
        assert(!swipeTracking && post_count == 0 && cleanup_posts == 0);
        if (action == 2) {
            assert(inputRequiresRestart);
            fixture_access = true;
            trackpad_timer_fired(timer, (void *)token);
            assert(inputRequiresRestart && cleanup_posts == 0);
        }
        CFRelease(timer);
        reset(); next_valid(); cases++;
    }
    iss_destroy();
    return cases;
}

int main(int argc, char **argv) {
    setenv("ISS_FORCE_EVENT_AUGMENTATION", "1", 1);
    if (argc > 1 && !strcmp(argv[1], "matrix")) {
        printf("PASS: %u request/recovery/lifecycle scenarios; no desktop input\n", recovery_matrix());
        return 0;
    }
    if (argc > 1 && !strcmp(argv[1], "stale")) {
        reset(); auto_confirm = true;
        deliver_swipe(); drain();
        clock_now += 3.0;
        CGEventRef companion = CGEventCreate(NULL);
        CGEventSetIntegerValueField(companion, (CGEventField)55, 29);
        CGEventSetIntegerValueField(companion, (CGEventField)132, 2);
        CGEventSetIntegerValueField(companion, kCGEventSourceUnixProcessID, 0);
        if (eventTapCallback(NULL, (CGEventType)29, companion, NULL) != companion || swipeTracking) {
            fprintf(stderr, "FAIL: lost terminal keeps companion input suppressed past idle deadline\n");
            return 1;
        }
        assert(post_count == 3 && cleanup_posts == 1);
        CFRelease(companion); iss_destroy();
        puts("PASS: stale gesture releases companion input without a second switch");
        return 0;
    }
    reset(); missing = true;
    deliver_swipe();
    if (swipeTracking || !interruptedHorizontalSwipe || post_count != 0) {
        fprintf(stderr, "FAIL: synchronous target rejection leaves physical gesture tracked as successful\n");
        return 1;
    }
    uint64_t attempts = asyncNextID;
    CGEventRef changed = CGEventCreate(NULL);
    CGEventSetIntegerValueField(changed, (CGEventField)55, 30);
    CGEventSetIntegerValueField(changed, (CGEventField)110, 23);
    CGEventSetIntegerValueField(changed, (CGEventField)123, 1);
    CGEventSetIntegerValueField(changed, (CGEventField)132, 2);
    CGEventSetDoubleValueField(changed, (CGEventField)124, 0.3);
    CGEventSetIntegerValueField(changed, kCGEventSourceUnixProcessID, 0);
    for (unsigned i = 0; i < 20; i++)
        assert(eventTapCallback(NULL, (CGEventType)30, changed, NULL) == NULL);
    assert(asyncNextID == attempts && post_count == 0);
    CFRelease(changed);
    missing = false; auto_confirm = true;
    deliver_swipe(); drain();
    assert(post_count == 3 && actual[0] == 2);
    iss_destroy();
    puts("PASS: rejected request drains once; next valid gesture works without retrying the failed gesture");
    return 0;
}
