# gruvbox-console-hypr

A Fedora-focused Hyprland + Noctalia v5 setup with a beautiful Gruvbox aesthetic, built to run **alongside KDE Plasma** as a separate login session. 

> **AI assistance note:** Parts of this project (especially installer debugging/refinement) were developed with AI assistant help. All changes were reviewed and tested by yours truly before publishing.

## Highlights

- **Hyprland 0.53+ Support:** Fully updated declarative block syntax for window and layer rules.
- **Noctalia v5 Integration:** Modern Noctalia shell with customized dock, workspaces, and Gruvbox UI colors.
- **Modern Animated Installer:** Features a smooth, interactive terminal wizard powered by `gum`, complete with progress spinners, multi-select menus, and Gruvbox hex styling.
- **Safety First:** Creates a KDE package baseline and performs a full `dnf` dry-run before touching Hyprland to ensure no Qt6 conflicts occur.
- **XWayland Scaling Fix:** Workaround for oversized Chromium/Electron/Firefox chrome on fractional scaling, and automatic `HYPRCURSOR_SIZE` injection.

## Requirements

- Fedora (tested on Fedora 44)
- Existing user session with `sudo` privileges
- `gum` (will be automatically bootstrapped by the installer if missing)

## Install

```bash
git clone https://github.com/SEOJIAF/gruvbox-console-hypr
cd gruvbox-console-hypr

# Run the modern interactive installer:
./install-v2-tui.sh
```

The installer will present an interactive `gum` checklist allowing you to run all phases or precisely select specific ones (like re-applying dotfiles).

### Installer Modes

**Interactive TUI (Default)**
```bash
./install-v2-tui.sh
```

**Simple Logging Mode (No Animations)**
Falls back to standard `stdout` text logging, useful for scripting or if you don't want the visual TUI.
```bash
./install-v2-tui.sh --simple
```

**Dry-Run Mode**
Safely tests the `dnf` transaction and configuration deployment without actually changing your system.
```bash
./install-v2-tui.sh --dry-run
```

## What the installer does

1. **Preflight:** Validates Fedora 44, internet connection, and snapshots your KDE packages.
2. **Hyprland:** Enables the `ashbuk/Hyprland-Fedora` COPR, performs a dry-run check, and installs Hyprland + utilities (`kitty`, `grim`, `slurp`).
3. **Noctalia:** Installs Noctalia v5 shell.
4. **Theme & Dotfiles:** Copies GTK, Qt, Kitty, and Font configurations to `~/.config/`. Dynamically templates and deploys your custom Noctalia state into `~/.local/state/noctalia/settings.toml`, resolving absolute wallpaper paths.
5. **Hyprland config wiring:** Injects the Noctalia management block into your `hyprland.conf` with properly mapped `SUPER + R` and media keys.
6. **Session integration:** Provisions a Wayland session desktop entry.
7. **Verification:** Validates that the KDE baseline has not been damaged by the transaction.

## Safety / Scope

This project is intentionally scoped to the Hyprland session and does **not**:
- remove KDE Plasma packages
- change display manager defaults
- overwrite your existing non-Hyprland configs aggressively

## After install

1. Log out
2. Select **Hyprland** at your display manager (login screen)
3. Log in again

## Repository layout

```text
dotfiles/
  hypr/         Base Hyprland config
  kitty/        Kitty terminal config (Gruvbox)
  gtk-3.0/      GTK3 session defaults
  gtk-4.0/      GTK4 session defaults
  qt6ct/        Qt platform theming config
  fonts/        IosevkaTerm Nerd Font Mono
  wallpaper/    Gruvbox backgrounds
  noctalia-settings.toml  Custom Noctalia v5 UI state
install-v2-tui.sh   Modern animated installer
```
