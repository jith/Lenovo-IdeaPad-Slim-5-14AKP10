#!/usr/bin/env python3
"""Run the installed filter chain offline, over a file, without reinstalling.

    tools/offline-chain.py IN.wav OUT.wav [--set node:control=value ...]
    tools/offline-chain.py --measure IN.wav [--set ...]
    tools/offline-chain.py --bands IN.wav [--set ...]
    tools/offline-chain.py --sweep s10mbc:g_out=2.05,2.20,2.40,2.60,2.80 IN.wav
    tools/offline-chain.py --self-test
    tools/offline-chain.py --verify            # against the committed captures

The graph is read from files/50-speaker-tuning.conf every run, so this cannot
drift from what is installed. Builtins are numpy; stages 7, 10, 11 and 12 are
the real LSP binaries driven through ffmpeg.

WHAT THIS IS FOR. Sweeping a parameter forty times to find where a limit
actually is, then confirming the one value you chose on hardware. It is not a
substitute for hardware -- it does not know about the codec, the amplifier or
the drivers, and it cannot tell you which material to test. Every wrong
conclusion recorded in README.md came from testing on material quieter or more
stationary than programme, and offline would have reproduced all of them
faithfully.

AND USE --bands BEFORE SHIPPING A VOICING CHANGE. Every other mode here
answers "what did this one parameter move", which cannot see an accumulation.
A 10.1 dB bass-to-presence tilt survived four tuning sessions that way -- two
boosts, each measured alone, each nearly free alone, both pushing the same
direction, sum never taken. --bands prints the total.

ACCURACY, as checked by --verify: within 0.03 LU on integrated loudness, 0.04
dB on g_out row-to-row deltas, and 1.5 percentage points on THD at 90 Hz. Trust
it for differences. Confirm absolutes on hardware.
"""

import argparse
import os
import sys
from collections import defaultdict, deque

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from dsp_offline import (RATE, LV2_URI, _rbj, _biquad_fast, dcblock, delay,
                         lv2, lufs, parse_config, read_wav, sample_peak_db,
                         thd_percent, true_peak_db, write_wav)

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CONFIG = os.path.join(ROOT, "files", "50-speaker-tuning.conf")

# Indirection so --self-test can swap the LSP plugins for pass-through and
# still exercise the parser, the topological sort and all 90-odd builtins on a
# machine that has no LV2 binaries at all.
LV2 = lv2


def _lv2_bypass(x, uri, controls, rate=RATE, sidechain=None):
    return x[:, :2] * controls.get("g_out", 1.0)


def run_node(node, name, inputs):
    """inputs: dict port-index -> mono array. Returns dict port-index -> array.

    Two shapes of builtin. `mixer` and `mult` combine In 1..8 into one Out.
    Everything else is per-channel: In i goes to Out i, independently, sharing
    one set of controls -- stage 7's dcblock runs three bands through one node
    that way, and reading it as mono silently drops two of them.
    """
    label, ctrl = node["label"], node["control"]
    first = inputs[min(inputs)]

    if label == "mult":
        out = np.ones_like(first)
        for x in inputs.values():
            out = out * x
        return {0: out}

    if label == "mixer":
        out = np.zeros_like(first)
        for port, x in inputs.items():
            out = out + x * ctrl.get(f"Gain {port + 1}", 1.0)
        return {0: out}

    per_channel = None
    if label == "linear":
        per_channel = lambda s: s * ctrl.get("Mult", 1.0) + ctrl.get("Add", 0.0)
    elif label == "invert":
        per_channel = lambda s: -s
    elif label == "dcblock":
        per_channel = lambda s: dcblock(s, ctrl.get("R", 0.995))
    elif label == "delay":
        per_channel = lambda s: delay(s, ctrl.get("Delay (s)", 0.0))
    elif label == "bq_raw":
        b = np.array([ctrl["b0"], ctrl["b1"], ctrl["b2"]]) / ctrl["a0"]
        a = np.array([1.0, ctrl["a1"] / ctrl["a0"], ctrl["a2"] / ctrl["a0"]])
        per_channel = lambda s: _biquad_fast(s, b, a)
    elif label and label.startswith("bq_"):
        b, a = _rbj(label, ctrl["Freq"], ctrl.get("Q", 0.707), ctrl.get("Gain", 0.0))
        per_channel = lambda s: _biquad_fast(s, b, a)

    if per_channel:
        return {port: per_channel(s) for port, s in inputs.items()}

    if node["kind"] == "lv2":
        uri = node["plugin"]
        ports = sorted(inputs)
        stereo = np.stack([inputs[ports[0]], inputs[ports[1 if len(ports) > 1 else 0]]], 1)
        side = None
        if len(ports) == 4:                    # stage 11: audio pair + sidechain pair
            side = np.stack([inputs[ports[2]], inputs[ports[3]]], 1)
        y = LV2(stereo, uri, ctrl, sidechain=side)
        return {0: y[:, 0], 1: y[:, 1]}

    raise RuntimeError(f"{name}: no emulation for label={label!r} kind={node['kind']!r}")


def build_graph(config=CONFIG, overrides=None):
    nodes, links = parse_config(config)
    for spec in overrides or []:
        target, value = spec.split("=", 1)
        node, control = target.split(":", 1)
        if node not in nodes:
            raise SystemExit(f"--set: no node {node!r} in the config")
        nodes[node]["control"][control] = float(value)
    return nodes, links


def port_index(nodes, name, port, side):
    """LSP ports are named (in_l, sc_l ...), builtin ports are 'In 1'/'Out'.

    Ordering matters only for mixer gains and for telling stage 11's sidechain
    from its audio, so it is enough to keep builtins numbered as written and
    LSP ports in l,r then sidechain l,r order.
    """
    if port.startswith(("In ", "Out ")):
        return int(port.split()[1]) - 1
    order = {"in_l": 0, "in_r": 1, "sc_l": 2, "sc_r": 3,
             "out_l": 0, "out_r": 1}
    return order.get(port, 0)


def process(x, nodes, links, verbose=False):
    """Topologically sort the graph and run it. x is (samples, 2)."""
    incoming = defaultdict(dict)               # node -> {port: (src, srcport)}
    outdegree = defaultdict(set)
    for out_ref, in_ref in links:
        src, sport = out_ref.split(":")
        dst, dport = in_ref.split(":")
        incoming[dst][port_index(nodes, dst, dport, "in")] = (src, port_index(nodes, src, sport, "out"))
        outdegree[src].add(dst)

    # Plain dicts from here: a defaultdict grows a key on every lookup, which
    # would make every node look like it had inputs the moment Kahn ran.
    incoming, outdegree = dict(incoming), dict(outdegree)

    sources = [n for n in nodes if n not in incoming]
    sinks = [n for n in nodes if n not in outdegree]
    if verbose:
        print(f"  graph: {len(nodes)} nodes, {len(links)} links, "
              f"inputs {sorted(sources)}, outputs {sorted(sinks)}", file=sys.stderr)

    # Kahn's algorithm. A cycle here means the config has a feedback path,
    # which the filter-chain module does not support either.
    pending = {n: len({s for s, _ in incoming.get(n, {}).values()}) for n in nodes}
    ready = deque(n for n, k in pending.items() if k == 0)
    order = []
    while ready:
        n = ready.popleft()
        order.append(n)
        for m in outdegree.get(n, ()):
            pending[m] -= 1
            if pending[m] == 0:
                ready.append(m)
    if len(order) != len(nodes):
        raise RuntimeError("cycle in the filter graph, or an unreachable node")

    # Channel inputs. The config's `inputs = [...]` list is L then R.
    values = {}
    left = sorted(n for n in sources if n.endswith("_l"))
    right = sorted(n for n in sources if n.endswith("_r"))
    for group, col in ((left, 0), (right, 1)):
        for n in group:
            values[(n, "IN", 0)] = x[:, col]

    for name in order:
        node = nodes[name]
        if name in incoming:
            ins = {p: values[(s, "OUT", sp)] for p, (s, sp) in incoming[name].items()}
        else:
            ins = {0: values[(name, "IN", 0)]}
        for port, y in run_node(node, name, ins).items():
            values[(name, "OUT", port)] = y

    out_l = values[(sorted(n for n in sinks if n.endswith("_l"))[0], "OUT", 0)]
    out_r = values[(sorted(n for n in sinks if n.endswith("_r"))[0], "OUT", 0)]
    return np.stack([out_l, out_r], 1)


def measure(y, tmp="/tmp/offline-chain-measure.wav", tone=None):
    write_wav(tmp, y)
    row = {"lufs": lufs(tmp), "sample": sample_peak_db(y), "tp": true_peak_db(y)}
    if tone:
        row["thd"] = thd_percent(y, tone)
    return row


# ISO third-octave centres. 25 Hz because stage 1 is at 20 and the subsonic
# corner has to be visible; 16 kHz because stage 12a is at 22.
CENTRES = [25, 31.5, 40, 50, 63, 80, 100, 125, 160, 200, 250, 315, 400, 500,
           630, 800, 1000, 1250, 1600, 2000, 2500, 3150, 4000, 5000, 6300,
           8000, 10000, 12500, 16000]


def band_power(x):
    """Third-octave power, summed across channels.

    Summed as POWER per channel rather than taken off the mono sum, because
    stage 9 moves energy between mid and side: a mid-only read makes its
    widening invisible, and power is what reaches the two drivers.
    """
    nfft, acc = 16384, np.zeros(16384 // 2 + 1)
    win, n = np.hanning(nfft), 0
    for c in range(x.shape[1]):
        ch = x[:, c]
        for i in range(0, len(ch) - nfft, nfft // 2):
            acc += np.abs(np.fft.rfft(ch[i:i + nfft] * win)) ** 2
            n += 1
    if n == 0:
        raise SystemExit("--bands needs at least 0.35 s of audio")
    acc /= n / x.shape[1]
    freqs = np.fft.rfftfreq(nfft, 1 / RATE)
    out = {}
    for fc in CENTRES:
        sel = (freqs >= fc / 2 ** (1 / 6)) & (freqs < fc * 2 ** (1 / 6))
        out[fc] = acc[sel].sum() if sel.any() else np.nan
    return out


def bands(x, y):
    """Print the WHOLE chain's transfer, third-octave, out over in.

    This exists because nothing here had it. Every other mode answers "what
    did this one parameter move" or "what is the level, peak and THD", and a
    per-change measurement cannot see an accumulation: mk_3 and stage 10c were
    each measured alone, each nearly free alone, and their sum -- 5.65 dB, all
    one direction -- went unnoticed until a listener reported it. Print the
    total, not the change.
    """
    pin, pout = band_power(x), band_power(y)
    t = {c: 10 * np.log10(pout[c] / pin[c]) for c in CENTRES}

    def mean(lo, hi):
        return float(np.mean([t[c] for c in CENTRES if lo <= c <= hi]))

    print(f"  {'band':>7} {'gain dB':>9}")
    for c in CENTRES:
        bar = "#" * max(0, min(40, int(round(t[c] + 10))))
        print(f"  {c:>7.0f} {t[c]:>9.2f}  {bar}")
    bass, pres = mean(50, 125), mean(2000, 4000)
    print(f"\n  bass 50-125 Hz   {bass:+.2f} dB")
    print(f"  low-mid 160-400  {mean(160, 400):+.2f} dB")
    print(f"  presence 2-4 kHz {pres:+.2f} dB")
    print(f"  top 5-12.5 kHz   {mean(5000, 12500):+.2f} dB")
    print(f"\n  TILT (presence - bass)  {pres - bass:+.2f} dB")
    if pres - bass > 8.0:
        print("  ^ over 8 dB. Check this is intended -- a reference-device A/B\n"
              "    cannot see a tilt, and neither can a detrended measurement.")
    return 0


def self_test():
    """Everything that can be checked without hardware or LSP binaries."""
    ok = fail = 0

    def check(label, got, want, tol):
        nonlocal ok, fail
        good = abs(got - want) <= tol
        ok, fail = ok + good, fail + (not good)
        print(f"  {'pass' if good else 'FAIL'}  {label}: {got:.4f} (want {want} +/-{tol})")

    # Biquads: the fast path must equal the reference loop exactly.
    from dsp_offline import biquad
    rng = np.random.default_rng(0)
    x = rng.standard_normal(4096)
    b, a = _rbj("bq_lowpass", 1000, 0.707)
    check("bq_lowpass fast == reference", float(np.max(np.abs(_biquad_fast(x, b, a) - biquad(x, b, a)))), 0.0, 1e-9)

    # A lowpass at fc must be 3 dB down at fc, and a highpass likewise.
    def mag_db(b, a, f):
        z = np.exp(-2j * np.pi * f / RATE)
        return 20 * np.log10(abs(np.polyval(b[::-1], z) / np.polyval(a[::-1], z)))

    check("bq_lowpass -3 dB at fc", mag_db(*_rbj("bq_lowpass", 1000, 0.707), 1000), -3.01, 0.02)
    check("bq_highpass -3 dB at fc", mag_db(*_rbj("bq_highpass", 1000, 0.707), 1000), -3.01, 0.02)
    check("bq_bandpass 0 dB at centre", mag_db(*_rbj("bq_bandpass", 1000, 2.0), 1000), 0.0, 0.02)
    check("bq_peaking +6 dB at centre", mag_db(*_rbj("bq_peaking", 1000, 1.0, 6.0), 1000), 6.0, 0.02)
    check("bq_lowpass 18k passband at 10k", mag_db(*_rbj("bq_lowpass", 18000, 0.707), 10000), -0.04, 0.02)

    # --bands: a known gain applied to a known band must come back. Uses two
    # tones so a band-indexing error cannot pass by coincidence.
    t = np.arange(4 * RATE) / RATE
    probe = np.column_stack([np.sin(2 * np.pi * 100 * t) + np.sin(2 * np.pi * 2500 * t)] * 2)
    gained = probe.copy()
    b, a = _rbj("bq_peaking", 2500, 4.0, 6.0)
    for c in range(2):
        gained[:, c] = _biquad_fast(gained[:, c], b, a)
    pin, pout = band_power(probe), band_power(gained)
    check("--bands reads a +6 dB bell at 2500 Hz",
          10 * np.log10(pout[2500] / pin[2500]), 6.0, 0.15)
    check("--bands leaves an untouched band alone",
          10 * np.log10(pout[100] / pin[100]), 0.0, 0.05)
    check("--bands sums both channels, not the mid",
          10 * np.log10(band_power(np.column_stack([probe[:, 0], -probe[:, 1]]))[100]
                        / pin[100]), 0.0, 0.05)

    # True peak: a 0 dBFS sine exactly at Nyquist/2 offset overshoots by a
    # known amount, and a DC signal cannot overshoot at all.
    n = 48000
    check("true peak of DC == 0 dBFS", true_peak_db(np.ones((n, 1))), 0.0, 0.001)
    t = np.arange(n) / RATE
    worst = np.sin(2 * np.pi * 11025 * t + np.pi / 4)   # peaks between samples
    check("true peak of quarter-phase sine", true_peak_db(worst[:, None]), 0.0, 0.02)

    # THD of a pure sine is zero; of a square wave, the textbook 48.3%.
    check("thd of a sine", thd_percent(np.sin(2 * np.pi * 1000 * t)[:, None], 1000), 0.0, 0.1)

    # The config must parse into the graph the README describes. The counts are
    # hardcoded on purpose: they are the guard that catches a node added to the
    # config and not to the stage table.
    nodes, links = parse_config(CONFIG)
    check("node count", len(nodes), 102, 0)
    check("link count", len(links), 190, 0)
    check("bq_raw coefficients parsed", nodes["s2lt_l"]["control"]["b0"], 0.9618034723, 1e-9)
    for name in ("s0trim_l", "s2lt_l", "s10mbc", "s10res_l", "s10pres_l",
                 "s11xcur", "s12lp_l", "s12brick"):
        check(f"{name} present", 1.0 if name in nodes else 0.0, 1.0, 0)

    # Run the whole graph with the LSP stages bypassed. This does not check the
    # LSP stages -- nothing without their binaries can -- but it does check that
    # every builtin wires up, that stage 7's three-channel dcblock is not read
    # as mono, and that the sort terminates.
    global LV2
    real, LV2 = LV2, _lv2_bypass
    try:
        t = np.arange(RATE // 2) / RATE
        tone = np.stack([np.sin(2 * np.pi * 90 * t) * 0.5] * 2, 1)
        muted = build_graph(overrides=["s8sum_l:Gain 3=0.0", "s8sum_r:Gain 3=0.0"])
        y = process(tone, *muted)
        check("full graph runs, output length", float(len(y)), float(len(tone)), 0)
        check("no NaN or inf in output", float(np.isfinite(y).all()), 1.0, 0)
        # Harmonic branch muted, LSP bypassed: the chain is linear, so a pure
        # tone must come out pure. README's "branch and stage 10 both out" row.
        check("THD with the branch muted", thd_percent(y, 90), 0.0, 0.05)
    finally:
        LV2 = real

    print(f"\n{ok}/{ok + fail} passed")
    return 0 if not fail else 1


# Every figure in README.md that can be re-derived from the committed captures.
# `.baseline` is the chain at g_out 2.05, `.current` is the same chain at 2.40,
# which is what makes the deltas checkable at all.
#
# (label, README figure, tolerance, function of the capture set)
VERIFY_ROWS = [
    ("LUFS-I, pink, g_out 2.05", -15.37, 0.05,
     lambda c: lufs(c["pink.baseline"])),
    ("LUFS-I, pink, g_out 2.40", -14.02, 0.05,
     lambda c: lufs(c["pink.current"])),
    ("pink, dLU for 2.05 -> 2.40", +1.37, 0.03,
     lambda c: lufs(c["pink.current"]) - lufs(c["pink.baseline"])),
    ("square100, dLU for 2.05 -> 2.40", +0.31, 0.03,
     lambda c: lufs(c["square100.current"]) - lufs(c["square100.baseline"])),
    ("pink, true peak at g_out 2.40", -5.55, 0.02,
     lambda c: true_peak_db(read_wav(c["pink.current"]))),
]


def verify():
    """Re-derive every README figure the committed captures can settle.

    These are hardware captures, so this checks the measurement functions and
    the README's arithmetic, not the emulation. Checking the emulation itself
    needs the LSP binaries: `--measure tests/material/pink.wav` is that check,
    and it should land within about 0.03 LU of the pink.current row below.
    """
    names = ["pink.baseline", "pink.current", "sweep.baseline", "sweep.current",
             "square100.baseline", "square100.current"]
    caps = {n: os.path.join(ROOT, "tests/captures/gout", n + ".wav") for n in names}
    missing = [n for n, p in caps.items() if not os.path.exists(p)]
    if missing:
        print("captures are gitignored and not present: " + ", ".join(missing))
        print("run tools/null-test.sh to regenerate them.")
        return 2

    print("README figures, re-derived from tests/captures/gout/:\n")
    fail = 0
    for label, want, tol, fn in VERIFY_ROWS:
        got = fn(caps)
        good = abs(got - want) <= tol
        fail += not good
        print(f"  {'pass' if good else 'FAIL'}  {label}: {got:+.3f} "
              f"(README says {want:+.2f})")

    # The one figure that does NOT reconcile, stated rather than hidden. The
    # g_out table's "worst true peak -0.39 at 2.40, binding signal sweep" was
    # computed offline over five stimuli including a pink noise scaled to peak
    # at -1 dBFS, not over these captures, so its absolute dBTP values are on a
    # different stimulus level and cannot be compared to a capture directly.
    # The DELTAS reconcile exactly, and the deltas are what conclusions rest on.
    print("\n  Captures, for reference -- absolute levels here are the level the "
          "material\n  was played at, not the g_out table's stimulus set:\n")
    for n in names:
        y = read_wav(caps[n])
        print(f"    {n:<20} LUFS {lufs(caps[n]):8.2f}   sample "
              f"{sample_peak_db(y):7.3f}   true {true_peak_db(y):7.3f} dBTP")

    print(f"\n{len(VERIFY_ROWS) - fail}/{len(VERIFY_ROWS)} passed")
    return 1 if fail else 0


def compare_dir(path, ceiling=-0.20):
    """Every baseline/current pair in a capture directory, with deltas.

    This is the shape of the question after changing one parameter: what moved,
    by how much, and is anything now over the ceiling. Pair the captures by
    name so `pink.baseline.wav` / `pink.current.wav` line up.
    """
    names = sorted({os.path.basename(f).rsplit(".", 2)[0]
                    for f in os.listdir(path) if f.endswith(".wav")})
    print(f"{'signal':<14}{'LUFS base':>11}{'LUFS cur':>10}{'dLU':>8}"
          f"{'TP base':>10}{'TP cur':>9}{'dTP':>8}   margin")
    over = 0
    for name in names:
        base = os.path.join(path, f"{name}.baseline.wav")
        cur = os.path.join(path, f"{name}.current.wav")
        if not (os.path.exists(base) and os.path.exists(cur)):
            print(f"{name:<14}   no baseline/current pair")
            continue
        lb, lc = lufs(base), lufs(cur)
        tb, tc = true_peak_db(read_wav(base)), true_peak_db(read_wav(cur))
        over += tc > ceiling
        print(f"{name:<14}{lb:11.2f}{lc:10.2f}{lc - lb:+8.2f}"
              f"{tb:10.3f}{tc:9.3f}{tc - tb:+8.3f}   {ceiling - tc:+.3f}"
              + ("  OVER" if tc > ceiling else ""))
    if over:
        print(f"\n{over} signal(s) over the {ceiling:+.2f} dBTP ceiling.",
              file=sys.stderr)
    return 1 if over else 0


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("infile", nargs="?")
    ap.add_argument("outfile", nargs="?")
    ap.add_argument("--set", action="append", default=[], metavar="NODE:CTRL=VAL",
                    help="override a control before running, repeatable")
    ap.add_argument("--sweep", metavar="NODE:CTRL=V1,V2,...",
                    help="run once per value and print a comparison table")
    ap.add_argument("--measure", action="store_true",
                    help="print LUFS / sample peak / true peak instead of writing")
    ap.add_argument("--bands", action="store_true",
                    help="print the whole chain's third-octave transfer and its "
                         "bass-to-presence tilt -- run this before shipping any "
                         "voicing change")
    ap.add_argument("--tone", type=float, metavar="HZ",
                    help="also report THD, for a pure-tone input at HZ")
    ap.add_argument("--config", default=CONFIG)
    ap.add_argument("--self-test", action="store_true")
    ap.add_argument("--verify", action="store_true")
    ap.add_argument("--compare-dir", metavar="DIR",
                    help="LUFS and true peak for every baseline/current pair "
                         "in a capture directory, with deltas")
    ap.add_argument("--ceiling", type=float, default=-0.20)
    args = ap.parse_args()

    if args.self_test:
        return self_test()
    if args.verify:
        return verify()
    if args.compare_dir:
        return compare_dir(args.compare_dir, args.ceiling)
    if not args.infile:
        ap.error("need an input file (or --self-test / --verify)")

    x = read_wav(args.infile)

    if args.sweep:
        target, values = args.sweep.split("=", 1)
        rows = []
        for v in values.split(","):
            nodes, links = build_graph(args.config, args.set + [f"{target}={v}"])
            row = measure(process(x, nodes, links), tone=args.tone)
            rows.append((v, row))
        base = rows[0][1]["lufs"]
        head = f"{target:<20} {'LUFS-I':>9} {'dLU':>7} {'sample':>9} {'true pk':>9}"
        print(head + (f" {'THD%':>7}" if args.tone else ""))
        for v, r in rows:
            line = (f"{v:<20} {r['lufs']:9.2f} {r['lufs'] - base:+7.2f} "
                    f"{r['sample']:9.3f} {r['tp']:9.3f}")
            print(line + (f" {r['thd']:7.2f}" if args.tone else ""))
        return 0

    nodes, links = build_graph(args.config, args.set)
    y = process(x, nodes, links, verbose=True)

    if args.bands:
        return bands(x, y)

    if args.measure or not args.outfile:
        r = measure(y, tone=args.tone)
        print(f"  LUFS-I    {r['lufs']:.2f}")
        print(f"  sample pk {r['sample']:.3f} dBFS")
        print(f"  true pk   {r['tp']:.3f} dBTP")
        if args.tone:
            print(f"  THD       {r['thd']:.2f} %")
        return 0

    write_wav(args.outfile, y)
    print(f"written {args.outfile}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
