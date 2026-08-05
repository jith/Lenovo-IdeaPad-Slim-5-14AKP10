#!/bin/sh
# Capture the current graph and null it against a stored baseline.
#
#   tools/null-test.sh baseline <dir> [material...]   # capture the reference
#   tools/null-test.sh compare  <dir> [material...]   # capture and subtract
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
OUTDIR=${2:-}
case $MODE in baseline|compare) ;; *) die "usage: $0 {baseline|compare} <dir> [material...]" ;; esac
[ -n "$OUTDIR" ] || die "usage: $0 $MODE <dir> [material...]"
shift 2
[ $# -gt 0 ] || set -- tests/material/pink.wav tests/material/sweep.wav

require_node "$SINK_DSP"
require_node "$MONITOR_RAW"
mkdir -p "$OUTDIR"

capture() {
    pw-record --target="$MONITOR_RAW" --format=f32 --rate=$RATE --channels=2 \
        "$2" &
    _rec=$!
    sleep 1
    pw-cat -p --target="$SINK_DSP" --format=f32 --rate=$RATE "$1" >/dev/null
    sleep 1
    kill -INT "$_rec" 2>/dev/null || true
    wait "$_rec" 2>/dev/null || true
    [ -s "$2" ] || die "captured nothing for $1"
}

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
        python3 "$DIR/null_residual.py" "$base" "$OUTDIR/$name.current.wav"
    fi
done

[ "$MODE" = baseline ] && echo "baselines written to $OUTDIR" || true
