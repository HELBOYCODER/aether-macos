#ifndef AETHER_HEV_BRIDGE_H
#define AETHER_HEV_BRIDGE_H

#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

int aether_hev_start(const char *config, size_t config_len, int tun_fd);
void aether_hev_stop(void);

#ifdef __cplusplus
}
#endif

#endif
