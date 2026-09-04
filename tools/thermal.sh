#!/bin/sh
# Hold the speaker at programme level for minutes and see if it gets quieter.
#
#   tools/thermal.sh [out.wav] [--soak SECONDS] [--level dBFS] [--mic NODE]
#                    [--shape-from RENDER.wav]
#
# ---------------------------------------------------------------------------
# WHAT THIS IS FOR, AND WHY IT IS NOT max-level.sh
# ---------------------------------------------------------------------------
# max-level.sh varies LEVEL and asks where the driver runs out now. This varies
# TIME at one level and asks whether it stays there. Those are different
# failures: the first is excursion, the second is a voice coil heating up,
# gaining resistance and losing sensitivity over minutes. Everything else in
# tools/ runs for seconds and is structurally blind to the second one.
#
# It exists because "how loud can it go" ends on an unmeasured claim -- that
# g_out above 4.25 costs something thermal that shows up "as compression and
# strain over minutes that no capture here is long enough to see". This is the
# capture that is long enough.
#
# THIS RUNS THROUGH THE RAW SINK, like max-level.sh and for the same reason:
# what is being measured is the speaker, and the chain's own dynamics would
# move the level while the driver is being asked to hold it.
#
# The level therefore has to be set to what the CHAIN delivers, not to full
# scale. The default -10.3 dBFS RMS is music2 -- the densest real master here --
# rendered through the shipped chain. Pink at that RMS has a lower crest than
# music, so it heats at least as hard for the same average power.
#
# ---------------------------------------------------------------------------
# THIS IS THE ONE MEASUREMENT IN THIS REPO THAT COULD DAMAGE SOMETHING
# ---------------------------------------------------------------------------
# Ten minutes of continuous programme-level noise into 2 W sealed drivers at
# hardware volume 100% is the stress the test is about. max-level.sh reaches
# full scale but only in half-second bursts; this does not stop. Stop it at the
# first buzz, rattle, scrape or smell of hot glue. There is no measurement here
# worth a driver.
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
        --soak) GENARGS="$GENARGS --soak ${2:?}"; shift 2 ;;
        --cool) GENARGS="$GENARGS --cool ${2:?}"; shift 2 ;;
        --recover) GENARGS="$GENARGS --recover ${2:?}"; shift 2 ;;
        --level) GENARGS="$GENARGS --level ${2:?}"; shift 2 ;;
        --tile) GENARGS="$GENARGS --tile ${2:?}"; shift 2 ;;
        --shape-from) GENARGS="$GENARGS --shape-from ${2:?}"; shift 2 ;;
        --gen-only) GENONLY=1; shift ;;
        -h|--help) sed -n '2,40p' "$0"; exit 0 ;;
        -*) die "unknown option $1" ;;
        *) OUT=$1; shift ;;
    esac
done
[ -n "$OUT" ] || OUT="thermal-$(date +%Y%m%d-%H%M%S).wav"
SCHED="${OUT%.wav}.schedule.json"
STIM="${OUT%.wav}.stimulus.wav"

# shellcheck disable=SC2086
python3 "$DIR/thermal.py" gen "$STIM" "$SCHED" $GENARGS
DUR=$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$STIM")

if [ "${GENONLY:-0}" = "1" ]; then
    echo
    echo "stimulus only: $STIM"
    echo "nothing was played."
    exit 0
fi

require_node "$SINK_RAW"
require_node "$MIC"

VOL_WAS=$(pactl get-sink-volume "$SINK_RAW" | awk 'NR==1{for(i=1;i<=NF;i++) if($i ~ /^[0-9]+%$/){print $i; exit}}')
[ -n "$VOL_WAS" ] || die "could not read the volume of $SINK_RAW"
restore() { pactl set-sink-volume "$SINK_RAW" "$VOL_WAS" 2>/dev/null || true; }
trap restore EXIT INT TERM PIPE HUP

echo
echo "out     $SINK_RAW at 100% (was $VOL_WAS, restored on exit)"
echo "mic     $MIC"
echo "writing $OUT"
echo
echo "This plays CONTINUOUSLY for about $((${DUR%.*} / 60)) min $((${DUR%.*} % 60)) s."
echo "Keep the room quiet and do not move the laptop."
echo "STOP WITH Ctrl-C at any buzz, rattle, scrape or smell. Nothing this"
echo "measures is worth a driver."
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
echo "  tools/thermal.py analyze $OUT $SCHED"
