#!/bin/sh
# Play the tone grid through the RAW hardware speaker and record it on the
# internal microphone, to find where the hardware starts to distort.
#
#   tools/max-level.sh [out.wav] [--mic NODE] [--freqs 500,1000] [--levels ...]
#
# ---------------------------------------------------------------------------
# WHY THE HARDWARE SINK GOES TO 100% FIRST
# ---------------------------------------------------------------------------
# The hardware sink's volume sits AFTER the monitor tap but BEFORE the
# amplifier, so it is the one control in this repo that changes what the
# speaker actually does without changing anything a sink capture can see.
# Every level in the resulting table is therefore quoted as "dBFS at hardware
# volume 100%", which is the only reference that makes them comparable to what
# the chain puts out. The script records the volume it found, sets 100%, and
# puts it back on exit.
#
# That also means this measurement is LOUD -- it ends on full-scale tones at
# the maximum the machine can produce. It is deliberately built up from -24
# dBFS one frequency at a time, so stop it at the first buzz or rattle.
#
# The grid goes through the RAW sink, not the DSP one: what is being measured
# is the speaker, and stages 5-8 synthesise harmonics on purpose, which would
# land on top of exactly the harmonics this is counting.
set -eu

DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
. "$DIR/common.sh"

need ffmpeg ffmpeg
need ffprobe ffmpeg
need pw-record pipewire-utils
need pw-cat pipewire-utils
need pactl pulseaudio-utils
need python3 python3
need_report

OUT=""
MIC=$MIC_DEFAULT
GENARGS=""
while [ $# -gt 0 ]; do
    case $1 in
        --mic) MIC=${2:?--mic needs a node name}; shift 2 ;;
        --freqs) GENARGS="$GENARGS --freqs ${2:?}"; shift 2 ;;
        --levels) GENARGS="$GENARGS --levels ${2:?}"; shift 2 ;;
        --burst) GENARGS="$GENARGS --burst ${2:?}"; shift 2 ;;
        --gap) GENARGS="$GENARGS --gap ${2:?}"; shift 2 ;;
        --ref) GENARGS="$GENARGS --ref ${2:?}"; shift 2 ;;
        -h|--help) sed -n '2,30p' "$0"; exit 0 ;;
        -*) die "unknown option $1" ;;
        *) OUT=$1; shift ;;
    esac
done
[ -n "$OUT" ] || OUT="maxlevel-$(date +%Y%m%d-%H%M%S).wav"
SCHED="${OUT%.wav}.schedule.json"

require_node "$SINK_RAW"
require_node "$MIC"

STIM=$(mktemp -t maxlevel-XXXXXX.wav)

# Restore the listening volume whatever happens, including Ctrl-C.
VOL_WAS=$(pactl get-sink-volume "$SINK_RAW" | awk 'NR==1{for(i=1;i<=NF;i++) if($i ~ /^[0-9]+%$/){print $i; exit}}')
[ -n "$VOL_WAS" ] || die "could not read the volume of $SINK_RAW"
restore() {
    pactl set-sink-volume "$SINK_RAW" "$VOL_WAS" 2>/dev/null || true
    rm -f "$STIM"
}
# PIPE included on purpose: piping this script into `head` kills it on the
# next echo, the EXIT trap never runs, and the speakers are left at 100%
# without anything saying so.
trap restore EXIT INT TERM PIPE HUP

# shellcheck disable=SC2086
python3 "$DIR/max-level.py" gen "$STIM" "$SCHED" $GENARGS

DUR=$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$STIM")

echo "out     $SINK_RAW at 100% (was $VOL_WAS, restored on exit)"
echo "mic     $MIC"
echo "writing $OUT"
echo
echo "This plays tones up to FULL SCALE for about ${DUR%.*} s."
echo "Keep the room quiet and do not move the laptop."
echo "Stop with Ctrl-C at the first buzz, rattle or scrape -- that is the"
echo "answer, and it is a cheaper way to get it than the table."
echo

pactl set-sink-volume "$SINK_RAW" 100%

pw-record --target="$MIC" --format=f32 --rate=$RATE --channels=2 "$OUT" &
REC=$!
sleep 1
pw-cat -p --target="$SINK_RAW" --format=f32 --rate=$RATE "$STIM" >/dev/null
sleep 1
kill -INT "$REC" 2>/dev/null || true
wait "$REC" 2>/dev/null || true

assert_sane_capture "$OUT" "mic capture"

echo
echo "captured $OUT"
echo
echo "  tools/max-level.py analyze $OUT $SCHED"
