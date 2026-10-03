#include <ApplicationServices/ApplicationServices.h>
#include <errno.h>
#include <string.h>
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
static CGError no_display(CGPoint p, uint32_t maximum, CGDirectDisplayID *d, uint32_t *n) {
    (void)p; (void)maximum; (void)d; (void)n; return kCGErrorFailure;
}
#define CGGetDisplaysWithPoint no_display
#define main original_recovery_main
#include "test_gesture_recovery.c"
#undef main
#define main original_payload_main
#include "test_horizontal_payload_policy.c"
#undef main

static void assert_neutral(CGEventRef event, int phase) {
    assert(event);
    assert(CGEventGetIntegerValueField(event, (CGEventField)132) == phase);
    for (int field = 124; field <= 126; field++)
        assert(CGEventGetDoubleValueField(event, (CGEventField)field) == 0);
    assert(CGEventGetDoubleValueField(event, (CGEventField)129) == 0);
    assert(CGEventGetDoubleValueField(event, (CGEventField)130) == 0);
    CFDataRef data = CGEventCreateData(NULL, event);
    const uint8_t *payload = NULL; size_t length = 0;
    assert(find_payload(data, &payload, &length));
    assert(length >= sizeof(QueueHeader) + sizeof(FluidGesture));
    FluidGesture fluid; VelocityEvent velocity;
    memcpy(&fluid, payload + sizeof(QueueHeader), sizeof(fluid));
    memset(&velocity, 0, sizeof(velocity));
    if (length >= sizeof(QueueHeader) + sizeof(fluid) + sizeof(velocity))
        memcpy(&velocity, payload + sizeof(QueueHeader) + sizeof(fluid), sizeof(velocity));
    assert(fluid.swipe_progress == 0 && fluid.position_x == 0 && fluid.position_y == 0);
    assert((fluid.base.options >> 24) == (unsigned)phase);
    assert(velocity.velocity_x == 0 && velocity.velocity_y == 0 && velocity.velocity_z == 0);
    CFRelease(data);
}

int main(void) {
    setenv("ISS_FORCE_EVENT_AUGMENTATION", "1", 1);
    unsetenv("ISS_FORCE_INSTANT_HORIZONTAL_PAYLOAD");
    unsigned cases = 0;
    for (int phase = 4; phase <= 8; phase += 4) {
        for (int companion_first = 0; companion_first <= 1; companion_first++) {
            begin_tracking(true);
            CGEventRef original = gesture(30, 1, phase);
            CGEventSetDoubleValueField(original, (CGEventField)124, 0.35);
            CGEventSetDoubleValueField(original, (CGEventField)125, 0.2);
            CGEventSetDoubleValueField(original, (CGEventField)129, 1000);
            CGEventSetDoubleValueField(original, (CGEventField)130, -50);
            CGEventRef end = iss_prepare_dock_swipe_event_for_current_os(original);
            CFRelease(original);
            CGEventSetIntegerValueField(end, kCGEventSourceUnixProcessID, 0);
            CGEventRef companion = gesture(29, 0, phase);
            unsigned before = cleanup_events;
            if (companion_first) assert(deliver(companion) == NULL);
            assert(deliver(end) == NULL);
            if (cleanup_events == before) {
                fprintf(stderr, "FAIL: tracked terminal phase %d never reaches Dock\n", phase);
                return 1;
            }
            assert_neutral(last_posted, phase);
            if (!companion_first) assert(deliver(companion) == NULL);
            assert(!swipeTracking && !swipeFired);
            CFRelease(end); CFRelease(companion);
            cases++;
        }
    }
    // Watchdog closure from a Begin lacking raw payload gets a current,
    // nonzero nanosecond timestamp and a neutral payload before marking.
    CGEventRef begin = gesture(30, 1, 1);
    CGEventSetTimestamp(begin, 1);
    CGEventRef cancelled = iss_copy_neutral_gesture_terminal(begin, 8);
    assert_neutral(cancelled, 8);
    assert(CGEventGetTimestamp(cancelled) > 1);
    assert(iss_is_neutral_gesture_terminal(cancelled));
    assert(!iss_copy_neutral_gesture_terminal(begin, 2));
    CFRelease(begin); CFRelease(cancelled);
    iss_set_swipe_override(false);
    iss_set_swipe_override(true);
    CGEventRef idle_end = gesture(30, 1, 4);
    assert_unchanged(idle_end);
    CFRelease(idle_end);
    begin_tracking(true);
    CGEventRef foreign_end = gesture(30, 1, 4);
    CGEventSetIntegerValueField(foreign_end, kCGEventSourceUnixProcessID, 12345);
    assert_unchanged(foreign_end);
    assert(swipeTracking);
    CFRelease(foreign_end);
    iss_destroy();
    if (last_posted) { CFRelease(last_posted); last_posted = NULL; }
    printf("PASS: %u terminal order/phase cases, idle and foreign pass-through; no desktop input\n", cases);
    return 0;
}
