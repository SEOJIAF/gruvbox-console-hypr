#!/usr/bin/env bash
# gruvbox-console-hypr installer for Fedora
# Run from the root of this dotfiles repository: ./install.sh
# It installs Hyprland/Noctalia alongside Plasma; it never removes Plasma packages
# and never changes the display manager or the default login-session selection.

set -Eeuo pipefail
IFS=$'\n\t'

APP_NAME='Gruvbox Console Hyprland'
REPO_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}"
DATA_DIR="${XDG_DATA_HOME:-$HOME/.local/share}"
BACKUP_ROOT="${XDG_STATE_HOME:-$HOME/.local/state}/gruvbox-console-hypr/backups"
STAMP="$(date +%Y%m%d-%H%M%S)"
USE_GUI=0
SCALE='1'
DO_PACKAGES=1
DO_LINKS=1
DO_FONTS=1
DO_SESSION_TWEAKS=1

log()  { printf '\033[1;33m==>\033[0m %s\n' "$*"; }
ok()   { printf '\033[1;32m OK\033[0m %s\n' "$*"; }
warn() { printf '\033[1;31mWARN\033[0m %s\n' "$*" >&2; }
die()  { warn "$*"; exit 1; }

cleanup() {
    local rc=$?
    if (( rc != 0 )); then
        warn "Installer stopped at line $1 (exit $rc). Existing backups, if any: $BACKUP_ROOT/$STAMP"
    fi
    exit "$rc"
}
trap 'cleanup $LINENO' ERR

usage() {
    cat <<EOF
Usage: ./install.sh [options]

Options:
  --gui              Use Zenity dialogs when available
  --scale SCALE      Hyprland integer scale (default: 1; allowed: 1, 2, 3)
  --no-packages      Do not enable COPR or install RPM packages
  --no-links         Do not link configuration files
  --no-fonts         Do not link fonts or refresh fontconfig cache
  --no-tweaks        Do not apply scale/touchpad/workspace settings to hyprland.conf
  --help             Show this help

This installer is intentionally Fedora-specific. It maintains KDE Plasma as a
separate login-session option and does not store, request, or embed sudo passwords.
EOF
}

require_repo_layout() {
    [[ -f "$REPO_DIR/hypr/hyprland.conf" ]] || die "Missing hypr/hyprland.conf beside install.sh"
    [[ -d "$REPO_DIR/noctalia" ]] || die "Missing noctalia/ beside install.sh"
    [[ -d "$REPO_DIR/kitty" ]] || die "Missing kitty/ beside install.sh"
}

have() { command -v "$1" >/dev/null 2>&1; }

backup_path() {
    local target=$1 rel
    rel="${target#$HOME/}"
    mkdir -p "$BACKUP_ROOT/$STAMP/$(dirname -- "$rel")"
    printf '%s\n' "$BACKUP_ROOT/$STAMP/$rel"
}

# Move a pre-existing user file/dir out of the way, but leave an already-correct
# symlink alone. This makes repeated runs safe.
link_path() {
    local source=$1 target=$2 backup
    [[ -e "$source" || -L "$source" ]] || die "Repository source missing: $source"
    mkdir -p "$(dirname -- "$target")"

    if [[ -L "$target" && "$(readlink -f -- "$target")" == "$(readlink -f -- "$source")" ]]; then
        ok "Already linked: $target"
        return
    fi
    if [[ -e "$target" || -L "$target" ]]; then
        backup="$(backup_path "$target")"
        log "Backing up $target -> $backup"
        mv -- "$target" "$backup"
    fi
    ln -s -- "$source" "$target"
    ok "Linked $target"
}

is_fedora() {
    [[ -r /etc/os-release ]] && . /etc/os-release && [[ ${ID:-} == fedora ]]
}

install_packages() {
    have dnf || die "dnf is required; this installer currently supports Fedora only."
    log "Checking sudo access (your password is handled only by sudo)"
    sudo -v

    # The Hyprland COPR used by this rice also provides Noctalia/Noctalia QS.
    # Do not enable it if the requested package is already available.
    if ! dnf -q repoquery --available hyprland >/dev/null 2>&1; then
        log "Enabling COPR lionheartp/Hyprland"
        sudo dnf -y copr enable lionheartp/Hyprland
    else
        ok "A Hyprland package source is already enabled"
    fi

    log "Installing Hyprland, portal integration, Noctalia, Kitty and Zenity"
    sudo dnf install -y \
        hyprland \
        xdg-desktop-portal-hyprland \
        qt5-qtwayland \
        noctalia-shell \
        kitty \
        zenity
    ok "Packages installed"
}

# Keep settings that depend on the current display ergonomics in the tracked
# Hyprland config. The operations are idempotent.
apply_hyprland_tweaks() {
    local conf="$REPO_DIR/hypr/hyprland.conf" tmp
    tmp="$(mktemp)"

    # Replace the first active generic monitor line. Integer scale 1 avoids the
    # fractional-scale client-size issue observed with Chromium/Electron/Firefox.
    awk -v scale="$SCALE" '
        BEGIN { changed=0 }
        /^[[:space:]]*monitor[[:space:]]*=/ && !changed {
            print "monitor=,preferred,auto," scale
            changed=1
            next
        }
        { print }
        END { if (!changed) print "monitor=,preferred,auto," scale }
    ' "$conf" >"$tmp"
    mv -- "$tmp" "$conf"

    if ! grep -qE '^[[:space:]]*touchpad[[:space:]]*\{' "$conf"; then
        cat >>"$conf" <<'EOF'

# Installer-managed ergonomics: natural/reversed touchpad scrolling.
input {
    touchpad {
        natural_scroll = true
    }
}
EOF
    elif ! grep -qE '^[[:space:]]*natural_scroll[[:space:]]*=' "$conf"; then
        # Add only inside the first touchpad block.
        awk '
            /^[[:space:]]*touchpad[[:space:]]*\{/ && !done { print; print "        natural_scroll = true"; done=1; next }
            { print }
        ' "$conf" >"$tmp"
        mv -- "$tmp" "$conf"
    fi

    # Add bindings 5-10 only if an older Phase-1 config did not include them.
    if ! grep -q 'workspace, 10' "$conf"; then
        cat >>"$conf" <<'EOF'

# Workspaces 1-9; Super+0 selects workspace 10.
bind = SUPER, 5, workspace, 5
bind = SUPER, 6, workspace, 6
bind = SUPER, 7, workspace, 7
bind = SUPER, 8, workspace, 8
bind = SUPER, 9, workspace, 9
bind = SUPER, 0, workspace, 10
bind = SUPER SHIFT, 5, movetoworkspace, 5
bind = SUPER SHIFT, 6, movetoworkspace, 6
bind = SUPER SHIFT, 7, movetoworkspace, 7
bind = SUPER SHIFT, 8, movetoworkspace, 8
bind = SUPER SHIFT, 9, movetoworkspace, 9
bind = SUPER SHIFT, 0, movetoworkspace, 10
EOF
    fi
    ok "Applied integer scale $SCALE, natural touchpad scrolling, and workspace bindings"
}

link_configs() {
    # Link the single Hyprland file, not ~/.config/hypr as a whole, so unrelated
    # per-user Hyprland files can coexist. Noctalia/Kitty are managed dotfile dirs.
    link_path "$REPO_DIR/hypr/hyprland.conf" "$CONFIG_DIR/hypr/hyprland.conf"
    link_path "$REPO_DIR/noctalia" "$CONFIG_DIR/noctalia"
    link_path "$REPO_DIR/kitty" "$CONFIG_DIR/kitty"
}

install_fonts() {
    local font_source="$REPO_DIR/fonts/IosevkaTermNerdFontMono"
    if [[ ! -d "$font_source" ]]; then
        warn "Font directory not found; leaving existing font setup untouched: $font_source"
        return
    fi
    link_path "$font_source" "$DATA_DIR/fonts/IosevkaTermNerdFontMono"
    have fc-cache && fc-cache -f "$DATA_DIR/fonts" || warn "fc-cache is unavailable; log out/in or run fc-cache manually."
    ok "Font cache refreshed"
}

reload_hyprland() {
    if [[ ${HYPRLAND_INSTANCE_SIGNATURE:-} && -n ${WAYLAND_DISPLAY:-} ]] && have hyprctl; then
        hyprctl reload >/dev/null && ok "Hyprland configuration reloaded" || warn "Could not hot-reload Hyprland; log out and back in."
    else
        warn "Not running inside Hyprland; select Hyprland from the display manager after installation."
    fi
}

terminal_choices() {
    printf '\n%s\n' "$APP_NAME"
    printf '%s\n' 'This installs a separate Hyprland session and preserves Plasma.'
    read -r -p 'Use integer display scale 1 (recommended) or 2? [1]: ' answer
    SCALE=${answer:-1}
}

gui_choices() {
    local picked
    picked=$(zenity --list --checklist --title="$APP_NAME" \
        --text='Choose installation components. Plasma and your display manager are not modified.' \
        --column='Install' --column='Component' --column='Purpose' \
        TRUE 'Packages' 'Hyprland, Noctalia, portal, Kitty, Zenity' \
        TRUE 'Configuration' 'Symlink Hyprland, Noctalia and Kitty configuration' \
        TRUE 'Fonts' 'Link IosevkaTerm Nerd Font Mono and refresh cache' \
        TRUE 'Tweaks' 'Scale 1, natural touchpad scroll, workspaces 1-10' \
        --separator='|' --width=760 --height=360) || exit 0
    DO_PACKAGES=0; DO_LINKS=0; DO_FONTS=0; DO_SESSION_TWEAKS=0
    [[ $picked == *Packages* ]] && DO_PACKAGES=1
    [[ $picked == *Configuration* ]] && DO_LINKS=1
    [[ $picked == *Fonts* ]] && DO_FONTS=1
    [[ $picked == *Tweaks* ]] && DO_SESSION_TWEAKS=1
    SCALE=$(zenity --list --radiolist --title="$APP_NAME" \
        --text='Display scale. Scale 1 avoids oversized Chromium, Electron, and Firefox chrome on fractional-scaled displays.' \
        --column='Use' --column='Scale' TRUE '1 (recommended)' FALSE '2' \
        --width=700 --height=260) || exit 0
    SCALE=${SCALE%% *}
    zenity --question --title="$APP_NAME" \
        --text="Proceed with the selected setup? Existing config paths will be backed up under:\n$BACKUP_ROOT/$STAMP" || exit 0
}

while (($#)); do
    case $1 in
        --gui) USE_GUI=1 ;;
        --scale) shift; SCALE=${1:-} ;;
        --no-packages) DO_PACKAGES=0 ;;
        --no-links) DO_LINKS=0 ;;
        --no-fonts) DO_FONTS=0 ;;
        --no-tweaks) DO_SESSION_TWEAKS=0 ;;
        --help|-h) usage; exit 0 ;;
        *) die "Unknown option: $1" ;;
    esac
    shift
done

[[ $SCALE =~ ^[123]$ ]] || die "--scale must be an integer: 1, 2, or 3"
require_repo_layout
is_fedora || die "Unsupported distribution. This installer is designed and tested for Fedora."

# If GUI was requested but Zenity is not installed yet, package installation will
# install it. Fall back gracefully for this first run rather than installing UI
# tooling before the user has approved package installation.
if (( USE_GUI )) && have zenity; then
    gui_choices
elif (( USE_GUI )); then
    warn 'Zenity is not installed yet; using the terminal for this first run.'
    terminal_choices
fi

log "$APP_NAME — repository: $REPO_DIR"
log "No Plasma packages, display-manager settings, or Firefox profiles are modified."
(( DO_PACKAGES )) && install_packages
(( DO_SESSION_TWEAKS )) && apply_hyprland_tweaks
(( DO_LINKS )) && link_configs
(( DO_FONTS )) && install_fonts
reload_hyprland

ok 'Installation complete.'
printf '\nNext steps:\n'
printf '%s\n' '  1. Log out and choose “Hyprland” in your display manager if you are not already in it.'
printf '%s\n' '  2. Fully restart Chromium/Electron/Firefox applications after changing scale.'
printf '%s\n' "  3. Backups (only if an existing path was replaced): $BACKUP_ROOT/$STAMP"
