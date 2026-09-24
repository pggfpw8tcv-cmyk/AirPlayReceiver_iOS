#pragma once
#include <cstddef>
#include <cstdint>
#include <vector>

namespace receiver {
constexpr size_t maxAccessUnit = 8 * 1024 * 1024;
struct NALView { const uint8_t *data; size_t size; };

// Views borrow input memory. Reject a whole access unit if its framing is invalid.
inline std::vector<NALView> splitAnnexB(const uint8_t *data, size_t size) {
    if (!data || size < 4 || size > maxAccessUnit) return {};
    auto prefix = [&](size_t i) -> size_t {
        if (i + 3 <= size && data[i] == 0 && data[i+1] == 0) {
            if (data[i+2] == 1) return 3;
            if (i + 4 <= size && data[i+2] == 0 && data[i+3] == 1) return 4;
        }
        return 0;
    };
    if (!prefix(0)) return {};
    std::vector<NALView> out;
    size_t cursor = 0;
    while (cursor < size) {
        size_t start = cursor + prefix(cursor);
        size_t end = start;
        while (end < size && !prefix(end)) ++end;
        if (end == start || out.size() >= 1024) return {};
        out.push_back({data + start, end - start});
        cursor = end;
    }
    return out;
}

inline std::vector<uint8_t> lengthPrefixed(const std::vector<NALView>& units) {
    std::vector<uint8_t> out;
    for (auto unit : units) {
        if (!unit.data || !unit.size || unit.size > maxAccessUnit ||
            out.size() + unit.size + 4 > maxAccessUnit) return {};
        const auto n = static_cast<uint32_t>(unit.size);
        out.insert(out.end(), {uint8_t(n >> 24), uint8_t(n >> 16), uint8_t(n >> 8), uint8_t(n)});
        out.insert(out.end(), unit.data, unit.data + unit.size);
    }
    return out;
}
}
