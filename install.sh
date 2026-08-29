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
SYNC_CONF_DEST=/etc/wireplumber/wireplumber.conf.d/54-volume-sync.conf
SYNC_SCRIPT_DEST=/usr/local/share/wireplumber/scripts/54-volume-sync.lua
# Going down with an A2DP session open leaves the receiver holding a stream
# endpoint for a host that is gone, and the next connect is answered with
# silence until the device is re-paired. The same script closes the session from
# the unit's ExecStop on shutdown and from the sleep hook before a suspend.
BT_SCRIPT_DEST=/usr/local/bin/speaker-dsp-bt-disconnect
BT_UNIT_DEST=/etc/systemd/system/speaker-dsp-bt-disconnect.service
BT_SLEEP_DEST=/usr/lib/systemd/system-sleep/55-speaker-dsp-bt
EXT_UNIT_OLD=/etc/systemd/user/external-dsp.service

print_user_restart_instructions() {
    echo "For each logged-in user, run:"
    echo "  systemctl --user restart pipewire pipewire-pulse wireplumber"
}

uninstall() {
    systemctl disable --now speaker-dsp-bt-disconnect.service >/dev/null 2>&1 || true

    rm -f -- \
        "$FILTER_DEST" \
        "$HIDE_CONF_DEST" \
        "$PRIORITY_CONF_DEST" \
        "$HIDE_SCRIPT_DEST" \
        "$EXT_FILTER_DEST" \
        "$EXT_CONF_DEST" \
        "$EXT_SCRIPT_DEST" \
        "$SYNC_CONF_DEST" \
        "$SYNC_SCRIPT_DEST" \
        "$BT_SCRIPT_DEST" \
        "$BT_UNIT_DEST" \
        "$BT_SLEEP_DEST" \
        "$EXT_UNIT_OLD" \
        /etc/systemd/user/external-dsp.service \
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
    [ -f "$FILES_DIR/55-bt-disconnect" ] || {
        echo "missing Bluetooth teardown script: $FILES_DIR/55-bt-disconnect" >&2
        exit 1
    }
    [ -f "$FILES_DIR/55-bt-disconnect.service" ] || {
        echo "missing Bluetooth teardown unit: $FILES_DIR/55-bt-disconnect.service" >&2
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
    install -D -m644 "$FILES_DIR/54-volume-sync.conf" "$SYNC_CONF_DEST"
    install -D -m644 "$FILES_DIR/54-volume-sync.lua" "$SYNC_SCRIPT_DEST"

    # The chains are per CLASS of output, not per device, so this expands to the
    # same file every time and can be generated here rather than by hand or by
    # the user. One copy of 150 lines of measured settings, two chains built
    # from it.
    SPEAKER_DSP_TEMPLATE="$FILES_DIR/52-external-tuning.conf" \
        python3 "$FILES_DIR/gen-external-chains.py" "$EXT_FILTER_DEST"
    chmod 644 "$EXT_FILTER_DEST"
    # Retire the watcher service from an earlier version. Only the unit is
    # removed here: the other "old" paths are now the SAME paths this function
    # has just written, so deleting them removed the files it had installed a
    # few lines earlier -- and still reported success, which is exactly how two
    # installs in a row appeared to do nothing at all.
    rm -f "$EXT_UNIT_OLD"
    install -D -m755 "$FILES_DIR/external-dsp" /usr/local/bin/external-dsp

    # One script, two callers: ExecStop on the way down, the sleep hook before a
    # suspend. Started as well as enabled, or ExecStop would not run until the
    # unit had been started once -- which for a shutdown-only unit means never.
    install -D -m755 "$FILES_DIR/55-bt-disconnect" "$BT_SCRIPT_DEST"
    install -D -m755 "$FILES_DIR/55-bt-disconnect" "$BT_SLEEP_DEST"
    install -D -m644 "$FILES_DIR/55-bt-disconnect.service" "$BT_UNIT_DEST"
    systemctl daemon-reload >/dev/null 2>&1 || true
    systemctl enable --now speaker-dsp-bt-disconnect.service >/dev/null 2>&1 || true

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
