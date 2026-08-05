#!/bin/sh
# Capture the current graph and null it against a stored baseline.
#
#   tools/null-test.sh baseline <dir> [material...]   # capture the reference
#   tools/null-test.sh compare [--pre-stage1] <dir> [material...]
#
# --pre-stage1 says the stored baseline is a pass-through capture taken before
# stage 1 existed, so its 20 Hz high-pass has to be applied to the baseline
# before subtracting. Leave it off for a baseline captured through this graph.
#
# Both captures come from the monitor of the physical sink, played through the
# virtual sink. Take the baseline BEFORE changing the graph and keep the WAVs
# outside the repo; every later claim of "unchanged" is measured against those
# files rather than against memory.
#
# The comparison sample-aligns by cross-correlation, inverts and sums. It
# reports the residual peak in dBFS overall and split at 30 Hz, because the
# stage 1 subsonic high-pass is expected to show up below 30 Hz and nowhere
# else.
set -eu

DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
. "$DIR/common.sh"

need ffmpeg ffmpeg
need pw-record pipewire-utils
need pw-cat pipewire-utils
need python3 python3
need_report
python3 -c 'import numpy' 2>/dev/null \
    || die "numpy missing. install with: sudo apt install python3-numpy"

MODE=${1:-}
case $MODE in baseline|compare) ;; *) die "usage: $0 {baseline|compare} [--pre-stage1] <dir> [material...]" ;; esac
shift
HP_ARGS=""
if [ "${1:-}" = "--pre-stage1" ]; then HP_ARGS="--hp 20"; shift; fi
OUTDIR=${1:-}
[ -n "$OUTDIR" ] || die "usage: $0 $MODE [--pre-stage1] <dir> [material...]"
shift
[ $# -gt 0 ] || set -- tests/material/pink.wav tests/material/sweep.wav

require_node "$SINK_DSP"
require_node "$SINK_RAW"
mkdir -p "$OUTDIR"

capture() {
    record_sink "$SINK_RAW" "$2"; _rec=$REC_PID
    sleep 1
    pw-cat -p --target="$SINK_DSP" --format=f32 --rate=$RATE "$1" >/dev/null
    sleep 1
    stop_record "$_rec"
    assert_sane_capture "$2" "$(basename "$1")"
}

FAILED=0
for m in "$@"; do
    [ -f "$m" ] || die "no such file: $m (run tools/make-test-material.sh)"
    name=$(basename "$m" .wav)
    if [ "$MODE" = baseline ]; then
        echo "baseline $name ..."
        capture "$m" "$OUTDIR/$name.baseline.wav"
    else
        base=$OUTDIR/$name.baseline.wav
        [ -f "$base" ] || die "no baseline for $name in $OUTDIR"
        echo "compare $name ..."
        capture "$m" "$OUTDIR/$name.current.wav"
        # Every item gets measured even when an earlier one fails; one bad
        # stage should not hide the rest of the picture.
        # shellcheck disable=SC2086
        python3 "$DIR/null_residual.py" $HP_ARGS \
            "$base" "$OUTDIR/$name.current.wav" || FAILED=1
    fi
done

if [ "$MODE" = baseline ]; then
    echo "baselines written to $OUTDIR"
fi
exit $FAILED
