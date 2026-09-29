#include <ApplicationServices/ApplicationServices.h>
#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <time.h>
#include <dlfcn.h>

static double clock_now = 100;
static unsigned sleeps, nested_runs, post_count;
static int actual[2] = {1, 0}, cursor_display;
static int count = 5;
static bool missing, reordered, overview, auto_confirm;
static int fail_create_after = -1;
static int cmdtab_pid, cmdtab_destination = 13;
static bool cmdtab_ambiguous;
static CGPoint locations[256];
static unsigned phases[256];
static double times[256], velocities[256], progress_values[256];
static CFArrayRef fixture_displays(int32_t connection, CFStringRef display);
static int32_t fixture_connection(void) { return 1; }
static uint64_t fixture_active(int32_t connection) { (void)connection; return (uint64_t)actual[0] + 10; }
static CGError fixture_at_point(CGPoint point, uint32_t max, CGDirectDisplayID *display, uint32_t *n) {
    (void)point; (void)max; *display = cursor_display + 1; *n = 1; return kCGErrorSuccess;
}
static CFUUIDRef fixture_uuid(CGDirectDisplayID display) {
    return CFUUIDCreateFromString(NULL, display == 1 ? CFSTR("00000000-0000-0000-0000-000000000001") : CFSTR("00000000-0000-0000-0000-000000000002"));
}
static CFArrayRef fixture_windows(CGWindowListOption option, CGWindowID window) {
    (void)window;
    if (option == kCGWindowListOptionAll && cmdtab_pid) {
        int values[] = {cmdtab_pid, 0, 42};
        CFNumberRef numbers[3];
        for (int i = 0; i < 3; i++) numbers[i] = CFNumberCreate(NULL, kCFNumberIntType, &values[i]);
        const void *keys[] = {kCGWindowOwnerPID, kCGWindowLayer, kCGWindowNumber};
        CFDictionaryRef entry = CFDictionaryCreate(NULL, keys, (const void **)numbers, 3, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
        CFArrayRef result = CFArrayCreate(NULL, (const void **)&entry, 1, &kCFTypeArrayCallBacks);
        CFRelease(entry);
        for (int i = 0; i < 3; i++) CFRelease(numbers[i]);
        return result;
    }
    if (!overview) return CFArrayCreate(NULL, NULL, 0, &kCFTypeArrayCallBacks);
    const void *keys[] = { kCGWindowOwnerName, kCGWindowLayer };
    int layer = 18;
    CFNumberRef number = CFNumberCreate(NULL, kCFNumberIntType, &layer);
    const void *values[] = {CFSTR("Dock"), number};
    CFDictionaryRef entry = CFDictionaryCreate(NULL, keys, values, 2, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
    int otherLayer = 20;
    CFNumberRef otherNumber = CFNumberCreate(NULL, kCFNumberIntType, &otherLayer);
    const void *otherValues[] = {CFSTR("Dock"), otherNumber};
    CFDictionaryRef other = CFDictionaryCreate(NULL, keys, otherValues, 2, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
    const void *entries[] = {entry, other};
    CFArrayRef result = CFArrayCreate(NULL, entries, 2, &kCFTypeArrayCallBacks);
    CFRelease(other); CFRelease(otherNumber);
    CFRelease(entry); CFRelease(number); return result;
}
static CGEventRef fixture_create(CGEventSourceRef source) {
    if (fail_create_after == 0) return NULL;
    if (fail_create_after > 0) fail_create_after--;
    CGEventRef event = CGEventCreate(source);
    if (event) CGEventSetLocation(event, CGPointMake(100 + cursor_display * 1000, 100));
    return event;
}
static void capture_post(CGEventTapLocation location, CGEventRef event) {
    (void)location; assert(post_count < 256);
    phases[post_count] = (unsigned)CGEventGetIntegerValueField(event, (CGEventField)132);
    times[post_count] = clock_now;
    velocities[post_count] = CGEventGetDoubleValueField(event, (CGEventField)129);
    progress_values[post_count] = CGEventGetDoubleValueField(event, (CGEventField)124);
    locations[post_count] = CGEventGetLocation(event);
    if (auto_confirm && phases[post_count] == 4) actual[locations[post_count].x >= 1000 ? 1 : 0] += progress_values[post_count] > 0 ? 1 : -1;
    post_count++;
}
static void capture_tap(CGEventTapProxy proxy, CGEventRef event) { (void)proxy; capture_post(kCGSessionEventTap, event); }
static int fixture_sleep(useconds_t duration) { sleeps++; clock_now += duration / 1000000.0; return 0; }
static CFRunLoopRunResult fixture_run(CFRunLoopMode mode, CFTimeInterval seconds, Boolean once) {
    (void)mode; (void)once; nested_runs++; clock_now += seconds; return kCFRunLoopRunTimedOut;
}
static CFAbsoluteTime fixture_now(void) { return clock_now; }
static int fixture_clock(clockid_t clock, struct timespec *value) {
    (void)clock; value->tv_sec = (time_t)clock_now; value->tv_nsec = (long)((clock_now - value->tv_sec) * 1e9); return 0;
}
static CFArrayRef fixture_spaces(int32_t connection, int32_t mask, CFArrayRef windows) {
    (void)connection; (void)mask; (void)windows;
    CFNumberRef number = CFNumberCreate(NULL, kCFNumberIntType, &cmdtab_destination);
    const void *values[] = {number, number};
    CFArrayRef result = CFArrayCreate(NULL, values, cmdtab_ambiguous ? 2 : 1, &kCFTypeArrayCallBacks);
    CFRelease(number); return result;
}
static void *fixture_dlopen(const char *path, int flags) { (void)path; (void)flags; return (void *)1; }
static void *fixture_dlsym(void *handle, const char *name) { (void)handle; (void)name; return (void *)&fixture_spaces; }
#define dlopen fixture_dlopen
#define dlsym fixture_dlsym
#define clock_gettime fixture_clock
#define CGSCopyManagedDisplaySpaces fixture_displays
#define CGSMainConnectionID fixture_connection
#define CGSGetActiveSpace fixture_active
#define CGGetDisplaysWithPoint fixture_at_point
#define CGDisplayCreateUUIDFromDisplayID fixture_uuid
#define CGWindowListCopyWindowInfo fixture_windows
#define CGEventCreate fixture_create
#define CGEventPost capture_post
#define CGEventTapPostEvent capture_tap
#define usleep fixture_sleep
#define CFRunLoopRunInMode fixture_run
#define CFAbsoluteTimeGetCurrent fixture_now
#ifndef ISS_TEST_SOURCE
#define ISS_TEST_SOURCE "../Sources/ISS/ISS.c"
#endif
#include ISS_TEST_SOURCE
#undef CGEventCreate

static CFArrayRef fixture_displays(int32_t connection, CFStringRef display) {
    (void)connection; (void)display;
    if (missing) return NULL;
    CFMutableArrayRef result = CFArrayCreateMutable(NULL, 0, &kCFTypeArrayCallBacks);
    for (int d = 0; d < 2; d++) {
        CFMutableArrayRef spaces = CFArrayCreateMutable(NULL, 0, &kCFTypeArrayCallBacks);
        for (int i = 0; i < count; i++) {
            int64_t id = 10 + 100 * d + i + (reordered && i == 4 ? 1000 : 0);
            CFNumberRef num = CFNumberCreate(NULL, kCFNumberSInt64Type, &id);
            const void *key = CFSTR("id64");
            CFDictionaryRef space = CFDictionaryCreate(NULL, &key, (const void **)&num, 1, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
            CFArrayAppendValue(spaces, space); CFRelease(space); CFRelease(num);
        }
        CFUUIDRef uuid = fixture_uuid(d + 1);
        CFStringRef name = CFUUIDCreateString(NULL, uuid); CFRelease(uuid);
        const void *keys[] = {CFSTR("Display Identifier"), CFSTR("Spaces"), CFSTR("Current Space")};
        const void *values[] = {name, spaces, CFArrayGetValueAtIndex(spaces, actual[d] < count ? actual[d] : 0)};
        CFDictionaryRef entry = CFDictionaryCreate(NULL, keys, values, 3, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
        CFArrayAppendValue(result, entry); CFRelease(entry); CFRelease(name); CFRelease(spaces);
    }
    return result;
}
static void deliver_swipe(void) {
    iss_set_swipe_override(true);
    CGEventRef event = CGEventCreate(NULL);
    CGEventSetIntegerValueField(event, (CGEventField)55, 30);
    CGEventSetIntegerValueField(event, (CGEventField)110, 23);
    CGEventSetIntegerValueField(event, (CGEventField)123, 1);
    CGEventSetIntegerValueField(event, kCGEventSourceUnixProcessID, 0);
    CGEventSetIntegerValueField(event, (CGEventField)132, 1);
    assert(eventTapCallback(NULL, (CGEventType)30, event, NULL) == NULL);
    CGEventSetIntegerValueField(event, (CGEventField)132, 2);
    CGEventSetDoubleValueField(event, (CGEventField)124, 0.2);
    assert(eventTapCallback(NULL, (CGEventType)30, event, NULL) == NULL);
    CFRelease(event);
}
static unsigned switch_count, last_switch;
static void switched(unsigned int index) { switch_count++; last_switch = index; }
#ifdef LEGACY_TRACE
int main(void) {
    setenv("ISS_FORCE_EVENT_AUGMENTATION", "0", 1);
    iss_set_switch_callback(switched);
    const double speeds[] = {100, 400, 800, 1000};
    for (unsigned i = 0; i < 4; i++) {
        iss_set_gesture_speed(speeds[i]);
        assert(iss_switch(ISSDirectionLeft));
        assert(iss_switch(ISSDirectionRight));
        assert(iss_switch_to_index(4));
        assert(!iss_switch_to_index(5));
        assert(iss_switch_to_index(1));
    }
    actual[0] = 0;
    assert(!iss_switch(ISSDirectionLeft));
    actual[0] = 4;
    assert(!iss_switch(ISSDirectionRight));
    actual[0] = 1;
    deliver_swipe();
    cmdtab_pid = 1234; lastCmdTabRelease = clock_now;
    assert(iss_follow_cmd_tab_application(cmdtab_pid));
    assert(!iss_follow_cmd_tab_application(cmdtab_pid));
    predictionsDict = CFDictionaryCreateMutable(NULL, 0, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
    assert(iss_switch(ISSDirectionRight));
    assert(iss_switch(ISSDirectionRight));
    assert(iss_switch(ISSDirectionLeft));
    assert(iss_switch_to_index(0));
    assert(!iss_switch(ISSDirectionLeft));
    iss_reset_predictions();
    assert(iss_switch(ISSDirectionRight));
    iss_destroy();
    printf("returns verified; callbacks=%u last=%u sleeps=%u nested=%u\n", switch_count, last_switch,
        sleeps, nested_runs);
    for (unsigned i = 0; i < post_count; i++)
        printf("phase=%u progress=%a velocity=%a time=%.2f\n", phases[i], progress_values[i], velocities[i], times[i]);
#ifndef EXPECT_BASELINE_BLOCKING
    assert(!asyncTimer && !async_busy());
    assert(!iss_request_switch(ISSDirectionRight, ISSSwitchSourceExplicit, NULL));
#endif
    return 0;
}
#elif defined(EXPECT_BASELINE_BLOCKING)
int main(void) {
    setenv("ISS_FORCE_EVENT_AUGMENTATION", "1", 1);
    deliver_swipe();
    assert(sleeps == 2 && nested_runs >= 60 && post_count == 3);
    printf("REPRODUCED: real callback sleeps %u times and enters nested runloop %u times before returning\n", sleeps, nested_runs);
    return 0;
}
#else
static uint64_t completed_ids[1024];
static ISSSwitchResult completed_results[1024];
static unsigned completion_count, scenarios;
static void completed(uint64_t id, ISSSwitchResult result) {
    assert(id && completion_count < 1024);
    for (unsigned i = 0; i < completion_count; i++) assert(completed_ids[i] != id);
    completed_ids[completion_count] = id;
    completed_results[completion_count++] = result;
    // Reentrant submissions are explicitly rejected.
    assert(!iss_request_switch(ISSDirectionRight, ISSSwitchSourceExplicit, NULL));
}
static void expect(uint64_t id, ISSSwitchResult result) {
    for (unsigned i = 0; i < completion_count; i++) {
        if (completed_ids[i] == id) { assert(completed_results[i] == result); return; }
    }
    assert(!"missing completion");
}
static void fire(void) {
    assert(asyncTimer);
    assert(CFRunLoopContainsTimer(CFRunLoopGetMain(), asyncTimer, kCFRunLoopCommonModes));
    CFRunLoopTimerRef timer = asyncTimer;
    CFRetain(timer);
    clock_now = CFRunLoopTimerGetNextFireDate(timer);
    async_timer_fired(timer, (void *)asyncTimerGeneration);
    CFRelease(timer);
}
static void drain(void) {
    unsigned limit = 500;
    while (asyncTimer && limit--) fire();
    assert(limit && !async_busy());
    assert(sleeps == 0 && nested_runs == 0);
}
static void reset(void) {
    iss_destroy();
    assert(!asyncTimer && !async_busy());
    post_count = sleeps = nested_runs = switch_count = completion_count = 0;
    actual[0] = 1; actual[1] = 0; cursor_display = 0; count = 5;
    missing = reordered = overview = auto_confirm = false;
    fail_create_after = -1; cmdtab_pid = 0; cmdtab_destination = 13; cmdtab_ambiguous = false;
    iss_set_gesture_speed(1000);
    iss_set_switch_callback(switched);
    clock_now = 100;
    scenarios++;
}
static uint64_t relative(ISSDirection dir) {
    return iss_request_switch(dir, ISSSwitchSourceExplicit, completed);
}
static uint64_t absolute(unsigned int index) {
    return iss_request_switch_to_index(index, ISSSwitchSourceExplicit, completed);
}
int main(void) {
    setenv("ISS_FORCE_EVENT_AUGMENTATION", "1", 1);
    reset();
    deliver_swipe();
    assert(sleeps == 0 && nested_runs == 0 && post_count == 0);
    auto_confirm = true;
    drain();
    assert(actual[0] == 2 && post_count == 3 && switch_count == 1);
    assert(phases[0] == 1 && phases[1] == 2 && phases[2] == 4);
    assert(times[1] - times[0] > .0099 && times[2] - times[1] > .0099);
    assert(velocities[0] == 0 && velocities[1] == 0 && velocities[2] == 100);

    reset();
    uint64_t id = relative(ISSDirectionRight);
    fire(); fire(); fire(); // Ended, confirmation outstanding
    assert(!completion_count && post_count == 3);
    fire(); // still the starting Space
    actual[0] = 2;
    drain(); expect(id, ISSSwitchResultSuccess);
    assert(switch_count == 1);

    reset(); id = relative(ISSDirectionRight);
    drain(); expect(id, ISSSwitchResultTimedOut);
    assert(post_count == 3 && !switch_count);
    assert(clock_now >= 103.02 && clock_now < 103.08);

    reset(); auto_confirm = true;
    id = relative(ISSDirectionRight);
    uint64_t newer = relative(ISSDirectionRight);
    expect(id, ISSSwitchResultSuperseded);
    drain(); expect(newer, ISSSwitchResultSuccess);
    assert(actual[0] == 3 && post_count == 6);

    reset(); auto_confirm = true;
    id = relative(ISSDirectionRight);
    newer = relative(ISSDirectionLeft);
    drain(); expect(id, ISSSwitchResultSuperseded); expect(newer, ISSSwitchResultAlreadyReached);
    assert(!post_count && !switch_count);

    reset(); auto_confirm = true;
    id = relative(ISSDirectionRight); fire();
    newer = relative(ISSDirectionLeft);
    drain(); expect(id, ISSSwitchResultSuperseded); expect(newer, ISSSwitchResultSuccess);
    assert(actual[0] == 1 && post_count == 6);
    assert(progress_values[2] > 0 && progress_values[5] < 0);

    reset(); auto_confirm = true;
    id = absolute(4); fire();
    newer = absolute(0);
    drain(); expect(id, ISSSwitchResultSuperseded); expect(newer, ISSSwitchResultSuccess);
    assert(actual[0] == 0 && post_count == 9 && switch_count == 1);

    reset(); auto_confirm = true;
    id = absolute(4); drain(); expect(id, ISSSwitchResultSuccess);
    assert(post_count == 9 && last_switch == 4);

    reset(); id = absolute(1); drain(); expect(id, ISSSwitchResultAlreadyReached);
    assert(!post_count);
    id = absolute(5); expect(id, ISSSwitchResultInvalidTarget);
    actual[0] = 0; id = relative(ISSDirectionLeft); expect(id, ISSSwitchResultInvalidTarget);
    actual[0] = 4; id = relative(ISSDirectionRight); expect(id, ISSSwitchResultInvalidTarget);
    missing = true; id = absolute(0); expect(id, ISSSwitchResultInvalidTarget);
    assert(!asyncTimer && !post_count);

    for (unsigned interruption = 0; interruption < 2; interruption++) {
        for (unsigned stage = 0; stage < 4; stage++) {
            reset(); id = relative(ISSDirectionRight);
            for (unsigned i = 0; i < stage; i++) fire();
            CGEventType type = interruption ? kCGEventTapDisabledByUserInput : kCGEventTapDisabledByTimeout;
            eventTapCallback(NULL, type, NULL, NULL);
            eventTapCallback(NULL, type, NULL, NULL);
            drain(); expect(id, ISSSwitchResultCancelled);
            assert(post_count == (stage ? 3u : 0u));
            auto_confirm = true; newer = relative(ISSDirectionRight); drain();
            expect(newer, ISSSwitchResultSuccess);
        }
    }
    for (unsigned stage = 0; stage < 4; stage++) {
        reset();
        id = iss_request_switch(ISSDirectionRight, ISSSwitchSourceTrackpad, completed);
        for (unsigned i = 0; i < stage; i++) fire();
        iss_set_swipe_override(false); drain(); expect(id, ISSSwitchResultCancelled);
        assert(post_count == (stage ? 3u : 0u));
    }
    reset(); auto_confirm = true; id = relative(ISSDirectionRight);
    iss_set_swipe_override(false); drain(); expect(id, ISSSwitchResultSuccess);

    for (unsigned stage = 0; stage < 4; stage++) {
        reset(); id = relative(ISSDirectionRight);
        for (unsigned i = 0; i < stage; i++) fire();
        CFRunLoopTimerRef stale = asyncTimer; CFRetain(stale);
        uintptr_t generation = asyncTimerGeneration;
        iss_destroy(); expect(id, ISSSwitchResultCancelled);
        unsigned posts = post_count, completions = completion_count;
        async_timer_fired(stale, (void *)generation); CFRelease(stale);
        assert(!asyncTimer && !async_busy() && post_count == posts && completion_count == completions);
    }
    for (unsigned change = 0; change < 6; change++) {
        reset(); id = absolute(4); fire(); fire(); fire();
        switch (change) {
        case 0: cursor_display = 1; break;
        case 1: reordered = true; break;
        case 2: count = 4; break;
        case 3: actual[0] = 0; break;
        case 4: missing = true; break;
        case 5: overview = true; break;
        }
        drain(); expect(id, ISSSwitchResultCancelled);
        assert(post_count == 3 && !switch_count);
    }
    reset(); overview = true; id = relative(ISSDirectionRight);
    drain(); expect(id, ISSSwitchResultCancelled); assert(!post_count);

    reset(); id = relative(ISSDirectionRight); fire();
    cursor_display = 1; newer = relative(ISSDirectionRight);
    expect(id, ISSSwitchResultSuperseded);
    fire(); fire(); // finish old phases, do not await its confirmation
    assert(post_count == 3 && !asyncStep.active);
    assert(CGPointEqualToPoint(locations[0], locations[1]) && CGPointEqualToPoint(locations[1], locations[2]));
    auto_confirm = true;
    drain(); expect(newer, ISSSwitchResultSuccess);
    assert(actual[1] == 1 && post_count == 6);

    reset(); auto_confirm = true; id = relative(ISSDirectionRight); fire();
    assert(!iss_switch(ISSDirectionLeft) && !iss_switch_to_index(0));
    iss_reset_predictions(); drain(); expect(id, ISSSwitchResultSuccess);

    for (unsigned stage = 0; stage < 3; stage++) {
        reset(); id = relative(ISSDirectionRight);
        for (unsigned i = 0; i < stage; i++) fire();
        fail_create_after = stage == 0 ? 1 : 0;
        fire(); expect(id, ISSSwitchResultPostFailed);
        assert(!async_busy() && !asyncTimer && !switch_count);
        fail_create_after = -1;
    }
    reset(); auto_confirm = true;
    iss_set_gesture_speed(400);
    id = absolute(3);
    iss_set_gesture_speed(1000);
    drain(); expect(id, ISSSwitchResultSuccess);
    assert(actual[0] == 3 && switch_count == 1);

    reset(); auto_confirm = true;
    id = iss_request_switch_to_index(3, ISSSwitchSourceCmdTab, completed);
    drain(); expect(id, ISSSwitchResultSuccess);
    assert(!switch_count);
    assert(!iss_request_follow_cmd_tab_application(0, completed));
    reset(); auto_confirm = true; cmdtab_pid = 1234;
    lastCmdTabRelease = clock_now;
    id = iss_request_follow_cmd_tab_application(cmdtab_pid, completed);
    assert(id && !cmdTabPending && !lastCmdTabRelease);
    drain(); expect(id, ISSSwitchResultSuccess);
    assert(actual[0] == 3 && !switch_count);
    // Native ownership, stale markers and ambiguous destinations are preserved.
    assert(!iss_request_follow_cmd_tab_application(cmdtab_pid, completed));
    lastCmdTabRelease = clock_now - 2;
    assert(!iss_request_follow_cmd_tab_application(cmdtab_pid, completed));
    lastCmdTabRelease = clock_now; cmdtab_ambiguous = true;
    assert(!iss_request_follow_cmd_tab_application(cmdtab_pid, completed));
    lastCmdTabRelease = clock_now; cmdtab_ambiguous = false;
    assert(!iss_request_follow_cmd_tab_application(cmdtab_pid, completed)); // already visible
    assert(!asyncTimer);

    reset(); auto_confirm = true;
    id = relative(ISSDirectionRight); fire();
    cmdtab_pid = 1234; lastCmdTabRelease = clock_now;
    newer = iss_request_follow_cmd_tab_application(cmdtab_pid, completed);
    expect(id, ISSSwitchResultSuperseded);
    drain(); expect(newer, ISSSwitchResultSuccess);
    assert(actual[0] == 3 && !switch_count);
    reset(); auto_confirm = true;
    id = relative(ISSDirectionRight);
    newer = absolute(100); expect(newer, ISSSwitchResultInvalidTarget);
    drain(); expect(id, ISSSwitchResultSuccess);
    assert(completion_count == 2 && actual[0] == 2);

    reset(); auto_confirm = true;
    id = iss_request_switch(ISSDirectionRight, ISSSwitchSourceTrackpad, completed);
    newer = absolute(3); iss_set_swipe_override(false);
    drain(); expect(id, ISSSwitchResultSuperseded); expect(newer, ISSSwitchResultSuccess);
    assert(switch_count == 1);

    reset(); auto_confirm = true;
    iss_set_gesture_speed(25);
    id = absolute(3); drain(); expect(id, ISSSwitchResultSuccess);
    assert(velocities[2] == 50 && velocities[5] == 50);

    // The CLI still waits for confirmation and returns the observed outcome.
    reset(); auto_confirm = true;
    assert(iss_switch(ISSDirectionRight));
    assert(actual[0] == 2 && sleeps == 2 && nested_runs == 1 && !async_busy());
    reset();
    assert(!iss_switch(ISSDirectionRight));
    assert(sleeps == 2 && nested_runs >= 60 && !async_busy());
    iss_destroy();
    printf("PASS: %u isolated scenarios; async callbacks do not wait; no desktop input\n", scenarios);
    return 0;
}
#endif
