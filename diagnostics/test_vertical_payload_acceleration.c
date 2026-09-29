#include <ApplicationServices/ApplicationServices.h>
#include <CoreFoundation/CoreFoundation.h>

#include <fcntl.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

#include "event_serialize.h"

static uint16_t read_be16(const uint8_t *bytes) {
    return (uint16_t)(((uint16_t)bytes[0] << 8) | bytes[1]);
}

static int32_t read_i32(const uint8_t *bytes) {
    int32_t value = 0;
    memcpy(&value, bytes, sizeof(value));
    return value;
}

static bool payload_progress(CFDataRef data, int32_t *progress) {
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
        if (field == 4205 && field_length >= 68) {
            *progress = read_i32(bytes + offset + 64);
            return true;
        }
        offset += field_length;
    }
    return false;
}

static CFDataRef read_file(const char *path) {
    const int descriptor = open(path, O_RDONLY);
    if (descriptor < 0) return NULL;
    struct stat info;
    if (fstat(descriptor, &info) != 0 || info.st_size <= 0) {
        close(descriptor);
        return NULL;
    }
    uint8_t *bytes = malloc((size_t)info.st_size);
    if (!bytes) {
        close(descriptor);
        return NULL;
    }
    const ssize_t count = read(descriptor, bytes, (size_t)info.st_size);
    close(descriptor);
    if (count != info.st_size) {
        free(bytes);
        return NULL;
    }
    return CFDataCreateWithBytesNoCopy(kCFAllocatorDefault, bytes,
                                       (CFIndex)info.st_size,
                                       kCFAllocatorMalloc);
}

int main(int argc, char **argv) {
    if (argc != 3) {
        fprintf(stderr, "Usage: %s EVENT_FILE MULTIPLIER\n", argv[0]);
        return 64;
    }
    const double multiplier = strtod(argv[2], NULL);
    if (multiplier <= 1.0) return 64;

    CFDataRef original_data = read_file(argv[1]);
    if (!original_data) return 2;
    CGEventRef event = CGEventCreateFromData(kCFAllocatorDefault,
                                              original_data);
    if (!event) {
        CFRelease(original_data);
        return 2;
    }

    int32_t payload_before = 0;
    if (!payload_progress(original_data, &payload_before)) return 2;
    const double outer_before = CGEventGetDoubleValueField(
        event, (CGEventField)124);

    CGEventRef accelerated = iss_accelerate_vertical_dock_swipe_event(
        event, multiplier, 100.0);
    if (!accelerated) {
        fprintf(stderr, "FAIL: accelerator rejected captured event\n");
        return 2;
    }

    CFDataRef mutated_data = CGEventCreateData(
        kCFAllocatorDefault, accelerated);
    int32_t payload_after = 0;
    if (!mutated_data || !payload_progress(mutated_data, &payload_after)) {
        return 2;
    }
    const double outer_after = CGEventGetDoubleValueField(
        accelerated, (CGEventField)124);

    const int64_t source_pid_before = CGEventGetIntegerValueField(
        event, kCGEventSourceUnixProcessID);
    const int64_t source_pid_after = CGEventGetIntegerValueField(
        accelerated, kCGEventSourceUnixProcessID);

    printf("OUTER_BEFORE=%.9f OUTER_AFTER=%.9f ", outer_before, outer_after);
    printf("PAYLOAD_BEFORE=%d PAYLOAD_AFTER=%d MULTIPLIER=%.1f\n",
           payload_before, payload_after, multiplier);
    printf("SOURCE_PID_BEFORE=%lld SOURCE_PID_AFTER=%lld\n",
           (long long)source_pid_before, (long long)source_pid_after);

    CFRelease(mutated_data);
    CFRelease(accelerated);
    CFRelease(event);
    CFRelease(original_data);

    int64_t expected = (int64_t)((double)payload_before * multiplier);
    if (expected > 65536) expected = 65536;
    if (expected < -65536) expected = -65536;
    if (payload_after != expected || source_pid_after != source_pid_before) {
        printf("FAIL: field-4205 progress or physical provenance differs\n");
        return 1;
    }
    printf("PASS: field-4205 progress and physical provenance accelerated together\n");
    return 0;
}
