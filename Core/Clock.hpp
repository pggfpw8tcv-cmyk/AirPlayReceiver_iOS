#pragma once
#include <cstdint>
#include <limits>
#include <optional>

namespace receiver {
// UxPlay timestamps are local CLOCK_REALTIME nanoseconds, not mach host time.
// Reject discontinuities instead of queueing media seconds into the future.
inline std::optional<uint64_t> hostPresentationTime(uint64_t pts, uint64_t realtimeNow,
                                                   uint64_t hostNow, uint64_t latency) {
    const bool future = pts >= realtimeNow;
    const auto distance = future ? pts - realtimeNow : realtimeNow - pts;
    if (distance > 3000000000ULL || latency > 3000000000ULL) return {};
    if (hostNow > std::numeric_limits<uint64_t>::max() - latency) return {};
    auto target = hostNow + latency;
    if (future) {
        if (target > std::numeric_limits<uint64_t>::max() - distance) return {};
        target += distance;
    } else {
        if (distance > target) return {};
        target -= distance;
    }
    // A full second of lateness is a stale stream, not a frame to play immediately.
    if (target < hostNow && hostNow - target > 1000000000ULL) return {};
    return target;
}
}
