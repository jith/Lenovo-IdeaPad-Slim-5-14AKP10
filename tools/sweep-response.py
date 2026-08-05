#!/usr/bin/env python3
"""Read a swept-sine mic capture and print the response curve, fc and Qtc.

    tools/sweep-response.py capture.wav [--f0 20] [--f1 20000] [--dur 30]

Expects the log sweep tools/measure-speaker.sh plays: f0 -> f1 over dur
seconds. The sweep start is found by fitting the tracked peak frequency over
the region with good signal-to-noise, so leading silence does not matter.

EVERYTHING HERE IS RELATIVE. The internal microphone is uncalibrated and sits
inside the chassis, so it contributes its own response and hears case
resonance along with the speaker. Use this to locate the resonance peak,
estimate its Q, and compare before against after. Do not read it as the
speaker's frequency response, and do not build a correction curve from it.
"""

import argparse
import json
import subprocess
import sys

import numpy as np

N = 8192
HOP = 512


def read_mono(path):
    try:
        probe = subprocess.run(
            ["ffprobe", "-v", "error", "-select_streams", "a:0",
             "-show_entries", "stream=sample_rate", "-of", "json", path],
            capture_output=True, text=True, check=True)
        rate = int(json.loads(probe.stdout)["streams"][0]["sample_rate"])
        raw = subprocess.run(
            ["ffmpeg", "-v", "error", "-i", path, "-ac", "1",
             "-f", "f32le", "-c:a", "pcm_f32le", "-"],
            capture_output=True, check=True).stdout
    except (subprocess.CalledProcessError, KeyError, IndexError) as e:
        sys.exit(f"cannot read {path}: {e}")
    return np.frombuffer(raw, dtype=np.float32).astype(np.float64), rate


def track(x, rate):
    """Per-frame (time, peak frequency, peak level dB)."""
    out = []
    win = np.hanning(N)
    for i in range(0, len(x) - N, HOP):
        spec = np.abs(np.fft.rfft(x[i:i + N] * win))
        freqs = np.fft.rfftfreq(N, 1 / rate)
        out.append(((i + N / 2) / rate, freqs[np.argmax(spec)],
                    20 * np.log10(spec.max() + 1e-12)))
    return np.array(out)


def find_start(frames, f0, f1, dur):
    """Fit the tracked frequency to the known sweep to recover its start."""
    ratio = f1 / f0
    # Fit only where SNR is good; the low end of the sweep is often buried.
    m = (frames[:, 1] > f0 * 20) & (frames[:, 1] < f1 * 0.9)
    if m.sum() < 10:
        sys.exit("not enough usable signal to locate the sweep")
    y = np.log10(frames[m, 1] / f0) * dur / np.log10(ratio)
    slope, intercept = np.polyfit(frames[m, 0], y, 1)
    return -intercept / slope, slope


def main():
    p = argparse.ArgumentParser(description=__doc__,
                                formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("capture")
    p.add_argument("--f0", type=float, default=20.0)
    p.add_argument("--f1", type=float, default=20000.0)
    p.add_argument("--dur", type=float, default=30.0)
    p.add_argument("--ref-lo", type=float, default=1300.0,
                   help="passband reference band, low edge (Hz)")
    p.add_argument("--ref-hi", type=float, default=2400.0)
    p.add_argument("--reference", default="tests/material/sweep.wav",
                   help="the stimulus WAV, analysed identically and divided "
                        "out. Pass '' to skip (not recommended)")
    args = p.parse_args()

    edges = args.f0 * 2 ** (np.arange(0, 61) / 6.0)
    centres = np.sqrt(edges[:-1] * edges[1:])

    def binned(path):
        x, rate = read_mono(path)
        frames = track(x, rate)
        t0, slope = find_start(frames, args.f0, args.f1, args.dur)
        if not 0.8 < slope < 1.2:
            print(f"  warning: {path}: sweep fit slope {slope:.3f} (want 1.0)")
        keep = ((frames[:, 0] > t0 + 0.2) &
                (frames[:, 0] < t0 + args.dur - 0.2))
        t = frames[keep, 0]
        freq = args.f0 * (args.f1 / args.f0) ** ((t - t0) / args.dur)
        level = np.convolve(frames[keep, 2], np.ones(15) / 15, mode="same")
        out = np.full(len(centres), np.nan)
        for i, (lo, hi) in enumerate(zip(edges[:-1], edges[1:])):
            sel = (freq >= lo) & (freq < hi)
            if sel.any():
                out[i] = level[sel].mean()
        return out, t0

    level, t0 = binned(args.capture)

    # A log sweep spends less time per hertz as it rises, so a fixed-window
    # FFT reads a FLAT system as a curve sloping about 1 dB/octave. Dividing
    # by the stimulus analysed the same way removes that, and any other
    # artefact the two share. Without it the tilt is indistinguishable from
    # the speaker's response, which is exactly the mistake it is here to stop.
    if args.reference:
        ref_level, _ = binned(args.reference)
        level = level - ref_level
        print(f"  normalised against {args.reference}")
    else:
        print("  WARNING: no --reference given. The log sweep's own spectral")
        print("  tilt (~1 dB/octave) is still in these numbers; treat the")
        print("  shape as indicative only.")

    valid = ~np.isnan(level)
    band = valid & (centres > args.ref_lo) & (centres < args.ref_hi)
    level = level - (level[band].mean() if band.any() else 0.0)

    print(f"  sweep starts at {t0:.2f}s")
    print(f"  levels are relative to the {args.ref_lo:g}-{args.ref_hi:g} Hz mean\n")
    print("   freq(Hz)   rel(dB)")
    for c, val in zip(centres, level):
        if np.isnan(val):
            continue
        print(f"  {c:8.0f}  {val:8.1f}  {'#' * max(0, int((val + 40) / 1.2))}")

    freq, level = centres[valid], level[valid]

    # Resonance: the highest point below the reference band.
    search = (freq > args.f0 * 4) & (freq < args.ref_lo)
    if not search.any():
        return 0
    fb, lb = freq[search], level[search]
    ipk = int(np.argmax(lb))
    fc, peak = fb[ipk], lb[ipk]
    half = peak - 3.0
    below_lo = fb[:ipk][lb[:ipk] < half]
    below_hi = fb[ipk:][lb[ipk:] < half]
    print(f"\n  resonance      fc = {fc:.0f} Hz, {peak:+.1f} dB above passband")
    if len(below_lo) and len(below_hi):
        bw = below_hi[0] - below_lo[-1]
        print(f"  -3 dB points   {below_lo[-1]:.0f} .. {below_hi[0]:.0f} Hz "
              f"(bandwidth {bw:.0f} Hz)")
        print(f"  Qtc            {fc / bw:.2f} from bandwidth, "
              f"{10 ** (peak / 20):.2f} from peak height")
        print(f"\n  The two Qtc estimates agree only for an ideal second-order")
        print(f"  resonance. Take the range, not either number.")
    for drop in (10.0, 20.0):
        under = fb[lb < -drop]
        if len(under):
            print(f"  output is {drop:.0f} dB down by {under[-1]:.0f} Hz")
    return 0


if __name__ == "__main__":
    sys.exit(main())
