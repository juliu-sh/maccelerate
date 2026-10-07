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

/** Use the preset and trackpad-recovery path on macOS 27 and later.
 * Selection depends on the product's major version, not an Apple build string.
 */
bool iss_uses_modern_horizontal_switching(void);

/** Translate a requested horizontal velocity to the current OS's range.
 * macOS 13–26 is unchanged. On macOS 27 and later the three preset velocities
 * become 1000, 4000, and 9999, independently of the minor or patch version.
 */
double iss_horizontal_switch_velocity(double requested_velocity);

/** Copy a consumed physical terminal, neutralizing both outer fields and every
 * existing field-4205 payload in place. Preserves unrelated HID metadata.
 * Phase must be Ended (4) or Cancelled (8). Malformed payloads fail closed.
 * The retained result is marked after reconstruction for safe cleanup posting.
 */
CGEventRef iss_copy_neutral_gesture_terminal(CGEventRef event, unsigned int phase);
bool iss_is_neutral_gesture_terminal(CGEventRef event);

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
