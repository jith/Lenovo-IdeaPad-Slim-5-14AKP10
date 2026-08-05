#!/bin/sh
# Shared node names and helpers for the speaker DSP tools.
# Sourced, not run. Keep node names here only -- files/speaker-dsp and
# files/50-speaker-tuning.conf are the other two places they appear.

SINK_DSP=effect_input.speaker-tuning
SINK_RAW=alsa_output.pci-0000_04_00.6.HiFi__Speaker__sink

# Mic1 on this machine is railed: it returns full-scale samples with a dozen
# distinct values whatever the room is doing. Mic2 is the working internal
# microphone -- a quiet room reads about -60 dBFS through it.
MIC_DEFAULT=alsa_input.pci-0000_04_00.6.HiFi__Mic2__source

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

# record_sink <sink> <file> -- start capturing a sink's output in the
# background, setting REC_PID. Caller stops it with stop_record "$REC_PID".
#
# Sets a global rather than echoing the PID: pw-record prints its filename on
# stdout, so a $(record_sink ...) substitution captures that too and then
# blocks until the pipe closes, which is never while the recorder is running.
#
# The capture point is the sink's monitor, which carries post-DSP audio when
# the chain is in front of it and unprocessed audio when it is not. Same node
# either way, so an A/B through it compares like with like.
#
# The monitor is also ahead of the codec's hardware volume, so turning the
# speakers down does not change what is measured. Measured on this machine:
# the same 3 s of pink noise captured at 100% / 40% / 15% hardware volume
# reads -21.378 / -21.444 / -21.444 dBFS -- a 16 dB change in volume moves the
# capture by 0.07 dB, which is capture-start jitter, not level. Use the
# hardware sink's volume to set a comfortable listening level, never the
# virtual sink's, which sits before the filter graph and would change what the
# level-dependent stages see.
#
# It has to be `-P stream.capture.sink=true` against the SINK's own name.
# `pw-record --target=<sink>.monitor` looks like it should work -- that is the
# name pactl prints -- but the monitor is not a native node, the target does
# not resolve, and pw-record writes full-scale garbage instead of failing.
record_sink() {
    pw-record -P 'stream.capture.sink=true' --target="$1" \
        --format=f32 --rate=$RATE --channels=2 "$2" >/dev/null 2>&1 &
    REC_PID=$!
}

stop_record() {
    kill -INT "$1" 2>/dev/null || true
    wait "$1" 2>/dev/null || true
}

# assert_sane_capture <file> <label> -- refuse to report numbers from a
# capture that is saturated or silent. A railed source and an unresolved
# target both produce a file that looks superficially fine, and every
# measurement downstream of one is meaningless.
assert_sane_capture() {
    [ -s "$1" ] || die "$2: captured nothing"
    ffmpeg -hide_banner -nostats -i "$1" -af astats=metadata=1 -f null - 2>&1 \
        | awk -v label="$2" -v f="$1" '
            /Peak level dB/ { if (pk == "") pk = $NF }
            /RMS level dB/  { if (rms == "") rms = $NF }
            END {
                if (pk == "" || rms == "") {
                    printf "error: %s: could not measure %s\n", label, f > "/dev/stderr"
                    exit 1
                }
                if (pk >= -0.001 && rms >= -3.0) {
                    printf "error: %s: capture is railed (peak %s dBFS, RMS %s dBFS).\n", label, pk, rms > "/dev/stderr"
                    printf "  A working capture never sits within 3 dB of full scale.\n" > "/dev/stderr"
                    printf "  Check the source is not Mic1, which is broken on this machine.\n" > "/dev/stderr"
                    exit 1
                }
                if (rms <= -90.0) {
                    printf "error: %s: capture is silent (RMS %s dBFS).\n", label, rms > "/dev/stderr"
                    exit 1
                }
            }' || exit 1
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
