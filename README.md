# Aether for macOS (menu-bar app)

A native SwiftUI wrapper around the [CluvexStudio/Aether](https://github.com/CluvexStudio/Aether)
CLI. Menu-bar only, no Dock icon. One click to connect, pick protocol/scan mode,
set system proxy, watch the live log.

## Features
- Menu-bar status item with connect/disconnect and live state colour
- Protocol picker: MASQUE / WireGuard / WARP-in-WARP (`gool`)
- Scan mode: turbo / balanced / thorough / stealth / ironclad
- Obfuscation: off / light / balanced / aggressive
- Optional system-wide SOCKS proxy via `networksetup` (127.0.0.1 only — never 0.0.0.0)
- Live log window + settings panel (persisted in UserDefaults)
- Bundled `aether` binary (v1.6.0) downloaded at build time, no runtime network fetch

## Security notes
- The SOCKS5 listener is always bound to `127.0.0.1` inside the bundle wrapper.
- System proxy, when enabled, targets only the active Wi-Fi/Ethernet service and
  points at `127.0.0.1` — it never exposes the tunnel to the LAN.
- No root, no network kext/driver; everything runs in the user session.
- `aether` is fetched from the official GitHub release (pinned version) and
  ad-hoc / Developer-ID signed with the bundled `entitlements.mac`.

## Build (GitHub Actions, zero local tooling)
1. Fork / push this repo to a public GitHub repo.
2. The `Build macOS .dmg` workflow runs on `macos-latest`, downloads the pinned
   `aether` binary, builds the app, signs it (ad-hoc unless you add secrets), and
   uploads `Aether.dmg` + `AetherApp.app` as a 90-day Artifact.
3. Optional: add repo Secrets `MACOS_SIGN_IDENTITY`, `APPLE_API_KEY`,
   `APPLE_KEY_ID`, `APPLE_ISSUER_ID` for a notarized, Gatekeeper-clean build.

## Install
Download `Aether.dmg` from Actions → Artifacts, open it, drag `AetherApp.app`
to Applications. On ad-hoc builds, right-click → Open the first time.

## License
App wrapper: MIT. Bundled `aether` binary: AGPL-3.0 (Cloudflare WARP client).
