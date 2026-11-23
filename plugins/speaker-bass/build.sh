#!/bin/sh
# Build the stereo speaker-bass LADSPA processor from this directory's sources.
set -eu

if [ "$#" -ne 1 ]; then
    echo "usage: $0 output.so" >&2
    exit 2
fi

src_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
exec cc -O3 -Wall -fopenmp-simd -fPIC -shared -o "$1" \
    "$src_dir/speaker_bass.c" "$src_dir/sustained_bass.c" "$src_dir/music_bass.c" -lm
