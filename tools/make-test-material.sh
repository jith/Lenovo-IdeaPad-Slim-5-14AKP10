#!/bin/sh
# Generate the synthetic test material into tests/material/ (gitignored).
#
#   tools/make-test-material.sh [dir]
#   tools/make-test-material.sh [--force] [dir]
#   tools/make-test-material.sh [--dir tests/material] --music TRACK [TRACK ...]
#
# EXISTING FILES ARE KEPT, and --force is the only way past that.
#
# Every file here is now reproducible -- the pink synthesis uses sox -R, so
# --force brings back byte-identical material and the stored captures in
# tests/captures/ stay valid. That was not true before 3 Sep 2026: pink.wav's
# noise was unseeded, tests/material/ is gitignored, and a plain re-run
# replaced the stimulus with different noise, leaving every null test against
# those captures quietly comparing two unrelated signals. Nothing failed; the
# residual just stopped meaning anything. The baselines were re-taken against
# a -R pink.wav on 3 Sep 2026 to close that off.
#
# The keep-by-default rule stays anyway. It is cheap, and it is the only thing
# standing between a capture set and a stimulus swapped out from under it if
# the synthesis is ever changed again.
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
FORCE=0

# The md5 of the pink.wav that tests/captures/pink.*.wav were recorded from,
# re-taken 3 Sep 2026. Unlike the 5 Aug file it predates nothing: it comes
# straight from the -R synthesis below, so --force reproduces it exactly and
# this check goes on passing. Recorded here because tests/material/ is
# gitignored, so the checksum is the only link between the stored captures and
# the stimulus they were made with.
PINK_BASELINE_MD5=afb157660e1fb003e79d6431cbb022a9

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
        --force) FORCE=1; shift ;;
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

if [ "$FORCE" = 1 ]; then
    echo "  --force: overwriting existing files. Synthesis is seeded, so" >&2
    echo "  these come back byte-identical; the checksum check at the end" >&2
    echo "  says whether the captures in tests/captures/ still match." >&2
    echo >&2
fi

# should_write <name> -- 0 to generate it, 1 if it exists and is being kept.
# sweep, sweep_fs and square100 are deterministic and would come back
# byte-identical, but they are guarded the same way: one rule to remember
# beats three files and a per-file exception.
should_write() {
    if [ "$FORCE" = 0 ] && [ -f "$OUT/$1" ]; then
        printf '  keep   %-14s (exists; --force to regenerate)\n' "$1"
        return 1
    fi
    return 0
}

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
        # music2.wav is the stimulus behind tests/captures/music2ab, so the
        # same keep-by-default rule applies here.
        should_write "music$n.wav" || continue
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
#
# -R seeds sox's noise, which is what makes this file reproducible at all.
# Without it every run produced different noise and silently orphaned the
# captures taken against the previous one. Do not remove it, and if the
# synth line above it ever changes, re-take the baselines and update
# PINK_BASELINE_MD5 in the same commit -- the two are one setting.
if should_write pink.wav; then
    echo "pink noise ..."
    # shellcheck disable=SC2086
    sox -R -n $FMT "$OUT/pink.tmp.wav" synth 60 pinknoise pinknoise gain -6
    CORRECTION=$(awk -v r="$(rms_dbfs "$OUT/pink.tmp.wav")" \
                     'BEGIN{printf "%.4f", -20.0 - r}')
    sox "$OUT/pink.tmp.wav" "$OUT/pink.wav" gain "$CORRECTION"
    rm -f "$OUT/pink.tmp.wav"
fi

# Log sweep 20 Hz -> 20 kHz over 30 s. `/` is sox's smooth exponential sweep,
# a fixed number of semitones per second; `:` would be a linear one.
if should_write sweep.wav; then
    echo "log sweep ..."
    # shellcheck disable=SC2086
    sox -n $FMT "$OUT/sweep.wav" synth 30 sine 20/20000 gain -6
fi

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
if should_write sweep_fs.wav; then
    echo "log sweep, full scale ..."
    # shellcheck disable=SC2086
    sox -n $FMT "$OUT/sweep_fs.wav" synth 30 sine 20/20000 gain 0
fi

# The same sweep 12 dB down, and the ONLY sweep that nulls. Stage 12's
# limiter makes the chain block-alignment dependent while it is engaging: a
# one-sample input shift moves the output by -21 dBFS, so the -6 dBFS sweep
# above cannot be used with null-test.sh any more (it fails at -18 to -20 dBFS
# on an unchanged graph). At -18 dBFS in, the chain lands at -7.9 dBFS out,
# the limiter never engages, and the null comes back: -80.5 dBFS measured on
# hardware against a -79.9 dBFS offline prediction.
#
# It is a weaker test than it looks. Anything quiet enough to null is too
# quiet to exercise the stages worth testing, so this buys back a sweep-shaped
# check of the static filtering and nothing about the dynamics. Prefer pink
# and square100, which pass at full level. See README "Repeatability".
if should_write sweep_quiet.wav; then
    echo "log sweep, quiet ..."
    # shellcheck disable=SC2086
    sox -n $FMT "$OUT/sweep_quiet.wav" synth 30 sine 20/20000 gain -18
fi

# 100 Hz square, 5 s. Its own harmonic series is the reference the virtual
# bass branch has to be judged against.
if should_write square100.wav; then
    echo "100 Hz square ..."
    # shellcheck disable=SC2086
    sox -n $FMT "$OUT/square100.wav" synth 5 square 100 gain -6
fi

echo
for f in pink sweep sweep_fs sweep_quiet square100; do
    printf '  %-14s RMS %8s dBFS\n' "$f.wav" "$(rms_dbfs "$OUT/$f.wav")"
done

# Printed because it is the number the file exists for, and because seeing it
# go over 0 dBFS here is what stops the next person "fixing" the level.
printf '  %-14s true peak %s dBTP (over 0 dBFS on purpose)\n' "sweep_fs.wav" \
    "$(python3 "$DIR/true-peak.py" "$OUT/sweep_fs.wav" 2>/dev/null \
        | awk 'NR==2{print $3}')"

# Whether this pink.wav is the one the stored captures were recorded from is
# not something you can tell by looking at it, and getting it wrong costs a
# null test that reports a large residual for no reason anyone can find. So
# say it on every run rather than leaving it to be rediscovered.
if [ -f "$OUT/pink.wav" ]; then
    have=$(md5sum "$OUT/pink.wav" | cut -d' ' -f1)
    if [ "$have" = "$PINK_BASELINE_MD5" ]; then
        echo "  pink.wav matches the stimulus tests/captures/pink.*.wav"
        echo "  were recorded from -- null tests against them are valid."
    else
        echo >&2
        echo "  WARNING: this pink.wav is NOT the one" >&2
        echo "  tests/captures/pink.baseline.wav and pink.current.wav were" >&2
        echo "  recorded from. Those captures cannot be nulled against it:" >&2
        echo "    have $have" >&2
        echo "    want $PINK_BASELINE_MD5" >&2
        echo "  Either the synth line changed, or this is an older pink.wav." >&2
        echo "  Regenerating with --force should restore the expected file;" >&2
        echo "  if it does not, re-take the baselines with tools/null-test.sh" >&2
        echo "  and update PINK_BASELINE_MD5." >&2
    fi
fi

echo
echo "written to $OUT (gitignored -- do not commit audio)"
echo "add three music tracks with known low-frequency content alongside them."
