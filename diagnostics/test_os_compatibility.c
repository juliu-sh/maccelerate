#include "event_serialize.h"

#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>

typedef struct {
    const char *version;
    bool expects_iohid_payload;
} VersionCase;

typedef struct {
    const char *version;
    bool expects_instant_horizontal_payload;
} BuildCase;

static uint16_t read_be16(const uint8_t *bytes) {
    return (uint16_t)(((uint16_t)bytes[0] << 8) | bytes[1]);
}

static bool serialized_event_has_field(CFDataRef data, uint16_t wanted) {
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
        if (field == wanted) return true;
        offset += field_length;
    }
    return false;
}

static bool prepared_event_matches_runtime_mode(bool expects_iohid_payload) {
    CGEventRef event = CGEventCreate(NULL);
    if (!event) return false;
    CGEventSetIntegerValueField(event, (CGEventField)55, 30);
    CGEventSetIntegerValueField(event, (CGEventField)110, 23);
    CGEventSetIntegerValueField(event, (CGEventField)123, 1);
    CGEventSetIntegerValueField(event, (CGEventField)132, 2);
    CGEventSetDoubleValueField(event, (CGEventField)124, 0.25);

    CGEventRef prepared = iss_prepare_dock_swipe_event_for_current_os(event);
    CFRelease(event);
    if (!prepared) return false;
    CFDataRef data = CGEventCreateData(kCFAllocatorDefault, prepared);
    CFRelease(prepared);
    if (!data) return false;
    const bool has_payload = serialized_event_has_field(data, 4205);
    CFRelease(data);
    printf("PREPARED_EVENT_FIELD_4205=%s\n", has_payload ? "present" : "absent");
    return has_payload == expects_iohid_payload;
}

int main(void) {
    const VersionCase cases[] = {
        {"13.0", false},
        {"15.7.6", false},
        {"26", false},
        {"26.6", false},
        {"27", true},
        {"27.0", true},
        {"28.1.2", true},
        {"", false},
        {"macOS 27", false},
        {"26beta", false},
        {"27.", false},
        {"27..0", false},
    };

    bool passed = true;
    for (size_t index = 0; index < sizeof(cases) / sizeof(cases[0]); index++) {
        const bool actual = iss_product_version_requires_event_augmentation(
            cases[index].version);
        printf("VERSION=%s EXPECTED=%s ACTUAL=%s\n",
               cases[index].version[0] ? cases[index].version : "<empty>",
               cases[index].expects_iohid_payload ? "iohid" : "legacy",
               actual ? "iohid" : "legacy");
        if (actual != cases[index].expects_iohid_payload) passed = false;
    }

    const BuildCase build_cases[] = {
        {"26A5388g", false},
        {"26A5406", false},
        {"26A5406d", false},
        {"26A5406e", true},
        {"26A5406f", true},
        {"26A5407", true},
        {"26B1", true},
        {"27A1", true},
        {"25Z9999z", false},
        {"26A", false},
        {"26A5406ee", false},
        {"macOS 27", false},
    };
    for (size_t index = 0;
         index < sizeof(build_cases) / sizeof(build_cases[0]); index++) {
        const bool actual =
            iss_build_version_uses_instant_horizontal_payload(
                build_cases[index].version);
        printf("BUILD=%s EXPECTED=%s ACTUAL=%s\n",
               build_cases[index].version,
               build_cases[index].expects_instant_horizontal_payload
                   ? "instant" : "render-safe",
               actual ? "instant" : "render-safe");
        if (actual !=
            build_cases[index].expects_instant_horizontal_payload) {
            passed = false;
        }
    }

    const char *runtime_expected = getenv("ISS_EXPECT_EVENT_AUGMENTATION");
    if (runtime_expected) {
        const bool expected = runtime_expected[0] == '1';
        const bool actual = iss_requires_event_augmentation();
        printf("RUNTIME_EXPECTED=%s RUNTIME_ACTUAL=%s\n",
               expected ? "iohid" : "legacy",
               actual ? "iohid" : "legacy");
        if (actual != expected) passed = false;
        if (!prepared_event_matches_runtime_mode(expected)) passed = false;
    }

    printf("%s: macOS compatibility routing\n", passed ? "PASS" : "FAIL");
    return passed ? 0 : 1;
}
