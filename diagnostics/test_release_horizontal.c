// Real synchronous, async, and physical-callback paths; all posting is mocked.
#define main existing_async_test_main
#include "test_async_switch.c"
#undef main
#define main existing_payload_policy_main
#include "test_horizontal_payload_policy.c"
#undef main
#include <errno.h>
#include <math.h>

static const char *product_version;
static const char *build_version;
static unsigned build_queries;
static bool expects_modern;
static double expected_velocity, expected_progress;

static void verify_posted_payload(CGEventRef event) {
    CFDataRef data = CGEventCreateData(NULL, event);
    assert(data);
    const uint8_t *payload = NULL;
    size_t length = 0;
    const bool found = find_payload(data, &payload, &length);
    assert(found == expects_modern);
    if (found) {
        assert(length >= sizeof(QueueHeader) + sizeof(FluidGesture));
        FluidGesture fluid;
        memcpy(&fluid, payload + sizeof(QueueHeader), sizeof(fluid));
        int32_t progress = (int32_t)(expected_progress * 65536.0);
        if (!progress && expected_progress != 0) progress = expected_progress < 0 ? -1 : 1;
        if (fluid.swipe_progress != progress) {
            fprintf(stderr, "FAIL: product=%s build=%s raw progress expected=%d actual=%d\n",
                    product_version, build_version, progress, fluid.swipe_progress);
            exit(1);
        }
        if (CGEventGetIntegerValueField(event, (CGEventField)132) == 4) {
            assert(length >= sizeof(QueueHeader) + sizeof(FluidGesture) + sizeof(VelocityEvent));
            VelocityEvent velocity;
            memcpy(&velocity, payload + sizeof(QueueHeader) + sizeof(FluidGesture), sizeof(velocity));
            assert(velocity.velocity_x == (int32_t)(expected_velocity * 65536.0));
        }
    }
    CFRelease(data);
}

int fixture_sysctlbyname(const char *name, void *out, size_t *size,
                        void *new_value, size_t new_size) {
    (void)new_value; (void)new_size;
    if (!strcmp(name, "kern.osversion")) build_queries++;
    const char *value = !strcmp(name, "kern.osproductversion") ? product_version
        : !strcmp(name, "kern.osversion") ? build_version : NULL;
    if (value == build_version && !strcmp(build_version, "unavailable")) value = NULL;
    if (!value) { errno = ENOENT; return -1; }
    size_t required = strlen(value) + 1;
    if (!out) { *size = required; return 0; }
    if (*size < required) { errno = ENOMEM; return -1; }
    memcpy(out, value, required); *size = required; return 0;
}

static void physical_swipe(ISSDirection direction) {
    iss_set_swipe_override(true);
    CGEventRef event = CGEventCreate(NULL);
    assert(event);
    CGEventSetIntegerValueField(event, (CGEventField)55, 30);
    CGEventSetIntegerValueField(event, (CGEventField)110, 23);
    CGEventSetIntegerValueField(event, (CGEventField)123, 1);
    CGEventSetIntegerValueField(event, kCGEventSourceUnixProcessID, 0);
    CGEventSetIntegerValueField(event, (CGEventField)132, 1);
    assert(eventTapCallback(NULL, (CGEventType)30, event, NULL) == NULL);
    CGEventSetIntegerValueField(event, (CGEventField)132, 2);
    CGEventSetDoubleValueField(event, (CGEventField)124,
        direction == ISSDirectionRight ? 0.2 : -0.2);
    assert(eventTapCallback(NULL, (CGEventType)30, event, NULL) == NULL);
    CGEventSetIntegerValueField(event, (CGEventField)132, 4);
    assert(eventTapCallback(NULL, (CGEventType)30, event, NULL) == NULL);
    CFRelease(event);
}

int main(int argc, char **argv) {
    assert(argc == 4);
    product_version = argv[1]; build_version = argv[2];
    bool modern = !strcmp(argv[3], "modern");
    unsetenv("ISS_FORCE_EVENT_AUGMENTATION");
    const double speeds[] = {100, 400, 1000};
    const double modern_speeds[] = {1000, 4000, 9999};
    unsigned cases = 0;
    for (int display = 0; display < 2; display++) {
        for (int path = 0; path < 3; path++) {
            if (!modern && path == 1) continue;
            for (int direction = 0; direction < 2; direction++) {
                for (unsigned speed = 0; speed < 3; speed++) {
                    reset(); auto_confirm = true;
                    expects_modern = modern;
                    expected_velocity = modern ? modern_speeds[speed] : speeds[speed];
                    expected_progress = speed == 2 ? 0.000016 : 1.0;
                    if (direction == ISSDirectionLeft) {
                        expected_velocity = -expected_velocity;
                        expected_progress = -expected_progress;
                    }
                    inspect_posted_event = verify_posted_payload;
                    cursor_display = display; actual[display] = 1;
                    iss_set_gesture_speed(speeds[speed]);
                    if (path == 0) assert(iss_perform_switch_gesture(direction, speeds[speed]));
                    else if (path == 1) assert(iss_request_switch(direction, ISSSwitchSourceExplicit, NULL));
                    else physical_swipe(direction);
                    if (path != 0 && modern) drain();
                    assert(post_count == 3 && phases[0] == 1 && phases[1] == 2 && phases[2] == 4);
                    double expected = modern ? modern_speeds[speed] : speeds[speed];
                    if (direction == ISSDirectionLeft) expected = -expected;
                    if (velocities[2] != expected) {
                        fprintf(stderr, "FAIL product=%s build=%s path=%d preset=%.0f expected=%.0f actual=%.0f\n",
                                product_version, build_version, path, speeds[speed], expected, velocities[2]);
                        return 1;
                    }
                    assert(locations[2].x == 100 + display * 1000);
                    if (modern) assert(velocities[0] == 0 && velocities[1] == 0);
                    if (modern) {
                        double expected_progress = speed == 2 ? 0.000016 : 1.0;
                        if (direction == ISSDirectionLeft) expected_progress = -expected_progress;
                        for (unsigned phase = 0; phase < 3; phase++) {
                            if (fabs(progress_values[phase] - expected_progress) > 1e-12) {
                                fprintf(stderr, "FAIL: preset=%.0f phase=%u expected progress=%.6f actual=%.6f\n",
                                        speeds[speed], phases[phase], expected_progress, progress_values[phase]);
                                return 1;
                            }
                        }
                    }
                    if (path == 2) {
                        assert(cleanup_posts == (modern ? 1u : 0u));
                        assert(!trackpadRecovery.timer && !trackpadRecovery.anchor);
                    }
                    cases++;
                }
            }
        }
    }
    iss_destroy();
    assert(build_queries == 0);
    printf("PASS: product=%s build=%s policy=%s; %u real-path cases, no desktop input\n",
           product_version, build_version, argv[3], cases);
    return 0;
}
