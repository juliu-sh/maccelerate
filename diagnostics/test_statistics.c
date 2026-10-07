// Build directly with ISS.c so the recorder's action boundary can be exercised
// without creating an event tap or sending any macOS input events.
// clang -std=c11 -Wall -Wextra -Werror diagnostics/test_statistics.c \
//   Sources/ISS/event_serialize.c -framework ApplicationServices \
//   -framework CoreFoundation -framework IOKit -o /tmp/test_statistics
#include "../Sources/ISS/ISS.c"

static unsigned int dirty_calls = 0;
static void became_dirty(void) { dirty_calls++; }

static uint64_t count_at(const ISSStatisticsSnapshot *snapshot,
                         ISSStatisticAction action, int speed, int reduced) {
    return snapshot->counts[((size_t)action * ISSStatisticSpeedCount
                             + (size_t)speed) * ISSStatisticMotionCount
                            + (size_t)reduced];
}

int main(void) {
    ISSStatisticsSnapshot snapshot = {0};
    iss_statistics_reset();
    iss_statistics_set_dirty_callback(became_dirty);

    iss_statistics_set_enabled(false);
    iss_set_gesture_speed(1000.0);
    statistics_record(ISSStatisticSpaceSwitch);
    iss_statistics_copy_snapshot(&snapshot);
    assert(count_at(&snapshot, ISSStatisticSpaceSwitch, 3, 0) == 0);

    iss_statistics_set_enabled(true);
    iss_set_gesture_speed(40.0);
    statistics_record(ISSStatisticSpaceSwitch);
    iss_statistics_copy_snapshot(&snapshot);
    assert(count_at(&snapshot, ISSStatisticSpaceSwitch, 3, 0) == 0);

    iss_set_gesture_speed(100.0);
    statistics_record(ISSStatisticSpaceSwitch);
    statistics_record(ISSStatisticAppSwitch);
    statistics_record(ISSStatisticMissionControl);
    statistics_record(ISSStatisticAppExpose);
    statistics_record(ISSStatisticOverviewGesture);
    assert(dirty_calls == 1);
    iss_statistics_copy_snapshot(&snapshot);
    for (int action = 0; action < ISSStatisticActionCount; action++) {
        assert(count_at(&snapshot, (ISSStatisticAction)action, 0, 0) == 1);
    }

    iss_statistics_take_snapshot(&snapshot);
    iss_statistics_copy_snapshot(&snapshot);
    assert(count_at(&snapshot, ISSStatisticSpaceSwitch, 0, 0) == 0);

    iss_statistics_set_reduce_motion(true);
    iss_set_gesture_speed(800.0);
    statistics_record(ISSStatisticOverviewGesture);
    statistics_record(ISSStatisticOverviewGesture);
    assert(dirty_calls == 2);
    iss_statistics_copy_snapshot(&snapshot);
    assert(count_at(&snapshot, ISSStatisticOverviewGesture, 2, 1) == 2);

    iss_statistics_reset();
    iss_statistics_copy_snapshot(&snapshot);
    assert(count_at(&snapshot, ISSStatisticOverviewGesture, 2, 1) == 0);
    statistics_record(ISSStatisticAppSwitch);
    assert(dirty_calls == 3);
    iss_statistics_take_snapshot(&snapshot);
    assert(count_at(&snapshot, ISSStatisticAppSwitch, 2, 1) == 1);

    puts("PASS: local statistics counters, bins, pause, reset and coalescing");
    return 0;
}
