// Exercise the shipped coordinator with a delayed, occasionally busy Dock.
// Only the OS boundary is simulated. No event tap or desktop input is installed.
#define main preserved_async_tests_main
#include "test_async_switch.c"
#undef main
#include <math.h>

static double dock_busy_until, pending_at, index_delay, animation_duration;
static int pending_index;
static unsigned ignored, accepted, drop_next;

static void observe_dock(void) {
    if (pending_at && clock_now >= pending_at) {
        actual[0] = pending_index;
        pending_at = 0;
    }
    fixture_animating = clock_now < dock_busy_until;
}
static void simulated_dock(CGEventRef event) {
    if (CGEventGetIntegerValueField(event, (CGEventField)132) != 4) return;
    observe_dock();
    if (drop_next) { drop_next--; ignored++; return; }
    if (clock_now < dock_busy_until) { ignored++; return; }
    int next = actual[0] + (CGEventGetDoubleValueField(event, (CGEventField)124) > 0 ? 1 : -1);
    if (next < 0 || next >= count) return;
    pending_index = next;
    pending_at = clock_now + index_delay;
    dock_busy_until = clock_now + animation_duration;
    accepted++;
    observe_dock();
}
static void prepare(double animation, double confirmation) {
    reset(); actual[0] = 0; count = 2;
    dock_busy_until = pending_at = 0;
    animation_duration = animation; index_delay = confirmation;
    ignored = accepted = drop_next = 0;
    inspect_posted_event = simulated_dock;
    before_snapshot = observe_dock;
}
static void until(double time) {
    unsigned limit = 2000;
    while (asyncTimer && CFRunLoopTimerGetNextFireDate(asyncTimer) <= time && limit--) fire();
    assert(limit);
    clock_now = time;
    observe_dock();
}
static void settled(void) {
    drain(); observe_dock();
    assert(!async_busy() && !asyncTimer);
}
static uint64_t request(ISSDirection direction) {
    uint64_t id = relative(direction);
    if (!id) {
        fputs("FAIL: app coordinator rejects this supported OS; rapid requests still bypass confirmation\n", stderr);
        exit(1);
    }
    return id;
}
int main(int argc, char **argv) {
    assert(argc == 3 || argc == 4);
    animation_symbol_available = argc == 3;
    setenv("ISS_FORCE_EVENT_AUGMENTATION", argv[1], 1);
    int test = atoi(argv[2]);
    if (test == 0) {
        prepare(.12, 0);
        uint64_t first = request(ISSDirectionRight);
        uint64_t latest = request(ISSDirectionLeft);
        settled(); expect(first, ISSSwitchResultSuperseded);
        expect(latest, ISSSwitchResultAlreadyReached);
        assert(actual[0] == 0 && !post_count && !switch_count && !statistics_total());
    } else if (test == 1) {
        prepare(.30, .20);
        uint64_t id = request(ISSDirectionRight);
        until(100.10);
        assert(!completion_count && !switch_count && !statistics_total() && actual[0] == 0);
        settled(); expect(id, ISSSwitchResultSuccess);
        assert(actual[0] == 1 && switch_count == 1 && statistics_total() == 1);
    } else if (test == 2) {
        prepare(.40, 0);
        uint64_t first = request(ISSDirectionRight);
        until(100.08);
        uint64_t second = request(ISSDirectionLeft);
        until(100.12);
        uint64_t latest = request(ISSDirectionRight);
        settled();
        expect(second, ISSSwitchResultSuperseded);
        assert(actual[0] == 1 && clock_now < 101);
        for (unsigned i = 0; i < completion_count; i++) {
            if (completed_ids[i] == latest)
                assert(completed_results[i] == ISSSwitchResultSuccess || completed_results[i] == ISSSwitchResultAlreadyReached);
        }
        (void)first;
    } else if (test == 3) {
        prepare(.60, 0);
        uint64_t first = request(ISSDirectionRight);
        until(100.18);
        uint64_t latest = request(ISSDirectionLeft);
        settled();
        assert(actual[0] == 0);
        expect(latest, ISSSwitchResultSuccess);
        assert(clock_now < 102 && accepted == 2);
        (void)first;
    } else if (test == 4) {
        prepare(.30, .12);
        request(ISSDirectionRight);
        until(100.06);
        request(ISSDirectionLeft);
        iss_reset_predictions(); // A delayed notification from an older step.
        until(100.09);
        uint64_t latest = request(ISSDirectionRight);
        settled();
        assert(actual[0] == 1 && clock_now < 101.5);
        for (unsigned i = 0; i < completion_count; i++)
            assert(completed_results[i] != ISSSwitchResultTimedOut);
        (void)latest;
    } else if (test == 5) {
        unsigned cases = 0;
        for (uint32_t seed = 1; seed <= 128; seed++) {
            uint32_t random = seed;
            prepare(.08 + (seed % 7) * .10, (seed % 4) * .02);
            count = 5;
            const double presets[] = {100, 400, 1000};
            iss_set_gesture_speed(presets[seed % 3]);
            unsigned goal = 0;
            uint64_t latest = 0;
            for (unsigned input = 0; input < 48; input++) {
                random = random * 1664525u + 1013904223u;
                until(clock_now + .015 + (random % 100) / 1000.0);
                if (random % 5 == 0) {
                    goal = (random >> 8) % count;
                    latest = absolute(goal);
                } else {
                    ISSDirection direction = (random >> 8) % 2 ? ISSDirectionRight : ISSDirectionLeft;
                    bool valid = direction == ISSDirectionRight ? goal + 1 < (unsigned)count : goal > 0;
                    uint64_t id = request(direction);
                    if (valid) { goal = direction == ISSDirectionRight ? goal + 1 : goal - 1; latest = id; }
                    else expect(id, ISSSwitchResultInvalidTarget);
                }
                if (input % 5 == 0) iss_reset_predictions();
            }
            settled();
            assert(completion_count == 48);
            if (actual[0] != (int)goal) {
                fprintf(stderr, "FAIL seed=%u actual=%d goal=%u\n", seed, actual[0], goal);
                return 1;
            }
            for (unsigned i = 0; i < completion_count; i++)
                if (completed_ids[i] == latest)
                    assert(completed_results[i] == ISSSwitchResultSuccess || completed_results[i] == ISSSwitchResultAlreadyReached);
            cases++;
        }
        printf("PASS: mode=%s %u seeded bursts, 6144 requests across presets, bounds, absolute targets and delayed notifications\n", argv[1], cases);
    } else if (test == 6) {
        // The old gesture is delayed, rather than discarded. A timer alone
        // must not declare the reverse goal done before that gesture arrives.
        prepare(.90, .70);
        request(ISSDirectionRight);
        until(100.08);
        uint64_t latest = request(ISSDirectionLeft);
        until(100.50);
        assert(!switch_count && !statistics_total());
        settled();
        if (animation_symbol_available) {
            expect(latest, ISSSwitchResultSuccess);
            assert(actual[0] == 0 && !pending_at && clock_now < 102.5);
        } else {
            expect(latest, ISSSwitchResultTimedOut);
            assert(actual[0] == 1 && !switch_count && !statistics_total());
            uint64_t next = request(ISSDirectionLeft);
            settled(); expect(next, ISSSwitchResultSuccess);
            assert(actual[0] == 0);
        }
    } else if (test == 7) {
        // An unavailable readiness API never turns a guessed index into success
        // or automatically replays an uncertain old gesture.
        assert(!animation_symbol_available);
        prepare(.60, 0);
        request(ISSDirectionRight); until(100.18);
        uint64_t failed = request(ISSDirectionLeft);
        settled(); expect(failed, ISSSwitchResultTimedOut);
        assert(actual[0] == 1 && ignored == 1);
        uint64_t next = request(ISSDirectionLeft);
        settled(); expect(next, ISSSwitchResultSuccess);
        assert(actual[0] == 0);
    } else if (test == 8) {
        prepare(0, 0); drop_next = 2;
        uint64_t id = request(ISSDirectionRight);
        until(100.30);
        assert(!switch_count && !statistics_total());
        settled(); expect(id, ISSSwitchResultSuccess);
        assert(actual[0] == 1 && ignored == 2 && accepted == 1 && post_count == 9 && clock_now < 101.5);
    } else if (test == 9) {
        prepare(0, 0);
        request(ISSDirectionRight); settled();
        until(100.08); drop_next = 1;
        uint64_t obsolete = request(ISSDirectionLeft);
        until(100.12);
        uint64_t latest = request(ISSDirectionRight);
        settled(); expect(obsolete, ISSSwitchResultSuperseded);
        expect(latest, ISSSwitchResultAlreadyReached);
        assert(actual[0] == 1 && ignored == 1 && accepted == 1 && clock_now < 100.6);
        assert(switch_count == 1 && statistics_total() == 1);
    } else if (test == 10) {
        prepare(0, 0); drop_next = 100;
        uint64_t id = request(ISSDirectionRight);
        settled(); expect(id, ISSSwitchResultTimedOut);
        assert(actual[0] == 0 && ignored == 3 && post_count == 9 && !switch_count && !statistics_total());
        assert(clock_now < 103.1);
        drop_next = 0;
        uint64_t next = request(ISSDirectionRight);
        settled(); expect(next, ISSSwitchResultSuccess);
        assert(actual[0] == 1 && statistics_total() == 1);
    } else return 2;
    printf("PASS: payload mode=%s rapid scenario=%d; observed=%d accepted=%u ignored=%u duration=%.3f; no desktop input\n",
           argv[1], test, actual[0] + 1, accepted, ignored, clock_now - 100);
    iss_destroy();
    return 0;
}
