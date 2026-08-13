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

# assert_unity_volume <sink> -- refuse to measure through a sink that is not at
# 100%.
#
# The virtual sink's volume is applied BEFORE the filter graph (measured: 50%
# on the virtual sink drops the hardware monitor by 18.08 dB, which is pactl's
# cubic 0.125). So a capture taken at 94% is 1.6 dB low, and 1.6 dB is larger
# than most of the differences this repo measures. It does not look like an
# error -- it looks like a tuning result, in the wrong direction.
#
# That is not hypothetical. A g_out 2.40 -> 2.60 change measured as 1.34 LU
# QUIETER because pipewire came back at 94% after a restart, and the whole
# capture set had to be thrown away. Hence a hard failure rather than a warning.
#
# Note this is the opposite rule to the HARDWARE sink, whose volume sits after
# the monitor tap and cannot affect a capture at all -- see record_sink below.
# Set your listening level there, never here.
#
# ---------------------------------------------------------------------------
# It is not only a LEVEL error. It is a VOICING error. -- session D, 13 Aug 2026
# ---------------------------------------------------------------------------
# Because the attenuation lands ahead of GOTT, the excursion limiter and the
# brickwall, turning the virtual sink down makes all three work LESS, and the
# delivered shape changes. Measured on a -6.3 LUFS master, each column re its
# own 1.6-10 kHz level:
#
#     re 1.6-10 kHz     93%      88%      79%
#     80 Hz           +0.88    +1.55    +2.78
#     200 Hz          +0.58    +0.83    +0.93
#     800 Hz          -0.21    -0.53    -1.41
#     10 kHz          +0.27    +0.49    +0.93
#
# Quieter is bassier and less mid-forward -- accidental loudness compensation,
# in the direction hearing wants. Percent maps to dB as 60*log10(pct): 88% is
# -3.3 dB and 76% is -7.2 dB, not "a bit down".
#
# THE DECISIVE TEST, if this is ever doubted again. A post-graph volume delivers
# exactly its own attenuation. A pre-graph one does not, because the dynamics
# give some back. At 60% (-11.14 dB) on loud programme the chain's output fell
# only 6.91 dB -- 4.2 dB of give-back. (The older 50% -> -18.08 dB observation
# above does NOT distinguish the two: it was taken at a level too low to engage
# the dynamics, where a pre-graph volume passes through exactly. Both readings
# are correct and only the loud one is diagnostic.)
#
# WHAT THIS COSTS THE MEASUREMENTS, and it is not nothing: unity is the right
# setting for REPRODUCIBILITY and the wrong one for REPRESENTATIVENESS. This
# machine is listened to at 76-88%, so a voicing measured here at 100% is 1-3 dB
# less bassy than the one the listener actually judges. When a measurement and
# an ear disagree by about that much in the bass, suspect this before concluding
# either is wrong. Take voicing captures at the listening volume, note it in the
# capture log, and keep both sides of any A/B at the SAME volume -- that, not
# unity as such, is what makes a comparison valid.
assert_unity_volume() {
    pactl get-sink-volume "$1" 2>/dev/null | awk -v s="$1" '
        NR == 1 {
            for (i = 1; i <= NF; i++)
                if ($i ~ /^[0-9]+%$/) { v = $i; sub(/%/, "", v); break }
            if (v == "") {
                printf "error: could not read the volume of %s\n", s > "/dev/stderr"
                exit 1
            }
            if (v + 0 != 100) {
                printf "error: %s is at %s%%, not 100%%.\n", s, v > "/dev/stderr"
                printf "  Its volume is applied BEFORE the filter graph, so every\n" > "/dev/stderr"
                printf "  level measured through it would be wrong by that much.\n" > "/dev/stderr"
                printf "  Fix with:  pactl set-sink-volume %s 100%%\n", s > "/dev/stderr"
                printf "  Set your listening level on the hardware sink instead.\n" > "/dev/stderr"
                exit 1
            }
        }' || exit 1
}

# record_operating_point <sink> -- for VOICING captures, where unity is not
# required but knowing the number is.
#
# assert_unity_volume above is the right guard for a LEVEL measurement, where
# two renditions are compared in LUFS and a 1.6 dB offset is fatal. It is the
# wrong guard for a response measurement taken at the listening volume, which is
# the only kind that can be compared against an ear. This one never fails: it
# prints the operating point so it lands in the capture log, and every capture
# in one comparison must show the same line or the comparison is void.
record_operating_point() {
    pactl get-sink-volume "$1" 2>/dev/null | awk -v s="$1" '
        NR == 1 {
            for (i = 1; i <= NF; i++)
                if ($i ~ /^[0-9]+%$/) { v = $i; sub(/%/, "", v); break }
            if (v == "") {
                printf "operating point: UNKNOWN -- could not read %s\n", s
                exit 0
            }
            db = 60 * log(v / 100) / log(10)
            printf "operating point: %s at %s%% (%+.2f dB into the graph)%s\n",
                   s, v, db, (v + 0 == 100 ? " -- unity" : "")
            if (v + 0 != 100)
                printf "  valid for voicing work as long as EVERY capture in this\n" \
                       "  comparison reports this same number. Not valid for level work.\n"
        }'
}

# warn_hardware_volume -- the level the SPEAKERS are at, which no capture sees.
#
# assert_unity_volume above guards the virtual sink because its volume lands
# inside the measurement. This is the opposite hazard and it is worse, because
# nothing catches it: the hardware sink's volume sits AFTER the monitor tap, so
# every capture, null test and loudness match in this repo reads identically at
# 100% and at 60%. The tooling cannot tell. Only your ears can.
#
# Found at 94% -- 1.61 dB down -- with the whole chain tuned as though it were
# not, which is 1.61 dB larger than most of what this repo argues about. It
# gets there on its own: `speaker-dsp off` copies the virtual sink's level
# across, a volume key press moves it, and pipewire has been seen returning to
# 94% after a restart.
#
# 100% is the right setting and there is measured headroom for it. See README,
# "What the drivers actually take": at 100% the chain's worst band sits 21 dB
# under the only frequency where these drivers mechanically run out.
warn_hardware_volume() {
    pactl get-sink-volume "$SINK_RAW" 2>/dev/null | awk -v s="$SINK_RAW" '
        NR == 1 {
            for (i = 1; i <= NF; i++)
                if ($i ~ /^[0-9]+%$/) { v = $i; sub(/%/, "", v); break }
            if (v != "" && v + 0 != 100) {
                printf "note: the speakers are at %s%%, not 100%%.\n", v
                printf "  This sits after the monitor tap, so no capture in\n"
                printf "  this repo can see it -- but you can hear it.\n"
                printf "  Fix with:  pactl set-sink-volume %s 100%%\n", s
            }
        }'
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
