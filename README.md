# portmaster-nix

<!-- BEGIN generated:badges -->
[![NixOS unstable](https://img.shields.io/badge/NixOS-unstable-78C0E8?logo=nixos&logoColor=white)](https://nixos.org)
[![License: GPL-3.0](https://img.shields.io/badge/License-GPL--3.0-blue.svg)](./LICENSE)
<!-- END generated:badges -->

NixOS packaging for [Portmaster](https://safing.io/portmaster/) — the free and open-source application firewall by [Safing](https://safing.io).

This flake builds Portmaster **v2.1.7 from source** (Go core + Rust/Tauri desktop + Angular UI) and provides a NixOS module with full systemd integration and security hardening.

<!-- BEGIN generated:upstream -->
## Upstream

| | |
|---|---|
| **Project** | [safing/portmaster](https://github.com/safing/portmaster) |
| **License** | AGPL-3.0 |
| **Tracked** | GitHub releases |
<!-- END generated:upstream -->

## Documentation

For long-form references beyond the README sections below, see:

- [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) — directory layout, component boundaries (Go core / Tauri desktop / Angular UI), NixOS-specific patches catalogue
- [`docs/BUILD.md`](docs/BUILD.md) — operator commands: dev shell, formatters, hooks, tests, update contract, troubleshooting
- [`docs/OPTIONS.md`](docs/OPTIONS.md) — full `services.portmaster.*` option reference
- [`docs/upstream-issue-draft.md`](docs/upstream-issue-draft.md) — draft of the upstream issue for nixpkgs upstreaming

## Components

| Component | Technology | Description |
|---|---|---|
| `portmaster-core` | Go | Firewall engine — DNS resolver, network filter, threat intelligence |
| `portmaster` (desktop) | Rust / Tauri | Native desktop app with system tray integration |
| `portmaster-ui` | Angular | Web UI served by the core at `127.0.0.1:817` |

<!-- BEGIN generated:installation -->
## Installation

Add as a flake input:

```nix
{
  inputs.portmaster = {
    url = "github:Daaboulex/portmaster-nix";
    inputs.nixpkgs.follows = "nixpkgs";
  };
}
```

Then add the overlay:

```nix
nixpkgs.overlays = [ inputs.portmaster.overlays.default ];
```

Import the NixOS module:

```nix
imports = [ inputs.portmaster.nixosModules.default ];
```
<!-- END generated:installation -->

## Usage

### 1. Add flake input

```nix
# flake.nix
inputs.portmaster = {
  url = "github:daaboulex/portmaster-nix";
  inputs.nixpkgs.follows = "nixpkgs";
};
```

### 2. Stack the overlay

```nix
nixpkgs.overlays = [
  inputs.portmaster.overlays.default
];
```

### 3. Import the NixOS module

```nix
imports = [
  inputs.portmaster.nixosModules.default
];
```

### 4. Enable Portmaster

```nix
services.portmaster = {
  enable = true;
  notifier.enable = true;  # System tray icon (autostart on login)
  # autostart = true;      # Start service on boot (default: true)
  # settings.devmode = true;  # Web UI at 127.0.0.1:817 (default: true)
  # extraArgs = [ "--verbose" ];
};
```

## Module Options

| Option | Type | Default | Description |
|---|---|---|---|
| `services.portmaster.enable` | bool | `false` | Enable Portmaster firewall service |
| `services.portmaster.package` | package | `pkgs.portmaster` | Portmaster package to use |
| `services.portmaster.autostart` | bool | `true` | Start service on boot. When `false`, the service is installed but must be started manually with `sudo systemctl start portmaster` |
| `services.portmaster.notifier.enable` | bool | `false` | XDG autostart for the system tray icon. Only launches if the service is active |
| `services.portmaster.notifier.delay` | int | `3` | Seconds to wait before launching the tray icon (lets the desktop system tray initialize) |
| `services.portmaster.settings` | attrs | `{}` | Freeform settings passed to portmaster-core |
| `services.portmaster.settings.devmode` | bool | `true` | Enable web UI at `127.0.0.1:817` |
| `services.portmaster.extraArgs` | list of str | `[]` | Extra CLI arguments for portmaster-core |

## What gets installed

- **System service**: `portmaster.service` — runs `portmaster-core` as root with proper capabilities and systemd hardening
- **Desktop app**: `portmaster` binary with `.desktop` file — launch from your application menu
- **System tray**: Optional XDG autostart entry (via `notifier.enable`) — starts in background/tray-only mode, checks that the service is running before launching
- **Web UI**: Available at `http://127.0.0.1:817` when `devmode` is enabled
- **Data directory**: `/var/lib/portmaster/` — managed via `systemd-tmpfiles`
- **Kernel module**: `netfilter_queue` — loaded automatically for packet filtering

## Manual service control

When `autostart = false`, Portmaster doesn't start on boot but is still fully installed:

```bash
sudo systemctl start portmaster   # Start the firewall
sudo systemctl stop portmaster    # Stop the firewall
sudo systemctl status portmaster  # Check status
```

The notifier tray icon (if enabled) will silently skip launching when the service isn't running — no "Connection refused" popup.

## NixOS-specific patches

### Profile persistence across rebuilds

On NixOS, every system rebuild generates new Nix store hashes, changing all binary paths. Without intervention, Portmaster treats each rebuild as a new application and creates a fresh profile — losing all per-app firewall rules.

This package includes a `nix_linux.go` tag handler (following the same pattern as the upstream Flatpak handler) that creates a stable `nix-pkg` tag from the derivation name and binary name. Profiles match on this tag instead of the volatile store path, so per-app rules persist across rebuilds.

### FHS path fixes

The Tauri desktop app hardcodes FHS paths (`/usr/bin/systemctl`, `/usr/bin/pkexec`) that don't exist on NixOS. This package patches them at build time:

| Upstream path | NixOS path | Purpose |
|---|---|---|
| `/sbin/systemctl` et al. | `${systemd}/bin/systemctl` | Service status detection |
| `/usr/bin/pkexec` | `/run/wrappers/bin/pkexec` | Polkit privilege elevation (SUID wrapper) |
| `/usr/bin/gksudo` | `/run/wrappers/bin/gksudo` | Fallback privilege elevation |

Without these patches, the desktop app cannot detect whether `portmaster.service` is running, and the "Start Service" button in the splash screen doesn't work.

## Architecture support

Currently only `x86_64-linux`. The upstream Go and Rust code is architecture-independent, but `aarch64-linux` has not been tested.

## Migration from v1

If you previously used the v1 packaging (binary fetch + self-update approach):

1. Stop the old service: `sudo systemctl stop portmaster-core`
2. Back up your config: `sudo cp -r /opt/safing/portmaster/config /tmp/portmaster-config-backup`
3. Rebuild with the new flake (this creates `/var/lib/portmaster/`)
4. Optionally restore config: `sudo cp -r /tmp/portmaster-config-backup/* /var/lib/portmaster/config/`
5. Clean up old data: `sudo rm -rf /opt/safing/portmaster`

> **Note**: v2 databases are not backward-compatible with v1. Threat intelligence and DNS cache will be re-downloaded automatically.

## Credits

- [Safing GmbH](https://safing.io) — Portmaster developers
- [NixOS/nixpkgs#264454](https://github.com/NixOS/nixpkgs/pull/264454) by WitteShadovv — earlier v1 packaging effort that informed this from-source build approach

## Development

```bash
git clone https://github.com/Daaboulex/portmaster-nix
cd portmaster-nix
nix develop                       # enter dev shell, installs pre-commit hooks
nix fmt                           # format flake + module + package
nix flake check --no-build        # eval check
nix build .#portmaster-core       # Go core only
nix build .#portmaster-ui         # Angular static bundle
nix build .#portmaster            # composed Tauri desktop + core + UI
./result/bin/portmaster --version
```

CI runs the same chain twice weekly via `.github/workflows/update.yml`. See [`docs/BUILD.md`](docs/BUILD.md) for the full operator reference (update contract, troubleshooting, manual service control).

<!-- BEGIN generated:options -->
<!-- END generated:options -->

## License

This packaging flake is [GPL-3.0-only](./LICENSE) licensed (matches upstream). Upstream Portmaster is [GPL-3.0-only](https://github.com/safing/portmaster/blob/master/LICENSE) by Safing GmbH.

<!-- BEGIN generated:footer -->
---

*Maintained as part of the [Daaboulex](https://github.com/Daaboulex) NixOS ecosystem.*
<!-- END generated:footer -->
