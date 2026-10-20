#pragma once
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#define RECEIVER_MIRROR_MAX_PAYLOAD (8 * 1024 * 1024)

/* Payload size of a mirror packet. 0 is valid (keepalive without payload). */
static inline bool receiver_mirror_size_valid(int64_t size) {
    return size >= 0 && size <= RECEIVER_MIRROR_MAX_PAYLOAD;
}

/* Checks 4-byte length-prefixed NAL units starting at `offset`.
   Every length must be > 0 and fit into the remaining data. */
static inline bool receiver_mirror_nals_valid(const uint8_t *data, size_t size, size_t offset) {
    if (!data || size == 0 || size > (size_t)RECEIVER_MIRROR_MAX_PAYLOAD || offset >= size) return false;
    size_t pos = offset;
    while (pos < size) {
        if (size - pos < 4) return false;
        uint32_t len = ((uint32_t)data[pos] << 24) | ((uint32_t)data[pos + 1] << 16) |
                       ((uint32_t)data[pos + 2] << 8) | (uint32_t)data[pos + 3];
        pos += 4;
        if (len == 0 || len > size - pos) return false;
        pos += len;
    }
    return true;
}

/* Checks an AVCDecoderConfigurationRecord (avcC): version 1, at least one
   SPS and one PPS, all lengths inside the buffer. */
static inline bool receiver_mirror_codec_valid(const uint8_t *data, size_t size) {
    if (!data || size < 7 || size > (size_t)RECEIVER_MIRROR_MAX_PAYLOAD || data[0] != 1) return false;
    size_t pos = 5;
    unsigned spsCount = data[pos++] & 0x1f;
    if (spsCount == 0) return false;
    for (unsigned i = 0; i < spsCount; ++i) {
        if (size - pos < 2) return false;
        size_t len = ((size_t)data[pos] << 8) | data[pos + 1];
        pos += 2;
        if (len == 0 || len > size - pos) return false;
        pos += len;
    }
    if (pos >= size) return false;
    unsigned ppsCount = data[pos++];
    if (ppsCount == 0) return false;
    for (unsigned i = 0; i < ppsCount; ++i) {
        if (size - pos < 2) return false;
        size_t len = ((size_t)data[pos] << 8) | data[pos + 1];
        pos += 2;
        if (len == 0 || len > size - pos) return false;
        pos += len;
    }
    return true;
}

#ifdef __cplusplus
}
#endif
