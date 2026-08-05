#!/bin/sh
# Generate the synthetic test material into tests/material/ (gitignored).
#
#   tools/make-test-material.sh [dir]
#
# Uses ffmpeg, which this machine has; sox is not installed. The equivalent
# sox commands are in README.md for anyone who prefers it.
#
# Drop your own music tracks alongside these. Three with known low-frequency
# content is the useful number -- the synthetic signals show what the chain
# does, music shows whether it is worth doing.
set -eu

DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
. "$DIR/common.sh"

need ffmpeg ffmpeg
need_report

OUT=${1:-tests/material}
mkdir -p "$OUT"

# Pink noise, 60 s, -20 dBFS RMS. Two passes: generate, measure, correct.
# The channels are independently seeded so the mid/side stage sees a real side
# signal -- duplicated mono would make S zero and leave stage 9 untested.
echo "pink noise ..."
ffmpeg -hide_banner -loglevel error -y \
    -f lavfi -i "anoisesrc=d=60:c=pink:r=$RATE:a=0.3:seed=1" \
    -f lavfi -i "anoisesrc=d=60:c=pink:r=$RATE:a=0.3:seed=2" \
    -filter_complex "[0:a][1:a]join=inputs=2:channel_layout=stereo" \
    -c:a pcm_f32le "$OUT/pink.tmp.wav"
RMS=$(ffmpeg -hide_banner -nostats -i "$OUT/pink.tmp.wav" -af astats=metadata=1 \
      -f null - 2>&1 | awk '/RMS level dB/{print $NF; exit}')
GAIN=$(awk -v r="$RMS" 'BEGIN{printf "%.4f", -20.0 - r}')
ffmpeg -hide_banner -loglevel error -y -i "$OUT/pink.tmp.wav" \
    -af "volume=${GAIN}dB" -c:a pcm_f32le "$OUT/pink.wav"
rm -f "$OUT/pink.tmp.wav"

# Log sweep 20 Hz -> 20 kHz over 30 s. ln(20000/20) = ln(1000).
echo "log sweep ..."
ffmpeg -hide_banner -loglevel error -y \
    -f lavfi -i "aevalsrc='0.5*sin(2*PI*20*30/log(1000)*(exp(t*log(1000)/30)-1))':d=30:s=$RATE:c=stereo" \
    -c:a pcm_f32le "$OUT/sweep.wav"

# 100 Hz square, 5 s. Its own harmonic series is the reference the virtual
# bass branch has to be judged against.
echo "100 Hz square ..."
ffmpeg -hide_banner -loglevel error -y \
    -f lavfi -i "aevalsrc='0.5*sgn(sin(2*PI*100*t))':d=5:s=$RATE:c=stereo" \
    -c:a pcm_f32le "$OUT/square100.wav"

echo
for f in pink sweep square100; do
    printf '  %-14s ' "$f.wav"
    ffmpeg -hide_banner -nostats -i "$OUT/$f.wav" -af astats=metadata=1 \
        -f null - 2>&1 | awk '/RMS level dB/{printf "RMS %s dBFS\n", $NF; exit}'
done
echo
echo "written to $OUT (gitignored -- do not commit audio)"
echo "add three music tracks with known low-frequency content alongside them."
