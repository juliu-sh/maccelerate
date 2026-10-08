// Shared asynchronous app coordinator. OS-specific gesture serialization stays
// in ISS.c; the synchronous CLI retains its existing event path.
typedef struct {
    ISSSpaceInfo info;
    CFArrayRef ids;
    CGPoint location;
    bool animationKnown, animating;
} ISSAsyncSnapshot;
typedef struct {
    uint64_t id;
    ISSAsyncSnapshot snapshot;
    unsigned int target;
    ISSSwitchSource source;
    ISSSwitchCompletion completion;
    double velocity;
    int speedIndex;
    uint64_t statisticsGeneration;
    unsigned int retries;
    double retryDeadline;
    double waitDeadline;
    bool reduceMotion, recordStatistics, moved;
} ISSAsyncRequest;
typedef struct {
    bool active;
    ISSAsyncSnapshot snapshot;
    unsigned int target;
    ISSDirection direction;
    double velocity, deadline, retryAt, quietSince, settleInterval, retryInterval;
    unsigned int lastObserved;
    bool lastAnimating;
    CGSGesturePhase nextPhase;
} ISSAsyncStep;
static ISSAsyncRequest asyncRequest;
static ISSAsyncStep asyncStep;
static CFRunLoopTimerRef asyncTimer;
static uintptr_t asyncTimerGeneration;
static uint64_t asyncNextID;
static bool asyncDelivering;

bool iss_uses_async_switching(void) { return true; }
static bool async_busy(void) { return asyncRequest.id || asyncStep.active; }
static double async_now(void) {
    struct timespec now;
    clock_gettime(CLOCK_MONOTONIC, &now);
    return (double)now.tv_sec + (double)now.tv_nsec / 1e9;
}
// Opt-in timing diagnostics contain request numbers and aggregate Space indices
// only. Disabled by default, without file writes or retained keyboard input.
static void async_trace(const char *action, int observed) {
    const char *enabled = getenv("MACCELERATE_SWITCH_TRACE");
    if (!enabled || strcmp(enabled, "1")) return;
    fprintf(stderr, "[ISS_SWITCH] t=%.6f action=%s request=%llu source=%u target=%u observed=%d step=%u retries=%u readiness=%d animating=%d\n",
        async_now(), action, (unsigned long long)asyncRequest.id,
        (unsigned int)asyncRequest.source, asyncRequest.target + 1,
        observed < 0 ? -1 : observed + 1,
        asyncStep.active ? asyncStep.target + 1 : 0, asyncRequest.retries,
        asyncStep.active ? asyncStep.snapshot.animationKnown : asyncRequest.snapshot.animationKnown,
        asyncStep.active ? asyncStep.lastAnimating : asyncRequest.snapshot.animating);
}
static double async_phase_delay(void) {
    return iss_requires_event_augmentation() ? 0.01 : 0;
}
static double async_settle_interval(void) {
    // Current Space can change before the compositor accepts a reversal. This
    // bounded quiet interval is a scheduling guard, not proof of animation end.
    if (asyncRequest.reduceMotion || asyncRequest.speedIndex >= 3) return 0.12;
    return asyncRequest.speedIndex >= 1 ? 0.16 : 0.24;
}
static double async_retry_interval(void) {
    if (asyncRequest.reduceMotion || asyncRequest.speedIndex >= 3) return 0.35;
    return asyncRequest.speedIndex >= 1 ? 0.60 : 1.0;
}
static const double kAsyncPollInterval = 0.025;
static const unsigned int kAsyncMaxRetries = 2;
typedef bool (*ISSDisplayIsAnimating)(CGSConnectionID, CFStringRef);
static ISSDisplayIsAnimating async_animation_query(void) {
    static bool loaded;
    static ISSDisplayIsAnimating query;
    if (!loaded) {
        loaded = true;
        query = (ISSDisplayIsAnimating)dlsym(RTLD_DEFAULT, "CGSManagedDisplayIsAnimating");
        if (!query) query = (ISSDisplayIsAnimating)dlsym(RTLD_DEFAULT, "SLSManagedDisplayIsAnimating");
    }
    return query;
}
static void async_release_snapshot(ISSAsyncSnapshot *snapshot) {
    if (snapshot->ids) CFRelease(snapshot->ids);
    memset(snapshot, 0, sizeof(*snapshot));
}

// Unlike the legacy lookup, decline ambiguous/missing cursor displays and
// current Spaces. A stale index must not redirect an asynchronous request.
static bool async_snapshot(ISSAsyncSnapshot *snapshot) {
    memset(snapshot, 0, sizeof(*snapshot));
    if (!cgs_symbols_available()) return false;
    CGEventRef event = CGEventCreate(NULL);
    if (!event) return false;
    CGPoint point = CGEventGetLocation(event);
    snapshot->location = point;
    CFRelease(event);
    CGDirectDisplayID displayID;
    uint32_t count;
    if (CGGetDisplaysWithPoint(point, 1, &displayID, &count) != kCGErrorSuccess || !count) return false;
    CFUUIDRef uuid = CGDisplayCreateUUIDFromDisplayID(displayID);
    if (!uuid) return false;
    CFStringRef identifier = CFUUIDCreateString(NULL, uuid);
    CFRelease(uuid);
    if (!identifier) return false;
    CGSConnectionID connection = CGSMainConnectionID();
    CFArrayRef displays = connection ? CGSCopyManagedDisplaySpaces(connection, NULL) : NULL;
    bool found = false;
    if (displays && CFGetTypeID(displays) == CFArrayGetTypeID()) {
        for (CFIndex d = 0; d < CFArrayGetCount(displays); d++) {
            CFTypeRef value = CFArrayGetValueAtIndex(displays, d);
            if (CFGetTypeID(value) != CFDictionaryGetTypeID()) continue;
            CFDictionaryRef display = (CFDictionaryRef)value;
            CFTypeRef name = CFDictionaryGetValue(display, CFSTR("Display Identifier"));
            if (!name || !CFEqual(name, identifier)) continue;
            CFTypeRef current = CFDictionaryGetValue(display, CFSTR("Current Space"));
            CFTypeRef spaces = CFDictionaryGetValue(display, CFSTR("Spaces"));
            if (!current || CFGetTypeID(current) != CFDictionaryGetTypeID()
                || !spaces || CFGetTypeID(spaces) != CFArrayGetTypeID()) break;
            CFTypeRef currentID = CFDictionaryGetValue((CFDictionaryRef)current, CFSTR("id64"));
            if (!currentID || CFGetTypeID(currentID) != CFNumberGetTypeID()) break;
            CFMutableArrayRef ids = CFArrayCreateMutable(NULL, 0, &kCFTypeArrayCallBacks);
            if (!ids) break;
            bool valid = true;
            for (CFIndex i = 0; i < CFArrayGetCount((CFArrayRef)spaces); i++) {
                CFTypeRef space = CFArrayGetValueAtIndex((CFArrayRef)spaces, i);
                CFTypeRef id = CFGetTypeID(space) == CFDictionaryGetTypeID()
                    ? CFDictionaryGetValue((CFDictionaryRef)space, CFSTR("id64")) : NULL;
                if (!id || CFGetTypeID(id) != CFNumberGetTypeID()
                    || CFArrayContainsValue(ids, CFRangeMake(0, CFArrayGetCount(ids)), id)) {
                    valid = false; break;
                }
                if (CFEqual(id, currentID)) {
                    snapshot->info.currentIndex = (unsigned int)i;
                    found = true;
                }
                CFArrayAppendValue(ids, id);
            }
            found = valid && found && CFStringGetCString(identifier,
                snapshot->info.displayID, sizeof(snapshot->info.displayID), kCFStringEncodingUTF8);
            if (found) {
                snapshot->ids = ids;
                snapshot->info.spaceCount = (unsigned int)CFArrayGetCount(ids);
                ISSDisplayIsAnimating query = async_animation_query();
                snapshot->animationKnown = query != NULL;
                snapshot->animating = query && query(connection, identifier);
            } else CFRelease(ids);
            break;
        }
    }
    if (displays) CFRelease(displays);
    CFRelease(identifier);
    return found;
}
static bool async_same_topology(const ISSAsyncSnapshot *a, const ISSAsyncSnapshot *b) {
    return a->ids && b->ids && strcmp(a->info.displayID, b->info.displayID) == 0
        && CFEqual(a->ids, b->ids);
}
static void async_complete(ISSAsyncRequest request, ISSSwitchResult result) {
    async_release_snapshot(&request.snapshot);
    // Prevent synchronous callback reentry from replacing partially returned
    // requests. App completions dispatch UI work onto the next main queue turn.
    bool wasDelivering = asyncDelivering;
    asyncDelivering = true;
    if (request.id && request.completion) request.completion(request.id, result);
    asyncDelivering = wasDelivering;
}
static void async_finish(ISSSwitchResult result) {
    async_trace(result == ISSSwitchResultSuccess ? "confirmed" :
        result == ISSSwitchResultAlreadyReached ? "already-reached" :
        result == ISSSwitchResultTimedOut ? "timeout" : "finished", -1);
    ISSAsyncRequest request = asyncRequest;
    memset(&asyncRequest, 0, sizeof(asyncRequest));
    if (result == ISSSwitchResultSuccess) {
        if (request.recordStatistics && request.statisticsGeneration == statisticsGeneration) {
            statistics_record_at(request.source == ISSSwitchSourceCmdTab
                ? ISSStatisticAppSwitch : ISSStatisticSpaceSwitch,
                request.speedIndex, request.reduceMotion);
        }
        if (request.source != ISSSwitchSourceCmdTab && switchCallback) switchCallback(request.target);
    }
    async_complete(request, result);
}
static void async_clear_step(void) {
    async_release_snapshot(&asyncStep.snapshot);
    memset(&asyncStep, 0, sizeof(asyncStep));
}
static void async_disarm(void) {
    ++asyncTimerGeneration;
    if (asyncTimer) {
        CFRunLoopTimerInvalidate(asyncTimer);
        CFRelease(asyncTimer);
        asyncTimer = NULL;
    }
}
static void async_tick(void);
static void async_timer_fired(CFRunLoopTimerRef timer, void *context) {
    if (timer != asyncTimer || (uintptr_t)context != asyncTimerGeneration) return;
    async_disarm();
    async_tick();
}
static void async_schedule(double delay) {
    async_disarm();
    CFRunLoopTimerContext context = {0, (void *)asyncTimerGeneration, NULL, NULL, NULL};
    asyncTimer = CFRunLoopTimerCreate(NULL, CFAbsoluteTimeGetCurrent() + delay,
        0, 0, 0, async_timer_fired, &context);
    if (!asyncTimer) {
        async_clear_step();
        async_finish(ISSSwitchResultPostFailed);
        return;
    }
    CFRunLoopAddTimer(CFRunLoopGetMain(), asyncTimer, kCFRunLoopCommonModes);
}
static void async_cancel(bool trackpadOnly) {
    if (!asyncRequest.id || (trackpadOnly && asyncRequest.source != ISSSwitchSourceTrackpad)) return;
    // Finish an already started three-phase sequence, but never start a new
    // step or wait for a cancelled target. Teardown is the exception below.
    if (!asyncStep.active || asyncStep.nextPhase == kCGSGesturePhaseNone) {
        async_disarm();
        async_clear_step();
    }
    async_finish(ISSSwitchResultCancelled);
}
static void async_cancel_trackpad_request(uint64_t id) {
    if (id && asyncRequest.id == id && asyncRequest.source == ISSSwitchSourceTrackpad)
        async_cancel(true);
}
static void async_shutdown(void) {
    async_disarm();
    async_clear_step();
    async_finish(ISSSwitchResultCancelled);
}
static bool async_overview_active(void) {
    CFArrayRef windows = CGWindowListCopyWindowInfo(kCGWindowListOptionOnScreenOnly, kCGNullWindowID);
    if (!windows) return false;
    bool active = iss_is_expose_detected_in_window_list(windows)
        || iss_is_mission_control_detected_in_window_list(windows);
    CFRelease(windows);
    return active;
}
static void async_tick(void) {
    if (inputRequiresRestart || !iss_has_event_access()) {
        iss_suspend_for_permission_change();
        return;
    }
    if (asyncStep.active && asyncStep.nextPhase != kCGSGesturePhaseNone) {
        CGSGesturePhase phase = asyncStep.nextPhase;
        if (!iss_post_dock_swipe_at(phase, asyncStep.direction, asyncStep.velocity, &asyncStep.snapshot.location)) {
            async_clear_step();
            async_finish(ISSSwitchResultPostFailed);
            return;
        }
        asyncStep.nextPhase = phase == kCGSGesturePhaseChanged
            ? kCGSGesturePhaseEnded : kCGSGesturePhaseNone;
        if (phase == kCGSGesturePhaseEnded) {
            double now = async_now();
            asyncStep.deadline = asyncRequest.retryDeadline
                ? asyncRequest.retryDeadline : now + kSpaceSwitchConfirmationTimeout;
            asyncStep.retryAt = now + asyncStep.retryInterval;
            asyncStep.quietSince = now;
            async_trace("ended", -1);
            // A newer display request must not wait for the old display.
            if (!asyncRequest.id || strcmp(asyncRequest.snapshot.info.displayID,
                                           asyncStep.snapshot.info.displayID) != 0) {
                async_clear_step();
                if (asyncRequest.id) async_schedule(0);
                return;
            }
        }
        async_schedule(phase == kCGSGesturePhaseEnded ? 0 : async_phase_delay());
        return;
    }
    if (!asyncRequest.id) { async_clear_step(); return; }
    ISSAsyncSnapshot current;
    if (!async_snapshot(&current)) {
        async_clear_step(); async_finish(ISSSwitchResultCancelled); return;
    }
    const ISSAsyncSnapshot *expected = asyncStep.active ? &asyncStep.snapshot : &asyncRequest.snapshot;
    bool valid = async_same_topology(&current, expected) && !async_overview_active();
    unsigned int observed = current.info.currentIndex;
    bool animationKnown = current.animationKnown;
    bool animating = current.animating;
    async_release_snapshot(&current);
    if (!valid) {
        async_clear_step(); async_finish(ISSSwitchResultCancelled); return;
    }
    if (asyncStep.active) {
        double now = async_now();
        if (animating != asyncStep.lastAnimating) {
            asyncStep.lastAnimating = animating;
            async_trace(animating ? "animation-busy" : "animation-idle", (int)observed);
        }
        if (observed != asyncStep.lastObserved) {
            asyncStep.lastObserved = observed;
            asyncStep.quietSince = now;
            async_trace("observed", (int)observed);
        }
        if (animating) {
            // Retain the step even if Current Space already names its target.
            // A later reversal must wait for this transition to stop accepting
            // or consuming its original gesture.
            asyncStep.quietSince = now;
            if (now >= asyncStep.deadline) {
                async_clear_step(); async_finish(ISSSwitchResultTimedOut); return;
            }
            async_schedule(kAsyncPollInterval); return;
        }
        if (observed == asyncStep.target) {
            double quiet = animationKnown ? kAsyncPollInterval : asyncStep.settleInterval;
            if (now - asyncStep.quietSince + 1e-9 < quiet) {
                async_schedule(kAsyncPollInterval); return;
            }
            if (observed != asyncRequest.snapshot.info.currentIndex) asyncRequest.moved = true;
            asyncRequest.snapshot.info.currentIndex = observed;
            asyncRequest.retries = 0;
            asyncRequest.retryDeadline = 0;
            async_clear_step();
        } else if (observed != asyncStep.snapshot.info.currentIndex) {
            async_clear_step(); async_finish(ISSSwitchResultCancelled); return;
        } else if (animationKnown && now >= asyncStep.retryAt && observed == asyncRequest.target) {
            // The latest goal supersedes a step that never took effect. Waiting
            // for that obsolete step's full timeout would block valid input.
            asyncRequest.snapshot.info.currentIndex = observed;
            asyncRequest.retries = 0;
            asyncRequest.retryDeadline = 0;
            async_trace("obsolete-step", (int)observed);
            async_clear_step();
        } else if (now >= asyncStep.deadline) {
            async_clear_step();
            // An unresolved older gesture can still arrive after this deadline.
            // Even a currently visible newer goal is not a confirmed outcome.
            async_finish(ISSSwitchResultTimedOut);
            return;
        } else if (now >= asyncStep.retryAt &&
                   animationKnown &&
                   asyncRequest.source == ISSSwitchSourceExplicit &&
                   asyncRequest.retries < kAsyncMaxRetries) {
            // Retry only an explicit still-unfulfilled goal from an observed
            // unchanged Space. Never replay a consumed physical/Cmd-Tab gesture.
            asyncRequest.retryDeadline = asyncStep.deadline;
            asyncRequest.retries++;
            asyncRequest.snapshot.info.currentIndex = observed;
            async_trace("retry", (int)observed);
            async_clear_step();
        } else {
            async_schedule(kAsyncPollInterval); return;
        }
    } else if (observed != asyncRequest.snapshot.info.currentIndex) {
        async_finish(ISSSwitchResultCancelled); return;
    }
    if (animating) {
        if (async_now() >= asyncRequest.waitDeadline) {
            async_finish(ISSSwitchResultTimedOut); return;
        }
        async_schedule(kAsyncPollInterval); return;
    }
    if (observed == asyncRequest.target) {
        async_finish(asyncRequest.moved ? ISSSwitchResultSuccess : ISSSwitchResultAlreadyReached);
        return;
    }
    asyncStep.active = true;
    asyncStep.snapshot = asyncRequest.snapshot;
    CFRetain(asyncStep.snapshot.ids);
    asyncStep.direction = asyncRequest.target > observed ? ISSDirectionRight : ISSDirectionLeft;
    asyncStep.target = asyncStep.direction == ISSDirectionRight ? observed + 1 : observed - 1;
    asyncStep.velocity = asyncRequest.velocity;
    asyncStep.lastObserved = observed;
    asyncStep.settleInterval = async_settle_interval();
    asyncStep.retryInterval = async_retry_interval();
    if (!iss_post_dock_swipe_at(kCGSGesturePhaseBegan, asyncStep.direction, asyncStep.velocity, &asyncStep.snapshot.location)) {
        async_clear_step(); async_finish(ISSSwitchResultPostFailed); return;
    }
    if (asyncRequest.source == ISSSwitchSourceTrackpad)
        trackpad_request_did_post(asyncRequest.id);
    async_trace("began", (int)observed);
    asyncStep.nextPhase = kCGSGesturePhaseChanged;
    async_schedule(async_phase_delay());
}
static uint64_t async_submit(bool relative, unsigned int value, ISSSwitchSource source,
                             ISSSwitchCompletion completion) {
    if (!iss_uses_async_switching() || !pthread_main_np() || asyncDelivering
        || inputRequiresRestart || !iss_has_event_access()) return 0;
    ISSAsyncRequest request = {0};
    request.id = ++asyncNextID;
    if (!request.id) request.id = ++asyncNextID;
    const uint64_t id = request.id;
    request.source = source;
    request.completion = completion;
    request.velocity = gestureSpeed;
    request.speedIndex = statistics_speed_index();
    request.reduceMotion = statisticsReduceMotion;
    request.recordStatistics = statisticsEnabled;
    request.statisticsGeneration = statisticsGeneration;
    request.waitDeadline = async_now() + kSpaceSwitchConfirmationTimeout;
    if (!async_snapshot(&request.snapshot)) {
        async_complete(request, ISSSwitchResultInvalidTarget); return id;
    }
    unsigned int base = request.snapshot.info.currentIndex;
    if (relative && asyncRequest.id && async_same_topology(&asyncRequest.snapshot, &request.snapshot))
        base = asyncRequest.target;
    else if (relative && asyncStep.active && async_same_topology(&asyncStep.snapshot, &request.snapshot))
        base = asyncStep.target;
    request.target = relative ? (value == ISSDirectionLeft ? base - 1 : base + 1) : value;
    if (request.target >= request.snapshot.info.spaceCount || (relative && value > ISSDirectionRight)
        || source > ISSSwitchSourceCmdTab) {
        if (source == ISSSwitchSourceTrackpad && relative && value <= ISSDirectionRight &&
            request.target >= request.snapshot.info.spaceCount)
            trackpad_note_boundary(id);
        async_complete(request, ISSSwitchResultInvalidTarget); return id;
    }
    // Preserve the synchronous multi-step calculation before applying the
    // build-specific horizontal velocity policy shared by both paths.
    if (!relative) {
        unsigned int current = request.snapshot.info.currentIndex;
        unsigned int steps = request.target > current ? request.target - current : current - request.target;
        if (steps) request.velocity *= steps;
    }
    request.velocity = iss_horizontal_switch_velocity(request.velocity);
    ISSAsyncRequest previous = asyncRequest;
    asyncRequest = request;
    async_trace("submitted", (int)request.snapshot.info.currentIndex);
    if (asyncStep.active && asyncStep.nextPhase == kCGSGesturePhaseNone
        && !async_same_topology(&asyncStep.snapshot, &request.snapshot)) {
        async_clear_step();
    }
    if (!asyncStep.active) async_schedule(0);
    async_complete(previous, ISSSwitchResultSuperseded);
    return id;
}
uint64_t iss_request_switch(ISSDirection direction, ISSSwitchSource source,
                            ISSSwitchCompletion completion) {
    return async_submit(true, (unsigned int)direction, source, completion);
}
uint64_t iss_request_switch_to_index(unsigned int index, ISSSwitchSource source,
                                     ISSSwitchCompletion completion) {
    return async_submit(false, index, source, completion);
}
