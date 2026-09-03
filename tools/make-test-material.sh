#!/bin/sh
# Generate the synthetic test material into tests/material/ (gitignored).
#
#   tools/make-test-material.sh [dir]
#   tools/make-test-material.sh [--dir tests/material] --music TRACK [TRACK ...]
#
# sox synthesises the signals; ffmpeg measures them, so the RMS printed here
# is the same measurement the rest of the tooling uses rather than sox's
# slightly different definition of the same word.
#
# MUSIC IS NOT OPTIONAL, and --music is how you add it. The synthetic signals
# show what the chain does; music is the only thing that shows whether it is
# doing it at a level you actually listen at. pink.wav is -20 dBFS RMS, roughly
# 12 dB below programme, and every conclusion in the README that later turned
# out to be wrong -- upward compression, the stage 8 crossfade, stage 11's
# threshold -- was drawn from it. Three tracks with real low-frequency content
# is the useful number, and loud modern masters are the point rather than a
# problem: they are what the level-dependent stages have to survive.
#
# --music converts to the graph format (48 kHz float32 stereo) and takes a
# 40-second excerpt from 25% into the track, past the intro and into the part
# with the whole arrangement in it. It does not normalise: the master's own
# level is the thing being tested.
#
# --music is TERMINAL: every argument after it is a track path, so --dir has to
# come first. That is the price of handling paths with spaces in them, which is
# most music -- see the note on the parser below.
set -eu

DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
. "$DIR/common.sh"

OUT=tests/material
MUSIC=0
while [ $# -gt 0 ]; do
    case $1 in
        # Terminal on purpose, and the tracks stay in "$@" rather than being
        # collected into a variable. `MUSIC="$*"` followed by `for track in
        # $MUSIC` re-splits on whitespace, so every path with a space in it
        # became several nonexistent paths -- which is most music. It failed as
        # "no such track: /home/you/Music/Some" and read like a missing file.
        # There are no arrays in POSIX sh; the positional parameters are the
        # only list that survives a space, so tracks are never copied out.
        --music) MUSIC=1; shift; break ;;
        --dir)   OUT=$2; shift 2 ;;
        *)       OUT=$1; shift ;;
    esac
done

# Requirements depend on the mode: only synthesis needs sox, and demanding it
# for --music would block the one path that has no synthesis in it.
need ffmpeg ffmpeg
if [ "$MUSIC" = 1 ]; then
    need ffprobe ffmpeg
else
    need sox sox
fi
need_report

mkdir -p "$OUT"

# ingest_music -- excerpt each track into music<N>.wav and report its loudness.
# The LUFS and true peak are printed because they are the numbers that decide
# whether a track is worth keeping: something mastered at -14 LUFS exercises
# stages 7, 10 and 11 where the synthetic material never reaches.
if [ "$MUSIC" = 1 ]; then
    [ $# -gt 0 ] || die "--music needs at least one track path"
    n=0
    for track in "$@"; do
        [ -f "$track" ] || die "no such track: $track"
        n=$((n + 1))
        dur=$(ffprobe -v error -show_entries format=duration \
                      -of csv=p=0 "$track" 2>/dev/null | cut -d. -f1)
        start=$(( ${dur:-160} / 4 ))
        ffmpeg -v error -y -ss "$start" -t 40 -i "$track" \
               -ar $RATE -ac 2 -c:a pcm_f32le "$OUT/music$n.wav"
        printf '  %-14s from %-28s LUFS-I %7s  ' \
               "music$n.wav" "$(basename "$track")" "$(lufs "$OUT/music$n.wav")"
        python3 "$DIR/true-peak.py" "$OUT/music$n.wav" 2>/dev/null \
            | awk 'NR==2{printf "true peak %s dBTP\n", $3}'
    done
    [ "$n" -ge 3 ] || echo "  note: $n track(s). Three is the useful number." >&2
    exit 0
fi

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

# The same sweep at FULL SCALE, and it is not redundant with the one above.
# Stage 12's `th` is bound by the full-scale sweep and by nothing else in this
# directory, and sweep.wav is 6 dB too quiet to show it. Measured 3 Sep 2026:
# against the quiet file the chain looks like it has 0.59 dB of spare
# true-peak headroom and `th` could be raised to 0.9650. Against this file the
# real headroom is 0.470 dB, the ceiling is th = 0.9400 (-0.210 dBTP, 0.010 dB
# to spare), and 0.9650 lands at +0.012 dBTP -- clipping. That is the same
# failure already recorded in the stage 12 comment of 50-speaker-tuning.conf,
# found there on hardware at +0.137 dBTP and re-derived here from scratch
# because the quiet sweep hid it a second time.
#
# Its true peak is ABOVE 0 dBFS by design, about +0.55 dBTP. A full-scale sine
# sweep is the worst inter-sample case there is; that is the whole point of
# keeping it. sox WILL warn here -- "output clipped 224 samples; decrease
# volume?" -- and the answer is no. The sample peak lands at exactly 0.000
# dBFS, which is what a full-scale master looks like. Do not normalise it down
# to make the warning go away; that turns it back into sweep.wav.
#
# Do NOT use it for acoustic response work -- sweep-response.py takes
# --reference tests/material/sweep.wav, and that file stays as it is.
echo "log sweep, full scale ..."
# shellcheck disable=SC2086
sox -n $FMT "$OUT/sweep_fs.wav" synth 30 sine 20/20000 gain 0

# 100 Hz square, 5 s. Its own harmonic series is the reference the virtual
# bass branch has to be judged against.
echo "100 Hz square ..."
# shellcheck disable=SC2086
sox -n $FMT "$OUT/square100.wav" synth 5 square 100 gain -6

echo
for f in pink sweep sweep_fs square100; do
    printf '  %-14s RMS %8s dBFS\n' "$f.wav" "$(rms_dbfs "$OUT/$f.wav")"
done

# Printed because it is the number the file exists for, and because seeing it
# go over 0 dBFS here is what stops the next person "fixing" the level.
printf '  %-14s true peak %s dBTP (over 0 dBFS on purpose)\n' "sweep_fs.wav" \
    "$(python3 "$DIR/true-peak.py" "$OUT/sweep_fs.wav" 2>/dev/null \
        | awk 'NR==2{print $3}')"
echo
echo "written to $OUT (gitignored -- do not commit audio)"
echo "add three music tracks with known low-frequency content alongside them."
