#include "event_serialize.h"

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#pragma pack(push, 1)
typedef struct {
    uint32_t size;
    uint32_t type;
    uint32_t options;
    uint8_t depth;
    uint8_t reserved[3];
} EventBase;

typedef struct {
    uint64_t timestamp;
    uint64_t sender_id;
    uint32_t options;
    uint32_t attribute_length;
    uint32_t event_count;
} QueueHeader;

typedef struct {
    EventBase base;
    int32_t position_x;
    int32_t position_y;
    int32_t position_z;
    uint32_t swipe_mask;
    uint16_t gesture_motion;
    uint16_t gesture_flavor;
    int32_t swipe_progress;
} FluidGesture;

typedef struct {
    EventBase base;
    int32_t velocity_x;
    int32_t velocity_y;
    int32_t velocity_z;
} VelocityEvent;
#pragma pack(pop)

static uint16_t read_be16(const uint8_t *bytes) {
    return (uint16_t)(((uint16_t)bytes[0] << 8) | bytes[1]);
}

static bool find_payload(CFDataRef data, const uint8_t **payload,
                         size_t *payload_length) {
    const uint8_t *bytes = CFDataGetBytePtr(data);
    const size_t length = (size_t)CFDataGetLength(data);
    if (length < 4 || bytes[0] != 0 || bytes[1] != 0 ||
        bytes[2] != 0 || bytes[3] != 2) return false;

    size_t offset = 4;
    while (offset + 4 <= length) {
        const uint16_t size = read_be16(bytes + offset);
        const uint16_t tag_and_field = read_be16(bytes + offset + 2);
        const uint16_t field = tag_and_field & 0x3fff;
        const uint8_t tag = (uint8_t)(tag_and_field >> 14);
        offset += 4;
        size_t field_length = 0;
        if (tag == 0) field_length = size == 1 ? 8 : size;
        else if (tag == 1 || tag == 3) field_length = (size_t)size * 4;
        else return false;
        if (offset + field_length > length) return false;
        if (field == 4205) {
            *payload = bytes + offset;
            *payload_length = field_length;
            return true;
        }
        offset += field_length;
    }
    return false;
}

static bool verify_policy(const char *force_value,
                          int32_t expected_progress,
                          int32_t expected_velocity) {
    setenv("ISS_FORCE_EVENT_AUGMENTATION", "1", 1);
    setenv("ISS_FORCE_INSTANT_HORIZONTAL_PAYLOAD", force_value, 1);

    CGEventRef event = CGEventCreate(NULL);
    if (!event) return false;
    CGEventSetIntegerValueField(event, (CGEventField)55, 30);
    CGEventSetIntegerValueField(event, (CGEventField)110, 23);
    CGEventSetIntegerValueField(event, (CGEventField)123, 1);
    CGEventSetIntegerValueField(event, (CGEventField)132, 4);
    CGEventSetDoubleValueField(event, (CGEventField)124, 0.000016);
    CGEventSetDoubleValueField(event, (CGEventField)125, 0.1);
    CGEventSetDoubleValueField(event, (CGEventField)129, 100.0);

    CGEventRef prepared = iss_prepare_dock_swipe_event_for_current_os(event);
    CFRelease(event);
    if (!prepared) return false;

    const double outer_progress = CGEventGetDoubleValueField(
        prepared, (CGEventField)124);
    const double outer_velocity = CGEventGetDoubleValueField(
        prepared, (CGEventField)129);
    CFDataRef data = CGEventCreateData(kCFAllocatorDefault, prepared);
    CFRelease(prepared);
    if (!data) return false;

    const uint8_t *payload = NULL;
    size_t payload_length = 0;
    const bool found = find_payload(data, &payload, &payload_length);
    bool matches = false;
    if (found && payload_length >= sizeof(QueueHeader) +
            sizeof(FluidGesture) + sizeof(VelocityEvent)) {
        FluidGesture fluid;
        VelocityEvent velocity;
        memcpy(&fluid, payload + sizeof(QueueHeader), sizeof(fluid));
        memcpy(&velocity,
               payload + sizeof(QueueHeader) + sizeof(FluidGesture),
               sizeof(velocity));
        matches = fluid.gesture_motion == 1 &&
            fluid.swipe_progress == expected_progress &&
            velocity.velocity_x == expected_velocity &&
            fabs(outer_progress - 0.000016) < 0.000001 &&
            fabs(outer_velocity - 100.0) < 0.001;
        printf("FORCE=%s MOTION=%u RAW_PROGRESS=%d RAW_VELOCITY=%d "
               "OUTER_PROGRESS=%.6f OUTER_VELOCITY=%.1f\n",
               force_value, fluid.gesture_motion, fluid.swipe_progress,
               velocity.velocity_x,
               outer_progress, outer_velocity);
    }
    CFRelease(data);
    return matches;
}

int main(void) {
    const bool render_safe = verify_policy("0", 1, 100 * 65536);
    const bool instant = verify_policy("1", 1 << 16, 400 * 65536);
    printf("%s: horizontal payload policy\n",
           render_safe && instant ? "PASS" : "FAIL");
    return render_safe && instant ? 0 : 1;
}
