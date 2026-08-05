#!/bin/sh
# Install or remove the minimal Speaker DSP starter.
#
#   sudo sh install.sh [install|uninstall]
set -eu

[ "$(id -u)" = "0" ] || { echo "run with sudo" >&2; exit 1; }

ACTION=${1:-install}
ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
FILES_DIR="$ROOT_DIR/files"
FILTER_DEST=/etc/pipewire/pipewire.conf.d/50-speaker-tuning.conf
HIDE_CONF_DEST=/etc/wireplumber/wireplumber.conf.d/50-hide-speaker-tuning.conf
PRIORITY_CONF_DEST=/etc/wireplumber/wireplumber.conf.d/51-speaker-sink-priority.conf
HIDE_SCRIPT_DEST=/usr/local/share/wireplumber/scripts/hide-speaker-tuning.lua

remove_legacy_user_files() {
    # /etc/passwd is intentionally used instead of getent: every path below
    # is an exact legacy project path for a locally-defined account.
    while IFS=: read -r _ _ _ _ _ user_home _; do
        [ -n "$user_home" ] && [ "$user_home" != "/" ] && [ -d "$user_home" ] || continue
        rm -f -- \
            "$user_home/.config/pipewire/pipewire.conf.d/50-speaker-tuning.conf" \
            "$user_home/.config/wireplumber/wireplumber.conf.d/50-hide-speaker-tuning.conf" \
            "$user_home/.config/wireplumber/wireplumber.conf.d/51-speaker-sink-priority.conf" \
            "$user_home/.local/share/wireplumber/scripts/hide-speaker-tuning.lua" \
            "$user_home/.local/bin/speaker-dsp" \
            "$user_home/.local/bin/speaker-loudness-follow" \
            "$user_home/.config/systemd/user/speaker-loudness.service" \
            "$user_home/.config/systemd/user/default.target.wants/speaker-loudness.service"
    done </etc/passwd
}

remove_legacy_system_files() {
    # Disable the old globally enabled user unit before removing its file.
    systemctl --global disable speaker-loudness.service >/dev/null 2>&1 || true

    rm -f -- \
        /usr/local/bin/speaker-dsp \
        /usr/local/bin/speaker-loudness-follow \
        /etc/systemd/user/speaker-loudness.service \
        /usr/local/share/speaker-dsp/fir-correction.wav
}

print_user_restart_instructions() {
    echo "For each logged-in user, run:"
    echo "  systemctl --user disable --now speaker-loudness.service 2>/dev/null || true"
    echo "  systemctl --user daemon-reload"
    echo "  systemctl --user restart pipewire pipewire-pulse wireplumber"
}

uninstall() {
    rm -f -- \
        "$FILTER_DEST" \
        "$HIDE_CONF_DEST" \
        "$PRIORITY_CONF_DEST" \
        "$HIDE_SCRIPT_DEST"

    remove_legacy_system_files
    remove_legacy_user_files

    echo "Removed the Speaker DSP filter and all known legacy project files."
    print_user_restart_instructions
}

install_filter() {
    [ -f "$FILES_DIR/50-speaker-tuning.conf" ] || {
        echo "missing filter config: $FILES_DIR/50-speaker-tuning.conf" >&2
        exit 1
    }
    [ -f "$FILES_DIR/50-hide-speaker-tuning.conf" ] || {
        echo "missing WirePlumber config: $FILES_DIR/50-hide-speaker-tuning.conf" >&2
        exit 1
    }
    [ -f "$FILES_DIR/51-speaker-sink-priority.conf" ] || {
        echo "missing WirePlumber config: $FILES_DIR/51-speaker-sink-priority.conf" >&2
        exit 1
    }
    [ -f "$FILES_DIR/hide-speaker-tuning.lua" ] || {
        echo "missing WirePlumber script: $FILES_DIR/hide-speaker-tuning.lua" >&2
        exit 1
    }
    [ -f "$FILES_DIR/speaker-dsp" ] || {
        echo "missing speaker switch helper: $FILES_DIR/speaker-dsp" >&2
        exit 1
    }

    # User configuration fragments merge with /etc. Remove exact old project
    # paths first, otherwise an old filter can create a duplicate sink.
    remove_legacy_system_files
    remove_legacy_user_files

    install -D -m644 "$FILES_DIR/50-speaker-tuning.conf" "$FILTER_DEST"
    install -D -m644 "$FILES_DIR/50-hide-speaker-tuning.conf" "$HIDE_CONF_DEST"
    install -D -m644 "$FILES_DIR/51-speaker-sink-priority.conf" "$PRIORITY_CONF_DEST"
    install -D -m644 "$FILES_DIR/hide-speaker-tuning.lua" "$HIDE_SCRIPT_DEST"
    install -D -m755 "$FILES_DIR/speaker-dsp" /usr/local/bin/speaker-dsp

    echo "Installed the pass-through Speaker DSP starter."
    print_user_restart_instructions
}

case "$ACTION" in
    install) install_filter ;;
    uninstall) uninstall ;;
    *)
        echo "usage: sudo sh install.sh [install|uninstall]" >&2
        exit 2
        ;;
esac
