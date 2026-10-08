#ifndef _ISS_H
#define _ISS_H

#include <stdbool.h>
#include <stdint.h>
#include <sys/types.h>
#include <CoreFoundation/CoreFoundation.h>
#include <ApplicationServices/ApplicationServices.h>

/** @brief Initialize resources
 * @return true on success, false on failure
 */
bool iss_init(void);

/** Permission checks do not prompt. A disabled/revoked input connection is
 * fail-closed until the process is restarted; settings remain available. */
bool iss_has_event_access(void);
bool iss_is_active(void);
bool iss_input_requires_restart(void);
void iss_suspend_for_permission_change(void);

/** @brief Clean up resources */
void iss_destroy(void);

/** @brief The direction to switch spaces towards */
typedef enum {
    ISSDirectionLeft = 0,
    ISSDirectionRight = 1
} ISSDirection;

/** @brief Native macOS window overview modes. */
typedef enum {
    ISSOverlayModeMissionControl = 0,
    ISSOverlayModeAppExpose = 1
} ISSOverlayMode;

/**
 * @brief Describes the current space state for the active display.
 */
typedef struct {
    unsigned int currentIndex; /**< Zero-based index of the active space */
    unsigned int spaceCount;   /**< Total number of user-visible spaces */
    char displayID[128];       /**< UUID string of the display */
} ISSSpaceInfo;

/**
 * @brief Performs the space switch if the requested move is within bounds.
 * @param direction The direction to switch spaces towards
 * @return On macOS 27+, true only after the target Space is observed. On
 * earlier systems, true if the switch was posted. False indicates bounds,
 * posting, or confirmation failure.
 */
bool iss_switch(ISSDirection direction);

/** Asynchronous app path on all supported macOS versions. Gesture payloads
 * remain OS-specific. All calls and completions run on the main
 * thread. A nonzero ID means accepted, not completed. Zero means unavailable
 * (wrong thread, missing permissions, or reentrant submission from a completion).
 * Completions may occur before submission returns. Do not reenter ISS from a
 * completion; dispatch follow-up work to the main queue instead.
 */
typedef enum {
    ISSSwitchSourceExplicit = 0,
    ISSSwitchSourceTrackpad = 1,
    ISSSwitchSourceCmdTab = 2
} ISSSwitchSource;
typedef enum {
    ISSSwitchResultSuccess = 0,
    ISSSwitchResultAlreadyReached,
    ISSSwitchResultSuperseded,
    ISSSwitchResultCancelled,
    ISSSwitchResultInvalidTarget,
    ISSSwitchResultPostFailed,
    ISSSwitchResultTimedOut
} ISSSwitchResult;
typedef void (*ISSSwitchCompletion)(uint64_t requestID, ISSSwitchResult result);
bool iss_uses_async_switching(void);
uint64_t iss_request_switch(ISSDirection direction, ISSSwitchSource source,
                            ISSSwitchCompletion completion);
uint64_t iss_request_switch_to_index(unsigned int index, ISSSwitchSource source,
                                     ISSSwitchCompletion completion);
/** Zero also means no eligible Cmd-Tab destination; native macOS keeps control. */
uint64_t iss_request_follow_cmd_tab_application(pid_t pid,
                                               ISSSwitchCompletion completion);

/**
 * @brief Retrieves the current space info for the display where the cursor is located.
 * @param info Output pointer that receives the info struct.
 * @return true on success, false if unavailable (e.g. API failure)
 */
bool iss_get_space_info(ISSSpaceInfo *info);

/**
 * @brief Retrieves the current space info for the active menu-bar display.
 * @param info Output pointer that receives the info struct.
 * @return true on success, false if unavailable (e.g. API failure)
 */
bool iss_get_menubar_space_info(ISSSpaceInfo *info);

/**
 * @brief Determines if a move in the given direction is allowed for the info.
 * @param info Space info snapshot.
 * @param direction Desired direction to move.
 * @return true if the move is permissible.
 */
bool iss_can_move(ISSSpaceInfo info, ISSDirection direction);

/**
 * @brief Attempts to switch directly to the provided space index.
 * @param targetIndex Zero-based index for the desired space.
 * @return On macOS 27+, true only after the target Space is observed. On
 * earlier systems, true if already on target or all switches were posted.
 */
bool iss_switch_to_index(unsigned int targetIndex);

/**
 * @brief Accelerates a Cmd-Tab activation when the chosen app has windows on
 * exactly one non-visible Space on the cursor's display.
 *
 * The app selection remains macOS-owned. If the shortcut was not observed or
 * the target is ambiguous, this leaves the native transition untouched.
 */
bool iss_follow_cmd_tab_application(pid_t pid);

/**
 * @brief Enables or disables interception of trackpad horizontal swipe gestures.
 *
 * When enabled, native horizontal dock-swipe gestures are suppressed and
 * replaced with instant space switches (no sliding animation).
 * @param enabled true to intercept, false to pass gestures through normally.
 */
void iss_set_swipe_override(bool enabled);

/**
 * @brief Configures a physical keyboard shortcut that is translated in-place
 * to macOS's native overlay shortcut.
 *
 * Carbon key codes are identical to CGKeyCode values. modifiers must contain
 * CGEventFlags (command/option/control/shift), not Carbon modifier bits.
 */
void iss_set_overlay_hotkey(ISSOverlayMode mode, unsigned int keyCode,
                            uint64_t modifiers, bool enabled);

/**
 * @brief Arms the next physical menu-item mouse-up to trigger an accelerated
 * overlay gesture through the trusted event-tap proxy.
 */
void iss_arm_overlay_menu(ISSOverlayMode mode);

/** @brief Cancels a pending menu overlay trigger. */
void iss_disarm_overlay_menu(void);

/**
 * @brief Returns and clears whether the armed physical menu click already
 * triggered the requested overlay.
 */
bool iss_take_overlay_menu_triggered(void);

/**
 * @brief Toggles an overlay using a physical AppKit event as provenance.
 * Intended for menu-item actions, where the current mouse-up event is trusted
 * by WindowServer but a freshly created synthetic keyboard event is not.
 * @return true when the trusted event was accepted for posting.
 */
bool iss_trigger_overlay_from_event(ISSOverlayMode mode, CGEventRef event);

/**
 * @brief Callback invoked after any successful space switch.
 * @param newSpaceIndex Zero-based index of the space that was switched to.
 */
typedef void (*ISSSwitchCallback)(unsigned int newSpaceIndex);

/**
 * @brief Registers a callback invoked after each successful space switch.
 * @param callback Function pointer, or NULL to clear.
 */
void iss_set_switch_callback(ISSSwitchCallback callback);

/** Completed Maccelerate actions, in the order used by statistics snapshots. */
typedef enum {
    ISSStatisticSpaceSwitch = 0,
    ISSStatisticAppSwitch = 1,
    ISSStatisticMissionControl = 2,
    ISSStatisticAppExpose = 3,
    ISSStatisticOverviewGesture = 4,
    ISSStatisticActionCount = 5
} ISSStatisticAction;

enum { ISSStatisticSpeedCount = 4, ISSStatisticMotionCount = 2,
       ISSStatisticBucketCount = 40 };

/** Flat array indexed by ((action * 4 + speed) * 2 + reduceMotion).
 * Speed indices retain Fast, Faster, legacy Fastest, and Instant bins so
 * previously recorded statistics remain readable. Fastest is no longer a UI preset.
 */
typedef struct {
    uint64_t counts[ISSStatisticBucketCount];
} ISSStatisticsSnapshot;

typedef void (*ISSStatisticsDirtyCallback)(void);

/** Statistics calls and the dirty callback share the input main runloop.
 * The callback must only schedule work; do not perform disk I/O in it.
 */
void iss_statistics_set_enabled(bool enabled);
void iss_statistics_set_reduce_motion(bool enabled);
void iss_statistics_set_dirty_callback(ISSStatisticsDirtyCallback callback);
void iss_statistics_copy_snapshot(ISSStatisticsSnapshot *snapshot);
void iss_statistics_take_snapshot(ISSStatisticsSnapshot *snapshot);
void iss_statistics_reset(void);

/**
 * @brief Resets the predicted space indices so the next bounds check falls back
 * to live CGS data. Call this whenever the active space changes externally
 * (e.g. from activeSpaceDidChangeNotification).
 */
void iss_reset_predictions(void);

// MARK: - Public API

/**
 * @brief Returns true when App Exposé is currently active.
 * Detects a Dock layer-18 overlay combined with 1-2 layer-20 windows.
 */
bool iss_is_expose_active(void);

/**
 * @brief Returns true when Mission Control is currently active.
 * Detects a Dock layer-18 overlay combined with 3+ layer-20 windows.
 */
bool iss_is_mission_control_active(void);

/**
 * @brief Enables or disables experimental overlay detection.
 * When disabled, iss_is_expose_active() and iss_is_mission_control_active() always return false.
 * @param enabled true to enable detection, false to disable.
 */
void iss_set_overlay_detection_enabled(bool enabled);

/**
 * @brief Sets the gesture speed for swipe override
 * @param speed The velocity value for the gesture
 */
void iss_set_gesture_speed(double speed);

#endif /* _ISS_H */
