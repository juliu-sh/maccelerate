// Private main-runloop state for macOS 27 and later.
// The legacy callback keeps its original event trace.
typedef enum {
    ISSTrackpadRequestNone,
    ISSTrackpadRequestPending,
    ISSTrackpadRequestPosted,
    ISSTrackpadRequestConfirmed,
    ISSTrackpadRequestAlreadyReached,
    ISSTrackpadRequestBoundary,
    ISSTrackpadRequestFailedBeforePost,
    ISSTrackpadRequestFailedAfterPost,
    ISSTrackpadRequestSuperseded
} ISSTrackpadRequestState;

static struct {
    uint64_t generation, requestGeneration, requestID, boundaryID;
    uint64_t inlineID;
    ISSSwitchResult inlineResult;
    ISSTrackpadRequestState requestState;
    bool submitting, hasInlineResult, posted;
    double deadline;
    CGEventRef anchor;
    CFRunLoopTimerRef timer;
} trackpadRecovery;
static uintptr_t trackpadTimerGeneration;
static const double kTrackpadIdleTimeout = 1.0;
static void async_cancel_trackpad_request(uint64_t id);

static double trackpad_now(void) {
    struct timespec now;
    clock_gettime(CLOCK_MONOTONIC, &now);
    return (double)now.tv_sec + (double)now.tv_nsec / 1e9;
}
static void trackpad_disarm(void) {
    ++trackpadTimerGeneration;
    if (trackpadRecovery.timer) {
        CFRunLoopTimerInvalidate(trackpadRecovery.timer);
        CFRelease(trackpadRecovery.timer);
        trackpadRecovery.timer = NULL;
    }
}
static void trackpad_finish_physical(void) {
    trackpad_disarm();
    if (trackpadRecovery.anchor) {
        CFRelease(trackpadRecovery.anchor);
        trackpadRecovery.anchor = NULL;
    }
}
static void trackpad_reset(void) {
    uint64_t generation = trackpadRecovery.generation + 1;
    trackpad_finish_physical();
    memset(&trackpadRecovery, 0, sizeof(trackpadRecovery));
    trackpadRecovery.generation = generation ? generation : 1;
}
static void trackpad_apply_result(uint64_t id, ISSSwitchResult result) {
    if (!id || id != trackpadRecovery.requestID ||
        trackpadRecovery.requestGeneration != trackpadRecovery.generation) return;
    if (result == ISSSwitchResultSuccess) {
        trackpadRecovery.requestState = ISSTrackpadRequestConfirmed;
    } else if (result == ISSSwitchResultAlreadyReached) {
        trackpadRecovery.requestState = ISSTrackpadRequestAlreadyReached;
    } else if (result == ISSSwitchResultInvalidTarget && id == trackpadRecovery.boundaryID) {
        trackpadRecovery.requestState = ISSTrackpadRequestBoundary;
    } else {
        trackpadRecovery.requestState = result == ISSSwitchResultSuperseded
            ? ISSTrackpadRequestSuperseded
            : trackpadRecovery.posted ? ISSTrackpadRequestFailedAfterPost
                                      : ISSTrackpadRequestFailedBeforePost;
        // Never retry Changed events from a partially consumed gesture.
        // Its terminal (or watchdog) closes it; a fresh Begin starts anew.
        if (swipeTracking) {
            swipeTracking = false;
            swipeFired = false;
            interruptedHorizontalSwipe = true;
            horizontalCompanionTail = !horizontalCompanionEnded;
        }
    }
}
static void trackpad_switch_completed(uint64_t id, ISSSwitchResult result) {
    if (trackpadRecovery.submitting) {
        // Scheduling failure / invalid targets may complete before submit
        // returns. Superseded belongs to the previous request in this call.
        if (result != ISSSwitchResultSuperseded) {
            trackpadRecovery.inlineID = id;
            trackpadRecovery.inlineResult = result;
            trackpadRecovery.hasInlineResult = true;
        }
        return;
    }
    trackpad_apply_result(id, result);
}
static void trackpad_note_boundary(uint64_t id) {
    if (trackpadRecovery.submitting) trackpadRecovery.boundaryID = id;
}
static void trackpad_request_did_post(uint64_t id) {
    if (id && id == trackpadRecovery.requestID &&
        trackpadRecovery.requestGeneration == trackpadRecovery.generation) {
        trackpadRecovery.posted = true;
        trackpadRecovery.requestState = ISSTrackpadRequestPosted;
    }
}
static void trackpad_submit(ISSDirection direction) {
    uint64_t generation = trackpadRecovery.generation;
    trackpadRecovery.submitting = true;
    trackpadRecovery.hasInlineResult = false;
    trackpadRecovery.posted = false;
    trackpadRecovery.requestID = 0;
    trackpadRecovery.boundaryID = 0;
    trackpadRecovery.requestState = ISSTrackpadRequestPending;
    uint64_t id = iss_request_switch(direction, ISSSwitchSourceTrackpad, trackpad_switch_completed);
    if (generation != trackpadRecovery.generation) return;
    trackpadRecovery.submitting = false;
    trackpadRecovery.requestID = id;
    trackpadRecovery.requestGeneration = generation;
    if (!id) {
        trackpadRecovery.requestState = ISSTrackpadRequestFailedBeforePost;
        swipeTracking = false; swipeFired = false;
        interruptedHorizontalSwipe = true;
        horizontalCompanionTail = !horizontalCompanionEnded;
    } else if (trackpadRecovery.hasInlineResult && trackpadRecovery.inlineID == id) {
        trackpad_apply_result(id, trackpadRecovery.inlineResult);
    }
}
static void trackpad_expire_if_due(void) {
    if (!trackpadRecovery.anchor || trackpad_now() < trackpadRecovery.deadline) return;
    if (inputRequiresRestart || !iss_has_event_access()) {
        iss_suspend_for_permission_change();
        return;
    }
    uint64_t requestID = trackpadRecovery.requestID;
    CGEventRef terminal = iss_copy_neutral_gesture_terminal(
        trackpadRecovery.anchor, kCGSGesturePhaseCancelled);
    trackpad_reset();
    swipeTracking = false; swipeFired = false;
    // Drain only late horizontal remnants, not unrelated companion input.
    // A new Begin supersedes this guard immediately.
    interruptedHorizontalSwipe = true;
    horizontalCompanionTail = !horizontalCompanionEnded;
    async_cancel_trackpad_request(requestID);
    if (terminal) {
        if (!inputRequiresRestart && iss_has_event_access())
            CGEventPost(kCGSessionEventTap, terminal);
        CFRelease(terminal);
    }
}
static void trackpad_timer_fired(CFRunLoopTimerRef timer, void *context) {
    if (timer != trackpadRecovery.timer || (uintptr_t)context != trackpadTimerGeneration) return;
    if (inputRequiresRestart || !swipeOverrideEnabled || !iss_has_event_access()) {
        if (!iss_has_event_access()) iss_suspend_for_permission_change();
        else trackpad_reset();
        return;
    }
    double remaining = trackpadRecovery.deadline - trackpad_now();
    if (remaining > 0) {
        CFRunLoopTimerSetNextFireDate(timer, CFAbsoluteTimeGetCurrent() + remaining);
        return;
    }
    trackpad_expire_if_due();
}
static bool trackpad_begin(CGEventRef event) {
    trackpad_reset();
    trackpadRecovery.anchor = CGEventCreateCopy(event);
    if (!trackpadRecovery.anchor) return false;
    trackpadRecovery.deadline = trackpad_now() + kTrackpadIdleTimeout;
    CFRunLoopTimerContext context = {0, (void *)++trackpadTimerGeneration, NULL, NULL, NULL};
    trackpadRecovery.timer = CFRunLoopTimerCreate(NULL,
        CFAbsoluteTimeGetCurrent() + kTrackpadIdleTimeout, 0, 0, 0,
        trackpad_timer_fired, &context);
    if (!trackpadRecovery.timer) { trackpad_reset(); return false; }
    CFRunLoopAddTimer(CFRunLoopGetMain(), trackpadRecovery.timer, kCFRunLoopCommonModes);
    return true;
}
static void trackpad_touch(void) {
    if (!trackpadRecovery.timer) return;
    trackpadRecovery.deadline = trackpad_now() + kTrackpadIdleTimeout;
    CFRunLoopTimerSetNextFireDate(trackpadRecovery.timer,
        CFAbsoluteTimeGetCurrent() + kTrackpadIdleTimeout);
}
