#!/bin/sh
# Hear Voice Isolation on your own voice: record the raw built-in mic and the
# Voice Isolation source at the same moment, then write one file that plays the
# raw take and then the processed one.
#
#   tools/voice-isolation-ab.sh [out.wav] [--seconds 25]
#
# Talk as you would on a call, with pauses, some typing and whatever the room
# is doing: the pauses are what Voice Isolation is for. The raw half is the two
# capsules summed to mono at 0.5 each, which is what the filter itself is fed,
# so the halves differ only by the processing. Both halves share one gain, so
# their levels compare. The two-channel raw take is kept beside the output as
# <out>-raw.wav: real speech and real room noise, for tuning the plugin offline.
set -eu
. "$(dirname "$0")/common.sh"

OUT=voice-isolation-ab.wav
SECS=25
while [ $# -gt 0 ]; do
    case "$1" in
        --seconds) SECS=$2; shift 2 ;;
        -*) die "unknown option $1" ;;
        *) OUT=$1; shift ;;
    esac
done

_missing=""
need pw-record pipewire-bin
need ffmpeg ffmpeg
need_report
require_node "$MIC_DEFAULT"
require_node voice-isolation

RAW=${OUT%.wav}-raw.wav
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

echo "Recording ${SECS} s. Talk normally, leave pauses, type a little."
timeout "$SECS" pw-record --target "$MIC_DEFAULT" --rate 48000 --channels 2 \
    --format f32 "$RAW" 2>/dev/null &
timeout "$SECS" pw-record --target voice-isolation --rate 48000 --channels 1 \
    --format f32 "$TMP/vi.wav" 2>/dev/null &
i=$SECS
while [ "$i" -gt 0 ]; do printf '\r  %2d s left ' "$i"; sleep 1; i=$((i - 1)); done
wait || true
printf '\r  done.        \n'

assert_sane_capture "$RAW" "raw mic"
[ -s "$TMP/vi.wav" ] || die "Voice Isolation captured nothing"

# One gain for both halves, from the raw take's peak, and 1 s of silence
# between them.
PEAK=$(ffmpeg -hide_banner -nostats -i "$RAW" -af "pan=mono|c0=0.5*c0+0.5*c1,astats" \
    -f null - 2>&1 | awk '/Peak level dB/ { v = $NF } END { print v }')
GAIN=$(awk -v p="$PEAK" 'BEGIN { printf "%.2f", -3 - p }')
ffmpeg -hide_banner -loglevel error -y -i "$RAW" -i "$TMP/vi.wav" -filter_complex \
    "[0]pan=mono|c0=0.5*c0+0.5*c1,volume=${GAIN}dB,apad=pad_dur=1[a];\
     [1]volume=${GAIN}dB[b];[a][b]concat=n=2:v=0:a=1" \
    -c:a pcm_s16le "$OUT"
echo "wrote $OUT: raw first, then Voice Isolation (both at ${GAIN} dB)"
echo "kept  $RAW: the raw two-channel take"
