#include "HEVBridge.h"
#include <pthread.h>
#include <stdlib.h>
#include <string.h>

/*
 This translation unit is the narrow ABI boundary used by PacketTunnelProvider.
 The final build links the upstream HEV static library (HevSocks5Tunnel) and
 provides these two functions without exposing HEV implementation details to Swift.
*/

extern int hev_socks5_tunnel_main_from_str(const unsigned char *, unsigned int, int);
extern void hev_socks5_tunnel_quit(void);

static pthread_t g_thread;
static int g_running = 0;

struct hev_start_args {
    unsigned char *config;
    unsigned int length;
    int tun_fd;
};

static void *hev_thread_main(void *opaque) {
    struct hev_start_args *args = opaque;
    int rc = hev_socks5_tunnel_main_from_str(args->config, args->length, args->tun_fd);
    free(args->config);
    free(args);
    g_running = 0;
    return (void *)(intptr_t)rc;
}

int aether_hev_start(const char *config, size_t config_len, int tun_fd) {
    if (!config || config_len == 0 || tun_fd < 0 || g_running) return -1;
    struct hev_start_args *args = calloc(1, sizeof(*args));
    if (!args) return -1;
    args->config = malloc(config_len);
    if (!args->config) { free(args); return -1; }
    memcpy(args->config, config, config_len);
    args->length = (unsigned int)config_len;
    args->tun_fd = tun_fd;
    g_running = 1;
    if (pthread_create(&g_thread, NULL, hev_thread_main, args) != 0) {
        g_running = 0;
        free(args->config);
        free(args);
        return -1;
    }
    pthread_detach(g_thread);
    return 0;
}

void aether_hev_stop(void) {
    if (g_running) hev_socks5_tunnel_quit();
}
