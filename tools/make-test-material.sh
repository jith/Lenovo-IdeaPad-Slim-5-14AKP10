#!/bin/sh
# Generate the synthetic test material into tests/material/ (gitignored).
#
#   tools/make-test-material.sh [dir]
#
# sox synthesises the signals; ffmpeg measures them, so the RMS printed here
# is the same measurement the rest of the tooling uses rather than sox's
# slightly different definition of the same word.
#
# Drop your own music tracks alongside these. Three with known low-frequency
# content is the useful number -- the synthetic signals show what the chain
# does, music shows whether it is worth doing.
set -eu

DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
. "$DIR/common.sh"

need sox sox
need ffmpeg ffmpeg
need_report

OUT=${1:-tests/material}
mkdir -p "$OUT"

# float32, matching what pw-cat and pw-record use, so nothing requantises.
FMT="-r $RATE -c 2 -b 32 -e float"

# rms_dbfs <file> -- overall RMS in dBFS, per ffmpeg astats.
rms_dbfs() {
    ffmpeg -hide_banner -nostats -i "$1" -af astats=metadata=1 -f null - 2>&1 \
        | awk '/RMS level dB/{print $NF; exit}'
}

# Pink noise, 60 s, -20 dBFS RMS. Two passes: synthesise, measure, correct.
# Two pinknoise specs, not one: with a single spec sox writes the same noise
# to both channels, the side signal is exactly zero and stage 9 goes untested.
#
# sox synthesises at 0 dBFS and its pink noise overshoots on a handful of
# samples, so `synth` warns about clipping however the gain is arranged --
# three to five samples in 5.76 million. It does not matter here: this file is
# a stimulus played identically down both paths, so whatever is clipped in it
# is clipped the same way in both captures and cancels exactly in the null
# subtraction. Do not "fix" it by lowering the level; that only changes where
# the level-dependent stages sit.
echo "pink noise ..."
# shellcheck disable=SC2086
sox -n $FMT "$OUT/pink.tmp.wav" synth 60 pinknoise pinknoise gain -6
CORRECTION=$(awk -v r="$(rms_dbfs "$OUT/pink.tmp.wav")" \
                 'BEGIN{printf "%.4f", -20.0 - r}')
sox "$OUT/pink.tmp.wav" "$OUT/pink.wav" gain "$CORRECTION"
rm -f "$OUT/pink.tmp.wav"

# Log sweep 20 Hz -> 20 kHz over 30 s. `/` is sox's smooth exponential sweep,
# a fixed number of semitones per second; `:` would be a linear one.
echo "log sweep ..."
# shellcheck disable=SC2086
sox -n $FMT "$OUT/sweep.wav" synth 30 sine 20/20000 gain -6

# 100 Hz square, 5 s. Its own harmonic series is the reference the virtual
# bass branch has to be judged against.
echo "100 Hz square ..."
# shellcheck disable=SC2086
sox -n $FMT "$OUT/square100.wav" synth 5 square 100 gain -6

echo
for f in pink sweep square100; do
    printf '  %-14s RMS %8s dBFS\n' "$f.wav" "$(rms_dbfs "$OUT/$f.wav")"
done
echo
echo "written to $OUT (gitignored -- do not commit audio)"
echo "add three music tracks with known low-frequency content alongside them."
