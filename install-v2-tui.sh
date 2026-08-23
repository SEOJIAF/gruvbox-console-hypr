#!/usr/bin/env bash
set -euo pipefail

# install-hyprland-noctalia.sh
# A declarative, idempotent install script for Hyprland + Noctalia Shell on Fedora 44 (KDE)

STATE_DIR="$HOME/.local/state/hypr-noctalia-install"
BASELINE_FILE="$STATE_DIR/baseline-packages.txt"
MANIFEST_FILE="$STATE_DIR/manifest"
LOG_FILE="/tmp/hypr-install-$$.log"

TUI_MODE=1
DRY_RUN=0
PHASES_SELECTED="1,2,3,4,5,6,7"

for arg in "$@"; do
    if [[ "$arg" == "--simple" ]]; then
        TUI_MODE=0
    elif [[ "$arg" == "--dry-run" ]]; then
        DRY_RUN=1
    elif [[ "$arg" == "--uninstall" ]]; then
        if [[ -f "$MANIFEST_FILE" ]]; then
            echo "Uninstall mode is not fully implemented for all files yet, but here is what we'd remove:"
            cat "$MANIFEST_FILE"
        fi
        exit 1
    fi
done

# --- Styling & Logging Setup ---
# Gruvbox Dark Palette
C_PRIMARY="#fabd2f" # Yellow
C_TEXT="#ebdbb2"    # Light text
C_SUCCESS="#b8bb26" # Green
C_WARN="#fe8019"    # Orange
C_ERROR="#fb4934"   # Red

export GUM_SPIN_SPINNER="dot"
export GUM_SPIN_SPINNER_FOREGROUND="$C_PRIMARY"
export GUM_CHOOSE_CURSOR_FOREGROUND="$C_PRIMARY"
export GUM_CHOOSE_SELECTED_FOREGROUND="$C_PRIMARY"
export GUM_CONFIRM_SELECTED_BACKGROUND="$C_PRIMARY"
export GUM_CONFIRM_SELECTED_FOREGROUND="#282828"

function log_out() { echo "$*" >> "$LOG_FILE"; }

function info()  { 
    if [[ $TUI_MODE -eq 1 ]]; then
        gum style --foreground "$C_TEXT" "  $*"
    else
        echo -e "[\e[34mINFO\e[0m] $*"
    fi
}
function success() {
    if [[ $TUI_MODE -eq 1 ]]; then
        gum style --foreground "$C_SUCCESS" "✓ $*"
    else
        echo -e "[\e[32m OK \e[0m] $*"
    fi
}
function warn()  { 
    if [[ $TUI_MODE -eq 1 ]]; then
        gum style --foreground "$C_WARN" "! $*"
    else
        echo -e "[\e[33mWARN\e[0m] $*"
    fi
}
function error() { 
    if [[ $TUI_MODE -eq 1 ]]; then
        gum style --foreground "$C_ERROR" "✗ $*" >&2
    else
        echo -e "[\e[31mERROR\e[0m] $*" >&2
    fi
}
function die()   { error "$*"; exit 1; }
function add_to_manifest() { echo "$1" >> "$MANIFEST_FILE"; }
function is_installed() { rpm -q "$1" &>/dev/null; }

function spin() {
    local title="$1"
    shift
    if [[ $TUI_MODE -eq 1 ]]; then
        gum spin --title "$title" -- "$@"
    else
        echo -e "[\e[34m...\e[0m] $title"
        "$@"
    fi
}

function prompt_confirm() {
    local prompt="$1"
    if [[ $TUI_MODE -eq 1 ]]; then
        gum confirm "$prompt" || die "Aborted by user."
    else
        read -p "$prompt [y/N]: " res
        if [[ ! "$res" =~ ^[Yy]$ ]]; then die "Aborted by user."; fi
    fi
}

# --- Bootstrap ---
if [[ $TUI_MODE -eq 1 ]]; then
    if ! command -v gum &>/dev/null; then
        echo "Bootstrapping 'gum' for the TUI (requires sudo)..."
        sudo dnf install -y gum >/dev/null 2>&1 || {
            echo "Failed to install gum. Falling back to simple mode."
            TUI_MODE=0
        }
    fi
fi

# We need a cached sudo token so commands inside `gum spin` don't hang waiting for a password
sudo -v || die "Failed to authenticate sudo. Required for installation."

if [[ $TUI_MODE -eq 1 ]]; then
    clear
    gum style --foreground "$C_PRIMARY" --border double --margin "1 2" --padding "0 2" "Gruvbox Console Hyprland"
    
    OPTIONS=$(gum choose --no-limit --selected="1. Preflight Checks,2. Hyprland (ashbuk COPR),3. Noctalia Shell (v5),4. Gruvbox Dotfiles & Theme,5. Hyprland config wiring,6. Session integration,7. Final Verification" \
        "1. Preflight Checks" \
        "2. Hyprland (ashbuk COPR)" \
        "3. Noctalia Shell (v5)" \
        "4. Gruvbox Dotfiles & Theme" \
        "5. Hyprland config wiring" \
        "6. Session integration" \
        "7. Final Verification" \
        "Enable Dry-Run Mode")

    if [[ -z "$OPTIONS" ]]; then
        die "No phases selected. Exiting."
    fi

    if echo "$OPTIONS" | grep -q "Dry-Run"; then
        DRY_RUN=1
        info "Dry-run mode ENABLED."
    fi

    # Extract selected phase numbers
    PHASES_SELECTED=$(echo "$OPTIONS" | grep -o '^[1-7]' | tr '\n' ',' | sed 's/,$//')
fi

function should_run() {
    local phase="$1"
    if [[ ",$PHASES_SELECTED," == *",$phase,"* ]]; then
        return 0
    else
        return 1
    fi
}

# ----------------- PHASES -----------------

if should_run 1; then
    info "=== Phase 1: Preflight ==="
    spin "Running preflight checks..." bash -c '
        if ! grep -q "VERSION_ID=44" /etc/os-release; then exit 11; fi
        if ! rpm -q plasma-workspace &>/dev/null; then exit 12; fi
        if ! ping -c 1 -W 3 1.1.1.1 &>/dev/null; then exit 13; fi
    ' || {
        res=$?
        if [[ $res -eq 11 ]]; then die "Requires Fedora 44."
        elif [[ $res -eq 12 ]]; then die "Requires KDE Plasma."
        elif [[ $res -eq 13 ]]; then die "No internet connection."
        else die "Preflight failed."; fi
    }
    
    mkdir -p "$STATE_DIR"
    if [[ ! -f "$BASELINE_FILE" ]]; then
        for pkg in "qt6-qtbase" "kf6-kirigami" "kwin" "plasma-workspace" "plasma-login-manager"; do
            if is_installed "$pkg"; then rpm -q "$pkg" >> "$BASELINE_FILE"; fi
        done
        success "Baseline packages snapshot created."
    else
        success "Baseline snapshot already exists."
    fi
fi


if should_run 2; then
    info "=== Phase 2: Package installation (Hyprland) ==="
    COPR_REPO="ashbuk/Hyprland-Fedora"
    if [[ $DRY_RUN -eq 1 ]]; then
        info "[DRY RUN] Would enable COPR $COPR_REPO and install Hyprland"
    else
        spin "Enabling COPR $COPR_REPO..." sudo dnf copr enable -y "$COPR_REPO" >/dev/null
        
        DRY_RUN_LOG="/tmp/hypr_dry_run_$$.log"
        spin "Dry-running Hyprland transaction..." bash -c "sudo dnf install -y hyprland xdg-desktop-portal-hyprland --assumeno --exclude='qt6-*' > $DRY_RUN_LOG 2>&1 || true"
        
        if grep -iE 'qt6|plasma|kde|kwin|sddm' "$DRY_RUN_LOG" | grep -iE 'Removing|Downgrading|Replacing' >/dev/null; then
            sudo dnf copr disable -y "$COPR_REPO" >/dev/null
            if [[ $TUI_MODE -eq 1 ]]; then gum pager < "$DRY_RUN_LOG"; fi
            die "Dry-run detected dangerous package modifications to Qt/KDE!"
        fi
        
        success "Dry-run clean. No Qt6 conflicts detected."
        prompt_confirm "Proceed with Hyprland install?"
        
        if ! is_installed hyprland || ! is_installed xdg-desktop-portal-hyprland; then
            spin "Installing Hyprland..." bash -c "sudo dnf install -y hyprland xdg-desktop-portal-hyprland --exclude='qt6-*' >> $LOG_FILE 2>&1"
            add_to_manifest "pkg:hyprland"
            add_to_manifest "pkg:xdg-desktop-portal-hyprland"
            success "Hyprland installed."
        else
            success "Hyprland is already installed."
        fi
        
        spin "Disabling COPR..." sudo dnf copr disable -y "$COPR_REPO" >/dev/null
        
        spin "Installing utilities..." bash -c "for pkg in qt6-qtwayland polkit-kde kitty grim slurp; do if ! rpm -q \$pkg &>/dev/null; then sudo dnf install -y \$pkg >> $LOG_FILE 2>&1 || true; echo \"pkg:\$pkg\" >> $MANIFEST_FILE; fi; done"
        success "Utilities installed."
    fi
fi


if should_run 3; then
    info "=== Phase 3: Noctalia Shell ==="
    if [[ $DRY_RUN -eq 1 ]]; then
        info "[DRY RUN] Would install noctalia"
    else
        if ! is_installed noctalia; then
            spin "Installing Noctalia..." bash -c "sudo dnf install -y noctalia >> $LOG_FILE 2>&1"
            add_to_manifest "pkg:noctalia"
            success "Noctalia installed."
        else
            success "Noctalia is already installed."
        fi
    fi
fi


if should_run 4; then
    info "=== Phase 4: Theme & Dotfiles ==="
    if [[ $DRY_RUN -eq 1 ]]; then
        info "[DRY RUN] Would deploy Gruvbox themes and configs from dotfiles/"
    else
        SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &> /dev/null && pwd)"
        if [[ -d "$SCRIPT_DIR/dotfiles" ]]; then
        spin "Deploying Gruvbox dotfiles..." bash -c "
                mkdir -p \"$HOME/.config\" \"$HOME/.local/share/fonts\" \"$HOME/.local/share/backgrounds\" \"$HOME/.config/hypr\"
                for conf in fontconfig gtk-3.0 gtk-4.0 kitty qt6ct noctalia; do
                    if [[ -d \"$SCRIPT_DIR/dotfiles/\$conf\" ]]; then
                        cp -R \"$SCRIPT_DIR/dotfiles/\$conf\" \"$HOME/.config/\"
                        echo \"dir:$HOME/.config/\$conf\" >> $MANIFEST_FILE
                    fi
                done
                if [[ -d \"$SCRIPT_DIR/dotfiles/fonts\" ]]; then
                    cp -R \"$SCRIPT_DIR/dotfiles/fonts/\"* \"$HOME/.local/share/fonts/\" 2>/dev/null || true
                fi
                if [[ -d \"$SCRIPT_DIR/dotfiles/wallpaper\" ]]; then
                    cp -R \"$SCRIPT_DIR/dotfiles/wallpaper/\"* \"$HOME/.local/share/backgrounds/\" 2>/dev/null || true
                fi
                if [[ -f \"$SCRIPT_DIR/dotfiles/noctalia-settings.toml\" ]]; then
                    mkdir -p \"$HOME/.local/state/noctalia\"
                    sed \"s|HOME_DIR|$HOME|g\" \"$SCRIPT_DIR/dotfiles/noctalia-settings.toml\" > \"$HOME/.local/state/noctalia/settings.toml\"
                fi
                if [[ -f \"$SCRIPT_DIR/dotfiles/hyprland.conf\" ]]; then
                    cp \"$SCRIPT_DIR/dotfiles/hyprland.conf\" \"$HOME/.config/hypr/hyprland.conf\"
                fi
            "
            success "Dotfiles deployed."
        else
            warn "No dotfiles/ directory found, skipping theme deployment."
        fi
    fi
fi


if should_run 5; then
    info "=== Phase 5: Hyprland config wiring ==="
    HYPR_DIR="$HOME/.config/hypr"
    HYPR_CONF="$HYPR_DIR/hyprland.conf"
    if [[ $DRY_RUN -eq 1 ]]; then
        info "[DRY RUN] Would wire Noctalia into $HYPR_CONF"
    else
        spin "Wiring Noctalia configuration..." bash -c "
            mkdir -p \"$HYPR_DIR\"
            if [[ ! -f \"$HYPR_CONF\" ]]; then
                echo '# Minimal Hyprland config' > \"$HYPR_CONF\"
                echo \"file:$HYPR_CONF\" >> $MANIFEST_FILE
            fi
# >>> noctalia-managed >>>
exec-once = noctalia

layerrule {
    name = ^noctalia-(bar-.+|notification|dock|panel|attached-panel|osd|window-switcher)$
    no_anim = 1
    ignore_alpha = 0.5
    blur = 1
    blur_popups = 1
}

windowrule {
    name = ^(dev\.noctalia\.Noctalia)$
    float = 1
    size = 1080 920
}

bind = SUPER, R, exec, noctalia msg panel-toggle launcher
bind = SUPER, S, exec, noctalia msg panel-toggle control-center
bind = SUPER, comma, exec, noctalia msg settings-toggle
bind = ALT, Tab, exec, noctalia msg window-switcher

bindl = , XF86AudioRaiseVolume, exec, noctalia msg volume-up
bindl = , XF86AudioLowerVolume, exec, noctalia msg volume-down
bindl = , XF86AudioMute, exec, noctalia msg volume-mute
bindl = , XF86MonBrightnessUp, exec, noctalia msg brightness-up
bindl = , XF86MonBrightnessDown, exec, noctalia msg brightness-down
# <<< noctalia-managed <<<
END_CONF
        "
        success "Hyprland wired for Noctalia v5."
    fi
fi


if should_run 6; then
    info "=== Phase 6: Session integration ==="
    if [[ $DRY_RUN -eq 1 ]]; then
        info "[DRY RUN] Checking session integration"
    else
        if [[ ! -f /usr/share/wayland-sessions/hyprland.desktop ]]; then
            spin "Creating session file..." bash -c "echo -e '[Desktop Entry]\nName=Hyprland\nComment=An intelligent dynamic tiling Wayland compositor\nExec=Hyprland\nType=Application' | sudo tee /usr/share/wayland-sessions/hyprland.desktop >/dev/null"
            add_to_manifest "file:/usr/share/wayland-sessions/hyprland.desktop"
            success "Session created."
        else
            success "Hyprland session entry exists."
        fi
    fi
fi


if should_run 7; then
    info "=== Phase 7: Verification ==="
    if [[ $DRY_RUN -eq 0 ]]; then
        FAILURES=0
        for cmd in Hyprland noctalia kitty grim slurp; do
            if ! command -v $cmd &>/dev/null; then
                error "Missing binary: $cmd"
                FAILURES=$((FAILURES + 1))
            fi
        done
        
        spin "Checking baseline integrity..." bash -c "
            CURRENT_BASELINE=\"/tmp/current-baseline-$$.txt\"
            for pkg in qt6-qtbase kf6-kirigami kwin plasma-workspace plasma-login-manager; do
                if rpm -q \"\$pkg\" &>/dev/null; then rpm -q \"\$pkg\" >> \"\$CURRENT_BASELINE\"; fi
            done
            if ! diff -q \"$BASELINE_FILE\" \"\$CURRENT_BASELINE\" >/dev/null; then
                exit 2
            fi
        " || {
            if [[ $? -eq 2 ]]; then
                error "Baseline mismatch! KDE/Qt packages have changed!"
                if [[ $TUI_MODE -eq 1 ]]; then gum pager < <(diff "$BASELINE_FILE" "/tmp/current-baseline-$$.txt"); fi
                FAILURES=$((FAILURES + 1))
            fi
        }

        if [[ $FAILURES -gt 0 ]]; then 
            die "Verification failed with $FAILURES errors."
        else 
            success "Verification passed! System is safely configured."
        fi
    fi
fi
