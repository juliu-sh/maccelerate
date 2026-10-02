#ifndef EVENT_SERIALIZE_H
#define EVENT_SERIALIZE_H

#include <ApplicationServices/ApplicationServices.h>
#include <stdbool.h>

/**
 * @brief Augments a synthetic dock-swipe CGEvent with the raw IOHID payload
 * that macOS 27 requires to recognize synthetic trackpad swipe gestures.
 *
 * The returned event is retained and the caller is responsible for releasing it.
 *
 * @param event A synthetic dock-swipe CGEvent with the public gesture fields set.
 * @return A retained, augmented CGEventRef, or NULL on failure.
 */
CGEventRef iss_augment_dock_swipe_event(CGEventRef event);

/**
 * @brief Returns a retained dock-swipe event prepared for the running OS.
 *
 * macOS 13–26 receives an ordinary copy. macOS 27+ receives a copy carrying
 * the raw field-4205 IOHID payload.
 */
CGEventRef iss_prepare_dock_swipe_event_for_current_os(CGEventRef event);

/**
 * @brief Returns a copy of a physical vertical dock-swipe event whose outer
 * gesture fields and embedded macOS 27 IOHID payload are accelerated together.
 *
 * macOS 27 reads field 4205 from physical dock-swipe events. Mutating only the
 * public CGEvent fields therefore has no visible effect. This function keeps
 * the captured payload metadata intact and changes only vertical position,
 * progress, and terminal velocity.
 *
 * The returned event is retained and the caller is responsible for releasing it.
 *
 * @param event A physical vertical dock-swipe event containing field 4205.
 * @param multiplier Progress multiplier. Values below 1 are treated as 1.
 * @param terminal_velocity Absolute velocity used for an ended event.
 * @return A retained accelerated event, or NULL if the payload is unsupported.
 */
CGEventRef iss_accelerate_vertical_dock_swipe_event(
    CGEventRef event, double multiplier, double terminal_velocity);

/**
 * @brief Returns whether a macOS product-version string selects the macOS 27
 * raw IOHID payload path.
 *
 * This pure helper is used by the runtime detector and compatibility tests.
 * Malformed or unavailable versions conservatively select the legacy path.
 */
bool iss_product_version_requires_event_augmentation(const char *version);

/**
 * @brief Returns whether an Apple build-version string selects the updated
 * horizontal animation payload introduced by macOS 27 build 26A5406e.
 *
 * Malformed versions conservatively retain the older render-safe payload.
 */
bool iss_build_version_uses_instant_horizontal_payload(const char *version);

/** The release-build velocity policy verified on macOS 27.0 / 26A428.
 * Older beta and unverified builds retain their existing behavior.
 */
bool iss_uses_release_horizontal_payload(void);

/** Translate a requested horizontal velocity to the current OS's range.
 * macOS 13–26 is unchanged. On 26A428 the three preset velocities become
 * 1000, 4000, and 9999; other macOS 27 builds retain the 100 cap.
 */
double iss_horizontal_switch_velocity(double requested_velocity);

/**
 * @brief Returns true when the running OS is macOS 27 or later.
 *
 * On these versions, synthetic dock-swipe events must carry the raw IOHID
 * payload created by iss_augment_dock_swipe_event() in order to be honored.
 *
 * For testing, set the environment variable ISS_FORCE_EVENT_AUGMENTATION=1
 * to enable augmentation on any version, or =0 to disable it.
 */
bool iss_requires_event_augmentation(void);

#endif /* EVENT_SERIALIZE_H */
