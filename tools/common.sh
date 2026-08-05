#!/bin/sh
# Shared node names and helpers for the speaker DSP tools.
# Sourced, not run. Keep node names here only -- files/speaker-dsp and
# files/50-speaker-tuning.conf are the other two places they appear.

SINK_DSP=effect_input.speaker-tuning
SINK_RAW=alsa_output.pci-0000_04_00.6.HiFi__Speaker__sink
# Post-DSP in tuned mode, unprocessed in raw mode: the same node either way,
# so an A/B through it compares like with like. Also ahead of the codec's
# hardware volume, so turning the speaker down does not change what is
# measured -- as long as you use the hardware sink's volume and not the
# virtual sink's, which sits before the filter graph.
MONITOR_RAW="$SINK_RAW.monitor"
MIC_DEFAULT=alsa_input.pci-0000_04_00.6.HiFi__Mic1__source

RATE=48000

# need <command> <apt package> -- report every missing tool, install nothing.
_missing=""
need() {
    command -v "$1" >/dev/null 2>&1 || _missing="$_missing $2"
}

need_report() {
    [ -z "$_missing" ] && return 0
    echo "missing tools. install with:" >&2
    # shellcheck disable=SC2086
    echo "  sudo apt install$(printf ' %s' $(echo $_missing | tr ' ' '\n' | sort -u))" >&2
    exit 1
}

# die <message>
die() { echo "error: $*" >&2; exit 1; }

# require_node <node.name> -- fail early rather than capturing silence.
require_node() {
    pactl list short sources 2>/dev/null | cut -f2 | grep -qx "$1" && return 0
    pactl list short sinks 2>/dev/null | cut -f2 | grep -qx "$1" && return 0
    die "node '$1' not found. \`pactl list short sinks\` and \`... sources\` show what exists."
}

# lufs <file> -- integrated loudness, ITU-R BS.1770 / EBU R128.
# Read from loudnorm's JSON rather than the ebur128 filter's summary: same
# measurement, but two decimals instead of one, and matching to 0.1 LU with a
# 0.1 LU readout leaves nothing to spare.
lufs() {
    ffmpeg -hide_banner -nostats -i "$1" -af loudnorm=print_format=json \
        -f null - 2>&1 \
        | awk -F'"' '/"input_i"/{v=$4} END{if (v=="") exit 1; print v}'
}
