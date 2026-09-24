#include "PTPProbe.hpp"
#include <cerrno>
#include <sys/socket.h>
#include <netinet/in.h>
#include <unistd.h>

namespace receiver {
PTPProbeResult probePTPPorts(uint16_t eventPort, uint16_t generalPort) {
    struct Socket {
        int fd = -1;
        ~Socket() { if (fd >= 0) close(fd); }
    } sockets[2];
    const uint16_t ports[] = {eventPort, generalPort};
    for (int i = 0; i < 2; ++i) {
        sockets[i].fd = socket(AF_INET, SOCK_DGRAM, 0);
        if (sockets[i].fd < 0) return {false, ports[i], errno};
        sockaddr_in address{};
        address.sin_family = AF_INET;
        address.sin_addr.s_addr = htonl(INADDR_ANY);
        address.sin_port = htons(ports[i]);
        if (bind(sockets[i].fd, reinterpret_cast<sockaddr *>(&address), sizeof(address)) < 0)
            return {false, ports[i], errno};
    }
    return {true, 0, 0};
}
}
