// Real synchronous, async, and physical-callback paths; all posting is mocked.
#define main existing_async_test_main
#include "test_async_switch.c"
#undef main
#include <errno.h>
#include <math.h>

static const char *product_version;
static const char *build_version;

int fixture_sysctlbyname(const char *name, void *out, size_t *size,
                        void *new_value, size_t new_size) {
    (void)new_value; (void)new_size;
    const char *value = !strcmp(name, "kern.osproductversion") ? product_version
        : !strcmp(name, "kern.osversion") ? build_version : NULL;
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
    bool release = !strcmp(argv[3], "release");
    bool modern = strcmp(argv[3], "legacy") != 0;
    unsetenv("ISS_FORCE_EVENT_AUGMENTATION");
    unsetenv("ISS_FORCE_INSTANT_HORIZONTAL_PAYLOAD");
    const double speeds[] = {100, 400, 1000};
    const double release_speeds[] = {1000, 4000, 9999};
    unsigned cases = 0;
    for (int display = 0; display < 2; display++) {
        for (int path = 0; path < 3; path++) {
            if (!modern && path == 1) continue;
            for (int direction = 0; direction < 2; direction++) {
                for (unsigned speed = 0; speed < 3; speed++) {
                    reset(); auto_confirm = true;
                    cursor_display = display; actual[display] = 1;
                    iss_set_gesture_speed(speeds[speed]);
                    if (path == 0) assert(iss_perform_switch_gesture(direction, speeds[speed]));
                    else if (path == 1) assert(iss_request_switch(direction, ISSSwitchSourceExplicit, NULL));
                    else physical_swipe(direction);
                    if (path != 0 && modern) drain();
                    assert(post_count == 3 && phases[0] == 1 && phases[1] == 2 && phases[2] == 4);
                    double expected = release ? release_speeds[speed] : modern ? 100 : speeds[speed];
                    if (direction == ISSDirectionLeft) expected = -expected;
                    if (velocities[2] != expected) {
                        fprintf(stderr, "FAIL product=%s build=%s path=%d preset=%.0f expected=%.0f actual=%.0f\n",
                                product_version, build_version, path, speeds[speed], expected, velocities[2]);
                        return 1;
                    }
                    assert(locations[2].x == 100 + display * 1000);
                    if (modern) assert(velocities[0] == 0 && velocities[1] == 0);
                    if (release) {
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
                    cases++;
                }
            }
        }
    }
    iss_destroy();
    printf("PASS: product=%s build=%s policy=%s; %u real-path cases, no desktop input\n",
           product_version, build_version, argv[3], cases);
    return 0;
}
