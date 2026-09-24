#include "MediaPacket.hpp"
#include "Clock.hpp"
#include "PTPProbe.hpp"
#include "MirrorSafety.h"
#include <cstdlib>
#include <iostream>
#include <limits>
#include <sys/socket.h>
#include <netinet/in.h>
#include <unistd.h>

#define CHECK(x) do { if (!(x)) { std::cerr << __LINE__ << ": " << #x << '\n'; std::exit(1); } } while (0)

int main() {
    CHECK(!receiver_mirror_size_valid(-1));
    CHECK(!receiver_mirror_size_valid(8 * 1024 * 1024 + 1));
    CHECK(receiver_mirror_size_valid(0)); // Keepalive headers may have no payload.
    const uint8_t truncated[] = {0,0,0};
    const uint8_t zeroNAL[] = {0,0,0,0};
    const uint8_t hugeNAL[] = {0x7f,0xff,0xff,0xff,0x65};
    const uint8_t validNAL[] = {0,0,0,2,0x65,0x80};
    CHECK(!receiver_mirror_nals_valid(truncated, sizeof(truncated), 0));
    CHECK(!receiver_mirror_nals_valid(zeroNAL, sizeof(zeroNAL), 0));
    CHECK(!receiver_mirror_nals_valid(hugeNAL, sizeof(hugeNAL), 0));
    CHECK(receiver_mirror_nals_valid(validNAL, sizeof(validNAL), 0));
    const uint8_t codec[] = {1,66,0,31,255,225,0,2,0x67,0x42,1,0,2,0x68,0xab};
    CHECK(receiver_mirror_codec_valid(codec, sizeof(codec)));
    for (size_t n = 0; n < sizeof(codec); ++n) CHECK(!receiver_mirror_codec_valid(codec, n));
    // A malformed access unit must not reach a platform decoder.
    const uint8_t frame[] = {0,0,0,1,0x67,0x42,0,0,1,0x68,0xab,0,0,0,1,0x65,0x80};
    auto units = receiver::splitAnnexB(frame, sizeof(frame));
    CHECK(units.size() == 3);
    CHECK(units[0].size == 2 && units[0].data[0] == 0x67);
    CHECK(units[2].size == 2 && units[2].data[1] == 0x80);
    auto avcc = receiver::lengthPrefixed(units);
    CHECK(avcc == std::vector<uint8_t>({0,0,0,2,0x67,0x42,0,0,0,2,0x68,0xab,0,0,0,2,0x65,0x80}));
    CHECK(receiver::splitAnnexB(nullptr, 100).empty());
    CHECK(receiver::splitAnnexB(frame, 4).empty());
    CHECK(receiver::splitAnnexB(frame + 4, 2).empty());
    const uint8_t emptyNAL[] = {0,0,1,0,0,1,0x65};
    CHECK(receiver::splitAnnexB(emptyNAL, sizeof(emptyNAL)).empty());
    CHECK(receiver::splitAnnexB(frame, receiver::maxAccessUnit + 1).empty());

    // Epoch nanoseconds cannot be used directly as host-clock seconds.
    auto target = receiver::hostPresentationTime(1000000000, 900000000, 2000000000, 250000000);
    CHECK(target && *target == 2350000000);
    CHECK(!receiver::hostPresentationTime(1, 9000000000, 2000000000, 250000000));
    CHECK(!receiver::hostPresentationTime(9000000000, 1, 2000000000, 250000000));
    CHECK(!receiver::hostPresentationTime(10, 10, std::numeric_limits<uint64_t>::max(), 1));

    // If the second bind fails, the first socket must be closed (no leaked port).
    int occupied = socket(AF_INET, SOCK_DGRAM, 0);
    CHECK(occupied >= 0);
    sockaddr_in address{}; address.sin_family = AF_INET; address.sin_addr.s_addr = htonl(INADDR_ANY);
    CHECK(bind(occupied, reinterpret_cast<sockaddr *>(&address), sizeof(address)) == 0);
    socklen_t size = sizeof(address);
    CHECK(getsockname(occupied, reinterpret_cast<sockaddr *>(&address), &size) == 0);
    auto result = receiver::probePTPPorts(0, ntohs(address.sin_port));
    CHECK(!result.available && result.error != 0 && result.failedPort == ntohs(address.sin_port));
    close(occupied);
    CHECK(receiver::probePTPPorts(0, 0).available);
    std::cout << "core tests passed\n";
}
