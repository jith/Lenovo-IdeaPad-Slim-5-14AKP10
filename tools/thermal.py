#!/usr/bin/env python3
"""Thermal compression: does the driver get quieter over MINUTES at one level?

    tools/thermal.py gen OUT.wav SCHED.json [--soak 480] [--level -10.3] ...
    tools/thermal.py analyze CAP.wav SCHED.json

Every other level measurement in this repo runs for seconds and answers "how
loud can it go right now". This one answers the question left open under *How
loud can it go*: a 2 W driver at its electrical maximum heats, its voice coil's
resistance rises with temperature, and sensitivity falls -- over minutes, which
no capture here was long enough to see.

THREE THINGS MAKE THIS MEASURABLE, and all three were learned the hard way by
tools/max-level.py; read its notes before changing anything here.

1. THE STIMULUS IS TILED AND IDENTICAL. One short pink segment is generated
   once and repeated. Every analysis window therefore has bit-identical INPUT,
   so window-to-window variation in the output is the driver, the room or the
   mic -- never the signal. Measuring a decay of a few tenths of a dB against a
   freshly-random noise window cannot work: the noise moves more than the
   effect.

2. THE STIMULUS IS SHAPED TO THE CHAIN'S OWN OUTPUT. Flat pink is the wrong
   spectrum and the wrong power distribution. --shape-from takes a rendered
   chain output and matches both its average magnitude spectrum and its RMS, so
   the coil is heated by what the speaker is actually asked to reproduce.

3. THERE IS A RECOVERY BLOCK, AND IT IS THE WHOLE CONTROL. Level falling over
   ten minutes is not by itself thermal -- the mic could drift, the room could
   warm, the fan could spin up. Thermal compression is REVERSIBLE: go quiet,
   let the coil cool, play the same thing again and the level comes back. Drift
   does not come back. A run whose recovery does not return is a run that
   measured something else, and analyze says so rather than reporting a number.

WHAT IT CANNOT TELL YOU. Where the driver is damaged. This measures sensitivity
loss from heating, which is reversible and benign in itself; x_max and the
thermal limit of these OEM drivers are unknown and are not what is being found
here. A driver can be perfectly linear right up until it is not.
"""

import argparse
import json
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from dsp_offline import read_wav, write_wav

RATE = 48000
BAND_LO, BAND_HI = 300.0, 8000.0


def pink(n, rng):
    """Pink noise by spectral shaping. Deterministic given the seed."""
    spec = rng.standard_normal(n // 2 + 1) + 1j * rng.standard_normal(n // 2 + 1)
    f = np.fft.rfftfreq(n, 1 / RATE)
    spec[1:] /= np.sqrt(f[1:])
    spec[0] = 0.0
    return np.fft.irfft(spec, n)


def crest_db(x):
    return 20 * np.log10(np.abs(x).max()) - rms_db(x)


def fit_crest(x, target_db, iters=8):
    """Clip x down to a target crest factor, holding RMS.

    The chain's own output is limiter-pinned at about 9.3 dB of crest. Noise
    is nearer 11.5, and normalising THAT to the chain's RMS puts the peak over
    full scale -- which the first version of this silently fixed by scaling
    everything down, quietly running the soak 1.16 dB below the level the whole
    test is about. Clip to the crest instead, which is also what the real
    signal has had done to it.
    """
    for _ in range(iters):
        r = np.sqrt(np.mean(x ** 2))
        lim = r * 10 ** (target_db / 20)
        if np.abs(x).max() <= lim * 1.001:
            break
        x = np.clip(x, -lim, lim)
    return x


def shape_to(x, ref, nfft=8192):
    """Give x the average magnitude spectrum of ref, keeping x stationary.

    x MUST be white here, not pink. Shaping already-pink noise by a measured
    spectrum applies the 1/f twice: the first version of this did exactly that
    and came out 19 dB adrift by 12.5 kHz, sloping the wrong way the whole way.
    """
    win = np.hanning(nfft)
    acc, k = np.zeros(nfft // 2 + 1), 0
    mono = ref.mean(axis=1) if ref.ndim > 1 else ref
    for i in range(0, len(mono) - nfft, nfft // 2):
        acc += np.abs(np.fft.rfft(mono[i:i + nfft] * win)) ** 2
        k += 1
    mag = np.sqrt(acc / max(k, 1))
    mag /= mag.max()
    # Apply as a zero-phase FFT filter over the whole tile, then taper the
    # joins so tiling introduces no click.
    X = np.fft.rfft(x)
    f = np.fft.rfftfreq(len(x), 1 / RATE)
    fr = np.fft.rfftfreq(nfft, 1 / RATE)
    return np.fft.irfft(X * np.interp(f, fr, mag), len(x))


def rms_db(x):
    return 20 * np.log10(np.sqrt(np.mean(x ** 2)) + 1e-300)


def band_db(x, lo=BAND_LO, hi=BAND_HI):
    """In-band power of one window, summed over channels."""
    n = len(x)
    w = np.hanning(n)
    f = np.fft.rfftfreq(n, 1 / RATE)
    sel = (f >= lo) & (f <= hi)
    tot = 0.0
    for c in range(x.shape[1] if x.ndim > 1 else 1):
        ch = x[:, c] if x.ndim > 1 else x
        tot += (np.abs(np.fft.rfft(ch * w)[sel]) ** 2).sum()
    return 10 * np.log10(tot + 1e-300)


def gen(args):
    rng = np.random.default_rng(args.seed)
    tile_n = int(args.tile * RATE)
    crest_target = None

    if args.shape_from:
        ref = read_wav(args.shape_from)
        # White in, because shape_to applies the reference spectrum outright.
        tile = shape_to(rng.standard_normal(tile_n), ref)
        act = np.abs(ref).max(axis=1) > 10 ** (-60 / 20)
        mono = ref[act].reshape(-1)
        crest_target = 20 * np.log10(np.abs(ref).max()) - rms_db(mono)
    else:
        tile = pink(tile_n, rng)

    # Cross-fade the tile onto itself so a repeat has no discontinuity.
    xf = int(0.010 * RATE)
    ramp = np.linspace(0, 1, xf)
    tile[:xf] = tile[:xf] * ramp + tile[-xf:] * (1 - ramp)
    tile = tile[:tile_n - xf]

    # Crest first, level second, or the level is a lie. Headroom check is a
    # hard failure: silently turning the soak down defeats the measurement.
    if crest_target is not None:
        tile = fit_crest(tile, crest_target)
    tile *= 10 ** (args.level / 20) / (np.sqrt(np.mean(tile ** 2)) + 1e-300)
    if np.abs(tile).max() >= 1.0:
        raise SystemExit(
            f"stimulus peaks at {20*np.log10(np.abs(tile).max()):+.2f} dBFS at "
            f"{args.level} dBFS RMS (crest {crest_db(tile):.2f} dB).\n"
            f"Lower --level or pass --shape-from so the crest is matched to the "
            f"chain's own limited output.")

    reps = max(1, int(round(args.soak * RATE / len(tile))))
    soak = np.tile(tile, reps)
    cool = np.zeros(int(args.cool * RATE))
    rec_reps = max(1, int(round(args.recover * RATE / len(tile))))
    recover = np.tile(tile, rec_reps)

    sig = np.concatenate([soak, cool, recover])
    out = np.column_stack([sig, sig])
    write_wav(args.out, out)

    sched = dict(rate=RATE, tile_samples=int(len(tile)), level_dbfs=args.level,
                 soak_samples=int(len(soak)), cool_samples=int(len(cool)),
                 recover_samples=int(len(recover)), seed=args.seed,
                 shaped_from=args.shape_from, peak_dbfs=float(20*np.log10(np.abs(out).max())))
    with open(args.sched, "w") as fh:
        json.dump(sched, fh, indent=2)

    print(f"{len(sig)/RATE:.0f} s total: {len(soak)/RATE:.0f} s soak at "
          f"{args.level:+.1f} dBFS RMS, {args.cool:.0f} s cool, "
          f"{len(recover)/RATE:.0f} s recovery")
    print(f"tile {len(tile)/RATE:.2f} s repeated {reps}x -- every window is the "
          f"same waveform")
    # Measured off the signal, never echoed from the arguments.
    print(f"MEASURED: RMS {rms_db(tile):.2f} dBFS, peak "
          f"{20*np.log10(np.abs(tile).max()):.2f} dBFS, crest "
          f"{crest_db(tile):.2f} dB"
          + (f" (chain's own crest {crest_target:.2f})" if crest_target else ""))
    return 0


def find_start(y, sched):
    """First sample of playback, from the capture's own energy."""
    n = int(0.1 * RATE)
    m = np.abs(y).max(axis=1) if y.ndim > 1 else np.abs(y)
    env = np.convolve(m, np.ones(n) / n, mode="same")
    thr = env.max() * 10 ** (-20 / 20)
    idx = np.argmax(env > thr)
    return int(idx)


def analyze(args):
    y = read_wav(args.cap)
    with open(args.sched) as fh:
        s = json.load(fh)
    t = s["tile_samples"]
    start = find_start(y, s)
    n_soak = s["soak_samples"] // t

    def window(i):
        a = start + i * t
        return y[a:a + t]

    lv = []
    for i in range(n_soak):
        w = window(i)
        if len(w) < t:
            break
        lv.append(band_db(w))
    lv = np.array(lv)
    if len(lv) < 6:
        raise SystemExit("capture too short or misaligned: only "
                         f"{len(lv)} soak windows found")

    # Skip the first window: onset settling is ~1 dB and level-independent,
    # and it is not thermal. max-level.py hit the same thing.
    cold = lv[1:4].mean()
    hot = lv[-3:].mean()

    rec_start = start + s["soak_samples"] + s["cool_samples"]
    rec = []
    for i in range(s["recover_samples"] // t):
        a = rec_start + i * t
        w = y[a:a + t]
        if len(w) < t:
            break
        rec.append(band_db(w))
    recovered = np.array(rec[1:4]).mean() if len(rec) >= 4 else float("nan")

    print(f"in-band {BAND_LO:.0f}-{BAND_HI:.0f} Hz, {t/RATE:.2f} s windows, "
          f"{len(lv)} of them over {len(lv)*t/RATE/60:.1f} min\n")
    print(f"{'minute':>8}{'level dB':>10}{'vs cold':>9}")
    per_min = max(1, int(round(60 * RATE / t)))
    for i in range(0, len(lv), per_min):
        chunk = lv[i:i + per_min]
        print(f"{i*t/RATE/60:8.1f}{chunk.mean():10.2f}{chunk.mean()-cold:+9.2f}")

    drop = cold - hot
    back = recovered - hot
    print(f"\n  cold  (windows 1-3)      {cold:8.2f} dB")
    print(f"  hot   (last 3 windows)   {hot:8.2f} dB")
    print(f"  after {s['cool_samples']/RATE:.0f} s of silence  {recovered:8.2f} dB")
    print(f"\n  compression over the soak   {drop:+.2f} dB")
    print(f"  recovered on cooling        {back:+.2f} dB")

    scatter = np.abs(np.diff(lv)).mean()
    print(f"  window-to-window scatter    {scatter:.2f} dB   "
          f"(anything smaller than this is not measured)")

    frac = back / drop if drop > 0 else float("nan")
    cool_s = s["cool_samples"] / RATE
    print()
    # Magnitude first: the category matters far less than whether the number
    # is big enough to act on. Everything else here uses a 1 dB criterion.
    if drop < max(3 * scatter, 0.05):
        print(f"VERDICT: no compression resolved. {drop:+.2f} dB is at or below "
              f"the {scatter:.2f} dB\n         scatter, so this says the driver "
              f"held -- not that it fell a little.")
    elif np.isnan(back):
        print(f"VERDICT: {drop:.2f} dB of drop, but no analysable recovery "
              f"block. Inconclusive:\n         without recovery this cannot be "
              f"told from drift.")
    elif frac >= 0.7:
        print(f"VERDICT: thermal compression, {drop:.2f} dB, and reversible -- "
              f"{frac*100:.0f}% came back\n         after {cool_s:.0f} s of "
              f"silence, which drift does not do.")
    elif frac >= 0.3:
        print(f"VERDICT: {drop:.2f} dB of drop, {frac*100:.0f}% of it recovered "
              f"in {cool_s:.0f} s. PARTIAL RECOVERY\n         is consistent "
              f"with thermal whose cooling constant is longer than the\n"
              f"         cooldown -- the magnet and basket hold heat after the "
              f"coil sheds it --\n         but it does not separate that from "
              f"amplifier heating or slow drift.\n         Lengthen --cool to "
              f"tell them apart.")
    else:
        print(f"VERDICT: level fell {drop:.2f} dB and only {frac*100:.0f}% came "
              f"back. Thermal compression\n         is reversible, so treat "
              f"this as drift -- mic, room or fan -- until a\n         longer "
              f"--cool says otherwise. Do not read it as a driver property.")

    if drop < 1.0:
        print(f"\n         Either way {drop:.2f} dB is far below the 1 dB "
              f"criterion this repo uses\n         everywhere else, and below "
              f"audibility. It does not gate a level change.")
    return 0


def main():
    ap = argparse.ArgumentParser()
    sub = ap.add_subparsers(dest="cmd", required=True)
    g = sub.add_parser("gen")
    g.add_argument("out"); g.add_argument("sched")
    g.add_argument("--soak", type=float, default=480.0)
    g.add_argument("--cool", type=float, default=90.0)
    g.add_argument("--recover", type=float, default=45.0)
    g.add_argument("--tile", type=float, default=5.0)
    g.add_argument("--level", type=float, default=-10.3,
                   help="RMS dBFS; default is music2 through the chain")
    g.add_argument("--seed", type=int, default=7)
    g.add_argument("--shape-from", default=None,
                   help="wav whose average spectrum the pink is matched to")
    g.set_defaults(func=gen)
    a = sub.add_parser("analyze")
    a.add_argument("cap"); a.add_argument("sched")
    a.set_defaults(func=analyze)
    args = ap.parse_args()
    return args.func(args)


if __name__ == "__main__":
    sys.exit(main())
