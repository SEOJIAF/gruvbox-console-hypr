#!/usr/bin/env bash
# gruvbox-console-hypr installer for Fedora
# Run from the root of this dotfiles repository: ./install.sh
# It installs Hyprland/Noctalia alongside Plasma; it never removes Plasma packages
# and never changes the display manager or the default login-session selection.
#
# Interactive by default: walks through a terminal TUI (whiptail) wizard. Pass
# any of --no-packages/--no-links/--no-fonts/--no-tweaks/--scale/--batch to
# skip the wizard and run non-interactively (e.g. from another script).

set -Eeuo pipefail
IFS=$'\n\t'

APP_NAME='Gruvbox Console Hyprland'
REPO_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}"
DATA_DIR="${XDG_DATA_HOME:-$HOME/.local/share}"
BACKUP_ROOT="${XDG_STATE_HOME:-$HOME/.local/state}/gruvbox-console-hypr/backups"
STAMP="$(date +%Y%m%d-%H%M%S)"
LOG_FILE="${TMPDIR:-/tmp}/gruvbox-console-hypr-install-$STAMP.log"

UI_MODE=''          # tui | gui | batch — decided after argument parsing
EXPLICIT_FLAGS=0     # set when a granular --no-* / --scale flag is passed
ASSUME_YES=0
SCALE='auto'
DO_PACKAGES=1
DO_LINKS=1
DO_FONTS=1
DO_SESSION_TWEAKS=1
SUDO_KEEPALIVE_PID=''
TRACE=0

log()  { printf '\033[1;33m==>\033[0m %s\n' "$*" | tee -a "$LOG_FILE" >&2; }
ok()   { printf '\033[1;32m OK\033[0m %s\n' "$*" | tee -a "$LOG_FILE" >&2; }
warn() { printf '\033[1;31mWARN\033[0m %s\n' "$*" | tee -a "$LOG_FILE" >&2; }
die()  { warn "$*"; exit 1; }

# Run a command, streaming its real output live to the terminal (so slow
# steps like "dnf install" show actual progress instead of looking frozen)
# while also capturing everything to $LOG_FILE.
run_step() {
    printf '\n[%s] $ %s\n' "$(date +%H:%M:%S)" "$*" >>"$LOG_FILE"
    "$@" 2>&1 | tee -a "$LOG_FILE"
}

cleanup() {
    local rc=$?
    [[ -n $SUDO_KEEPALIVE_PID ]] && kill "$SUDO_KEEPALIVE_PID" 2>/dev/null
    if (( rc != 0 )); then
        warn "Installer stopped at line $1 (exit $rc)."
        warn "Full log: $LOG_FILE"
        [[ -d "$BACKUP_ROOT/$STAMP" ]] && warn "Backups made so far: $BACKUP_ROOT/$STAMP"
    fi
    exit "$rc"
}
trap 'cleanup $LINENO' ERR

usage() {
    cat <<EOF
Usage: ./install.sh [options]

With no options, and when run from an interactive terminal, this walks
through a whiptail-based TUI wizard. Any of the flags below skip the wizard
and run non-interactively instead.

Options:
  --tui              Force the terminal TUI wizard (whiptail)
  --gui              Force Zenity graphical dialogs instead of the TUI
  --batch, --yes     Skip all prompts; run with current flag values
  -x, --trace        Enable bash xtrace debugging output
  --scale SCALE      Monitor scale: 'auto' (default) or integer 1/2/3. Auto
                     keeps the fractional scale and fixes oversized Chromium/
                     Electron/Firefox chrome via the XWayland force_zero_scaling
                     fix instead of shrinking/growing the whole UI.
  --no-packages      Do not enable COPR or install RPM packages
  --no-links         Do not link configuration files
  --no-fonts         Do not link fonts or refresh fontconfig cache
  --no-tweaks        Do not apply scale/touchpad/workspace settings to hyprland.conf
  --log-file PATH    Write the install log somewhere other than /tmp
  --help             Show this help

This installer is intentionally Fedora-specific. It maintains KDE Plasma as a
separate login-session option and does not store, request, or embed sudo
passwords — sudo prompts for its own password interactively as needed.
EOF
}

require_repo_layout() {
    [[ -f "$REPO_DIR/hypr/hyprland.conf" ]] || die "Missing hypr/hyprland.conf beside install.sh"
    [[ -d "$REPO_DIR/noctalia" ]] || die "Missing noctalia/ beside install.sh"
    [[ -d "$REPO_DIR/kitty" ]] || die "Missing kitty/ beside install.sh"
    [[ -d "$REPO_DIR/gtk-3.0" ]] || die "Missing gtk-3.0/ beside install.sh"
    [[ -d "$REPO_DIR/gtk-4.0" ]] || die "Missing gtk-4.0/ beside install.sh"
    [[ -d "$REPO_DIR/qt6ct" ]] || die "Missing qt6ct/ beside install.sh"
}

have() { command -v "$1" >/dev/null 2>&1; }

backup_path() {
    local target=$1 rel
    rel="${target#"$HOME"/}"
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
    # shellcheck disable=SC1091
    [[ -r /etc/os-release ]] && . /etc/os-release && [[ ${ID:-} == fedora ]]
}

install_packages() {
    local repoquery_rc
    have dnf || die "dnf is required; this installer currently supports Fedora only."

    # The Hyprland COPR used by this rice also provides Noctalia/Noctalia QS.
    # Do not enable it if the requested package is already available.
    # This can block on metadata/mirror issues, so time it out and proceed.
    log "Checking whether hyprland is already available in enabled repos (timeout: 120s)"
    if run_step timeout 120 dnf -q repoquery --available hyprland; then
        ok "A Hyprland package source is already enabled"
    else
        repoquery_rc=$?
        if [[ $repoquery_rc -eq 124 ]]; then
            warn "Repo availability probe timed out; enabling COPR directly to continue."
        else
            warn "hyprland not found in currently enabled repos; enabling COPR."
        fi
        log "Enabling COPR lionheartp/Hyprland"
        run_step sudo dnf -y copr enable lionheartp/Hyprland
    fi

    log "Installing Hyprland, portal integration, Noctalia, theming tools, and helpers"
    run_step sudo dnf install -y \
        hyprland \
        xdg-desktop-portal-hyprland \
        qt5-qtwayland \
        qt6ct \
        noctalia-shell \
        kitty \
        newt \
        zenity
    ok "Packages installed"
}

# Keep settings that depend on the current display ergonomics in the tracked
# Hyprland config. The operations are idempotent.
apply_hyprland_tweaks() {
    local conf="$REPO_DIR/hypr/hyprland.conf" tmp
    tmp="$(mktemp)"

    # Keep the monitor on the fractional 'auto' scale so the whole UI is sized
    # natively. Oversized Chromium/Electron/Firefox chrome at fractional scale is
    # fixed below via XWayland + force_zero_scaling, not by forcing integer scale.
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
    cat "$tmp" >"$conf"
    rm -f -- "$tmp"

    # Chromium/Electron/Firefox round a fractional monitor scale up to the next
    # integer for their own chrome and render oversized. Forcing them onto XWayland
    # with force_zero_scaling lets Hyprland upscale them to the fractional scale.
    if ! grep -qE '^[[:space:]]*force_zero_scaling[[:space:]]*=' "$conf"; then
        cat >>"$conf" <<'EOF'

# Installer-managed: force Chromium/Electron/Firefox onto XWayland so their
# chrome matches the fractional monitor scale instead of rounding up to 2x.
env = MOZ_ENABLE_WAYLAND,0
env = ELECTRON_OZONE_PLATFORM_HINT,x11

xwayland {
    force_zero_scaling = true
}
EOF
    fi

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
        cat "$tmp" >"$conf"
        rm -f -- "$tmp"
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

    if ! grep -q 'launcher toggle' "$conf"; then
        cat >>"$conf" <<'EOF'

# Noctalia launcher
bind = SUPER, R, exec, qs ipc -c noctalia-shell call launcher toggle
EOF
    fi
    ok "Applied scale $SCALE with XWayland fractional-scaling fix, natural touchpad scrolling, workspace bindings, and launcher keybind"
}

link_configs() {
    # Link the single Hyprland file, not ~/.config/hypr as a whole, so unrelated
    # per-user Hyprland files can coexist. Noctalia/Kitty are managed dotfile dirs.
    link_path "$REPO_DIR/hypr/hyprland.conf" "$CONFIG_DIR/hypr/hyprland.conf"
    link_path "$REPO_DIR/noctalia" "$CONFIG_DIR/noctalia"
    link_path "$REPO_DIR/kitty" "$CONFIG_DIR/kitty"
    link_path "$REPO_DIR/gtk-3.0" "$CONFIG_DIR/gtk-3.0"
    link_path "$REPO_DIR/gtk-4.0" "$CONFIG_DIR/gtk-4.0"
    link_path "$REPO_DIR/qt6ct" "$CONFIG_DIR/qt6ct"
}

install_fonts() {
    local font_source="$REPO_DIR/fonts/IosevkaTermNerdFontMono"
    if [[ ! -d "$font_source" ]]; then
        warn "Font directory not found; leaving existing font setup untouched: $font_source"
        return
    fi
    link_path "$font_source" "$DATA_DIR/fonts/IosevkaTermNerdFontMono"
    if have fc-cache; then
        run_step fc-cache -f "$DATA_DIR/fonts"
        ok "Font cache refreshed"
    else
        warn "fc-cache is unavailable; log out/in or run fc-cache manually."
    fi
}

reload_hyprland() {
    if [[ -n ${HYPRLAND_INSTANCE_SIGNATURE:-} && -n ${WAYLAND_DISPLAY:-} ]] && have hyprctl; then
        if hyprctl reload >/dev/null; then
            ok "Hyprland configuration reloaded"
        else
            warn "Could not hot-reload Hyprland; log out and back in."
        fi
        warn "env vars (scale/XWayland fixes) only apply at Hyprland's own startup — log out and back in to fully apply those."
    else
        warn "Not running inside Hyprland; select Hyprland from the display manager after installation."
    fi
}

# ---------------------------------------------------------------------------
# UI: three ways to gather the same DO_PACKAGES/DO_LINKS/DO_FONTS/
# DO_SESSION_TWEAKS/SCALE choices — TUI (default), GUI (--gui), or none
# (--batch / explicit flags / non-interactive shell).
# ---------------------------------------------------------------------------

ensure_whiptail() {
    have whiptail && return 0
    log "whiptail (from the 'newt' package) is needed for the TUI wizard; installing it"
    if have dnf && sudo -v 2>/dev/null; then
        run_step sudo dnf install -y newt && have whiptail && return 0
    fi
    return 1
}

tui_choices() {
    whiptail --title "$APP_NAME" --msgbox \
"This installs Hyprland + Noctalia as a SECOND login-session option on Fedora, alongside your existing KDE Plasma session.

Plasma's packages, config, and your display manager's settings are never touched. Any pre-existing file this installer would overwrite is backed up first, under:
$BACKUP_ROOT/$STAMP

Press Enter to continue." 16 76

    local components
    components=$(whiptail --title "$APP_NAME" --checklist \
        "Choose what to install/apply (Space to toggle, Enter to confirm):" 16 76 4 \
        packages "Hyprland, Noctalia, Kitty, dependencies (dnf/COPR)" ON \
        links    "Symlink configs into ~/.config (backs up existing files)" ON \
        fonts    "Link IosevkaTerm Nerd Font Mono + refresh font cache" ON \
        tweaks   "Scale fix, natural touchpad scroll, workspaces 1-10" ON \
        3>&1 1>&2 2>&3) || { warn "Cancelled."; exit 0; }

    DO_PACKAGES=0; DO_LINKS=0; DO_FONTS=0; DO_SESSION_TWEAKS=0
    [[ $components == *packages* ]] && DO_PACKAGES=1
    [[ $components == *links* ]] && DO_LINKS=1
    [[ $components == *fonts* ]] && DO_FONTS=1
    [[ $components == *tweaks* ]] && DO_SESSION_TWEAKS=1

    if (( DO_SESSION_TWEAKS )); then
        SCALE=$(whiptail --title "$APP_NAME" --radiolist \
            "Monitor scale. A fractional scale can make Electron/Chromium/Firefox chrome render oversized (their toolkits round it up); 'auto' keeps the fractional scale and fixes that via XWayland instead of resizing the whole UI." \
            17 78 3 \
            auto "Keep fractional scale + XWayland fix (recommended)" ON \
            1    "Force integer scale 1 (smaller UI everywhere)" OFF \
            2    "Force integer scale 2 (larger UI everywhere)" OFF \
            3>&1 1>&2 2>&3) || { warn "Cancelled."; exit 0; }
    fi

    local summary="About to run, with backups (if needed) under:\n$BACKUP_ROOT/$STAMP\n\n"
    (( DO_PACKAGES )) && summary+="  - Install packages via dnf/COPR\n"
    (( DO_SESSION_TWEAKS )) && summary+="  - Apply hyprland.conf tweaks (scale=$SCALE)\n"
    (( DO_LINKS )) && summary+="  - Symlink configs into ~/.config\n"
    (( DO_FONTS )) && summary+="  - Link fonts + refresh font cache\n"
    summary+="\nProceed?"
    whiptail --title "$APP_NAME" --yesno "$(printf '%b' "$summary")" 18 76 || { warn "Cancelled."; exit 0; }
}

# Runs the chosen steps with real, live output (not hidden behind a gauge —
# "dnf install" alone can take minutes, and a gauge with no new progress to
# report during that time just looks frozen). A short whiptail/zenity dialog
# announces each step so it's still obvious what's about to produce output.
run_install() {
    local total=0 step=0
    for flag in DO_PACKAGES DO_SESSION_TWEAKS DO_LINKS DO_FONTS; do
        [[ ${!flag} == 1 ]] && ((++total))
    done
    ((++total)) # reload_hyprland always runs

    announce_step() {
        step=$((step + 1))
        log "Step $step/$total: $1"
    }

    if (( DO_PACKAGES )); then
        log "Requesting sudo access (needed for package installation)..."
        sudo -v || die "sudo access is required to install packages"
        ( while true; do sleep 60; sudo -n true || exit; done ) &
        SUDO_KEEPALIVE_PID=$!
        announce_step "installing packages via dnf — this can take a few minutes, real dnf output follows below"
        install_packages
    fi
    if (( DO_SESSION_TWEAKS )); then
        announce_step "applying Hyprland session tweaks (scale=$SCALE, touchpad, workspaces, launcher keybind)"
        apply_hyprland_tweaks
    fi
    if (( DO_LINKS )); then
        announce_step "linking configuration files into $CONFIG_DIR"
        link_configs
    fi
    if (( DO_FONTS )); then
        announce_step "installing fonts into $DATA_DIR/fonts"
        install_fonts
    fi
    announce_step "reloading Hyprland (if currently running)"
    reload_hyprland

    if [[ -n $SUDO_KEEPALIVE_PID ]]; then
        kill "$SUDO_KEEPALIVE_PID" 2>/dev/null
        SUDO_KEEPALIVE_PID=''
    fi

    ok "Installation complete. Full log: $LOG_FILE"
    if have whiptail && [[ -t 0 && -t 1 ]]; then
        whiptail --title "$APP_NAME" --msgbox \
"Installation complete.

Next steps:
  1. Log out and choose \"Hyprland\" at the login screen if you're not
     already in it (a fresh login is needed to fully apply scale/XWayland
     env vars, not just a config reload).
  2. Fully restart any open Electron/Chromium/Firefox windows.

Full log: $LOG_FILE" 16 76
    fi
}

# Zenity-based graphical fallback for people who'd rather click than use the
# terminal TUI. Kept intentionally simple relative to the TUI wizard.
gui_choices() {
    local picked
    picked=$(zenity --list --checklist --title="$APP_NAME" \
        --text='Choose installation components. Plasma and your display manager are not modified.' \
        --column='Install' --column='Component' --column='Purpose' \
        TRUE 'Packages' 'Hyprland, Noctalia, portal, Kitty, dependencies' \
        TRUE 'Configuration' 'Symlink Hyprland, Noctalia and Kitty configuration' \
        TRUE 'Fonts' 'Link IosevkaTerm Nerd Font Mono and refresh cache' \
        TRUE 'Tweaks' 'Scale fix, natural touchpad scroll, workspaces 1-10' \
        --separator='|' --width=760 --height=360) || exit 0
    DO_PACKAGES=0; DO_LINKS=0; DO_FONTS=0; DO_SESSION_TWEAKS=0
    [[ $picked == *Packages* ]] && DO_PACKAGES=1
    [[ $picked == *Configuration* ]] && DO_LINKS=1
    [[ $picked == *Fonts* ]] && DO_FONTS=1
    [[ $picked == *Tweaks* ]] && DO_SESSION_TWEAKS=1
    SCALE=$(zenity --list --radiolist --title="$APP_NAME" \
        --text='Monitor scale. Auto keeps the fractional scale and fixes oversized Chromium, Electron, and Firefox chrome with the XWayland fix.' \
        --column='Use' --column='Scale' TRUE 'auto (recommended)' FALSE '1' FALSE '2' \
        --width=700 --height=260) || exit 0
    SCALE=${SCALE%% *}
    zenity --question --title="$APP_NAME" \
        --text="Proceed with the selected setup? Existing config paths will be backed up under:\n$BACKUP_ROOT/$STAMP" || exit 0
}

# Last-resort interactive fallback when whiptail can't be installed (e.g. no
# network) and --gui wasn't requested. Only asks the one choice that most
# affects visual results; everything else keeps its flag/default value.
fallback_prompts() {
    warn "whiptail is unavailable; falling back to plain terminal prompts."
    printf '\n%s\n%s\n' "$APP_NAME" 'This installs a separate Hyprland session and preserves Plasma.'
    read -r -p 'Monitor scale: auto (default; keeps fractional scale + XWayland fix) or integer 1/2? [auto]: ' answer
    SCALE=${answer:-auto}
}

# ---------------------------------------------------------------------------

while (($#)); do
    case $1 in
        --tui) UI_MODE="tui" ;;
        --gui) UI_MODE="gui" ;;
        --batch|--yes) ASSUME_YES=1 ;;
        -x|--trace) TRACE=1 ;;
        --scale) shift; SCALE=${1:-}; EXPLICIT_FLAGS=1 ;;
        --no-packages) DO_PACKAGES=0; EXPLICIT_FLAGS=1 ;;
        --no-links) DO_LINKS=0; EXPLICIT_FLAGS=1 ;;
        --no-fonts) DO_FONTS=0; EXPLICIT_FLAGS=1 ;;
        --no-tweaks) DO_SESSION_TWEAKS=0; EXPLICIT_FLAGS=1 ;;
        --log-file) shift; LOG_FILE=${1:-$LOG_FILE} ;;
        --help|-h) usage; exit 0 ;;
        *) die "Unknown option: $1 (see --help)" ;;
    esac
    shift
done

[[ $SCALE == auto || $SCALE =~ ^[123]$ ]] || die "--scale must be 'auto' or an integer 1, 2, or 3"
require_repo_layout
is_fedora || die "Unsupported distribution. This installer is designed and tested for Fedora."
mkdir -p "$(dirname -- "$LOG_FILE")"
: >"$LOG_FILE"
(( TRACE )) && set -x

# Decide the UI mode if not forced by --tui/--gui: prefer the TUI wizard when
# running interactively with no scripting flags already given; otherwise run
# straight through with whatever flags/defaults were provided.
if [[ -z $UI_MODE ]]; then
    if (( ASSUME_YES )) || (( EXPLICIT_FLAGS )) || [[ ! -t 0 || ! -t 1 ]]; then
        UI_MODE="batch"
    else
        UI_MODE="tui"
    fi
fi

log "$APP_NAME — repository: $REPO_DIR"
log "No Plasma packages, display-manager settings, or Firefox profiles are modified."
log "Full log: $LOG_FILE"

case $UI_MODE in
    gui)
        have zenity || { warn 'Zenity is not installed yet; installing it first.'; sudo dnf install -y zenity || die "Could not install zenity"; }
        gui_choices
        run_install
        ;;
    tui)
        if ensure_whiptail; then
            tui_choices
        else
            warn "Could not obtain whiptail; continuing with plain prompts."
            fallback_prompts
        fi
        run_install
        ;;
    batch)
        run_install
        printf '\nNext steps:\n'
        printf '%s\n' '  1. Log out and choose "Hyprland" in your display manager if you are not already in it.'
        printf '%s\n' '  2. Fully restart Chromium/Electron/Firefox applications after this run (env vars need a fresh session).'
        printf '%s\n' "  3. Backups (only if an existing path was replaced): $BACKUP_ROOT/$STAMP"
        ;;
esac
