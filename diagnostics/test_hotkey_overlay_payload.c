#include "event_serialize.h"

#include <ApplicationServices/ApplicationServices.h>
#include <CoreFoundation/CoreFoundation.h>
#include <mach/mach_time.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static uint16_t read_be16(const uint8_t *bytes) {
    return (uint16_t)(((uint16_t)bytes[0] << 8) | bytes[1]);
}

static uint32_t read_u32(const uint8_t *bytes) {
    uint32_t value = 0;
    memcpy(&value, bytes, sizeof(value));
    return value;
}

static uint16_t read_u16(const uint8_t *bytes) {
    uint16_t value = 0;
    memcpy(&value, bytes, sizeof(value));
    return value;
}

static int32_t read_i32(const uint8_t *bytes) {
    int32_t value = 0;
    memcpy(&value, bytes, sizeof(value));
    return value;
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

int main(void) {
    if (setenv("ISS_FORCE_EVENT_AUGMENTATION", "1", 1) != 0) return 2;

    CGEventRef event = CGEventCreate(NULL);
    if (!event) return 2;
    CGEventSetIntegerValueField(event, (CGEventField)55, 30);
    CGEventSetIntegerValueField(event, (CGEventField)110, 23);
    CGEventSetIntegerValueField(event, (CGEventField)115, 0);
    CGEventSetIntegerValueField(event, (CGEventField)123, 2);
    CGEventSetDoubleValueField(event, (CGEventField)124, 1.0);
    CGEventSetDoubleValueField(event, (CGEventField)125, 0.1);
    CGEventSetDoubleValueField(event, (CGEventField)126, 1.0);
    CGEventSetDoubleValueField(event, (CGEventField)129, 100.0);
    CGEventSetDoubleValueField(event, (CGEventField)130, 100.0);
    CGEventSetIntegerValueField(event, (CGEventField)132, 4);
    CGEventSetIntegerValueField(event, (CGEventField)134, 4);
    CGEventSetDoubleValueField(event, (CGEventField)138, 3.0);
    CGEventSetDoubleValueField(event, (CGEventField)169,
                               (double)mach_absolute_time());
    CGEventSetTimestamp(event, mach_absolute_time());

    CGEventRef prepared = iss_prepare_dock_swipe_event_for_current_os(event);
    CFRelease(event);
    if (!prepared) return 2;

    CFDataRef data = CGEventCreateData(kCFAllocatorDefault, prepared);
    CFRelease(prepared);
    if (!data) return 2;

    const uint8_t *payload = NULL;
    size_t payload_length = 0;
    if (!find_payload(data, &payload, &payload_length) ||
        payload_length != 96) {
        CFRelease(data);
        printf("FAIL: expected a 96-byte field-4205 payload\n");
        return 1;
    }

    const uint32_t event_count = read_u32(payload + 24);
    const uint32_t phase_options = read_u32(payload + 36);
    const uint16_t motion = read_u16(payload + 60);
    const int32_t progress = read_i32(payload + 64);
    const int32_t velocity_x = read_i32(payload + 84);
    const int32_t velocity_y = read_i32(payload + 88);
    CFRelease(data);

    printf("EVENT_COUNT=%u PHASE_OPTIONS=0x%08x MOTION=%u ",
           event_count, phase_options, motion);
    printf("PROGRESS=%d VELOCITY_X=%d VELOCITY_Y=%d\n",
           progress, velocity_x, velocity_y);
    if (event_count != 2 || phase_options != 0x04000000 || motion != 2 ||
        progress != 65536 || velocity_x != 6553600 ||
        velocity_y != 6553600) {
        printf("FAIL: vertical hotkey payload differs from committed profile\n");
        return 1;
    }
    printf("PASS: vertical hotkey payload commits full progress and both velocities\n");
    return 0;
}
