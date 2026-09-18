#include "HEVBridge.h"
#include <pthread.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <unistd.h>
#include <stdatomic.h>
#include <stdint.h>

extern int hev_socks5_tunnel_main_from_str(const unsigned char *, unsigned int, int);
extern void hev_socks5_tunnel_quit(void);

static pthread_t g_thread;
static _Atomic int g_running = 0;
static int g_app_fd = -1;
static int g_hev_fd = -1;

struct hev_start_args { unsigned char *config; unsigned int length; int tun_fd; };

static void *hev_thread_main(void *opaque) {
    struct hev_start_args *args = opaque;
    int rc = hev_socks5_tunnel_main_from_str(args->config, args->length, args->tun_fd);
    int fd = args->tun_fd;
    free(args->config);
    free(args);
    close(fd);
    g_hev_fd = -1;
    atomic_store(&g_running, 0);
    return (void *)(intptr_t)rc;
}

int aether_hev_start(const char *config, size_t config_len) {
    if (!config || config_len == 0 || config_len > UINT_MAX || atomic_load(&g_running)) return -1;

    int fds[2] = {-1, -1};
    if (socketpair(AF_UNIX, SOCK_DGRAM, 0, fds) != 0) return -1;

    struct hev_start_args *args = calloc(1, sizeof(*args));
    if (!args) { close(fds[0]); close(fds[1]); return -1; }
    args->config = malloc(config_len);
    if (!args->config) { free(args); close(fds[0]); close(fds[1]); return -1; }
    memcpy(args->config, config, config_len);
    args->length = (unsigned int)config_len;
    args->tun_fd = fds[1];

    g_app_fd = fds[0];
    g_hev_fd = fds[1];
    atomic_store(&g_running, 1);

    if (pthread_create(&g_thread, NULL, hev_thread_main, args) != 0) {
        atomic_store(&g_running, 0);
        close(fds[0]); close(fds[1]);
        g_app_fd = g_hev_fd = -1;
        free(args->config); free(args);
        return -1;
    }
    return g_app_fd;
}

void aether_hev_stop(void) {
    if (!atomic_load(&g_running)) {
        if (g_app_fd >= 0) { close(g_app_fd); g_app_fd = -1; }
        return;
    }
    hev_socks5_tunnel_quit();
    pthread_join(g_thread, NULL);
    if (g_app_fd >= 0) { close(g_app_fd); g_app_fd = -1; }
}
