#!/bin/sh
# Measure the loudness difference between the tuned and raw paths and print
# the trim to enter at stage 13.
#
#   tools/loudness-match.sh [material.wav]
#
# Both captures are taken from the monitor of the PHYSICAL sink, which carries
# post-DSP audio in tuned mode and unprocessed audio in raw mode. Same node
# either way, so the comparison is exact.
#
# The trim always attenuates the louder path at its own output, never boosts
# the quieter one. It is applied after everything, at stage 13 -- stages 7, 10
# and 11 are level-dependent, so trimming the chain input would change what
# they see and you would no longer be comparing the same processing.
set -eu

DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
. "$DIR/common.sh"

need ffmpeg ffmpeg
need pw-record pipewire-utils
need pw-cat pipewire-utils
need pactl pulseaudio-utils
need_report

MATERIAL=${1:-tests/material/pink.wav}
[ -f "$MATERIAL" ] || die "no such file: $MATERIAL (run tools/make-test-material.sh)"

require_node "$SINK_DSP"
require_node "$SINK_RAW"

WORK=$(mktemp -d -t loudmatch-XXXXXX)
trap 'rm -rf "$WORK"' EXIT

DUR=$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$MATERIAL")

# capture <label> <target-sink> -- targets the sink directly rather than
# switching the default, so the desktop's output selection is left alone.
capture() {
    _out=$WORK/$1.wav
    record_sink "$SINK_RAW" "$_out"; _rec=$REC_PID
    sleep 1
    pw-cat -p --target="$2" --format=f32 --rate=$RATE "$MATERIAL" >/dev/null
    sleep 1
    stop_record "$_rec"
    assert_sane_capture "$_out" "$1"
}

echo "material $MATERIAL (${DUR}s)"
echo "capture  $SINK_RAW (monitor)"
echo
echo "This plays through the speakers twice. Set a comfortable level with the"
echo "HARDWARE sink's volume -- it sits after the monitor tap, so it does not"
echo "affect the measurement. Do not use the virtual sink's volume, which is"
echo "before the filter graph and would."
echo

echo "1/2 tuned ..."
capture tuned "$SINK_DSP"
echo "2/2 raw ..."
capture raw "$SINK_RAW"

L_TUNED=$(lufs "$WORK/tuned.wav") || die "loudness measurement failed (tuned)"
L_RAW=$(lufs "$WORK/raw.wav") || die "loudness measurement failed (raw)"

echo
echo "integrated loudness (ITU-R BS.1770)"
printf '  tuned  %8s LUFS\n' "$L_TUNED"
printf '  raw    %8s LUFS\n' "$L_RAW"

awk -v t="$L_TUNED" -v r="$L_RAW" -v raw="$SINK_RAW" '
BEGIN {
    d = t - r
    printf "  delta  %+8.2f LU (tuned - raw)\n\n", d
    if (d > 0.05) {
        printf "tuned is louder. Trim the tuned path at stage 13 of\n"
        printf "files/50-speaker-tuning.conf, then reinstall:\n"
        printf "  s13trim_l / s13trim_r   \"Mult\" = %.6f   (%.2f dB)\n", \
               10 ^ (-d / 20), -d
        printf "\nleave the raw path alone.\n"
    } else if (d < -0.05) {
        printf "raw is louder. Trim the raw path at its own output:\n"
        printf "  pactl set-sink-volume %s %.2f%%\n", raw, 100 * 10 ^ (d / 20)
        printf "\nleave stage 13 at Mult = 1.0.\n"
    } else {
        printf "matched within 0.1 LU. Leave stage 13 at Mult = 1.0.\n"
    }
}'
