// Tests the private byte parser without posting input or requiring event access.
#include <assert.h>
#include <stdio.h>
#include "../Sources/ISS/event_serialize.c"

static void put32(uint8_t *bytes, size_t offset, uint32_t value) {
    memcpy(bytes + offset, &value, 4);
}
static uint32_t get32(const uint8_t *bytes, size_t offset) {
    uint32_t value; memcpy(&value, bytes + offset, 4); return value;
}
int main(void) {
    // Queue header (28), fluid node (40), velocity node (28).
    // Offsets intentionally independent of the parser's structure declarations.
    uint8_t original[96] = {0}, bytes[100];
    put32(original, 24, 2);
    put32(original, 28, 40); put32(original, 32, 23);
    put32(original, 36, 0x04001234);
    for (size_t offset = 44; offset <= 64; offset += 4)
        put32(original, offset, 0x10000 + (uint32_t)offset);
    put32(original, 64, 0x20000);
    put32(original, 68, 28); put32(original, 72, 9);
    put32(original, 76, 0x87654321);
    for (size_t offset = 84; offset <= 92; offset += 4)
        put32(original, offset, 0xfffe0000);
    unsigned cases = 0;
    for (unsigned phase = 4; phase <= 8; phase += 4) {
        memcpy(bytes, original, 96);
        assert(iss_clear_terminal_payload(bytes, 96, phase, 123456));
        uint64_t timestamp; memcpy(&timestamp, bytes, 8); assert(timestamp == 123456);
        assert(get32(bytes, 36) == ((phase << 24) | 0x1234));
        assert(!get32(bytes, 44) && !get32(bytes, 48) && !get32(bytes, 52));
        assert(!get32(bytes, 64) && !get32(bytes, 84) && !get32(bytes, 88) && !get32(bytes, 92));
        assert(!memcmp(bytes + 56, original + 56, 8));
        assert(get32(bytes, 76) == 0x87654321); cases++;
    }
    for (size_t length = 0; length < 96; length++) {
        memcpy(bytes, original, 96);
        assert(!iss_clear_terminal_payload(bytes, length, 4, 1)); cases++;
    }
    const size_t offsets[] = {20, 24, 24, 28, 28, 32, 68, 68};
    const uint32_t values[] = {UINT32_MAX, 0, UINT32_MAX, 0, UINT32_MAX, 999, 16, UINT32_MAX};
    for (size_t i = 0; i < sizeof(offsets)/sizeof(offsets[0]); i++) {
        memcpy(bytes, original, 96); put32(bytes, offsets[i], values[i]);
        assert(!iss_clear_terminal_payload(bytes, 96, 8, 1)); cases++;
    }
    memcpy(bytes, original, 96); memset(bytes + 96, 0, 4);
    assert(!iss_clear_terminal_payload(bytes, 100, 8, 1)); cases++;
    // Header attributes remain intact and correctly shift all node offsets.
    memcpy(bytes, original, 28); put32(bytes, 20, 4); put32(bytes, 28, 0xabcdef01);
    memcpy(bytes + 32, original + 28, 68);
    assert(iss_clear_terminal_payload(bytes, 100, 8, 42));
    assert(get32(bytes, 28) == 0xabcdef01 && !get32(bytes, 68)); cases++;
    // Node order is not assumed: velocity may precede the fluid node.
    memcpy(bytes, original, 28); memcpy(bytes + 28, original + 68, 28);
    memcpy(bytes + 56, original + 28, 40);
    assert(iss_clear_terminal_payload(bytes, 96, 4, 42));
    assert(!get32(bytes, 44) && !get32(bytes, 48) && !get32(bytes, 52));
    assert(!get32(bytes, 92)); cases++;
    printf("PASS: %u neutral payload and malformed-data cases; no desktop input\n", cases);
}
