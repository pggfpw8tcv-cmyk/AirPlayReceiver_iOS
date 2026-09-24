// Test-only discovery backend: exercise real UxPlay sockets without advertising on the LAN.
#include "raop.h"
#include <cstdlib>
#include <cstring>
#include <iostream>
#include <string>
#include <sys/socket.h>
#include <arpa/inet.h>
#include <unistd.h>
extern "C" {
void *dnssd_private_init(dnssd_t *, int *error) { *error = 0; return std::malloc(1); }
void dnssd_private_destroy(void *p) { std::free(p); }
int dnssd_register_raop(dnssd_t *, unsigned short) { return 0; }
int dnssd_register_airplay(dnssd_t *, unsigned short) { return 0; }
void dnssd_unregister_raop(dnssd_t *) {}
void dnssd_unregister_airplay(dnssd_t *) {}
const char *dnssd_get_raop_txt(dnssd_t *, int *n) { *n = 0; return ""; }
const char *dnssd_get_airplay_txt(dnssd_t *, int *n) { *n = 0; return ""; }
}
#define CHECK(x) do { if (!(x)) { std::cerr << __LINE__ << ": " << #x << '\n'; std::exit(1); } } while (0)
int main() {
    raop_callbacks_t callbacks{};
    callbacks.audio_process = [](void *, raop_ntp_t *, audio_decode_struct *) {};
    callbacks.video_process = [](void *, raop_ntp_t *, video_decode_struct *) {};
    callbacks.video_flush = [](void *) {};
    callbacks.audio_set_client_volume = [](void *) -> double { return 0; };
    // Partial initialization must be destructible after a failed key/socket setup.
    raop_t *partial = raop_init(&callbacks);
    CHECK(partial);
    raop_destroy(partial);

    char path[] = "/tmp/receiver-core-test-XXXXXX";
    CHECK(mkdtemp(path));
    const auto key = std::string(path) + "/key";
    const char mac[] = {2,0,0,0,0,1};
    int error = 0;
    auto *dns = dnssd_init("Test Receiver", 13, mac, 6, 0, &error);
    CHECK(dns && !error);
    for (int iteration = 0; iteration < 2; ++iteration) {
        auto *server = raop_init(&callbacks);
        CHECK(server);
        raop_set_log_level(server, 0);
        CHECK(raop_init2(server, 0, "02:00:00:00:00:01", key.c_str()) == 0);
        raop_set_dnssd(server, dns);
        unsigned short port = 0;
        CHECK(raop_start_httpd(server, &port) > 0 && port);
        raop_set_port(server, port);
        int fd = socket(AF_INET, SOCK_STREAM, 0);
        CHECK(fd >= 0);
        timeval timeout{3, 0};
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, sizeof(timeout));
        sockaddr_in peer{}; peer.sin_family = AF_INET; peer.sin_port = htons(port);
        peer.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
        CHECK(connect(fd, reinterpret_cast<sockaddr *>(&peer), sizeof(peer)) == 0);
        const std::string request = "OPTIONS * RTSP/1.0\r\nCSeq: 1\r\n\r\n";
        CHECK(send(fd, request.data(), request.size(), 0) == (ssize_t)request.size());
        std::string response;
        char buffer[4096];
        while (response.find("\r\n\r\n") == std::string::npos) {
            auto count = recv(fd, buffer, sizeof(buffer), 0);
            CHECK(count > 0); response.append(buffer, count);
            CHECK(response.size() <= 65536);
        }
        CHECK(response.find("200 OK") != std::string::npos);
        CHECK(response.find("SETUP") != std::string::npos);
        close(fd);
        raop_destroy(server);
    }
    dnssd_destroy(dns);
    unlink(key.c_str()); rmdir(path);
    std::cout << "upstream initialization, RTSP and restart passed\n";
}
