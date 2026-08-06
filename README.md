# gruvbox-console-hypr

A Fedora-focused Hyprland + Noctalia setup with a flat Gruvbox aesthetic, built to run **alongside KDE Plasma** as a separate login session.

## Highlights

- Hyprland session with Noctalia shell (`qs -c noctalia-shell`)
- Gruvbox color palette and flat UI styling (no blur/shadows)
- IosevkaTerm Nerd Font Mono across terminal + shell UI
- XWayland scaling workaround for oversized Chromium/Electron/Firefox chrome on fractional scaling
- Interactive installer with terminal TUI (whiptail) + non-interactive flags
- Idempotent config linking with timestamped backups

## Requirements

- Fedora (tested on Fedora 44)
- Existing user session with `sudo` privileges

## Install

```bash
git clone <your-fork-or-repo-url> ~/rice/gruvbox-console-hypr
cd ~/rice/gruvbox-console-hypr
./install.sh
```

The default installer mode is an interactive terminal wizard.

## Installer modes

### Interactive (default)

```bash
./install.sh
```

### Trace/debug output

```bash
./install.sh --trace
```

### Non-interactive

```bash
./install.sh --batch --scale auto
```

## Useful flags

```text
--tui              Force whiptail terminal wizard
--gui              Use Zenity dialogs instead of terminal wizard
--batch, --yes     Skip prompts and run directly
--trace, -x        Enable bash xtrace
--scale auto|1|2|3 Monitor scale mode
--no-packages      Skip package/COPR installation
--no-links         Skip config symlinking
--no-fonts         Skip font linking + cache refresh
--no-tweaks        Skip Hyprland tweak injection
--log-file PATH    Custom installer log path
```

## What the installer does

1. Enables COPR: `lionheartp/Hyprland`
2. Installs required packages (Hyprland, portal, Noctalia, Kitty, `qt6ct`, etc.)
3. Applies session tweaks in `hypr/hyprland.conf`:
   - workspace binds up to 10
   - natural touchpad scrolling
   - XWayland scaling fix + Firefox/Electron env vars
4. Symlinks config from this repo into `~/.config`:
   - `hypr/hyprland.conf`
   - `noctalia/`
   - `kitty/`
   - `gtk-3.0/`
   - `gtk-4.0/`
   - `qt6ct/`
5. Links fonts into `~/.local/share/fonts` and refreshes cache

If a destination already exists, it is moved to:

```text
~/.local/state/gruvbox-console-hypr/backups/<timestamp>/
```

## Safety / scope

This project is intentionally scoped to the Hyprland session and does **not**:

- remove KDE Plasma packages
- change display manager defaults
- modify Firefox profile files directly

## After install

1. Log out
2. Select **Hyprland** at login
3. Log in again

For env-based scaling/theme variables, a full re-login is required (not just `hyprctl reload`).

## Troubleshooting

### Installer appears stuck during package step

It is usually waiting on `dnf` (metadata, mirrors, key import, or lock). Check:

```bash
tail -f /tmp/gruvbox-console-hypr-install-*.log
ps -ef | grep -E 'dnf|install.sh' | grep -v grep
```

### Dolphin/Qt apps still look light

Ensure the new session env is loaded (logout/login), then verify:

```bash
echo "$QT_QPA_PLATFORMTHEME"   # should be qt6ct
echo "$QT_STYLE_OVERRIDE"      # should be Breeze
```

### Re-apply config links only

```bash
./install.sh --batch --no-packages --no-fonts --scale auto
```

## Repository layout

```text
hypr/         Hyprland config
noctalia/     Noctalia config and color scheme
kitty/        Kitty config (Gruvbox)
gtk-3.0/      GTK3 session defaults
gtk-4.0/      GTK4 session defaults
qt6ct/        Qt platform theming config
fonts/        IosevkaTerm Nerd Font Mono files
install.sh    Installer
```
