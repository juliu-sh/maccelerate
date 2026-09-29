#include "include/ISS.h"
#include "event_serialize.h"

#include <ApplicationServices/ApplicationServices.h>
#include <CoreFoundation/CoreFoundation.h>
#include <CoreGraphics/CGEventTypes.h>
#include <assert.h>
#include <dlfcn.h>
#include <float.h>
#include <mach/mach_time.h>
#include <stdbool.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>
#include <pthread.h>
#include <time.h>

static const CGEventField kCGSEventTypeField = (CGEventField)55;
static const CGEventField kCGEventGestureHIDType = (CGEventField)110;
static const CGEventField kCGEventGestureSwipeMask = (CGEventField)115;
static const CGEventField kCGEventGestureSwipeMotion = (CGEventField)123;
static const CGEventField kCGEventGestureSwipeProgress = (CGEventField)124;
static const CGEventField kCGEventGestureSwipePositionX = (CGEventField)125;
static const CGEventField kCGEventGestureSwipePositionY = (CGEventField)126;
static const CGEventField kCGEventGestureSwipeVelocityX = (CGEventField)129;
static const CGEventField kCGEventGestureSwipeVelocityY = (CGEventField)130;
static const CGEventField kCGEventGesturePhase = (CGEventField)132;
static const CGEventField kCGEventGesturePhaseAlias = (CGEventField)134;
static const CGEventField kCGEventGestureZoomDeltaY = (CGEventField)138;
static const CGEventField kCGEventSourceUnixProcessIDAlias = (CGEventField)169;

// See IOHIDEventType enum in IOHIDFamily
static const uint32_t kIOHIDEventTypeDockSwipe = 23;

typedef uint32_t CGSEventType;
enum {
    kCGSEventScrollWheel = 22,
    kCGSEventZoom = 28,
    kCGSEventGesture = 29,
    kCGSEventDockControl = 30,
    kCGSEventFluidTouchGesture = 31,
};

typedef CF_ENUM(uint8_t, CGSGesturePhase) {
    kCGSGesturePhaseNone = 0,
    kCGSGesturePhaseBegan = 1,
    kCGSGesturePhaseChanged = 2,
    kCGSGesturePhaseEnded = 4,
    kCGSGesturePhaseCancelled = 8,
    kCGSGesturePhaseMayBegin = 128,
};

// Limited subset of motion constants observed in synthetic Dock swipe traces.
typedef CF_ENUM(uint16_t, CGGestureMotion) {
    kCGGestureMotionHorizontal = 1,
    kCGGestureMotionVertical = 2,
};

typedef int32_t CGSConnectionID;
typedef uint64_t CGSSpaceID;

typedef CFArrayRef (*ISSCopySpacesForWindows)(CGSConnectionID, int32_t, CFArrayRef);

extern CFArrayRef CGSCopyManagedDisplaySpaces(CGSConnectionID connection, CFStringRef display) __attribute__((weak_import));
extern CFStringRef CGSCopyActiveMenuBarDisplayIdentifier(CGSConnectionID connection) __attribute__((weak_import));
extern CGSConnectionID CGSMainConnectionID(void) __attribute__((weak_import));
extern CGSSpaceID CGSGetActiveSpace(CGSConnectionID connection) __attribute__((weak_import));

static CFMachPortRef globalTap = NULL;
static CFRunLoopSourceRef globalSource = NULL;
static bool cmdTabPending = false;
static CFAbsoluteTime lastCmdTabKeyDown = 0;
static CFAbsoluteTime lastCmdTabRelease = 0;
static const CFTimeInterval kCmdTabActivationWindow = 1.5;

// Overlay detection state
static bool overlayDetectionEnabled = false;

// Swipe override state
static bool swipeOverrideEnabled = false;
static bool swipeTracking = false;
static bool swipeFired = false;
// Drain only the interrupted horizontal sequence, never unrelated gestures.
static bool interruptedHorizontalSwipe = false;

typedef struct {
    bool enabled;
    CGKeyCode keyCode;
    CGEventFlags modifiers;
} ISSOverlayHotkey;

static ISSOverlayHotkey overlayHotkeys[2] = {0};
static int activeOverlayHotkey = -1;
static bool activeOverlayHotkeyWasAccelerated = false;
static int pendingMenuOverlay = -1;
static bool menuOverlayWasTriggered = false;

static const CGEventFlags kRelevantHotkeyFlags =
    kCGEventFlagMaskCommand | kCGEventFlagMaskAlternate |
    kCGEventFlagMaskControl | kCGEventFlagMaskShift;
static const CGEventFlags kNativeOverlayFlags =
    kCGEventFlagMaskControl | kCGEventFlagMaskSecondaryFn |
    kCGEventFlagMaskNumericPad | kCGEventFlagMaskNonCoalesced;

// Gesture speed state
static double gestureSpeed = 1000.0;
// Build 26A5388g accepts larger horizontal velocities but can leave the
// WindowServer transition incomplete (missing menu bar/windows). 100 is the
// highest configured preset verified to complete reliably on macOS 27.
static const double kMacOS27MaxGestureVelocity = 100.0;
static const CFTimeInterval kSpaceSwitchConfirmationTimeout = 3.0;
static const CFTimeInterval kSpaceSwitchPollInterval = 0.05;

static ISSSwitchCallback switchCallback = NULL;

// Predictions dictionary: DisplayID (CFStringRef) -> Index (CFNumberRef)
static CFMutableDictionaryRef predictionsDict = NULL;

static bool get_prediction(const char *displayID, unsigned int *outIndex) {
    if (!displayID || !predictionsDict) return false;
    
    CFStringRef key = CFStringCreateWithCString(NULL, displayID, kCFStringEncodingUTF8);
    const void *value = CFDictionaryGetValue(predictionsDict, key);
    CFRelease(key);

    if (value) {
        CFNumberGetValue((CFNumberRef)value, kCFNumberIntType, outIndex);
        return true;
    }
    return false;
}

static void set_prediction(const char *displayID, unsigned int index) {
    if (!displayID || !predictionsDict) return;
    
    CFStringRef key = CFStringCreateWithCString(NULL, displayID, kCFStringEncodingUTF8);
    CFNumberRef val = CFNumberCreate(NULL, kCFNumberIntType, &index);
    CFDictionarySetValue(predictionsDict, key, val);
    CFRelease(key);
    CFRelease(val);
}

static bool extract_space_info_from_display(CFDictionaryRef displayDict,
                                            CGSSpaceID activeSpace,
                                            bool hasActiveSpace,
                                            ISSSpaceInfo *outInfo);
static bool load_space_info_for_display(ISSSpaceInfo *info, bool useCursorDisplay);
static bool load_space_info_for_identifier(ISSSpaceInfo *info, const char *displayID);
static bool iss_perform_switch_gesture(ISSDirection direction, double velocity);
static bool iss_switch_with_info(const ISSSpaceInfo *info, ISSDirection direction);
static bool iss_should_block_switch(const ISSSpaceInfo *info, ISSDirection direction);
static bool iss_wait_for_space_index(const char *displayID, unsigned int targetIndex);

static void async_cancel(bool trackpadOnly);
static void async_shutdown(void);
static bool async_busy(void);

static bool valid_overlay_mode(ISSOverlayMode mode) {
    return mode == ISSOverlayModeMissionControl ||
           mode == ISSOverlayModeAppExpose;
}

static CGKeyCode native_overlay_keycode(ISSOverlayMode mode) {
    return mode == ISSOverlayModeMissionControl ? 126 : 125;
}

static bool overlay_hotkeys_enabled(void) {
    return overlayHotkeys[ISSOverlayModeMissionControl].enabled ||
           overlayHotkeys[ISSOverlayModeAppExpose].enabled;
}

static double vertical_gesture_multiplier(void) {
    if (gestureSpeed >= 1000.0) return 10.0;
    if (gestureSpeed >= 800.0) return 8.0;
    if (gestureSpeed >= 400.0) return 4.0;
    if (gestureSpeed >= 100.0) return 2.0;
    return 1.0;
}

static useconds_t overlay_phase_delay(void) {
    if (gestureSpeed >= 800.0) return 10000;
    if (gestureSpeed >= 400.0) return 16000;
    return 30000;
}

static useconds_t overlay_progressive_phase_delay(void) {
    // A physical accelerated trackpad gesture gives WindowServer several
    // committed progress samples across compositor frames. A single jump from
    // epsilon to 1.0 is accepted, but the overlay then finishes with the
    // ordinary keyboard animation. Four samples reproduce the physical path
    // without an event loop or a long-running synthetic gesture stream.
    return 16000;
}

static bool post_overlay_phase(CGEventTapProxy proxy, CGEventRef provenance,
                               CGSGesturePhase phase, double progress,
                               double velocity) {
    CGEventRef event = CGEventCreateCopy(provenance);
    if (!event) return false;

    CGEventSetType(event, (CGEventType)kCGSEventDockControl);
    CGEventSetIntegerValueField(event, kCGSEventTypeField,
                                kCGSEventDockControl);
    CGEventSetIntegerValueField(event, kCGEventGestureHIDType,
                                kIOHIDEventTypeDockSwipe);
    CGEventSetIntegerValueField(event, kCGEventGestureSwipeMask, 0);
    CGEventSetIntegerValueField(event, kCGEventGesturePhase, phase);
    CGEventSetIntegerValueField(event, kCGEventGestureSwipeMotion,
                                kCGGestureMotionVertical);
    CGEventSetDoubleValueField(event, kCGEventGestureSwipeProgress, progress);
    CGEventSetDoubleValueField(event, kCGEventGestureSwipeVelocityX,
                               velocity);
    CGEventSetTimestamp(event, mach_absolute_time());

    CGEventRef event_to_post = NULL;
    if (iss_requires_event_augmentation()) {
        CGEventSetIntegerValueField(event, kCGEventGesturePhaseAlias, phase);
        CGEventSetDoubleValueField(event, kCGEventGestureSwipePositionX, 0.1);
        CGEventSetDoubleValueField(event, kCGEventGestureSwipePositionY, 0.0);
        CGEventSetDoubleValueField(event, kCGEventGestureSwipeVelocityY,
                                   velocity);
        CGEventSetDoubleValueField(event, kCGEventGestureZoomDeltaY, 3.0);
        CGEventSetDoubleValueField(event, kCGEventSourceUnixProcessIDAlias,
                                   (double)mach_absolute_time());
    } else {
        // macOS 13–26 consumes the public CGEvent fields directly.
        CGEventSetDoubleValueField(event, kCGEventGestureSwipeVelocityY,
                                   velocity);
    }
    event_to_post = iss_prepare_dock_swipe_event_for_current_os(event);
    CFRelease(event);
    if (!event_to_post) return false;

    // CGEventCreateFromData rewrites the visible source PID. Restore the
    // physical mouse/key event provenance before posting the replacement.
    const int64_t source_pid = CGEventGetIntegerValueField(
        provenance, kCGEventSourceUnixProcessID);
    CGEventSetIntegerValueField(
        event_to_post, kCGEventSourceUnixProcessID, source_pid);
    if (proxy) {
        CGEventTapPostEvent(proxy, event_to_post);
    } else {
        CGEventPost(kCGSessionEventTap, event_to_post);
    }
    CFRelease(event_to_post);
    return true;
}

static double overlay_progress_for_mode(ISSOverlayMode mode) {
    double current_position = 0.0;
    if (iss_is_mission_control_active()) {
        current_position = 1.0;
    } else if (iss_is_expose_active()) {
        current_position = -1.0;
    }

    double target_position =
        mode == ISSOverlayModeMissionControl ? 1.0 : -1.0;
    if (current_position == target_position) {
        target_position = 0.0;
    }
    return target_position - current_position;
}

static bool post_accelerated_overlay(CGEventTapProxy proxy,
                                     CGEventRef provenance,
                                     ISSOverlayMode mode) {
    if (!valid_overlay_mode(mode) || !provenance ||
        vertical_gesture_multiplier() <= 1.0) {
        return false;
    }

    const double progress = overlay_progress_for_mode(mode);
    if (progress == 0.0) return true;
    const double sign = progress < 0.0 ? -1.0 : 1.0;
    const double epsilon = sign * 0.000016;
    const useconds_t delay = overlay_phase_delay();

    // FasterSwiper's macOS 27 commit sequence: begin at epsilon, move to the
    // target, then end at epsilon with a signed terminal velocity.
    if (!post_overlay_phase(proxy, provenance, kCGSGesturePhaseBegan,
                            epsilon, 0.0)) {
        return false;
    }
    usleep(delay);
    if (iss_requires_event_augmentation()) {
        const useconds_t progressive_delay =
            overlay_progressive_phase_delay();
        if (!post_overlay_phase(proxy, provenance, kCGSGesturePhaseChanged,
                                progress * 0.25, 0.0)) return false;
        usleep(progressive_delay);
        if (!post_overlay_phase(proxy, provenance, kCGSGesturePhaseChanged,
                                progress * 0.50, 0.0)) return false;
        usleep(progressive_delay);
        if (!post_overlay_phase(proxy, provenance, kCGSGesturePhaseChanged,
                                progress * 0.75, 0.0)) return false;
        usleep(progressive_delay);
        if (!post_overlay_phase(proxy, provenance, kCGSGesturePhaseChanged,
                                progress, 0.0)) return false;
        usleep(progressive_delay);
        return post_overlay_phase(
            proxy, provenance, kCGSGesturePhaseEnded, progress,
            sign * kMacOS27MaxGestureVelocity);
    }

    if (!post_overlay_phase(proxy, provenance, kCGSGesturePhaseChanged,
                            progress, 0.0)) return false;
    usleep(delay);
    return post_overlay_phase(
        proxy, provenance, kCGSGesturePhaseEnded, epsilon,
        sign * gestureSpeed);
}

static CGEventRef translate_physical_overlay_hotkey(CGEventTapProxy proxy,
                                                     CGEventType type,
                                                     CGEventRef event) {
    if (type != kCGEventKeyDown && type != kCGEventKeyUp) return event;

    const pid_t sourcePid = (pid_t)CGEventGetIntegerValueField(
        event, kCGEventSourceUnixProcessID);
    if (sourcePid != 0) return event;

    const CGKeyCode keyCode = (CGKeyCode)CGEventGetIntegerValueField(
        event, kCGKeyboardEventKeycode);
    const CGEventFlags modifiers = CGEventGetFlags(event) & kRelevantHotkeyFlags;

    if (type == kCGEventKeyDown) {
        if (CGEventGetIntegerValueField(event, kCGKeyboardEventAutorepeat) != 0) {
            return activeOverlayHotkey >= 0 ? NULL : event;
        }

        activeOverlayHotkey = -1;
        for (int mode = ISSOverlayModeMissionControl;
             mode <= ISSOverlayModeAppExpose; mode++) {
            const ISSOverlayHotkey hotkey = overlayHotkeys[mode];
            if (hotkey.enabled && hotkey.keyCode == keyCode &&
                hotkey.modifiers == modifiers) {
                activeOverlayHotkey = mode;
                break;
            }
        }
        if (activeOverlayHotkey < 0) return event;

        const ISSOverlayMode mode = (ISSOverlayMode)activeOverlayHotkey;
        if (post_accelerated_overlay(proxy, event, mode)) {
            activeOverlayHotkeyWasAccelerated = true;
            return NULL;
        }
        activeOverlayHotkeyWasAccelerated = false;
    } else {
        if (activeOverlayHotkey < 0 ||
            overlayHotkeys[activeOverlayHotkey].keyCode != keyCode) {
            return event;
        }
        if (activeOverlayHotkeyWasAccelerated) {
            activeOverlayHotkey = -1;
            activeOverlayHotkeyWasAccelerated = false;
            return NULL;
        }
    }

    CGEventSetIntegerValueField(event, kCGKeyboardEventKeycode,
                                native_overlay_keycode(
                                    (ISSOverlayMode)activeOverlayHotkey));
    CGEventSetFlags(event, kNativeOverlayFlags);
    if (type == kCGEventKeyUp) activeOverlayHotkey = -1;
    return event;
}

static CGEventRef accelerate_physical_vertical_gesture(
    CGEventTapProxy proxy, CGEventRef event) {
    const CGSGesturePhase phase = (CGSGesturePhase)CGEventGetIntegerValueField(
        event, kCGEventGesturePhase);
    if (phase == kCGSGesturePhaseBegan || phase == kCGSGesturePhaseCancelled) {
        return event;
    }
    if (phase != kCGSGesturePhaseChanged && phase != kCGSGesturePhaseEnded) {
        return event;
    }

    const double multiplier = vertical_gesture_multiplier();
    if (multiplier <= 1.0) {
        return event;
    }

    if (iss_requires_event_augmentation()) {
        CGEventRef accelerated = iss_accelerate_vertical_dock_swipe_event(
            event, multiplier, kMacOS27MaxGestureVelocity);
        if (!accelerated) {
            return event;
        }

        // Post downstream from this physical event tap so the replacement
        // remains in the same trusted gesture stream, then suppress the
        // unaccelerated original.
        CGEventTapPostEvent(proxy, accelerated);
        CFRelease(accelerated);
        return NULL;
    }

    // Older macOS versions consume the outer CGEvent fields directly.
    const double progress = CGEventGetDoubleValueField(
        event, kCGEventGestureSwipeProgress);
    const double positionY = CGEventGetDoubleValueField(
        event, kCGEventGestureSwipePositionY);
    CGEventSetDoubleValueField(event, kCGEventGestureSwipeProgress,
                               progress * multiplier);
    CGEventSetDoubleValueField(event, kCGEventGestureSwipePositionY,
                               positionY * multiplier);

    if (phase == kCGSGesturePhaseEnded) {
        const double velocityY = CGEventGetDoubleValueField(
            event, kCGEventGestureSwipeVelocityY);
        if (velocityY != 0.0) {
            const double signedVelocity = velocityY < 0.0
                ? -gestureSpeed : gestureSpeed;
            CGEventSetDoubleValueField(event, kCGEventGestureSwipeVelocityX,
                                       signedVelocity);
            CGEventSetDoubleValueField(event, kCGEventGestureSwipeVelocityY,
                                       signedVelocity);
        }
    }
    return event;
}

// Perform a swipe-override switch: get space info, compute target, switch,
// and notify the handler with the target index.
static void swipe_override_switch(ISSDirection dir) {
    if (iss_uses_async_switching()) {
        iss_request_switch(dir, ISSSwitchSourceTrackpad, NULL);
        return;
    }
    ISSSpaceInfo info;
    if (!iss_get_space_info(&info)) {
        iss_perform_switch_gesture(dir, gestureSpeed);
        return;
    }

    unsigned int predicted;
    unsigned int current = get_prediction(info.displayID, &predicted) ? predicted : info.currentIndex;
    unsigned int target = dir == ISSDirectionLeft ? current - 1 : current + 1;

    if (iss_switch_with_info(&info, dir)) {
        set_prediction(info.displayID, target);
        if (switchCallback) { switchCallback(target); }
    }
}

static CGEventRef eventTapCallback(CGEventTapProxy proxy, CGEventType type,
                                   CGEventRef event, void *refcon) {
    (void)refcon;

    // Re-enable if the system disabled our tap for being too slow
    if (type == kCGEventTapDisabledByTimeout || type == kCGEventTapDisabledByUserInput) {
        async_cancel(false);
        interruptedHorizontalSwipe = interruptedHorizontalSwipe || swipeTracking;
        swipeTracking = false;
        swipeFired = false;
        cmdTabPending = false;
        lastCmdTabKeyDown = 0;
        lastCmdTabRelease = 0;
        if (globalTap) CGEventTapEnable(globalTap, true);
        return event;
    }

    // Cmd-Tab chooses the app in the Dock. Remember the physical shortcut,
    // then let the Dock receive every event unchanged. The activation observer
    // uses this short-lived marker so Dock clicks and other app activations
    // retain their native Space transition.
    if (type == kCGEventKeyDown) {
        const CGKeyCode keyCode = (CGKeyCode)CGEventGetIntegerValueField(
            event, kCGKeyboardEventKeycode);
        const CGEventFlags flags = CGEventGetFlags(event);
        if (keyCode == 48 && (flags & kCGEventFlagMaskCommand)
            && !(flags & (kCGEventFlagMaskControl | kCGEventFlagMaskAlternate))) {
            cmdTabPending = true;
            lastCmdTabKeyDown = CFAbsoluteTimeGetCurrent();
            lastCmdTabRelease = 0;
        } else if (keyCode == 53) {
            cmdTabPending = false;
            lastCmdTabKeyDown = 0;
        }
    } else if (type == kCGEventLeftMouseDown) {
        cmdTabPending = false;
        lastCmdTabKeyDown = 0;
        lastCmdTabRelease = 0;
    } else if (type == kCGEventFlagsChanged && cmdTabPending
               && !(CGEventGetFlags(event) & kCGEventFlagMaskCommand)) {
        cmdTabPending = false;
        lastCmdTabRelease = CFAbsoluteTimeGetCurrent();
    }

    if (overlay_hotkeys_enabled() &&
        (type == kCGEventKeyDown || type == kCGEventKeyUp)) {
        return translate_physical_overlay_hotkey(proxy, type, event);
    }

    if (type == kCGEventLeftMouseUp && pendingMenuOverlay >= 0) {
        const pid_t source_pid = (pid_t)CGEventGetIntegerValueField(
            event, kCGEventSourceUnixProcessID);
        if (source_pid == 0) {
            const ISSOverlayMode mode = (ISSOverlayMode)pendingMenuOverlay;
            menuOverlayWasTriggered = post_accelerated_overlay(
                proxy, event, mode);
        }
        pendingMenuOverlay = -1;
        return event;
    }

    if (!swipeOverrideEnabled) return event;

    CGSEventType eventType =
        (CGSEventType)CGEventGetIntegerValueField(event, kCGSEventTypeField);

    // Pass through synthetic events (non-HID source). Real gesture events
    // from the trackpad have sourcePid == 0 (HID kernel).
    if (eventType == kCGSEventDockControl || eventType == kCGSEventGesture) {
        pid_t sourcePid = (pid_t)CGEventGetIntegerValueField(event, kCGEventSourceUnixProcessID);
        if (sourcePid != 0) return event;
    }

    if (eventType == kCGSEventDockControl) {
        uint32_t hidType =
            (uint32_t)CGEventGetIntegerValueField(event, kCGEventGestureHIDType);
        if (hidType != kIOHIDEventTypeDockSwipe) return event;

        uint16_t motion =
            (uint16_t)CGEventGetIntegerValueField(event, kCGEventGestureSwipeMotion);
        if (motion == kCGGestureMotionVertical) {
            return accelerate_physical_vertical_gesture(proxy, event);
        }
        if (motion != kCGGestureMotionHorizontal) return event;

        CGSGesturePhase phase =
            (CGSGesturePhase)CGEventGetIntegerValueField(event, kCGEventGesturePhase);

        if (interruptedHorizontalSwipe) {
            if (phase == kCGSGesturePhaseBegan) {
                interruptedHorizontalSwipe = false;
            } else {
                if (phase == kCGSGesturePhaseEnded || phase == kCGSGesturePhaseCancelled) {
                    interruptedHorizontalSwipe = false;
                }
                return NULL;
            }
        }

        switch (phase) {
        case kCGSGesturePhaseBegan:
            if (iss_is_expose_active()) return event;
            swipeTracking = true;
            swipeFired = false;
            return NULL;

        case kCGSGesturePhaseChanged: {
            if (!swipeTracking) return event;
            if (!swipeFired) {
                double progress =
                    CGEventGetDoubleValueField(event, kCGEventGestureSwipeProgress);
                if (progress != 0.0) {
                    ISSDirection dir =
                        progress > 0 ? ISSDirectionRight : ISSDirectionLeft;
                    swipeFired = true;
                    swipe_override_switch(dir);
                }
            }
            return NULL;
        }

        case kCGSGesturePhaseEnded: {
            if (!swipeTracking) return event;
            if (!swipeFired) {
                double velocity =
                    CGEventGetDoubleValueField(event, kCGEventGestureSwipeVelocityX);
                if (velocity != 0.0) {
                    ISSDirection dir =
                        velocity > 0 ? ISSDirectionRight : ISSDirectionLeft;
                    swipeFired = true;
                    swipe_override_switch(dir);
                }
            }
            swipeTracking = false;
            swipeFired = false;
            return NULL;
        }

        case kCGSGesturePhaseCancelled:
            swipeTracking = false;
            swipeFired = false;
            return NULL;

        default:
            return swipeTracking ? NULL : event;
        }
    }

    // Suppress companion gesture events during active swipe tracking
    if (eventType == kCGSEventGesture && swipeTracking) {
        return NULL;
    }

    return event;
}

static bool cgs_symbols_available(void) {
    return (&CGSMainConnectionID != NULL) &&
           (&CGSGetActiveSpace != NULL) &&
           (&CGSCopyManagedDisplaySpaces != NULL);
}

static bool extract_space_info_from_display(CFDictionaryRef displayDict,
                                            CGSSpaceID activeSpace,
                                            bool hasActiveSpace,
                                            ISSSpaceInfo *outInfo) {
    if (!displayDict || !outInfo) {
        return false;
    }

    memset(outInfo->displayID, 0, sizeof(outInfo->displayID));
    CFStringRef identifier = (CFStringRef)CFDictionaryGetValue(displayDict, CFSTR("Display Identifier"));
    if (identifier && CFGetTypeID(identifier) == CFStringGetTypeID()) {
        CFStringGetCString(identifier, outInfo->displayID, sizeof(outInfo->displayID), kCFStringEncodingUTF8);
    }

    const void *spacesValue = CFDictionaryGetValue(displayDict, CFSTR("Spaces"));
    if (!spacesValue || CFGetTypeID(spacesValue) != CFArrayGetTypeID()) {
        return false;
    }

    // Try to get current space from display dict (more accurate per-display)
    CGSSpaceID displayActiveSpace = 0;
    const void *currentSpaceValue = CFDictionaryGetValue(displayDict, CFSTR("Current Space"));
    if (currentSpaceValue && CFGetTypeID(currentSpaceValue) == CFDictionaryGetTypeID()) {
        CFDictionaryRef currentSpaceDict = (CFDictionaryRef)currentSpaceValue;
        CFNumberRef currentSpaceID = (CFNumberRef)CFDictionaryGetValue(currentSpaceDict, CFSTR("id64"));
        if (currentSpaceID && CFGetTypeID(currentSpaceID) == CFNumberGetTypeID()) {
            CFNumberGetValue(currentSpaceID, kCFNumberSInt64Type, &displayActiveSpace);
        }
    }
    
    // Use display-specific active space if available, otherwise use global
    CGSSpaceID targetActiveSpace = displayActiveSpace != 0 ? displayActiveSpace : activeSpace;
    bool hasTargetActiveSpace = displayActiveSpace != 0 || hasActiveSpace;

    CFArrayRef spaces = (CFArrayRef)spacesValue;
    const CFIndex spaceCount = CFArrayGetCount(spaces);

    unsigned int totalSpaces = 0;
    unsigned int activeIndex = 0;
    bool foundActive = false;

    for (CFIndex i = 0; i < spaceCount; i++) {
        const void *spaceValue = CFArrayGetValueAtIndex(spaces, i);
        if (!spaceValue || CFGetTypeID(spaceValue) != CFDictionaryGetTypeID()) {
            continue;
        }

        CFDictionaryRef spaceDict = (CFDictionaryRef)spaceValue;
        CFNumberRef idNumber = (CFNumberRef)CFDictionaryGetValue(spaceDict, CFSTR("id64"));
        if (!idNumber || CFGetTypeID(idNumber) != CFNumberGetTypeID()) {
            continue;
        }

        CGSSpaceID candidate = 0;
        if (CFNumberGetValue(idNumber, kCFNumberSInt64Type, &candidate)) {
            if (!foundActive && hasTargetActiveSpace && candidate == targetActiveSpace) {
                activeIndex = totalSpaces;
                foundActive = true;
            }
            totalSpaces++;
        }
    }

    if (totalSpaces == 0 || (hasTargetActiveSpace && !foundActive)) {
        return false;
    }

    outInfo->spaceCount = totalSpaces;
    outInfo->currentIndex = foundActive ? activeIndex : 0;
    return true;
}

static bool load_space_info_for_display(ISSSpaceInfo *info, bool useCursorDisplay) {
    if (!cgs_symbols_available()) {
        fprintf(stderr, "ISS: required CGS symbols missing\n");
        return false;
    }

    CGSConnectionID connection = CGSMainConnectionID();
    if (connection == 0) {
        fprintf(stderr, "ISS: CGSMainConnectionID returned 0\n");
        return false;
    }

    CGSSpaceID activeSpace = 0;
    bool hasActiveSpace = false;
    if (&CGSGetActiveSpace != NULL) {
        activeSpace = CGSGetActiveSpace(connection);
        if (activeSpace != 0) {
            hasActiveSpace = true;
        } else {
            fprintf(stderr, "ISS: CGSGetActiveSpace returned 0\n");
            return false;
        }
    }

    // Get display identifier based on mode
    CFStringRef activeDisplayIdentifier = NULL;
    
    if (useCursorDisplay) {
        // Get display where cursor is located
        CGEventRef tempEvent = CGEventCreate(NULL);
        CGPoint cursorLocation = CGEventGetLocation(tempEvent);
        CFRelease(tempEvent);
        
        CGDirectDisplayID cursorDisplay = 0;
        uint32_t cursorDisplayCount = 0;
        
        if (CGGetDisplaysWithPoint(cursorLocation, 1, &cursorDisplay, &cursorDisplayCount) == kCGErrorSuccess && cursorDisplayCount > 0) {
            CFUUIDRef displayUUID = CGDisplayCreateUUIDFromDisplayID(cursorDisplay);
            if (displayUUID) {
                activeDisplayIdentifier = CFUUIDCreateString(NULL, displayUUID);
                CFRelease(displayUUID);
            }
        }
    } else {
        // Get menubar display
        if (&CGSCopyActiveMenuBarDisplayIdentifier != NULL) {
            activeDisplayIdentifier = CGSCopyActiveMenuBarDisplayIdentifier(connection);
        }
    }

    CFArrayRef displays = CGSCopyManagedDisplaySpaces(connection, activeDisplayIdentifier);
    if (!displays && activeDisplayIdentifier) {
        displays = CGSCopyManagedDisplaySpaces(connection, NULL);
    }
    if (!displays) {
        if (activeDisplayIdentifier) {
            CFRelease(activeDisplayIdentifier);
        }
        return false;
    }

    const CFIndex displayCount = CFArrayGetCount(displays);
    CFDictionaryRef targetDisplay = NULL;
    CFDictionaryRef fallbackDisplay = NULL;

    for (CFIndex i = 0; i < displayCount; i++) {
        const void *displayValue = CFArrayGetValueAtIndex(displays, i);
        if (!displayValue || CFGetTypeID(displayValue) != CFDictionaryGetTypeID()) {
            continue;
        }

        CFDictionaryRef displayDict = (CFDictionaryRef)displayValue;

        if (!fallbackDisplay) {
            fallbackDisplay = displayDict;
        }

        if (!activeDisplayIdentifier || targetDisplay) {
            continue;
        }

        CFStringRef identifier = (CFStringRef)CFDictionaryGetValue(displayDict, CFSTR("Display Identifier"));
        if (identifier && CFGetTypeID(identifier) == CFStringGetTypeID() && CFEqual(identifier, activeDisplayIdentifier)) {
            targetDisplay = displayDict;
        }
    }

    if (!targetDisplay) {
        targetDisplay = fallbackDisplay;
    }

    bool success = false;
    if (targetDisplay) {
        success = extract_space_info_from_display(targetDisplay, activeSpace, hasActiveSpace, info);
    }

    if (activeDisplayIdentifier) {
        CFRelease(activeDisplayIdentifier);
    }
    CFRelease(displays);

    return success;
}

static bool load_space_info_for_identifier(ISSSpaceInfo *info, const char *displayID) {
    if (!info || !displayID || !cgs_symbols_available()) {
        return false;
    }

    const CGSConnectionID connection = CGSMainConnectionID();
    if (connection == 0) {
        return false;
    }

    const CGSSpaceID activeSpace = CGSGetActiveSpace(connection);
    const bool hasActiveSpace = activeSpace != 0;
    CFArrayRef displays = CGSCopyManagedDisplaySpaces(connection, NULL);
    CFStringRef wantedID = CFStringCreateWithCString(
        NULL, displayID, kCFStringEncodingUTF8);
    if (!displays || !wantedID) {
        if (displays) CFRelease(displays);
        if (wantedID) CFRelease(wantedID);
        return false;
    }

    bool success = false;
    const CFIndex displayCount = CFArrayGetCount(displays);
    for (CFIndex i = 0; i < displayCount; i++) {
        const void *displayValue = CFArrayGetValueAtIndex(displays, i);
        if (!displayValue || CFGetTypeID(displayValue) != CFDictionaryGetTypeID()) {
            continue;
        }

        CFDictionaryRef displayDict = (CFDictionaryRef)displayValue;
        CFStringRef identifier = (CFStringRef)CFDictionaryGetValue(
            displayDict, CFSTR("Display Identifier"));
        if (identifier && CFGetTypeID(identifier) == CFStringGetTypeID()
            && CFEqual(identifier, wantedID)) {
            success = extract_space_info_from_display(
                displayDict, activeSpace, hasActiveSpace, info);
            break;
        }
    }

    CFRelease(wantedID);
    CFRelease(displays);
    return success;
}

static bool iss_should_block_switch(const ISSSpaceInfo *info, ISSDirection direction) {
    if (!info) {
        return false;
    }
    if (info->spaceCount == 0) {
        return true;
    }

    unsigned int predicted;
    unsigned int current = get_prediction(info->displayID, &predicted) ? predicted : info->currentIndex;

    if (direction == ISSDirectionLeft) {
        return current == 0;
    }

    return current + 1 >= info->spaceCount;
}

bool iss_can_move(ISSSpaceInfo info, ISSDirection direction) {
    return !iss_should_block_switch(&info, direction);
}

static bool iss_post_dock_swipe_at(CGSGesturePhase phase, ISSDirection direction, double velocity,
                                    const CGPoint *location) {
    const bool isRight = (direction == ISSDirectionRight);

    // Preserve the library's direction sign in the serialized macOS 27 path.
    // The original prototype inverted it, so a right request hit the left
    // boundary on build 26A5388g.
    const double progress = iss_requires_event_augmentation()
                                ? (isRight ? 0.000016 : -0.000016)
                                : (isRight ? (double)FLT_TRUE_MIN : -(double)FLT_TRUE_MIN);

    // Velocity of gesture based on speed setting
    const double vel = isRight ? velocity : -velocity;
    const double modernVel = isRight ? velocity : -velocity;

    CGEventRef ev = CGEventCreate(NULL);
    if (!ev) {
        return false;
    }
    if (location) CGEventSetLocation(ev, *location);
    CGEventSetIntegerValueField(ev, kCGSEventTypeField, kCGSEventDockControl);
    CGEventSetIntegerValueField(ev, kCGEventGestureHIDType, kIOHIDEventTypeDockSwipe);
    CGEventSetIntegerValueField(ev, kCGEventGesturePhase, phase);
    CGEventSetDoubleValueField(ev, kCGEventGestureSwipeProgress, progress);
    CGEventSetIntegerValueField(ev, kCGEventGestureSwipeMotion, kCGGestureMotionHorizontal);

    if (iss_requires_event_augmentation()) {
        CGEventSetIntegerValueField(ev, kCGEventGesturePhaseAlias, phase);
        CGEventSetDoubleValueField(ev, kCGEventGestureZoomDeltaY, 3.0);
        CGEventSetDoubleValueField(ev, kCGEventSourceUnixProcessIDAlias,
                                    (double)mach_absolute_time());
        CGEventSetDoubleValueField(ev, kCGEventGestureSwipePositionX, 0.1);

        // Match FasterSwiper: only the Ended event carries velocity.
        if (phase == kCGSGesturePhaseEnded) {
            CGEventSetDoubleValueField(ev, kCGEventGestureSwipeVelocityX, modernVel);
        }

        CGEventRef augmented = iss_augment_dock_swipe_event(ev);
        CFRelease(ev);
        if (!augmented) {
            return false;
        }
        CGEventPost(kCGSessionEventTap, augmented);
        CFRelease(augmented);
        return true;
    }

    CGEventSetDoubleValueField(ev, kCGEventGestureSwipeVelocityX, vel);
    CGEventSetDoubleValueField(ev, kCGEventGestureSwipeVelocityY, vel);
    CGEventPost(kCGSessionEventTap, ev);
    CFRelease(ev);
    return true;
}

static bool iss_post_dock_swipe(CGSGesturePhase phase, ISSDirection direction, double velocity) {
    return iss_post_dock_swipe_at(phase, direction, velocity, NULL);
}

static bool iss_perform_switch_gesture(ISSDirection direction, double velocity) {
    // Send three gesture events--began, changed, and ended
    // If we only send two then mission control doesn't work.
    // macOS 27 drops augmented phases posted back-to-back.
    const bool requiresAugmentation = iss_requires_event_augmentation();
    const useconds_t phaseDelay = requiresAugmentation ? 10000 : 0;
    const double effectiveVelocity =
        requiresAugmentation && velocity > kMacOS27MaxGestureVelocity
            ? kMacOS27MaxGestureVelocity
            : velocity;

    if (!iss_post_dock_swipe(kCGSGesturePhaseBegan, direction,
                             effectiveVelocity)) {
        return false;
    }
    if (phaseDelay) usleep(phaseDelay);

    if (!iss_post_dock_swipe(kCGSGesturePhaseChanged, direction,
                             effectiveVelocity)) {
        return false;
    }
    if (phaseDelay) usleep(phaseDelay);

    return iss_post_dock_swipe(kCGSGesturePhaseEnded, direction,
                               effectiveVelocity);
}

/** @brief Walks a CGWindowListCopyWindowInfo result
 *
 * Used for trying to determine if Exposé or Mission Control is active.
 *
 * @param windowList The window list to scan
 * @param outLayer18Count The count of layer-18 windows
 * @param outLayer20Count The count of layer-20 windows
 */
static void scan_dock_window_list(CFArrayRef windowList,
                                  int *outLayer18Count,
                                  int *outLayer20Count) {
    *outLayer18Count = 0;
    *outLayer20Count = 0;
    CFIndex count = CFArrayGetCount(windowList);
    for (CFIndex i = 0; i < count; i++) {
        CFDictionaryRef info = (CFDictionaryRef)CFArrayGetValueAtIndex(windowList, i);
        CFStringRef owner = (CFStringRef)CFDictionaryGetValue(info, CFSTR("kCGWindowOwnerName"));
        if (!owner || !CFEqual(owner, CFSTR("Dock"))) continue;
        int layer = 0;
        CFNumberRef layerNum = (CFNumberRef)CFDictionaryGetValue(info, CFSTR("kCGWindowLayer"));
        if (layerNum) {
            CFNumberGetValue(layerNum, kCFNumberIntType, &layer);
        }
        if (layer == 18) {
            (*outLayer18Count)++;
            continue;
        }
        if (layer == 20) {
            (*outLayer20Count)++;
        }
    }
}

// Testable helpers
bool iss_is_expose_detected_in_window_list(CFArrayRef windowList) {
    int layer18Count = 0;
    int layer20Count = 0;
    scan_dock_window_list(windowList, &layer18Count, &layer20Count);
    // App Exposé: layer-18 present, at least one layer-20, AND count(layer=20) <= count(layer=18)
    return layer18Count > 0 && layer20Count > 0 && layer20Count <= layer18Count;
}

bool iss_is_mission_control_detected_in_window_list(CFArrayRef windowList) {
    int layer18Count = 0;
    int layer20Count = 0;
    scan_dock_window_list(windowList, &layer18Count, &layer20Count);
    // Mission Control: layer-18 present AND count(layer=20) > count(layer=18)
    return layer18Count > 0 && layer20Count > layer18Count;
}

/// Returns true when App Exposé is active (1-2 layer-20 windows)
/// This heuristic is empirical and may not work in all cases.
bool iss_is_expose_active(void) {
    if (!overlayDetectionEnabled) return false;
    CFArrayRef windowList = CGWindowListCopyWindowInfo(
        kCGWindowListOptionOnScreenOnly, kCGNullWindowID);
    if (!windowList) return false;
    bool result = iss_is_expose_detected_in_window_list(windowList);
    CFRelease(windowList);
    return result;
}

/// Returns true when Mission Control is active (3+ layer-20 windows)
/// This heuristic is empirical and may not work in all cases.
bool iss_is_mission_control_active(void) {
    if (!overlayDetectionEnabled) return false;
    CFArrayRef windowList = CGWindowListCopyWindowInfo(
        kCGWindowListOptionOnScreenOnly, kCGNullWindowID);
    if (!windowList) return false;
    bool result = iss_is_mission_control_detected_in_window_list(windowList);
    CFRelease(windowList);
    return result;
}

void iss_set_overlay_detection_enabled(bool enabled) {
    overlayDetectionEnabled = enabled;
}

#include "async_switch.h"

bool iss_init(void) {
    if (globalTap) {
        return true;
    }

    if (!predictionsDict) {
        predictionsDict = CFDictionaryCreateMutable(NULL, 0, &kCFCopyStringDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
    }

    CGEventMask mask = CGEventMaskBit(kCGEventKeyDown) |
        CGEventMaskBit(kCGEventKeyUp) | CGEventMaskBit(kCGEventFlagsChanged)
        | CGEventMaskBit(kCGEventLeftMouseDown) | CGEventMaskBit(kCGEventLeftMouseUp)
        | (1ULL << kCGSEventGesture) | (1ULL << kCGSEventDockControl);
    globalTap = CGEventTapCreate(
        kCGSessionEventTap,
        kCGHeadInsertEventTap,
        kCGEventTapOptionDefault,
        mask,
        eventTapCallback,
        NULL
    );

    if (!globalTap) {
        return false;
    }

    globalSource = CFMachPortCreateRunLoopSource(NULL, globalTap, 0);
    CFRunLoopAddSource(CFRunLoopGetMain(), globalSource, kCFRunLoopCommonModes);
    CGEventTapEnable(globalTap, true);

    return true;
}

void iss_destroy(void) {
    async_shutdown();
    swipeTracking = false;
    swipeFired = false;
    interruptedHorizontalSwipe = false;
    cmdTabPending = false;
    lastCmdTabKeyDown = 0;
    lastCmdTabRelease = 0;
    if (predictionsDict) {
        CFRelease(predictionsDict);
        predictionsDict = NULL;
    }
    if (globalTap) {
        CGEventTapEnable(globalTap, false);
        if (globalSource) {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), globalSource, kCFRunLoopCommonModes);
            CFRelease(globalSource);
            globalSource = NULL;
        }
        CFRelease(globalTap);
        globalTap = NULL;
    }
}

bool iss_get_space_info(ISSSpaceInfo *info) {
    if (!info) {
        return false;
    }

    memset(info, 0, sizeof(*info));
    return load_space_info_for_display(info, true);
}

bool iss_get_menubar_space_info(ISSSpaceInfo *info) {
    if (!info) {
        return false;
    }

    memset(info, 0, sizeof(*info));
    return load_space_info_for_display(info, false);
}

static bool iss_wait_for_space_index(const char *displayID, unsigned int targetIndex) {
    const CFAbsoluteTime deadline = CFAbsoluteTimeGetCurrent() + kSpaceSwitchConfirmationTimeout;

    do {
        // Let the Dock consume the gesture while keeping the menu-bar app's
        // main runloop responsive. This also makes the short-lived CLI work.
        CFRunLoopRunInMode(kCFRunLoopDefaultMode, kSpaceSwitchPollInterval, false);

        ISSSpaceInfo current;
        memset(&current, 0, sizeof(current));
        if (load_space_info_for_identifier(&current, displayID)
            && current.currentIndex == targetIndex) {
            return true;
        }
    } while (CFAbsoluteTimeGetCurrent() < deadline);

    fprintf(stderr, "ISS: timed out waiting for Space index %u\n", targetIndex);
    return false;
}

static bool iss_switch_with_info(const ISSSpaceInfo *info, ISSDirection direction) {
    if (iss_should_block_switch(info, direction)) {
        return false;
    }

    unsigned int predicted;
    const unsigned int current = get_prediction(info->displayID, &predicted)
                                     ? predicted
                                     : info->currentIndex;
    const unsigned int target = direction == ISSDirectionLeft ? current - 1 : current + 1;

    if (!iss_perform_switch_gesture(direction, gestureSpeed)) {
        return false;
    }

    return !iss_requires_event_augmentation()
        || iss_wait_for_space_index(info->displayID, target);
}

bool iss_switch(ISSDirection direction) {
    if (async_busy()) return false;
    ISSSpaceInfo info;
    if (iss_get_space_info(&info)) {
        unsigned int predicted;
        unsigned int current = get_prediction(info.displayID, &predicted) ? predicted : info.currentIndex;
        unsigned int target = direction == ISSDirectionLeft ? current - 1 : current + 1;

        if (!iss_switch_with_info(&info, direction)) {
            return false;
        }
        set_prediction(info.displayID, target);
        if (switchCallback) { switchCallback(target); }
        return true;
    }

    return iss_perform_switch_gesture(direction, gestureSpeed);
}

static bool iss_switch_to_index_internal(unsigned int targetIndex, bool notify,
                                         bool usePrediction) {
    if (async_busy()) return false;
    ISSSpaceInfo info;
    if (!iss_get_space_info(&info)) {
        return false;
    }

    assert(info.spaceCount > 0);

    if (targetIndex >= info.spaceCount) {
        return false;
    }

    unsigned int predicted;
    unsigned int currentIndex = usePrediction
        && get_prediction(info.displayID, &predicted) ? predicted : info.currentIndex;

    if (currentIndex == targetIndex) {
        return true;
    }

    ISSDirection direction = currentIndex < targetIndex ? ISSDirectionRight : ISSDirectionLeft;
    unsigned int steps = direction == ISSDirectionRight ? (targetIndex - currentIndex) : (currentIndex - targetIndex);

    // Multiply velocity by number of steps for faster multi-space switching
    double velocity = gestureSpeed * steps;

    for (unsigned int i = 0; i < steps; i++) {
        if (!iss_perform_switch_gesture(direction, velocity)) {
            return false;
        }
        if (iss_requires_event_augmentation()) {
            const unsigned int expectedIndex = direction == ISSDirectionRight
                                                   ? currentIndex + i + 1
                                                   : currentIndex - i - 1;
            if (!iss_wait_for_space_index(info.displayID, expectedIndex)) {
                return false;
            }
        }
    }

    set_prediction(info.displayID, targetIndex);
    if (notify && switchCallback) { switchCallback(targetIndex); }
    return true;
}

bool iss_switch_to_index(unsigned int targetIndex) {
    return iss_switch_to_index_internal(targetIndex, true, true);
}

// Like yabai's SIP-enabled focus path, macOS owns the app selection and a
// fast Dock gesture gets to the activated app's Space first. We use the ISS
// gesture implementation already present here. Space membership has no public
// API, so keep the private lookup optional and decline uncertain destinations.
static ISSCopySpacesForWindows copy_spaces_for_windows(void) {
    static ISSCopySpacesForWindows function = NULL;
    static bool resolved = false;
    if (!resolved) {
        resolved = true;
        void *skyLight = dlopen(
            "/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight",
            RTLD_LAZY | RTLD_LOCAL);
        if (skyLight) {
            function = (ISSCopySpacesForWindows)dlsym(
                skyLight, "SLSCopySpacesForWindows");
        }
    }
    return function;
}

static CGSSpaceID single_space_for_window(CGSConnectionID connection,
                                          CGWindowID windowID,
                                          ISSCopySpacesForWindows copySpaces,
                                          bool *multipleSpaces) {
    CFNumberRef number = CFNumberCreate(NULL, kCFNumberSInt32Type, &windowID);
    if (!number) return 0;
    CFArrayRef ids = CFArrayCreate(NULL, (const void **)&number, 1,
                                   &kCFTypeArrayCallBacks);
    CFRelease(number);
    if (!ids) return 0;

    // 7 includes ordinary desktop, full-screen and system-managed Spaces.
    CFArrayRef spaces = copySpaces(connection, 7, ids);
    CFRelease(ids);
    if (!spaces) return 0;

    CGSSpaceID spaceID = 0;
    if (CFArrayGetCount(spaces) > 1) {
        *multipleSpaces = true;
    } else if (CFArrayGetCount(spaces) == 1) {
        CFTypeRef value = CFArrayGetValueAtIndex(spaces, 0);
        if (value && CFGetTypeID(value) == CFNumberGetTypeID()) {
            CFNumberGetValue((CFNumberRef)value, kCFNumberSInt64Type, &spaceID);
        }
    }
    CFRelease(spaces);
    return spaceID;
}

static bool cursor_display_index_for_space(CGSSpaceID spaceID,
                                            const ISSSpaceInfo *info,
                                            unsigned int *outIndex) {
    const CGSConnectionID connection = CGSMainConnectionID();
    CFArrayRef displays = CGSCopyManagedDisplaySpaces(connection, NULL);
    if (!displays) return false;

    bool found = false;
    for (CFIndex i = 0; i < CFArrayGetCount(displays) && !found; ++i) {
        CFTypeRef displayValue = CFArrayGetValueAtIndex(displays, i);
        if (!displayValue || CFGetTypeID(displayValue) != CFDictionaryGetTypeID()) continue;
        CFDictionaryRef display = (CFDictionaryRef)displayValue;
        CFStringRef identifier = (CFStringRef)CFDictionaryGetValue(
            display, CFSTR("Display Identifier"));
        if (!identifier || CFGetTypeID(identifier) != CFStringGetTypeID()) continue;
        char displayID[sizeof(info->displayID)] = {0};
        if (!CFStringGetCString(identifier, displayID, sizeof(displayID),
                                kCFStringEncodingUTF8)
            || strcmp(displayID, info->displayID) != 0) continue;

        CFArrayRef spaces = (CFArrayRef)CFDictionaryGetValue(display, CFSTR("Spaces"));
        if (!spaces || CFGetTypeID(spaces) != CFArrayGetTypeID()) break;
        unsigned int index = 0;
        for (CFIndex j = 0; j < CFArrayGetCount(spaces); ++j) {
            CFTypeRef spaceValue = CFArrayGetValueAtIndex(spaces, j);
            if (!spaceValue || CFGetTypeID(spaceValue) != CFDictionaryGetTypeID()) continue;
            CFNumberRef idNumber = (CFNumberRef)CFDictionaryGetValue(
                (CFDictionaryRef)spaceValue, CFSTR("id64"));
            if (!idNumber || CFGetTypeID(idNumber) != CFNumberGetTypeID()) continue;
            CGSSpaceID candidate = 0;
            if (!CFNumberGetValue(idNumber, kCFNumberSInt64Type, &candidate)) continue;
            if (candidate == spaceID && index < info->spaceCount) {
                *outIndex = index;
                found = true;
                break;
            }
            ++index;
        }
        break;
    }
    CFRelease(displays);
    return found;
}

static bool resolve_cmd_tab_destination(pid_t pid, unsigned int *outIndex) {
    const CFAbsoluteTime now = CFAbsoluteTimeGetCurrent();
    const bool recentShortcut =
        (lastCmdTabRelease > 0
         && now - lastCmdTabRelease <= kCmdTabActivationWindow)
        || (cmdTabPending && lastCmdTabKeyDown > 0
            && now - lastCmdTabKeyDown <= kCmdTabActivationWindow);
    cmdTabPending = false;
    lastCmdTabKeyDown = 0;
    lastCmdTabRelease = 0;
    if (pid <= 0 || !recentShortcut || !cgs_symbols_available()) return false;

    ISSCopySpacesForWindows copySpaces = copy_spaces_for_windows();
    if (!copySpaces) return false;

    ISSSpaceInfo info;
    if (!iss_get_space_info(&info) || !info.displayID[0]) return false;

    CFArrayRef windows = CGWindowListCopyWindowInfo(
        kCGWindowListOptionAll, kCGNullWindowID);
    if (!windows) return false;

    const CGSConnectionID connection = CGSMainConnectionID();
    CGSSpaceID destination = 0;
    bool ambiguous = false;
    for (CFIndex i = 0; i < CFArrayGetCount(windows); ++i) {
        CFTypeRef value = CFArrayGetValueAtIndex(windows, i);
        if (!value || CFGetTypeID(value) != CFDictionaryGetTypeID()) continue;
        CFDictionaryRef window = (CFDictionaryRef)value;
        CFNumberRef owner = (CFNumberRef)CFDictionaryGetValue(
            window, kCGWindowOwnerPID);
        CFNumberRef layer = (CFNumberRef)CFDictionaryGetValue(
            window, kCGWindowLayer);
        int32_t ownerPID = 0, windowLayer = -1;
        if (!owner || !layer || CFGetTypeID(owner) != CFNumberGetTypeID()
            || CFGetTypeID(layer) != CFNumberGetTypeID()
            || !CFNumberGetValue(owner, kCFNumberSInt32Type, &ownerPID)
            || !CFNumberGetValue(layer, kCFNumberSInt32Type, &windowLayer)
            || ownerPID != pid || windowLayer != 0) continue;

        CFNumberRef alpha = (CFNumberRef)CFDictionaryGetValue(
            window, kCGWindowAlpha);
        double opacity = 1.0;
        if (alpha && CFGetTypeID(alpha) == CFNumberGetTypeID()
            && CFNumberGetValue(alpha, kCFNumberDoubleType, &opacity)
            && opacity <= 0.0) continue;

        CFNumberRef number = (CFNumberRef)CFDictionaryGetValue(
            window, kCGWindowNumber);
        CGWindowID windowID = 0;
        if (!number || CFGetTypeID(number) != CFNumberGetTypeID()
            || !CFNumberGetValue(number, kCFNumberSInt32Type, &windowID)) continue;
        bool multipleSpaces = false;
        CGSSpaceID spaceID = single_space_for_window(
            connection, windowID, copySpaces, &multipleSpaces);
        if (multipleSpaces) {
            ambiguous = true;
            break;
        }
        if (!spaceID) continue;
        if (destination && destination != spaceID) {
            ambiguous = true;
            break;
        }
        destination = spaceID;
    }
    CFRelease(windows);

    unsigned int index = 0;
    if (ambiguous || !destination
        || !cursor_display_index_for_space(destination, &info, &index)
        || index == info.currentIndex) return false;

    *outIndex = index;
    return true;
}

bool iss_follow_cmd_tab_application(pid_t pid) {
    if (async_busy()) return false;
    unsigned int index;
    // Keep the original synchronous CLI/legacy semantics and eligibility.
    return resolve_cmd_tab_destination(pid, &index)
        && iss_switch_to_index_internal(index, false, false);
}

uint64_t iss_request_follow_cmd_tab_application(pid_t pid,
                                               ISSSwitchCompletion completion) {
    if (!iss_uses_async_switching() || !pthread_main_np() || asyncDelivering) return 0;
    unsigned int index;
    if (!resolve_cmd_tab_destination(pid, &index)) return 0;
    return iss_request_switch_to_index(index, ISSSwitchSourceCmdTab, completion);
}

void iss_set_swipe_override(bool enabled) {
    if (!enabled) async_cancel(true);
    swipeOverrideEnabled = enabled;
    if (!enabled) {
        swipeTracking = false;
        swipeFired = false;
        interruptedHorizontalSwipe = false;
    }
}

void iss_set_overlay_hotkey(ISSOverlayMode mode, unsigned int keyCode,
                            uint64_t modifiers, bool enabled) {
    if (!valid_overlay_mode(mode)) return;
    overlayHotkeys[mode].enabled = enabled;
    overlayHotkeys[mode].keyCode = (CGKeyCode)keyCode;
    overlayHotkeys[mode].modifiers =
        (CGEventFlags)modifiers & kRelevantHotkeyFlags;
    if (!enabled && activeOverlayHotkey == (int)mode) activeOverlayHotkey = -1;
}

void iss_arm_overlay_menu(ISSOverlayMode mode) {
    pendingMenuOverlay = valid_overlay_mode(mode) ? mode : -1;
    menuOverlayWasTriggered = false;
}

void iss_disarm_overlay_menu(void) {
    pendingMenuOverlay = -1;
}

bool iss_take_overlay_menu_triggered(void) {
    const bool triggered = menuOverlayWasTriggered;
    menuOverlayWasTriggered = false;
    return triggered;
}

bool iss_trigger_overlay_from_event(ISSOverlayMode mode, CGEventRef event) {
    if (!valid_overlay_mode(mode) || !event) return false;
    const pid_t sourcePid = (pid_t)CGEventGetIntegerValueField(
        event, kCGEventSourceUnixProcessID);
    if (sourcePid != 0) return false;

    CGEventRef keyDown = CGEventCreateCopy(event);
    CGEventRef keyUp = CGEventCreateCopy(event);
    if (!keyDown || !keyUp) {
        if (keyDown) CFRelease(keyDown);
        if (keyUp) CFRelease(keyUp);
        return false;
    }

    const CGKeyCode keyCode = native_overlay_keycode(mode);
    CGEventSetType(keyDown, kCGEventKeyDown);
    CGEventSetIntegerValueField(keyDown, kCGKeyboardEventKeycode, keyCode);
    CGEventSetIntegerValueField(keyDown, kCGKeyboardEventAutorepeat, 0);
    CGEventSetFlags(keyDown, kNativeOverlayFlags);
    CGEventSetTimestamp(keyDown, mach_absolute_time());

    CGEventSetType(keyUp, kCGEventKeyUp);
    CGEventSetIntegerValueField(keyUp, kCGKeyboardEventKeycode, keyCode);
    CGEventSetIntegerValueField(keyUp, kCGKeyboardEventAutorepeat, 0);
    CGEventSetFlags(keyUp, kNativeOverlayFlags);
    CGEventSetTimestamp(keyUp, mach_absolute_time() + 1);

    CGEventPost(kCGSessionEventTap, keyDown);
    CGEventPost(kCGSessionEventTap, keyUp);
    CFRelease(keyDown);
    CFRelease(keyUp);
    return true;
}

void iss_set_gesture_speed(double speed) {
    gestureSpeed = speed;
}

void iss_reset_predictions(void) {
    if (predictionsDict) {
        CFDictionaryRemoveAllValues(predictionsDict);
    }
}

void iss_set_switch_callback(ISSSwitchCallback callback) {
    switchCallback = callback;
}
