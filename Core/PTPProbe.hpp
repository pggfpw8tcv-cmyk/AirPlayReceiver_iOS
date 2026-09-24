#pragma once
#include <cstdint>
namespace receiver {
struct PTPProbeResult { bool available; uint16_t failedPort; int error; };
// Checks exclusive IPv4 binds only. Does NOT establish clock synchronization.
PTPProbeResult probePTPPorts(uint16_t eventPort = 319, uint16_t generalPort = 320);
}
