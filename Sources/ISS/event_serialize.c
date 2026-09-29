#include "event_serialize.h"

#include <ApplicationServices/ApplicationServices.h>
#include <CoreFoundation/CoreFoundation.h>
#include <ctype.h>
#include <errno.h>
#include <limits.h>
#include <mach/mach_time.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <sys/sysctl.h>

#pragma pack(push, 1)

typedef struct {
    uint32_t size;
    uint32_t type;
    uint32_t options;
    uint8_t depth;
    uint8_t reserved[3];
} IOHIDEventBase;

typedef struct {
    IOHIDEventBase base;
    int32_t position_x;
    int32_t position_y;
    int32_t position_z;
    uint32_t swipe_mask;
    uint16_t gesture_motion;
    uint16_t gesture_flavor;
    int32_t swipe_progress;
} IOHIDFluidTouchGestureData;

typedef struct {
    IOHIDEventBase base;
    int32_t velocity_x;
    int32_t velocity_y;
    int32_t velocity_z;
} IOHIDVelocityEventData;

typedef struct {
    uint64_t timestamp;
    uint64_t sender_id;
    uint32_t options;
    uint32_t attribute_length;
    uint32_t event_count;
} IOHIDSystemQueueElementHeader;

#pragma pack(pop)

static const uint32_t kIOHIDEventTypeVelocity = 9;
static const uint32_t kIOHIDEventTypeFluidTouchGesture = 23;
static const uint16_t kIOHIDGestureFlavorDockPrimary = 3;
static const uint16_t kCGEventRawIOHIDPayloadField = 4205;
static const double kUpdatedHorizontalVelocity = 400.0;

static const CGEventField kCGEventGestureSwipeProgress = (CGEventField)124;
static const CGEventField kCGEventGestureSwipePositionY = (CGEventField)126;
static const CGEventField kCGEventGestureSwipeVelocityX = (CGEventField)129;
static const CGEventField kCGEventGestureSwipeVelocityY = (CGEventField)130;
static const CGEventField kCGEventGesturePhase = (CGEventField)132;

static uint16_t iss_read_be16(const uint8_t *bytes) {
    return (uint16_t)(((uint16_t)bytes[0] << 8) | bytes[1]);
}

static uint32_t iss_read_u32(const uint8_t *bytes) {
    uint32_t value = 0;
    memcpy(&value, bytes, sizeof(value));
    return value;
}

static int32_t iss_read_i32(const uint8_t *bytes) {
    int32_t value = 0;
    memcpy(&value, bytes, sizeof(value));
    return value;
}

static void iss_write_i32(uint8_t *bytes, int32_t value) {
    memcpy(bytes, &value, sizeof(value));
}

static int32_t iss_scale_fixed1616(int32_t value, double multiplier,
                                   int32_t absolute_limit) {
    double scaled = (double)value * multiplier;
    if (scaled > absolute_limit) scaled = absolute_limit;
    if (scaled < -absolute_limit) scaled = -absolute_limit;
    return (int32_t)scaled;
}

static bool iss_find_serialized_field(uint8_t *bytes, size_t length,
                                      uint16_t wanted_field,
                                      uint8_t **field_bytes,
                                      size_t *field_length) {
    // CGEventCreateData format version 2 begins with 00 00 00 02.
    if (length < 4 || bytes[0] != 0 || bytes[1] != 0 ||
        bytes[2] != 0 || bytes[3] != 2) {
        return false;
    }

    size_t offset = 4;
    while (offset + 4 <= length) {
        const uint16_t size = iss_read_be16(bytes + offset);
        const uint16_t tag_and_field = iss_read_be16(bytes + offset + 2);
        const uint16_t field = tag_and_field & 0x3fff;
        const uint8_t tag = (uint8_t)(tag_and_field >> 14);
        offset += 4;

        size_t value_length = 0;
        if (tag == 0) {
            value_length = size == 1 ? 8 : size;
        } else if (tag == 1 || tag == 3) {
            value_length = (size_t)size * 4;
        } else {
            return false;
        }
        if (offset + value_length > length) return false;
        if (field == wanted_field) {
            *field_bytes = bytes + offset;
            *field_length = value_length;
            return true;
        }
        offset += value_length;
    }
    return false;
}

static int32_t iss_double_to_fixed1616(double val) {
    int32_t fixed = (int32_t)(val * 65536.0);
    if (fixed == 0 && val != 0.0) {
        return val > 0.0 ? 1 : -1;
    }
    return fixed;
}

bool iss_build_version_uses_instant_horizontal_payload(const char *version) {
    if (!version || !isdigit((unsigned char)version[0])) return false;

    errno = 0;
    char *cursor = NULL;
    const long kernel_major = strtol(version, &cursor, 10);
    if (errno != 0 || cursor == version || kernel_major < 1 ||
        kernel_major > INT_MAX || !isupper((unsigned char)*cursor)) {
        return false;
    }

    const char train = *cursor++;
    if (!isdigit((unsigned char)*cursor)) return false;
    errno = 0;
    char *build_end = NULL;
    const long build_number = strtol(cursor, &build_end, 10);
    if (errno != 0 || build_end == cursor || build_number < 0 ||
        build_number > INT_MAX) {
        return false;
    }

    char suffix = '\0';
    if (*build_end != '\0') {
        if (!islower((unsigned char)*build_end) || build_end[1] != '\0') {
            return false;
        }
        suffix = *build_end;
    }

    if (kernel_major != 26) return kernel_major > 26;
    if (train != 'A') return train > 'A';
    if (build_number != 5406) return build_number > 5406;
    return suffix >= 'e';
}

static bool iss_running_build_uses_instant_horizontal_payload(void) {
    const char *force_override = getenv(
        "ISS_FORCE_INSTANT_HORIZONTAL_PAYLOAD");
    if (force_override) return strcmp(force_override, "1") == 0;

    static int cached_result = -1;
    if (cached_result != -1) return cached_result == 1;

    char version[32] = {0};
    size_t size = sizeof(version);
    if (sysctlbyname("kern.osversion", version, &size, NULL, 0) != 0) {
        cached_result = 0;
        return false;
    }
    version[sizeof(version) - 1] = '\0';
    cached_result = iss_build_version_uses_instant_horizontal_payload(version)
        ? 1 : 0;
    return cached_result == 1;
}

static uint8_t *iss_generate_iohid_payload(CGEventRef event, size_t *out_length) {
    int64_t phase = CGEventGetIntegerValueField(event, (CGEventField)132);
    int64_t motion = CGEventGetIntegerValueField(event, (CGEventField)123);
    double progress = CGEventGetDoubleValueField(event, (CGEventField)124);
    double pos_x = CGEventGetDoubleValueField(event, (CGEventField)125);
    double pos_y = CGEventGetDoubleValueField(event, (CGEventField)126);
    double vel_x = CGEventGetDoubleValueField(event, (CGEventField)129);
    double vel_y = CGEventGetDoubleValueField(event, (CGEventField)130);
    int64_t swipe_mask = CGEventGetIntegerValueField(event, (CGEventField)115);

    // Build 26A5406e no longer derives instant horizontal animation from the
    // former epsilon/100 raw values. Keep the outer CGEvent fields unchanged
    // for Dock routing, but commit full progress and the verified terminal
    // velocity inside field 4205. Older macOS 27 builds retain the render-safe
    // payload validated on 26A5388g.
    if (motion == 1 &&
        iss_running_build_uses_instant_horizontal_payload()) {
        if (progress != 0.0) progress = progress < 0.0 ? -1.0 : 1.0;
        if (phase == 4 && vel_x != 0.0) {
            vel_x = vel_x < 0.0
                ? -kUpdatedHorizontalVelocity : kUpdatedHorizontalVelocity;
        }
    }

    bool include_velocity = (vel_x != 0.0 || vel_y != 0.0 || phase == 4);
    uint32_t event_count = include_velocity ? 2 : 1;
    size_t payload_length = sizeof(IOHIDSystemQueueElementHeader) + sizeof(IOHIDFluidTouchGestureData);
    if (include_velocity) {
        payload_length += sizeof(IOHIDVelocityEventData);
    }

    uint8_t *payload = (uint8_t *)malloc(payload_length);
    if (!payload) {
        return NULL;
    }
    memset(payload, 0, payload_length);

    IOHIDSystemQueueElementHeader *header = (IOHIDSystemQueueElementHeader *)payload;
    uint64_t timestamp = CGEventGetTimestamp(event);
    if (timestamp == 0) {
        timestamp = mach_absolute_time();
    }
    header->timestamp = timestamp;
    header->sender_id = 0;
    header->options = 0;
    header->attribute_length = 0;
    header->event_count = event_count;

    IOHIDFluidTouchGestureData *fluid = (IOHIDFluidTouchGestureData *)(payload + sizeof(IOHIDSystemQueueElementHeader));
    fluid->base.size = sizeof(IOHIDFluidTouchGestureData);
    fluid->base.type = kIOHIDEventTypeFluidTouchGesture;
    fluid->base.options = (uint32_t)((phase & 0xFF) << 24);
    fluid->base.depth = 0;
    fluid->position_x = iss_double_to_fixed1616(pos_x);
    fluid->position_y = iss_double_to_fixed1616(pos_y);
    fluid->position_z = 0;
    fluid->swipe_mask = (uint32_t)swipe_mask;
    fluid->gesture_motion = (uint16_t)motion;
    fluid->gesture_flavor = kIOHIDGestureFlavorDockPrimary;
    fluid->swipe_progress = iss_double_to_fixed1616(progress);

    if (include_velocity) {
        IOHIDVelocityEventData *velocity = (IOHIDVelocityEventData *)(payload + sizeof(IOHIDSystemQueueElementHeader) + sizeof(IOHIDFluidTouchGestureData));
        velocity->base.size = sizeof(IOHIDVelocityEventData);
        velocity->base.type = kIOHIDEventTypeVelocity;
        velocity->base.options = 0;
        velocity->base.depth = 1;
        velocity->velocity_x = iss_double_to_fixed1616(vel_x);
        velocity->velocity_y = iss_double_to_fixed1616(vel_y);
        velocity->velocity_z = 0;
    }

    *out_length = payload_length;
    return payload;
}

CGEventRef iss_augment_dock_swipe_event(CGEventRef event) {
    if (!event) {
        return NULL;
    }

    CFDataRef data = CGEventCreateData(kCFAllocatorDefault, event);
    if (!data) {
        return NULL;
    }

    const uint8_t *bytes = CFDataGetBytePtr(data);
    CFIndex length = CFDataGetLength(data);

    // Verify format version 2 (first 4 bytes: 00 00 00 02)
    if (length < 4 || bytes[0] != 0 || bytes[1] != 0 || bytes[2] != 0 || bytes[3] != 2) {
        CFRelease(data);
        return NULL;
    }

    size_t payload_length = 0;
    uint8_t *payload = iss_generate_iohid_payload(event, &payload_length);
    if (!payload) {
        CFRelease(data);
        return NULL;
    }

    // Allocate buffer for original data + 4-byte Tag + payload
    size_t new_length = (size_t)length + 4 + payload_length;
    uint8_t *new_bytes = (uint8_t *)malloc(new_length);
    if (!new_bytes) {
        free(payload);
        CFRelease(data);
        return NULL;
    }

    // Copy original event data
    memcpy(new_bytes, bytes, length);

    // Append 4-byte Tag:
    // Word 1: Size Words (payload_length in big-endian)
    new_bytes[length] = (uint8_t)((payload_length >> 8) & 0xFF);
    new_bytes[length + 1] = (uint8_t)(payload_length & 0xFF);
    // Word 2: (Type << 14) | Field ID (4205 in big-endian)
    new_bytes[length + 2] = (uint8_t)((4205 >> 8) & 0xFF);
    new_bytes[length + 3] = (uint8_t)(4205 & 0xFF);

    // Append Payload
    memcpy(new_bytes + length + 4, payload, payload_length);

    free(payload);
    CFRelease(data);

    CFDataRef new_data = CFDataCreate(kCFAllocatorDefault, new_bytes, (CFIndex)new_length);
    free(new_bytes);
    if (!new_data) {
        return NULL;
    }

    CGEventRef result = CGEventCreateFromData(kCFAllocatorDefault, new_data);
    CFRelease(new_data);
    return result;
}

CGEventRef iss_prepare_dock_swipe_event_for_current_os(CGEventRef event) {
    if (!event) return NULL;
    if (iss_requires_event_augmentation()) {
        return iss_augment_dock_swipe_event(event);
    }
    return CGEventCreateCopy(event);
}

CGEventRef iss_accelerate_vertical_dock_swipe_event(
    CGEventRef event, double multiplier, double terminal_velocity) {
    if (!event) return NULL;
    if (multiplier < 1.0) multiplier = 1.0;
    if (terminal_velocity < 0.0) terminal_velocity = -terminal_velocity;

    const int64_t phase = CGEventGetIntegerValueField(
        event, kCGEventGesturePhase);
    if (phase != 2 && phase != 4) return NULL;

    CFDataRef data = CGEventCreateData(kCFAllocatorDefault, event);
    if (!data) return NULL;

    const CFIndex data_length = CFDataGetLength(data);
    if (data_length <= 0) {
        CFRelease(data);
        return NULL;
    }
    uint8_t *bytes = (uint8_t *)malloc((size_t)data_length);
    if (!bytes) {
        CFRelease(data);
        return NULL;
    }
    memcpy(bytes, CFDataGetBytePtr(data), (size_t)data_length);
    CFRelease(data);

    uint8_t *payload = NULL;
    size_t payload_length = 0;
    const size_t fluid_offset = sizeof(IOHIDSystemQueueElementHeader);
    if (!iss_find_serialized_field(
            bytes, (size_t)data_length, kCGEventRawIOHIDPayloadField,
            &payload, &payload_length) ||
        payload_length < fluid_offset + sizeof(IOHIDFluidTouchGestureData) ||
        iss_read_u32(payload + fluid_offset) !=
            sizeof(IOHIDFluidTouchGestureData) ||
        iss_read_u32(payload + fluid_offset + sizeof(uint32_t)) !=
            kIOHIDEventTypeFluidTouchGesture) {
        free(bytes);
        return NULL;
    }

    // A vertical overlay has a single committed destination at +/-1. Scaling
    // beyond that can leave WindowServer between desktop and overlay states.
    const int32_t one_gesture = 1 << 16;
    const size_t position_y_offset = fluid_offset +
        offsetof(IOHIDFluidTouchGestureData, position_y);
    const size_t progress_offset = fluid_offset +
        offsetof(IOHIDFluidTouchGestureData, swipe_progress);
    iss_write_i32(
        payload + position_y_offset,
        iss_scale_fixed1616(
            iss_read_i32(payload + position_y_offset), multiplier,
            one_gesture));
    iss_write_i32(
        payload + progress_offset,
        iss_scale_fixed1616(
            iss_read_i32(payload + progress_offset), multiplier,
            one_gesture));

    if (phase == 4 &&
        payload_length >= fluid_offset + sizeof(IOHIDFluidTouchGestureData) +
            sizeof(IOHIDVelocityEventData)) {
        const size_t velocity_offset =
            fluid_offset + sizeof(IOHIDFluidTouchGestureData);
        if (iss_read_u32(payload + velocity_offset) ==
                sizeof(IOHIDVelocityEventData) &&
            iss_read_u32(payload + velocity_offset + sizeof(uint32_t)) ==
                kIOHIDEventTypeVelocity) {
            const size_t velocity_x_offset = velocity_offset +
                offsetof(IOHIDVelocityEventData, velocity_x);
            const size_t velocity_y_offset = velocity_offset +
                offsetof(IOHIDVelocityEventData, velocity_y);
            const int32_t old_velocity =
                iss_read_i32(payload + velocity_y_offset);
            const int32_t fixed_velocity =
                iss_double_to_fixed1616(terminal_velocity);
            const int32_t signed_velocity =
                old_velocity < 0 ? -fixed_velocity : fixed_velocity;
            iss_write_i32(payload + velocity_x_offset, signed_velocity);
            iss_write_i32(payload + velocity_y_offset, signed_velocity);
        }
    }

    CFDataRef changed_data = CFDataCreateWithBytesNoCopy(
        kCFAllocatorDefault, bytes, data_length, kCFAllocatorMalloc);
    if (!changed_data) {
        free(bytes);
        return NULL;
    }
    CGEventRef result = CGEventCreateFromData(
        kCFAllocatorDefault, changed_data);
    CFRelease(changed_data);
    if (!result) return NULL;

    // Rebuilding a CGEvent changes its visible source PID to this process.
    // Restore the captured HID source and timestamp while preserving the raw
    // payload's sender ID and all other physical metadata byte-for-byte.
    const int64_t source_pid = CGEventGetIntegerValueField(
        event, kCGEventSourceUnixProcessID);
    CGEventSetIntegerValueField(
        result, kCGEventSourceUnixProcessID, source_pid);
    CGEventSetTimestamp(result, CGEventGetTimestamp(event));

    const double progress = CGEventGetDoubleValueField(
        event, kCGEventGestureSwipeProgress);
    const double position_y = CGEventGetDoubleValueField(
        event, kCGEventGestureSwipePositionY);
    double accelerated_progress = progress * multiplier;
    double accelerated_position_y = position_y * multiplier;
    if (accelerated_progress > 1.0) accelerated_progress = 1.0;
    if (accelerated_progress < -1.0) accelerated_progress = -1.0;
    if (accelerated_position_y > 1.0) accelerated_position_y = 1.0;
    if (accelerated_position_y < -1.0) accelerated_position_y = -1.0;
    CGEventSetDoubleValueField(
        result, kCGEventGestureSwipeProgress, accelerated_progress);
    CGEventSetDoubleValueField(
        result, kCGEventGestureSwipePositionY, accelerated_position_y);

    if (phase == 4) {
        const double old_velocity = CGEventGetDoubleValueField(
            event, kCGEventGestureSwipeVelocityY);
        const double signed_velocity =
            old_velocity < 0.0 ? -terminal_velocity : terminal_velocity;
        CGEventSetDoubleValueField(
            result, kCGEventGestureSwipeVelocityX, signed_velocity);
        CGEventSetDoubleValueField(
            result, kCGEventGestureSwipeVelocityY, signed_velocity);
    }
    return result;
}

bool iss_product_version_requires_event_augmentation(const char *version) {
    if (!version || version[0] == '\0') return false;

    errno = 0;
    char *end = NULL;
    const long major = strtol(version, &end, 10);
    if (errno != 0 || end == version || major < 1 || major > INT_MAX) {
        return false;
    }
    if (*end != '\0' && *end != '.') return false;

    // Product versions contain non-empty decimal components. Reject labels or
    // malformed values instead of accidentally selecting a compatibility path.
    bool expects_digit = false;
    for (const char *cursor = end; *cursor != '\0'; cursor++) {
        if (*cursor == '.') {
            if (expects_digit) return false;
            expects_digit = true;
        } else if (isdigit((unsigned char)*cursor)) {
            expects_digit = false;
        } else {
            return false;
        }
    }
    if (expects_digit) return false;
    return major >= 27;
}

bool iss_requires_event_augmentation(void) {
    static int cached_result = -1;
    if (cached_result != -1) {
        return cached_result;
    }

    const char *force_override = getenv("ISS_FORCE_EVENT_AUGMENTATION");
    if (force_override) {
        cached_result = (strcmp(force_override, "1") == 0) ? 1 : 0;
        return cached_result;
    }

    char version[32];
    size_t size = sizeof(version);
    if (sysctlbyname("kern.osproductversion", version, &size, NULL, 0) != 0) {
        cached_result = 0;
        return false;
    }

    cached_result = iss_product_version_requires_event_augmentation(version)
        ? 1 : 0;
    return cached_result;
}
