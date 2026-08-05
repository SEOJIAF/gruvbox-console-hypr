# gruvbox-console-hypr

A Hyprland + Noctalia rice: "old computer, Gruvbox, modernized bare-metal Linux console."

Runs as a second Wayland session alongside an existing KDE Plasma install on
Fedora 44 — Plasma is never touched (packages, config, or display manager
state).

## Status

Scaffold only (Phase 0). Nothing installed yet. Later phases will fill in:

- `hypr/` — Hyprland config
- `noctalia/` — Noctalia shell config
- `gtk-3.0/`, `gtk-4.0/` — session-scoped GTK theming
- `kitty/` — terminal config with Gruvbox ANSI colors
- `fontconfig/`, `fonts/` — monospace console fonts
- `wallpaper/` — flat Gruvbox wallpaper
- `applications/` — Hyprland session `.desktop` entry (if not already provided by the package)
- `install.sh` — idempotent installer, packages via `dnf`/COPR, symlinks configs, never touches Plasma or the display manager's enabled state

## Prerequisites

- Fedora 44
- Existing, working KDE Plasma session

## Install

```
git clone <this-repo> ~/rice/gruvbox-console-hypr
cd ~/rice/gruvbox-console-hypr
./install.sh
```

## Out of scope

- Display manager visual theming (shared with Plasma, left as-is)
- Anything under `~/.config/plasma*`, `~/.config/kde*`, `kwinrc`
