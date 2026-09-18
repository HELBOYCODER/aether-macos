#include "HEVBridge.h"
#include <pthread.h>
#include <stdlib.h>
#include <string.h>
#include <stdatomic.h>
#include <stdint.h>

extern int hev_socks5_tunnel_main_from_str(const unsigned char *, unsigned int, int);
extern void hev_socks5_tunnel_quit(void);

static pthread_t g_thread;
static _Atomic int g_running = 0;

struct hev_start_args {
    unsigned char *config;
    unsigned int length;
    int tun_fd;
};

static void *hev_thread_main(void *opaque) {
    struct hev_start_args *args = opaque;
    int rc = hev_socks5_tunnel_main_from_str(
        args->config, args->length, args->tun_fd
    );
    free(args->config);
    free(args);
    atomic_store(&g_running, 0);
    return (void *)(intptr_t)rc;
}

int aether_hev_start(const char *config, size_t config_len, int tun_fd) {
    if (!config || config_len == 0 || config_len > UINT_MAX ||
        tun_fd < 0 || atomic_load(&g_running)) {
        return -1;
    }

    struct hev_start_args *args = calloc(1, sizeof(*args));
    if (!args) return -1;

    args->config = malloc(config_len);
    if (!args->config) {
        free(args);
        return -1;
    }

    memcpy(args->config, config, config_len);
    args->length = (unsigned int)config_len;
    args->tun_fd = tun_fd;
    atomic_store(&g_running, 1);

    if (pthread_create(&g_thread, NULL, hev_thread_main, args) != 0) {
        atomic_store(&g_running, 0);
        free(args->config);
        free(args);
        return -1;
    }

    return 0;
}

void aether_hev_stop(void) {
    if (!atomic_load(&g_running)) return;
    hev_socks5_tunnel_quit();
    pthread_join(g_thread, NULL);
}
