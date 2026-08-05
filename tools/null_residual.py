#!/usr/bin/env python3
"""Sample-align two captures, subtract, and report the residual.

    tools/null_residual.py baseline.wav current.wav [--hp FREQ] [--hp-q Q]

Alignment is by cross-correlation, so a constant latency difference between
the two paths -- the brickwall limiter's lookahead, for instance -- does not
count as a residual. A gain difference does, and is meant to: that is the
whole point of comparing before any trim is applied.

--hp COMPENSATES A BASELINE THAT PREDATES STAGE 1

By default nothing is compensated: both captures are compared exactly as
recorded, which is what you want when the baseline was taken through the same
graph and the question is whether a stage you just edited changed anything.

Pass --hp 20 only when the baseline is a genuine pass-through capture taken
before stage 1 existed. Stage 1 is a 20 Hz biquad high-pass whose magnitude is
flat to within 0.01 dB above 50 Hz but whose phase is not: at 1 kHz it still
rotates the signal enough that the raw difference reaches only -31 dBFS, and
against pink noise the broadband residual lands near -25 dBFS. That is phase,
not error, and subtraction cannot tell them apart -- so against a
pre-stage-1 baseline a -60 dBFS null is unreachable however correct the rest
of the chain is. Applying the same high-pass to the baseline first isolates
the question actually worth answering.

Applying it when the baseline ALREADY contains stage 1 high-passes that side
twice and reports a fictitious ~-17 dBFS residual, so the default is off.
"""

import argparse
import json
import subprocess
import sys

import numpy as np

SPLIT_HZ = 30.0
LIMIT_DB = -60.0


def read_wav(path):
    """Return (samples as float32 [n, channels], rate).

    Decoded through ffmpeg rather than the stdlib wave module, which rejects
    the float32 WAVs that `pw-record --format=f32` writes."""
    try:
        probe = subprocess.run(
            ["ffprobe", "-v", "error", "-select_streams", "a:0",
             "-show_entries", "stream=sample_rate,channels",
             "-of", "json", path],
            capture_output=True, text=True, check=True)
        info = json.loads(probe.stdout)["streams"][0]
        rate, ch = int(info["sample_rate"]), int(info["channels"])
        raw = subprocess.run(
            ["ffmpeg", "-v", "error", "-i", path,
             "-f", "f32le", "-c:a", "pcm_f32le", "-"],
            capture_output=True, check=True).stdout
    except (subprocess.CalledProcessError, KeyError, IndexError) as e:
        sys.exit(f"cannot read {path}: {e}")
    return np.frombuffer(raw, dtype=np.float32).reshape(-1, ch), rate


def highpass(x, rate, freq, q):
    """Apply the same second-order high-pass PipeWire's bq_highpass builds.

    Audio EQ cookbook coefficients, applied in the frequency domain: this is
    offline analysis, and multiplying by the exact response avoids the startup
    transient a time-domain pass would leave at the head of the file."""
    w0 = 2.0 * np.pi * freq / rate
    alpha = np.sin(w0) / (2.0 * q)
    cw = np.cos(w0)
    b = np.array([(1 + cw) / 2, -(1 + cw), (1 + cw) / 2])
    a = np.array([1 + alpha, -2 * cw, 1 - alpha])

    n = 1 << int(np.ceil(np.log2(len(x) * 2)))
    z = np.exp(-2j * np.pi * np.fft.rfftfreq(n) )
    h = (b[0] + b[1] * z + b[2] * z**2) / (a[0] + a[1] * z + a[2] * z**2)
    out = np.fft.irfft(np.fft.rfft(x, n, axis=0) * h[:, None], n, axis=0)
    return out[:len(x)]


def align(a, b):
    """Shift b to line up with a, using the loudest channel of a."""
    ch = int(np.argmax(np.max(np.abs(a), axis=0)))
    x, y = a[:, ch], b[:, ch]
    n = 1 << int(np.ceil(np.log2(len(x) + len(y))))
    corr = np.fft.irfft(np.fft.rfft(x, n) * np.conj(np.fft.rfft(y, n)), n)
    lag = int(np.argmax(np.abs(corr)))
    if lag > n // 2:
        lag -= n
    b = b[-lag:] if lag < 0 else np.vstack(
        [np.zeros((lag, b.shape[1]), np.float32), b])
    m = min(len(a), len(b))
    return a[:m], b[:m], lag


def db(x):
    peak = float(np.max(np.abs(x))) if x.size else 0.0
    return -np.inf if peak == 0 else 20.0 * np.log10(peak)


def split_at(x, rate, fc):
    """Split into (below fc, above fc). Brickwall in the frequency domain --
    this is offline analysis, so there is no reason to accept filter skirts
    smearing one band into the other."""
    spec = np.fft.rfft(x, axis=0)
    cut = int(np.ceil(fc * spec.shape[0] / (rate / 2)))
    low_spec = np.zeros_like(spec)
    low_spec[:cut] = spec[:cut]
    low = np.fft.irfft(low_spec, n=len(x), axis=0)
    return low, x - low


def main():
    p = argparse.ArgumentParser(description=__doc__,
                                formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("baseline")
    p.add_argument("current")
    p.add_argument("--hp", type=float, default=0.0,
                   help="high-pass to apply to the baseline before "
                        "subtracting, Hz. Use 20 only when the baseline "
                        "predates stage 1 (default 0, no compensation)")
    p.add_argument("--hp-q", type=float, default=0.707, help="its Q")
    args = p.parse_args()

    a, rate_a = read_wav(args.baseline)
    b, rate_b = read_wav(args.current)
    if rate_a != rate_b:
        sys.exit(f"rate mismatch: {rate_a} vs {rate_b}")
    if a.shape[1] != b.shape[1]:
        sys.exit(f"channel mismatch: {a.shape[1]} vs {b.shape[1]}")

    a, b, lag = align(a, b)
    if len(a) < rate_a:
        sys.exit("less than a second of overlap after alignment")

    raw_resid = a - b
    if args.hp > 0:
        a = highpass(a, rate_a, args.hp, args.hp_q)
    resid = a - b
    low, high = split_at(resid, rate_a, SPLIT_HZ)

    print(f"  aligned by {lag:+d} samples ({1000.0 * lag / rate_a:+.2f} ms), "
          f"{len(a) / rate_a:.1f} s compared")
    print(f"  baseline peak            {db(a):7.1f} dBFS")
    if args.hp > 0:
        print(f"  residual, uncompensated  {db(raw_resid):7.1f} dBFS   "
              f"(phase of the {args.hp:g} Hz high-pass, not error)")
        print(f"  residual, stage 1 undone {db(resid):7.1f} dBFS")
    else:
        print(f"  residual                 {db(resid):7.1f} dBFS")
    print(f"    below {SPLIT_HZ:g} Hz            {db(low):7.1f} dBFS")
    print(f"    above {SPLIT_HZ:g} Hz            {db(high):7.1f} dBFS")

    ok = db(high) < LIMIT_DB
    print(f"  {'PASS' if ok else 'FAIL'}: residual above {SPLIT_HZ:g} Hz is "
          f"{'below' if ok else 'NOT below'} {LIMIT_DB:g} dBFS")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
