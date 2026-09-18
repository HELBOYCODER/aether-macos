# Aether macOS Packet Tunnel

This target is the macOS Network Extension boundary for the Aether client.

The Android reference implementation uses Android's `VpnService` plus a TUN-to-SOCKS adapter. macOS cannot reuse `VpnService`; the equivalent system integration is `NEPacketTunnelProvider`.

Important: this first target establishes the correct Network Extension lifecycle and routing boundary. It deliberately does **not** claim to have a working packet-to-SOCKS dataplane yet. The next implementation stage must port the Aether/HEV dataplane and preserve endpoint bypasses so the tunnel does not route its own upstream connection back into itself.

Original Android reference: https://github.com/immaghzbad/AetherST
