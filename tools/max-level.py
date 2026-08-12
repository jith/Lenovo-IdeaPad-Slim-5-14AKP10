#!/usr/bin/env python3
"""Find the drive level at which this speaker starts to distort, frequency by
frequency.

    tools/max-level.py gen     stimulus.wav schedule.json [--burst 0.45] ...
    tools/max-level.py analyze capture.wav  schedule.json [--thd 3,5,10]

`gen` writes sine bursts -- a sync burst at each end, and between them either
a plain staircase of every level at every frequency, or, with `--ref`, each
test level bracketed by a reference level. `tools/max-level.sh` plays it
through the RAW hardware sink and records it on the internal microphone.
`analyze` aligns the capture against the schedule and, for each burst,
measures

    fundamental   how much of the tone came back
    THD           harmonics 2..12, local-noise-corrected
    compression   how far the fundamental has fallen behind the drive

and then reports, per frequency, the highest drive level that stayed clean.

WHICH MODE. The staircase covers a whole grid cheaply and its THD figures are
sound, but its compression figures are fitted against its own quiet end and
are only good to about +-2 dB at the frequencies where the driver is weakest
-- which are the ones worth knowing about. Use `--ref` for anything that turns
on 1 dB. On this machine the staircase found the shape and `--ref -18` found
the number.

WHY A MICROPHONE AND NOT THE SINK MONITOR. The monitor tap sits ahead of the
codec's volume control and ahead of the amplifier and driver, so it cannot see
clipping or a cone hitting its limit -- it returns whatever the DSP produced.
Everything this script is looking for happens after that point, which leaves
the microphone as the only instrument that can see it.

WHAT THE MICROPHONE CAVEAT DOES AND DOES NOT COST HERE. The internal mic is
uncalibrated and sits inside the chassis, so its absolute response is not
usable -- see README, "The microphone caveat". Two things save this
measurement from that:

  - THD is a RATIO taken at one frequency and one mic position. The mic's
    response at f and at 2f does not cancel, so the absolute percentage is
    approximate, but its behaviour ACROSS LEVEL at fixed f is exactly the
    valid use the caveat allows.
  - compression is a relative level change at ONE frequency, which is the
    same kind of comparison.

Neither reads the mic's frequency response, and neither is used to build a
correction curve.

The one thing that could still fake a result is the capture chain distorting
before the speaker does. `tools/max-level.sh --validate` is the control for
that: re-run one frequency with the mic gain 6 dB lower and confirm the
measured THD does not move.
"""

import argparse
import json
import subprocess
import sys

import numpy as np

# Blackman-Harris 4-term: -92 dB sidelobes. A Hann window's -31 dB first
# sidelobe would put the fundamental's own leakage on top of harmonics that
# are 40-60 dB down, and every THD figure here lives in that range.
BH4 = (0.35875, 0.48829, 0.14128, 0.01168)

# Half-width, in bins, of the band summed for a partial. BH4's main lobe is
# 8 bins wide, so +-6 collects it with a little room for frequency error.
HALF = 6

# Local noise floor is the median bin power in a ring around the partial,
# scaled up to the partial's bandwidth. Inner edge clears the main lobe.
RING_IN, RING_OUT = 16, 64

FREQS = [80, 100, 125, 160, 200, 250, 315, 400, 500, 630, 800, 1000,
         1250, 1600, 2000, 2500, 3150, 4000, 5000, 6300, 8000, 10000,
         12500, 16000]
LEVELS = [-24, -21, -18, -15, -12, -9, -6, -3, 0]

SYNC_FREQ = 3000.0
SYNC_AMP = 0.25
SYNC_DUR = 0.25


def window(n):
    k = np.arange(n)
    w = np.zeros(n)
    for i, a in enumerate(BH4):
        w += (-1) ** i * a * np.cos(2 * np.pi * i * k / n)
    return w


def burst(freq, amp, dur, rate, ramp):
    n = int(round(dur * rate))
    t = np.arange(n) / rate
    x = amp * np.sin(2 * np.pi * freq * t)
    r = int(round(ramp * rate))
    if r > 0 and 2 * r < n:
        e = 0.5 * (1 - np.cos(np.pi * np.arange(r) / r))
        x[:r] *= e
        x[-r:] *= e[::-1]
    return x


def cmd_gen(args):
    if args.gap is None:
        args.gap = 0.6 if args.ref is not None else 0.15
    if args.ref is not None:
        return cmd_gen_interleaved(args)
    rate = args.rate
    sched = {"rate": rate, "burst": args.burst, "gap": args.gap,
             "ramp": args.ramp, "segments": []}
    parts = []
    pos = 0

    def append(x):
        nonlocal pos
        parts.append(x)
        start = pos
        pos += len(x)
        return start

    def silence(dur):
        append(np.zeros(int(round(dur * rate))))

    silence(0.5)
    sched["sync_head"] = append(
        burst(SYNC_FREQ, SYNC_AMP, SYNC_DUR, rate, args.ramp))
    silence(0.5)

    for f in args.freqs:
        for db in args.levels:
            amp = 10 ** (db / 20.0)
            start = append(burst(f, amp, args.burst, rate, args.ramp))
            sched["segments"].append(
                {"freq": f, "db": db, "start": start,
                 "n": int(round(args.burst * rate))})
            silence(args.gap)
        silence(0.35)

    silence(0.5)
    sched["sync_tail"] = append(
        burst(SYNC_FREQ, SYNC_AMP, SYNC_DUR, rate, args.ramp))
    silence(0.5)

    mono = np.concatenate(parts).astype(np.float32)
    stereo = np.column_stack([mono, mono]).ravel()
    sched["length"] = len(mono)

    subprocess.run(
        ["ffmpeg", "-v", "error", "-y", "-f", "f32le", "-ar", str(rate),
         "-ac", "2", "-i", "-", "-c:a", "pcm_f32le", args.stimulus],
        input=stereo.tobytes(), check=True)
    with open(args.schedule, "w") as fh:
        json.dump(sched, fh)

    dur = len(mono) / rate
    print(f"{len(sched['segments'])} bursts, "
          f"{len(args.freqs)} frequencies x {len(args.levels)} levels")
    print(f"{args.stimulus}  {dur:.1f} s")


def cmd_gen_interleaved(args):
    """Reference, test, reference, test ... as separate bursts with gaps.

    Two things have to be true at once and only this arrangement gets both.

    BRACKETING, because a fitted baseline is not accurate enough. A plain
    rising staircase measures compression against a line fitted through its
    own quiet end, and at 500 Hz those points scatter by 2 dB -- larger than
    the effect. Putting the same reference level on both sides of every test
    level replaces the fit with a difference.

    GAPS, because the room is in the measurement. The internal mic hears
    reverberation, and at 500 Hz this room decays slowly enough that a
    reference block 250 ms after a full-scale block reads 7.6 dB HIGH -- the
    tail of the previous block, not the driver. Measured: at one drive level,
    -18 dBFS, the same reference block read -47.7 dBFS after silence, -43.0
    after a -6 dBFS block and -40.1 after a 0 dBFS block, a perfect ranking by
    what preceded it. Stepping the amplitude of an unbroken tone -- which is
    otherwise the obvious way to hold the room and the driver still -- cannot
    be rescued from this, because the tail never gets a chance to decay. The
    gap has to be long enough that it does.

    The onset settling that motivated the unbroken tone in the first place
    (1.15 dB over the first 250 ms, and nearly level-independent) turns out
    not to need it: reference and test are bursts of the same length analysed
    at the same offset, so it is common to both and cancels in the difference.
    """
    rate = args.rate
    sched = {"rate": rate, "burst": args.burst, "gap": args.gap,
             "ramp": args.ramp, "ref": args.ref, "interleaved": True,
             "segments": []}
    parts = []
    pos = 0

    def append(x):
        nonlocal pos
        parts.append(x)
        start = pos
        pos += len(x)
        return start

    def silence(dur):
        append(np.zeros(int(round(dur * rate))))

    silence(0.5)
    sched["sync_head"] = append(
        burst(SYNC_FREQ, SYNC_AMP, SYNC_DUR, rate, args.ramp))
    silence(0.5)

    n = int(round(args.burst * rate))
    for f in args.freqs:
        plan = []
        for db in args.levels:
            plan += [args.ref, db]
        plan.append(args.ref)
        for i, db in enumerate(plan):
            start = append(burst(f, 10 ** (db / 20.0), args.burst, rate,
                                 args.ramp))
            sched["segments"].append(
                {"freq": f, "db": db, "start": start, "n": n,
                 "role": "ref" if db == args.ref and i % 2 == 0 else "test",
                 "block": i})
            silence(args.gap)
        silence(0.4)

    silence(0.5)
    sched["sync_tail"] = append(
        burst(SYNC_FREQ, SYNC_AMP, SYNC_DUR, rate, args.ramp))
    silence(0.5)

    mono = np.concatenate(parts).astype(np.float32)
    stereo = np.column_stack([mono, mono]).ravel()
    sched["length"] = len(mono)

    subprocess.run(
        ["ffmpeg", "-v", "error", "-y", "-f", "f32le", "-ar", str(rate),
         "-ac", "2", "-i", "-", "-c:a", "pcm_f32le", args.stimulus],
        input=stereo.tobytes(), check=True)
    with open(args.schedule, "w") as fh:
        json.dump(sched, fh)

    print(f"{len(sched['segments'])} blocks, {len(args.freqs)} frequencies, "
          f"each test level bracketed by {args.ref:+d} dBFS")
    print(f"{args.stimulus}  {len(mono) / rate:.1f} s")


def read_wav(path):
    """Return (samples[n, ch], rate). Channels are kept separate: a downmix
    of two mic channels reads correlated content hot and would move every
    level in the table."""
    probe = subprocess.run(
        ["ffprobe", "-v", "error", "-select_streams", "a:0", "-show_entries",
         "stream=sample_rate,channels", "-of", "json", path],
        capture_output=True, text=True, check=True)
    info = json.loads(probe.stdout)["streams"][0]
    rate, ch = int(info["sample_rate"]), int(info["channels"])
    raw = subprocess.run(
        ["ffmpeg", "-v", "error", "-i", path, "-f", "f32le", "-c:a",
         "pcm_f32le", "-"], capture_output=True, check=True).stdout
    x = np.frombuffer(raw, dtype=np.float32).astype(np.float64)
    return x.reshape(-1, ch), rate


def tone_envelope(x, freq, rate, bw=60.0):
    """Magnitude of the component at `freq`, by complex demodulation and a
    boxcar average. Used only to find the sync bursts."""
    t = np.arange(len(x)) / rate
    z = x * np.exp(-2j * np.pi * freq * t)
    n = max(1, int(round(rate / bw)))
    k = np.ones(n) / n
    return np.abs(np.convolve(z, k, mode="same"))


def find_sync(x, rate, lo, hi):
    """Index of the first sample in [lo, hi) where the sync tone reaches half
    its peak there. Half-peak on a 30 ms raised-cosine ramp is within a
    millisecond of the burst start, and the two syncs are differenced against
    the same criterion, so what is left of that bias cancels."""
    seg = x[lo:hi]
    env = tone_envelope(seg, SYNC_FREQ, rate)
    peak = env.max()
    if peak <= 0:
        return None
    above = np.flatnonzero(env >= 0.5 * peak)
    return None if len(above) == 0 else lo + int(above[0])


def band_power(psd, centre_bin, half=HALF):
    lo = max(0, centre_bin - half)
    hi = min(len(psd), centre_bin + half + 1)
    return float(psd[lo:hi].sum())


def local_noise(psd, centre_bin, half=HALF):
    """Power the partial's band would hold if it contained only noise."""
    lo1 = max(0, centre_bin - RING_OUT)
    hi1 = max(0, centre_bin - RING_IN)
    lo2 = min(len(psd), centre_bin + RING_IN)
    hi2 = min(len(psd), centre_bin + RING_OUT)
    ring = np.concatenate([psd[lo1:hi1], psd[lo2:hi2]])
    if len(ring) == 0:
        return 0.0
    return float(np.median(ring)) * (2 * half + 1)


def analyse_segment(x, freq, rate, nfft):
    """Fundamental power, harmonic powers and noise floor for one burst.
    `x` is [n, ch]; channel powers are summed, which is a two-microphone
    energy estimate rather than a downmix."""
    if len(x) < nfft:
        return None
    off = (len(x) - nfft) // 2
    seg = x[off:off + nfft]
    w = window(nfft)
    psd = np.zeros(nfft // 2 + 1)
    for c in range(seg.shape[1]):
        psd += np.abs(np.fft.rfft(seg[:, c] * w)) ** 2

    # Scale so a full-scale sine on one channel reads 0 dBFS. Parseval over
    # the one-sided main lobe of an A*sin gives N*A^2/4*sum(w^2); the channel
    # count divides back out because the two mic channels are summed above.
    ref = seg.shape[1] * nfft * float((w ** 2).sum()) / 4.0

    hz = rate / nfft
    b1 = int(round(freq / hz))
    p1_raw = band_power(psd, b1)
    n1 = local_noise(psd, b1)
    p1 = max(p1_raw - n1, 1e-30)

    harm, hp = [], 0.0
    for k in range(2, 13):
        fk = k * freq
        if fk > 0.97 * rate / 2:
            break
        bk = int(round(fk / hz))
        pk = band_power(psd, bk) - local_noise(psd, bk)
        pk = max(pk, 0.0)
        harm.append((k, pk))
        hp += pk

    return {"p1": p1, "snr_db": 10 * np.log10(p1_raw / max(n1, 1e-30)),
            "thd": float(np.sqrt(hp / p1)),
            # Mic-referenced levels. These say nothing about the speaker --
            # the mic is uncalibrated -- but they do say how much headroom the
            # CAPTURE has left, which is what stops the mic's own clipping
            # being read as the speaker's.
            "p1_dbfs": 10 * np.log10(p1 / ref),
            "hd_dbfs": 10 * np.log10(max(hp, 1e-30) / ref),
            "noise_dbfs": 10 * np.log10(max(n1, 1e-30) / ref),
            "harm": [(k, float(np.sqrt(max(pk, 0.0) / p1))) for k, pk in harm],
            "top_harm": max(harm, key=lambda kv: kv[1])[0] if harm else 0}


def cmd_analyze(args):
    with open(args.schedule) as fh:
        sched = json.load(fh)
    x, rate = read_wav(args.capture)
    if rate != sched["rate"]:
        sys.exit(f"capture is {rate} Hz, schedule is {sched['rate']} Hz")

    mono = x.sum(axis=1)
    # Never let the two search windows overlap, or a short capture finds the
    # same sync twice and the drift check reports -1000000 ppm.
    win = min(int(8 * rate), len(mono) // 2)
    head = find_sync(mono, rate, 0, win)
    tail = find_sync(mono, rate, len(mono) - win, len(mono))
    if head is None or tail is None:
        sys.exit("could not find the sync bursts -- is the capture silent?")

    span_s = sched["sync_tail"] - sched["sync_head"]
    span_c = tail - head
    drift = span_c / span_s - 1.0
    if abs(drift) > 2e-3:
        sys.exit(f"playback and capture clocks disagree by {drift * 1e6:.0f} "
                 "ppm -- too much to index a 0.45 s burst by schedule")

    def to_capture(s):
        return head + int(round((s - sched["sync_head"]) * span_c / span_s))

    if sched.get("interleaved"):
        return report_interleaved(x, rate, sched, to_capture, args, drift)

    nfft = args.nfft
    rows = {}
    weak = 0
    for seg in sched["segments"]:
        a = to_capture(seg["start"])
        b = a + seg["n"]
        guard = int(round(sched["ramp"] * rate * 1.5))
        a, b = a + guard, b - guard
        if a < 0 or b > len(x):
            continue
        r = analyse_segment(x[a:b], seg["freq"], rate, nfft)
        if r is None:
            continue
        if r["snr_db"] < args.min_snr:
            weak += 1
            r["weak"] = True
        rows.setdefault(seg["freq"], {})[seg["db"]] = r

    report(rows, sched, args, drift, weak)


def report_interleaved(x, rate, sched, to_capture, args, drift):
    # The usable part of a block is shorter than a burst, so fall back to the
    # largest power of two that fits rather than silently analysing nothing.
    guard = int(round(sched["ramp"] * rate * 1.5))
    avail = sched["segments"][0]["n"] - 2 * guard
    nfft = min(args.nfft, 1 << int(np.log2(avail)))
    blocks = {}
    for seg in sched["segments"]:
        # The window ends just before the ramp-down and runs backwards from
        # there, so it sits as late in the burst as it can. Same offset for
        # reference and test, which is what makes the onset settling cancel.
        b = to_capture(seg["start"]) + seg["n"] - guard
        a = b - nfft
        if a < 0 or b > len(x):
            continue
        r = analyse_segment(x[a:b], seg["freq"], rate, nfft)
        if r is None:
            continue
        r.update(role=seg["role"], db=seg["db"])
        blocks.setdefault(seg["freq"], {})[seg["block"]] = r

    levels = sorted({s["db"] for s in sched["segments"]
                     if s["role"] == "test"})
    ref_db = sched["ref"]

    print(f"clock drift {drift * 1e6:+.0f} ppm over the capture; "
          f"{nfft} point analysis window ({1000 * nfft / rate:.0f} ms)")
    print(f"every test level bracketed by {ref_db:+d} dBFS, as separate "
          f"bursts {1000 * sched['gap']:.0f} ms apart. Compression is the")
    print("difference between test and the mean of its two references, so "
          "drift and onset settling cancel.")
    print()
    print("Compression dB -- drive asked for, minus output delivered, "
          "against the bracketing reference.")
    print()
    hdr = "  freq  " + "".join(f"{db:>7}" for db in levels) + f"{'noise':>8}"
    print(hdr)
    print("  " + "-" * (len(hdr) - 2))

    out = {}
    for f in sorted(blocks):
        bl = blocks[f]
        comp, thd, resid = {}, {}, []
        for i, r in sorted(bl.items()):
            if r["role"] != "test":
                continue
            neigh = [bl[j]["p1_dbfs"] for j in (i - 1, i + 1)
                     if j in bl and bl[j]["role"] == "ref"]
            if not neigh:
                continue
            ref_out = float(np.mean(neigh))
            if len(neigh) == 2:
                resid.append(abs(neigh[0] - neigh[1]))
            comp[r["db"]] = (r["db"] - ref_db) - (r["p1_dbfs"] - ref_out)
            thd[r["db"]] = r["thd"]
        # Spread between the two references bracketing the same test block is
        # this row's own error bar -- no model, no fit, just repeatability.
        err = float(np.median(resid)) if resid else float("nan")
        cells = [f"{comp[db]:>7.2f}" if db in comp else f"{'.':>7}"
                 for db in levels]
        print(f"  {f:>5}  " + "".join(cells) + f"{err:>8.2f}")
        out[f] = {"comp": comp, "thd": thd, "err": err}

    print()
    print("  The last column is the median disagreement between the two "
          "reference blocks that bracket the same test.")
    print("  Compression smaller than that is not measured, it is scatter.")

    print()
    print("THD %, same blocks.")
    print()
    hdr2 = "  freq  " + "".join(f"{db:>7}" for db in levels)
    print(hdr2)
    print("  " + "-" * (len(hdr2) - 2))
    for f in sorted(blocks):
        cells = [f"{100 * out[f]['thd'][db]:>7.1f}" if db in out[f]["thd"]
                 else f"{'.':>7}" for db in levels]
        print(f"  {f:>5}  " + "".join(cells))

    print()
    print(f"Ceiling: highest drive whose compression stays under "
          f"{args.max_comp:.1f} dB, and what the next 3 dB would return.")
    print()
    print(f"  {'freq':>5}  {'ceiling':>9}  {'comp there':>11}  "
          f"{'THD there':>10}  {'next 3 dB returns':>18}")
    print("  " + "-" * 62)
    ceil = {}
    for f in sorted(blocks):
        c = out[f]["comp"]
        best = None
        for db in reversed(levels):
            if db in c and c[db] <= args.max_comp:
                best = db
                break
        ceil[f] = best
        if best is None:
            print(f"  {f:>5}  {'none':>9}")
            continue
        nxt = [db for db in levels if db > best]
        gain = ""
        if nxt:
            d = nxt[0] - best
            gain = f"{d - (c[nxt[0]] - c[best]):>13.2f} dB"
        label = ">0" if best == max(levels) else f"{best:+d}"
        print(f"  {f:>5}  {label:>9}  {c[best]:>9.2f} dB  "
              f"{100 * out[f]['thd'][best]:>9.1f}%  {gain:>18}")

    if args.json:
        with open(args.json, "w") as fh:
            json.dump({"ref": ref_db, "levels": levels,
                       "per_freq": {str(f): {"comp": v["comp"],
                                             "thd": v["thd"], "err": v["err"]}
                                    for f, v in out.items()},
                       "ceiling": {str(f): v for f, v in ceil.items()}},
                      fh, indent=1)
        print(f"\nwrote {args.json}")


def report(rows, sched, args, drift, weak):
    levels = sorted({db for v in rows.values() for db in v})
    thresholds = [float(t) for t in args.thd.split(",")]

    print(f"clock drift {drift * 1e6:+.0f} ppm over the capture; "
          f"{weak} of {sum(len(v) for v in rows.values())} bursts below "
          f"{args.min_snr:.0f} dB SNR and excluded")
    print()
    print("THD %, by drive level. '.' = fundamental too close to the noise "
          "floor to measure.")
    print()
    head = "  freq  " + "".join(f"{db:>7}" for db in levels)
    print(head)
    print("  " + "-" * (len(head) - 2))

    out = {}
    for f in sorted(rows):
        cells = []
        for db in levels:
            r = rows[f].get(db)
            if r is None or r.get("weak"):
                cells.append(f"{'.':>7}")
            else:
                cells.append(f"{100 * r['thd']:>7.1f}")
        print(f"  {f:>5}  " + "".join(cells))

        # Compression: fit a unit-slope line through the quietest clean
        # points, then read how far each louder point has fallen behind it.
        clean = [(db, r) for db, r in sorted(rows[f].items())
                 if not r.get("weak")]
        comp, scatter = {}, None
        if len(clean) >= 3:
            # The driver is linear at the bottom of the grid, so the offset
            # between drive and output there is the unity-slope reference.
            # Median, not mean: one reflection-affected point in the baseline
            # would otherwise tilt every compression figure in the row.
            base = clean[:max(3, len(clean) // 3)]
            resid = [r["p1_dbfs"] - db for db, r in base]
            off = float(np.median(resid))
            scatter = float(np.max(resid) - np.min(resid))
            for db, r in clean:
                comp[db] = (db + off) - r["p1_dbfs"]
        out[f] = {"thd": {db: r["thd"] for db, r in clean},
                  "comp": comp, "baseline_scatter": scatter,
                  "snr": {db: r["snr_db"] for db, r in clean},
                  "top_harm": {db: r["top_harm"] for db, r in clean},
                  "p1_dbfs": {db: r["p1_dbfs"] for db, r in rows[f].items()},
                  "hd_dbfs": {db: r["hd_dbfs"] for db, r in rows[f].items()},
                  "noise_dbfs": {db: r["noise_dbfs"]
                                 for db, r in rows[f].items()}}

    if args.raw:
        for label, key in (("fundamental at the mic", "p1_dbfs"),
                           ("harmonics at the mic", "hd_dbfs"),
                           ("local noise floor at the mic", "noise_dbfs")):
            print()
            print(f"{label}, dBFS of the capture. Relative only -- the mic is "
                  "uncalibrated. What these are for is headroom: if the "
                  "fundamental")
            print("approaches 0 dBFS the capture chain is clipping and every "
                  "THD figure above it is the microphone's, not the speaker's.")
            print()
            print(head)
            print("  " + "-" * (len(head) - 2))
            for f in sorted(rows):
                cells = [f"{out[f][key].get(db, float('nan')):>7.1f}"
                         for db in levels]
                print(f"  {f:>5}  " + "".join(cells))

    print()
    print("Compression dB -- how far the fundamental has fallen behind the "
          "drive. Positive is output the driver did not deliver.")
    print()
    print(head)
    print("  " + "-" * (len(head) - 2))
    for f in sorted(rows):
        cells = []
        for db in levels:
            c = out[f]["comp"].get(db)
            cells.append(f"{'.':>7}" if c is None else f"{c:>7.2f}")
        print(f"  {f:>5}  " + "".join(cells))

    print()
    print("Highest drive level that stayed clean, dBFS. A level passes when "
          f"THD is at or under the column and compression is under "
          f"{args.max_comp:.1f} dB.")
    print("'>0' means nothing in the grid broke it -- full scale is clean at "
          "that frequency.")
    print()
    cols = ("  freq  " + "".join(f"{f'THD<{t:g}%':>10}" for t in thresholds)
            + f"{'+-dB':>8}")
    print(cols)
    print("  " + "-" * (len(cols) - 2))
    ceilings = {}
    for f in sorted(rows):
        cells = []
        for t in thresholds:
            # Scan DOWN from full scale and take the first level that passes.
            # Scanning up and stopping at the first failure reads a single
            # noisy point at the quiet end -- where the fundamental is nearest
            # the room floor and the figures scatter most -- as the ceiling
            # for the whole row. Distortion rises with level, so the highest
            # passing level is the ceiling.
            best = None
            for db in reversed(levels):
                thd = out[f]["thd"].get(db)
                comp = out[f]["comp"].get(db)
                if thd is None:
                    continue
                if 100 * thd <= t and (comp is None or comp <= args.max_comp):
                    best = db
                    break
            cells.append(f"{'none':>10}" if best is None else
                         f"{('>0' if best == 0 else f'{best:+d}'):>10}")
            ceilings.setdefault(f, {})[t] = best
        s = out[f]["baseline_scatter"]
        cells.append(f"{'?':>8}" if s is None else f"{s:>8.1f}")
        print(f"  {f:>5}  " + "".join(cells))
    print()
    print("  The last column is the spread of the linear baseline the "
          "compression figures are measured against.")
    print("  A row whose spread is comparable to the compression it reports "
          "has not measured anything.")

    if args.json:
        with open(args.json, "w") as fh:
            json.dump({"levels": levels, "per_freq": out,
                       "ceilings": {str(f): v for f, v in ceilings.items()}},
                      fh, indent=1)
        print(f"\nwrote {args.json}")


def main():
    p = argparse.ArgumentParser(description=__doc__,
                                formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = p.add_subparsers(dest="cmd", required=True)

    g = sub.add_parser("gen")
    g.add_argument("stimulus")
    g.add_argument("schedule")
    g.add_argument("--rate", type=int, default=48000)
    g.add_argument("--burst", type=float, default=0.45)
    # Interleaved mode needs a long gap: it compares bursts at very different
    # levels, so the tail of a loud one has to be gone before the quiet one
    # that follows is measured. The plain staircase only ever steps 3 dB at a
    # time and does not.
    g.add_argument("--gap", type=float, default=None)
    g.add_argument("--ramp", type=float, default=0.03)
    g.add_argument("--freqs", type=lambda s: [float(v) for v in s.split(",")],
                   default=FREQS)
    g.add_argument("--levels", type=lambda s: [int(v) for v in s.split(",")],
                   default=LEVELS)
    g.add_argument("--ref", type=int,
                   help="switch to interleaved mode and use this level as the "
                        "reference each test level is bracketed by. This is "
                        "the mode that can resolve 1 dB of compression; the "
                        "plain staircase cannot.")
    g.set_defaults(func=cmd_gen)

    a = sub.add_parser("analyze")
    a.add_argument("capture")
    a.add_argument("schedule")
    a.add_argument("--nfft", type=int, default=16384)
    a.add_argument("--min-snr", type=float, default=12.0,
                   help="drop a burst whose fundamental is less than this "
                        "far above the local noise floor")
    a.add_argument("--max-comp", type=float, default=1.0)
    a.add_argument("--thd", default="3,5,10")
    a.add_argument("--raw", action="store_true",
                   help="also print mic-referenced levels, which is how you "
                        "check the capture chain is not what clipped")
    a.add_argument("--json")
    a.set_defaults(func=cmd_analyze)

    args = p.parse_args()
    args.func(args)


if __name__ == "__main__":
    main()
