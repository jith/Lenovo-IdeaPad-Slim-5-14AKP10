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
# The external chains are GENERATED per device into the user's own conf.d by
# 'external-dsp generate', so nothing external is installed system-wide except
# the generator and the template it reads. The old single-chain config and its
# target-tracking script are removed here if an earlier version left them.
EXT_FILTER_DEST=/etc/pipewire/pipewire.conf.d/52-external-tuning.conf
EXT_CONF_DEST=/etc/wireplumber/wireplumber.conf.d/52-external-target.conf
EXT_SCRIPT_DEST=/usr/local/share/wireplumber/scripts/52-external-target.lua
EXT_FILTER_OLD=/etc/pipewire/pipewire.conf.d/52-external-tuning.conf
EXT_CONF_OLD=/etc/wireplumber/wireplumber.conf.d/52-external-target.conf
EXT_SCRIPT_OLD=/usr/local/share/wireplumber/scripts/52-external-target.lua
EXT_UNIT_OLD=/etc/systemd/user/external-dsp.service

print_user_restart_instructions() {
    echo "For each logged-in user, run:"
    echo "  systemctl --user restart pipewire pipewire-pulse wireplumber"
}

uninstall() {
    rm -f -- \
        "$FILTER_DEST" \
        "$HIDE_CONF_DEST" \
        "$PRIORITY_CONF_DEST" \
        "$HIDE_SCRIPT_DEST" \
        "$EXT_FILTER_OLD" \
        "$EXT_CONF_OLD" \
        "$EXT_SCRIPT_OLD" \
        "$EXT_UNIT_OLD" \
        /usr/local/bin/gen-external-chains.py \
        /usr/local/bin/external-dsp-watch \
        /etc/systemd/user/external-dsp-watch.service \
        /usr/local/share/speaker-dsp/52-external-tuning.conf \
        /etc/wireplumber/wireplumber.conf.d/53-hide-absent-tuned.conf \
        /usr/local/share/wireplumber/scripts/53-hide-absent-tuned.lua \
        /usr/local/bin/speaker-dsp \
        /usr/local/bin/external-dsp

    echo "Removed the system-wide Speaker DSP files."
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
    [ -f "$FILES_DIR/52-external-tuning.conf" ] || {
        echo "missing external filter config: $FILES_DIR/52-external-tuning.conf" >&2
        exit 1
    }
    [ -f "$FILES_DIR/gen-external-chains.py" ] || {
        echo "missing chain generator: $FILES_DIR/gen-external-chains.py" >&2
        exit 1
    }
    [ -f "$FILES_DIR/52-external-target.lua" ] || {
        echo "missing target script: $FILES_DIR/52-external-target.lua" >&2
        exit 1
    }
    [ -f "$FILES_DIR/52-external-target.conf" ] || {
        echo "missing target config: $FILES_DIR/52-external-target.conf" >&2
        exit 1
    }
    [ -f "$FILES_DIR/external-dsp" ] || {
        echo "missing external switch helper: $FILES_DIR/external-dsp" >&2
        exit 1
    }

    # The target script is not optional. Without it the external chain has no
    # resolved target, and PipeWire routes its output into the INTERNAL chain --
    # everything processed twice, by two chains tuned for different speakers.
    # Refuse to install the filter without its script.

    install -D -m644 "$FILES_DIR/50-speaker-tuning.conf" "$FILTER_DEST"
    install -D -m644 "$FILES_DIR/50-hide-speaker-tuning.conf" "$HIDE_CONF_DEST"
    install -D -m644 "$FILES_DIR/51-speaker-sink-priority.conf" "$PRIORITY_CONF_DEST"
    install -D -m644 "$FILES_DIR/hide-speaker-tuning.lua" "$HIDE_SCRIPT_DEST"
    install -D -m755 "$FILES_DIR/speaker-dsp" /usr/local/bin/speaker-dsp
    install -D -m644 "$FILES_DIR/52-external-tuning.conf" \
        /usr/local/share/speaker-dsp/52-external-tuning.conf
    install -D -m644 "$FILES_DIR/52-external-target.conf" "$EXT_CONF_DEST"
    install -D -m644 "$FILES_DIR/52-external-target.lua" "$EXT_SCRIPT_DEST"

    # The chains are per CLASS of output, not per device, so this expands to the
    # same file every time and can be generated here rather than by hand or by
    # the user. One copy of 150 lines of measured settings, two chains built
    # from it.
    SPEAKER_DSP_TEMPLATE="$FILES_DIR/52-external-tuning.conf" \
        python3 "$FILES_DIR/gen-external-chains.py" "$EXT_FILTER_DEST"
    chmod 644 "$EXT_FILTER_DEST"
    # Retire the previous single-chain setup, or its "External (Tuning)" sink
    # loads alongside the generated per-device ones and every stream is
    # processed twice.
    rm -f "$EXT_FILTER_OLD" "$EXT_CONF_OLD" "$EXT_SCRIPT_OLD" "$EXT_UNIT_OLD"
    install -D -m755 "$FILES_DIR/external-dsp" /usr/local/bin/external-dsp

    echo "Installed the fourteen-stage Speaker DSP filter chain (internal)"
    echo "and the six-stage External (Tuning) chain for every other output."
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
