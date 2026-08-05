#!/bin/sh
# Play a log sweep through the raw hardware speaker and record it on the
# internal microphone, for offline analysis of the sealed-box resonance.
#
#   tools/measure-speaker.sh [out.wav] [--mic NODE] [--level 0.3]
#
# ---------------------------------------------------------------------------
# WHAT THIS MEASUREMENT IS AND IS NOT
# ---------------------------------------------------------------------------
# The internal microphone is uncalibrated and sits inside the chassis. It
# hears case resonance and its own arbitrary frequency response along with the
# speaker. It is NOT a measurement microphone.
#
# Valid uses:
#   - locating the resonance peak fc
#   - estimating Qtc from the shape of that peak
#   - relative before/after comparison, same mic, same position, same level
#
# Not valid: any absolute claim about frequency response. Do not read a dip at
# 4 kHz as a speaker dip; it is as likely to be the mic or the chassis.
#
# The sweep is played through the RAW sink deliberately, so what is measured
# is the speaker and not the DSP.
set -eu

DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
. "$DIR/common.sh"

need ffmpeg ffmpeg
need pw-record pipewire-utils
need pw-cat pipewire-utils
need pactl pulseaudio-utils
need_report

OUT=""
MIC=$MIC_DEFAULT
LEVEL=0.3
while [ $# -gt 0 ]; do
    case $1 in
        --mic) MIC=${2:?--mic needs a node name}; shift 2 ;;
        --level) LEVEL=${2:?--level needs a value}; shift 2 ;;
        -h|--help) sed -n '2,30p' "$0"; exit 0 ;;
        -*) die "unknown option $1" ;;
        *) OUT=$1; shift ;;
    esac
done
[ -n "$OUT" ] || OUT="sweep-$(date +%Y%m%d-%H%M%S).wav"

require_node "$SINK_RAW"
require_node "$MIC"

SWEEP=$(mktemp -t sweep-XXXXXX.wav)
trap 'rm -f "$SWEEP"' EXIT

# 30 s log sweep, 20 Hz -> 20 kHz. ln(20000/20) = ln(1000).
ffmpeg -hide_banner -loglevel error -y \
    -f lavfi -i "aevalsrc='$LEVEL*sin(2*PI*20*30/log(1000)*(exp(t*log(1000)/30)-1))':d=30:s=$RATE:c=stereo" \
    -c:a pcm_f32le "$SWEEP"

echo "sweep   20 Hz -> 20 kHz, 30 s, amplitude $LEVEL"
echo "out     $SINK_RAW"
echo "mic     $MIC"
echo "writing $OUT"
echo
echo "Keep the room quiet and do not move the laptop for the next 35 s."
echo "Stop and report if you hear buzzing, rattling or scraping."
echo

pw-record --target="$MIC" --format=f32 --rate=$RATE --channels=2 "$OUT" &
REC=$!
# Let the capture stream settle before the sweep starts.
sleep 1
pw-cat -p --target="$SINK_RAW" --format=f32 --rate=$RATE "$SWEEP" >/dev/null
sleep 1
kill -INT "$REC" 2>/dev/null || true
wait "$REC" 2>/dev/null || true

echo
echo "captured $OUT"
echo
echo "Find the resonance peak, then read fc and Qtc off it:"
echo "  ffmpeg -i $OUT -lavfi ashowinfo -f null -   # sanity: is there signal"
echo "  ffmpeg -i $OUT -lavfi 'showspectrumpic=s=1600x800:legend=1' spectrum.png"
echo
echo "fc is the peak frequency. Qtc = fc / bandwidth at -3 dB from the peak."
echo "Feed both to tools/lt-coeffs.py together with the target you want."
