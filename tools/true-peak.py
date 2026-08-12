#!/usr/bin/env python3
"""Exact inter-sample peak of a wav, and what the usual meters say instead.

    tools/true-peak.py FILE [FILE ...] [--ceiling -0.20] [--compare]

Prints sample peak and true peak in dB. Exits non-zero if any file is over the
ceiling, so it can gate a change: run it on a fresh capture after raising
g_out and it will tell you whether you have just started clipping the DAC.

WHY THIS EXISTS. ffmpeg's two built-in answers are fine until the moment they
are not, and the moment they are not is the one you need them for. Measured
with --compare over tests/captures/gout/, exact against loudnorm and ebur128:

    signal              exact   loudnorm   ebur128    error
    pink.current       -5.551     -5.520    -5.500   +0.03/+0.05
    square100.current  -0.540     -0.580    -0.600   -0.04/-0.06
    sweep.current      -0.908     -1.140    -1.100   -0.23/-0.19

Within 0.06 dB on pink and on the square, and then both drop 0.2 dB low on the
sweep -- both reading back roughly the sample peak. 0.2 dB is comparable to the
whole margin the -0.20 dBTP ceiling leaves, and high-frequency content is
exactly what the ceiling exists for, so neither meter can gate this decision.

(An earlier note in README.md said loudnorm reads 1.4 dB HIGH on the sweep and
ebur128 low by about as much. Neither direction nor magnitude reproduces on the
committed captures -- the error is small, and both meters lean the same way.
--compare is here so the next such number gets checked rather than believed.)

The method here has no filter design in it and so nothing to be approximately
right about: zero-pad the spectrum by 16x, inverse transform, take the maximum.
That is band-limited reconstruction, which is what the DAC does.

Whole-file FFT, so memory is about 16x the file. Fine for a 60 s capture.
"""

import argparse
import os
import re
import subprocess
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from dsp_offline import read_wav, sample_peak_db, true_peak_db


def ffmpeg_meters(path):
    """(loudnorm true peak, ebur128 true peak) -- the two numbers not to use."""
    def run(af):
        return subprocess.run(
            ["ffmpeg", "-hide_banner", "-nostats", "-i", path,
             "-af", af, "-f", "null", "-"],
            capture_output=True, text=True).stderr

    # Two passes, not one filter chain. loudnorm is not a pure analyser -- in
    # single-pass mode it normalises what it passes on, so an ebur128 chained
    # after it measures the normalised stream and reads ten dB out.
    out = run("loudnorm=print_format=json")
    norm = re.search(r'"input_tp"\s*:\s*"?(-?[\d.]+)', out)
    out = run("ebur128=peak=true")
    # Only the Summary block. ebur128's per-frame lines carry a FTPK field that
    # also matches "Peak: ... dBFS", and taking the last of those reads back a
    # frame value ten dB out.
    ebu = re.search(r"True peak:.*?Peak:\s*(-?[\d.]+) dBFS", out, re.S)
    return (float(norm.group(1)) if norm else float("nan"),
            float(ebu.group(1)) if ebu else float("nan"))


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("files", nargs="+")
    ap.add_argument("--ceiling", type=float, default=-0.20,
                    help="fail above this, in dBTP (default -0.20, stage 12's)")
    ap.add_argument("--oversample", type=int, default=16)
    ap.add_argument("--compare", action="store_true",
                    help="also print loudnorm's and ebur128's answers")
    args = ap.parse_args()

    head = f"{'file':<34}{'sample':>9}{'true':>9}{'margin':>9}"
    print(head + (f"{'loudnorm':>10}{'ebur128':>9}" if args.compare else ""))

    over = 0
    for path in args.files:
        x = read_wav(path)
        sample, tp = sample_peak_db(x), true_peak_db(x, args.oversample)
        margin = args.ceiling - tp
        over += margin < 0
        line = (f"{os.path.basename(path):<34}{sample:9.3f}{tp:9.3f}"
                f"{margin:+9.3f}")
        if args.compare:
            norm, ebu = ffmpeg_meters(path)
            line += f"{norm:10.3f}{ebu:9.3f}"
        print(line + ("   OVER" if margin < 0 else ""))

    if over:
        print(f"\n{over} file(s) over the {args.ceiling:+.2f} dBTP ceiling.",
              file=sys.stderr)
    return 1 if over else 0


if __name__ == "__main__":
    sys.exit(main())
