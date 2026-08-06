# gruvbox-console-hypr

A Hyprland + Noctalia rice: "old computer, Gruvbox, modernized bare-metal Linux console."

Runs as a second Wayland session alongside an existing KDE Plasma install on
Fedora 44 — Plasma is never touched (packages, config, or display manager
state).

## Status

Phase 3 done (Gruvbox palette + monospace typography), plus a real
`install.sh` and a round of ergonomics fixes (see below). Remaining:
GTK/Qt/cursor coherence, wallpaper, final docs.

- `hypr/` — Hyprland config
- `noctalia/` — Noctalia shell config (`~/.config/noctalia`)
- `gtk-3.0/`, `gtk-4.0/` — session-scoped GTK theming
- `kitty/` — terminal config with Gruvbox ANSI colors
- `fontconfig/`, `fonts/` — monospace console fonts
- `wallpaper/` — flat Gruvbox wallpaper
- `applications/` — Hyprland session `.desktop` entry (if not already provided by the package)
- `install.sh` — idempotent Fedora installer: enables the COPR if needed,
  installs packages via `dnf`, symlinks configs with timestamped backups of
  anything pre-existing, links fonts + refreshes fontconfig, and applies the
  session tweaks below to a fresh clone's `hypr/hyprland.conf`. Supports
  `--gui` (Zenity dialogs), `--scale auto|1|2|3`, and `--no-packages`/
  `--no-links`/`--no-fonts`/`--no-tweaks` to skip steps. Never touches
  Plasma packages, the display manager, or Firefox's profile.

## Packages / COPRs installed so far

- COPR `lionheartp/Hyprland` (`copr:copr.fedorainfracloud.org:lionheartp:Hyprland`)
  was **already enabled on this machine** before this rice was started — not
  added by this repo. It provides `hyprland`, `xdg-desktop-portal-hyprland`,
  and the noctalia packages below.
- `dnf install hyprland xdg-desktop-portal-hyprland qt5-qtwayland` (Phase 1).
  `qt6-qtwayland` was already installed. Ships its own login-screen entry at
  `/usr/share/wayland-sessions/hyprland.desktop` — no custom `.desktop` file
  needed.
- `dnf install noctalia-shell` (Phase 2). dnf resolved this to the
  **`noctalia-shell-legacy`** package (pulling `noctalia-qs-legacy`, their
  Quickshell fork) plus weak deps `cliphist` and `wlsunset` — not the plain
  `noctalia-shell`/`noctalia-qs` packages that also exist in the same COPR.
  Launched via `qs -c noctalia-shell` (added as `exec-once` in
  `hypr/hyprland.conf`).
- Side effect noted: the Hyprland install transaction also bumped
  `plasma-breeze-qt6`/`plasma-breeze-common` from 6.7.2→6.7.3 (shared
  dependency getting the newer available build) — verified this was a
  version upgrade, not a removal; Plasma's Breeze theme package is intact.

## Noctalia config locations

- `~/.config/noctalia/` — `settings.json`, `colors.json`, `plugins.json` +
  `colorschemes/`, `plugins/` dirs. This is what's symlinked into the repo
  (`noctalia/`).
- `~/.local/state/noctalia/` — caches, plugin git checkouts, usage stats.
  Deliberately **not** brought into the repo (runtime state, not config;
  includes nested git repos that would be messy to track).

## Palette & typography (Phase 3)

- **Color scheme:** Noctalia ships a stock `Gruvbox` preset
  (`/etc/xdg/quickshell/noctalia-shell/Assets/ColorScheme/Gruvbox/Gruvbox.json`)
  with correct canonical hex values, but it maps primary=green /
  secondary=yellow — backwards from this rice's brief (yellow/orange primary
  accent, aqua/green secondary). Rather than editing the package-owned file,
  added a custom scheme at `noctalia/colorschemes/Gruvbox-Console/Gruvbox-Console.json`
  (scanned automatically from `~/.config/noctalia/colorschemes/`) with the
  same canonical hex values but primary/secondary swapped, and selected it via
  `colorSchemes.predefinedScheme` in `settings.json`.
- **Hyprland borders:** `general.col.active_border` = bright yellow
  `#fabd2f`, `col.inactive_border` = `#504945` (bg2) in `hypr/hyprland.conf`.
- **Flat/no-blur/no-shadow:** in `noctalia/settings.json`, zeroed
  `general.{boxRadiusRatio,iRadiusRatio,radiusRatio,screenRadiusRatio}` and
  `bar.frameRadius`, disabled `bar.outerCorners`,
  `general.{enableBlurBehind,enableShadows}`; enabled `bar.showOutline` and
  `ui.boxBorderEnabled` for hard 1px borders instead. Set
  `bar.backgroundOpacity`/`ui.panelBackgroundOpacity` to `1` (fully opaque,
  no glass look).
- **Typography:** downloaded **IosevkaTerm Nerd Font Mono** (Regular/Bold/
  Italic/BoldItalic only, from the official
  [nerd-fonts](https://github.com/ryanoasis/nerd-fonts) v3.5.0 release —
  the `...Mono` variant so nerd-font glyph icons stay fixed-width and align
  in the bar/terminal) into `fonts/IosevkaTermNerdFontMono/`, symlinked into
  `~/.local/share/fonts/`. Not packaged in Fedora's repos or any enabled
  COPR (`dnf search iosevka`/`nerd-fonts` returned nothing). Set as both
  `ui.fontDefault` and `ui.fontFixed` in Noctalia's settings (monospace
  everywhere, not just the terminal).
- **Terminal:** `kitty` (already installed as a Hyprland dependency) themed
  via `kitty +kitten themes --dump-theme "Gruvbox Dark"` — the actual
  upstream [gruvbox-community/gruvbox-contrib](https://github.com/gruvbox-community/gruvbox-contrib)
  kitty config, saved as `kitty/gruvbox-dark.conf` and included from
  `kitty/kitty.conf`, which also sets the Iosevka Term Mono font family and
  a block cursor.

## Ergonomics fixes (post-Phase-3)

- **Kitty bold/italic text rendering broken:** `bold_font`/`italic_font` in
  `kitty/kitty.conf` were set to literal strings like `IosevkaTerm Nerd Font
  Mono Bold` — that's a style, not a font family name, so `fc-match` silently
  fell back to **Noto Sans** (a proportional font) for any bolded text. Since
  `ls --color` bolds directory names, this broke the monospace grid on
  practically every directory listing. Fixed by setting all three to `auto`,
  kitty's documented default that lets it resolve styles from `font_family`
  correctly. Also dropped `font_size` 11→10.
- **More workspaces:** Hyprland itself has no workspace limit — Phase 1's
  minimal config only bound keys for 1-4. Added `SUPER`/`SUPER SHIFT` + `1-9`
  and `0` (→ workspace 10) in `hypr/hyprland.conf`.
- **Oversized Electron/Chromium/Firefox chrome:** this panel's monitor scale
  is a fractional `1.5` (`hyprctl monitors`). Toolkits without full
  fractional-scale support (GTK, Chromium/Electron) round that up to `2` for
  their own window chrome while page/app content correctly renders at `1.5`
  — hence oversized toolbars/tabs/menus with normal-looking content.
  Quickshell/Noctalia isn't affected (proper fractional-scale support), so
  the monitor scale itself was kept at `auto` (1.5). Fixed instead with:
  `xwayland { force_zero_scaling = true }` (Hyprland upscales XWayland
  clients from a scale-1 render, avoiding the rounding entirely) plus
  `env = MOZ_ENABLE_WAYLAND,0` and `env = ELECTRON_OZONE_PLATFORM_HINT,x11`
  to push Firefox and Electron apps onto XWayland. `env` directives only
  apply at Hyprland's own startup, not on `hyprctl reload` — a full
  logout/login (or fresh session) is needed after this change, not just a
  reload.
- **Touchpad scroll direction:** `input.touchpad.natural_scroll = true` in
  `hypr/hyprland.conf`.
- **Noctalia app launcher keybind:** `SUPER, R` → `qs ipc -c noctalia-shell
  call launcher toggle`.

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
