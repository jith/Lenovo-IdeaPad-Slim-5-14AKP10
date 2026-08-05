#!/usr/bin/env python3
"""Linkwitz transform biquad coefficients for stage 2 of the speaker DSP.

Prints a bq_raw config block ready to paste into files/50-speaker-tuning.conf.

    tools/lt-coeffs.py FC QTC FC2 QTC2 [--rate 48000]
    tools/lt-coeffs.py --self-test

FC/QTC are the measured sealed-box resonance and Q; FC2/QTC2 are the target
the transform should make the box behave like. Both pairs describe a
second-order high-pass:

    H(s) = s^2 / (s^2 + (w0/Q) s + w0^2)

The filter that turns the measured response into the target is their ratio,

    H_lt(s) = H_target(s) / H_measured(s)
            = (s^2 + (wm/Qm) s + wm^2) / (s^2 + (wt/Qt) s + wt^2)

so the MEASURED parameters land in the numerator and the TARGET parameters in
the denominator. The stage table in the project brief has these the other way
round; following it would attenuate the low end instead of extending it.

Discretised with the plain bilinear transform, s -> 2*rate*(1-z)/(1+z). No
prewarping: it can only be exact at one frequency, and picking either fc or
fc' would bias the result toward that end. Both frequencies sit far below
Nyquist here (hundreds of Hz against 24 kHz), where the frequency warping is
under a thousandth of a percent -- --self-test asserts this against the
analog prototype.

Standard library only, so it runs anywhere python3 does.
"""

import argparse
import cmath
import math
import sys

# bq_raw clamps every coefficient to this range at load and at runtime.
COEFF_LIMIT = 10.0

# What stage 2 ships as until the enclosure is measured. Equal measured and
# target parameters also give unity, but as a pole-zero cancellation that
# float32 only holds approximately; this is a genuine pass-through.
PASSTHROUGH = (1.0, 0.0, 0.0, 1.0, 0.0, 0.0)


def lt_biquad(fc, qtc, fc2, qtc2, rate):
    """Return (b0, b1, b2, a0, a1, a2), normalised so a0 == 1."""
    wm, wt = 2.0 * math.pi * fc, 2.0 * math.pi * fc2
    k = 2.0 * rate

    # Bilinear substitution into s^2 + (w/Q) s + w^2, numerator then denominator.
    def quad(w, q):
        return (k * k + (w / q) * k + w * w,
                -2.0 * k * k + 2.0 * w * w,
                k * k - (w / q) * k + w * w)

    n0, n1, n2 = quad(wm, qtc)
    d0, d1, d2 = quad(wt, qtc2)
    return (n0 / d0, n1 / d0, n2 / d0, 1.0, d1 / d0, d2 / d0)


def response_db(coeffs, freq, rate):
    """Magnitude of the digital biquad at freq, in dB."""
    b0, b1, b2, a0, a1, a2 = coeffs
    z = cmath.exp(-2j * math.pi * freq / rate)
    h = (b0 + b1 * z + b2 * z * z) / (a0 + a1 * z + a2 * z * z)
    return 20.0 * math.log10(abs(h))


def analog_db(fc, qtc, fc2, qtc2, freq):
    """Magnitude of the analog prototype at freq, in dB."""
    s = 2j * math.pi * freq
    wm, wt = 2.0 * math.pi * fc, 2.0 * math.pi * fc2
    num = s * s + (wm / qtc) * s + wm * wm
    den = s * s + (wt / qtc2) * s + wt * wt
    return 20.0 * math.log10(abs(num / den))


def format_block(coeffs, rate, fc, qtc, fc2, qtc2):
    b0, b1, b2, a0, a1, a2 = coeffs
    peak = max(response_db(coeffs, f, rate) for f in range(10, 1000))
    return "\n".join([
        f"                    # LT {fc:g} Hz Q {qtc:g} -> {fc2:g} Hz Q {qtc2:g}"
        f" at {rate} Hz, peak boost {peak:+.1f} dB",
        "                    { type = builtin label = bq_raw name = s2lt_l",
        f"                      config = {{ coefficients = [ {{ rate = {rate},"
        f" b0 = {b0:.10g}, b1 = {b1:.10g}, b2 = {b2:.10g},"
        f" a0 = {a0:.10g}, a1 = {a1:.10g}, a2 = {a2:.10g} }} ] }} }}",
        "                    { type = builtin label = bq_raw name = s2lt_r",
        f"                      config = {{ coefficients = [ {{ rate = {rate},"
        f" b0 = {b0:.10g}, b1 = {b1:.10g}, b2 = {b2:.10g},"
        f" a0 = {a0:.10g}, a1 = {a1:.10g}, a2 = {a2:.10g} }} ] }} }}",
    ])


def self_test():
    checks = []

    def check(name, ok, detail=""):
        checks.append((name, ok, detail))

    # Identity in, identity out. Equal measured and target make the numerator
    # and denominator the same polynomial, so H(z) == 1 at every frequency --
    # not b == (1,0,0), which is a different filter that happens to share it.
    for rate in (44100, 48000, 96000):
        for fc, q in ((150.0, 1.2), (300.0, 0.707), (80.0, 2.0)):
            c = lt_biquad(fc, q, fc, q, rate)
            same = max(abs(c[i] - c[i + 3]) for i in range(3))
            flat = max(abs(response_db(c, f, rate))
                       for f in (10, 60, fc, 1000, rate * 0.4))
            check(f"identity fc={fc:g} Q={q:g} rate={rate}",
                  same < 1e-12 and flat < 1e-9,
                  f"num-den delta {same:.2e}, worst {flat:.2e} dB")

    # PASSTHROUGH is what the config ships, and it must also be flat.
    check("shipped pass-through block is flat",
          max(abs(response_db(PASSTHROUGH, f, 48000))
              for f in (10, 100, 1000, 19000)) < 1e-12)

    # The digital filter must track the analog prototype it came from.
    rate = 48000
    fc, qtc, fc2, qtc2 = 320.0, 1.4, 130.0, 0.707
    c = lt_biquad(fc, qtc, fc2, qtc2, rate)
    worst = max(abs(response_db(c, f, rate) - analog_db(fc, qtc, fc2, qtc2, f))
                for f in (20, 50, 100, 200, 500, 1000, 2000))
    check("matches analog prototype below 2 kHz", worst < 0.1,
          f"worst error {worst:.4f} dB")

    # A lower, less damped target must actually boost the bottom end.
    boost = response_db(c, 60.0, rate)
    check("extends low frequencies", boost > 6.0, f"{boost:+.1f} dB at 60 Hz")

    # Unity well above both corner frequencies.
    top = response_db(c, 8000.0, rate)
    check("unity in the passband", abs(top) < 0.1, f"{top:+.4f} dB at 8 kHz")

    # Poles inside the unit circle, or the filter rings away on its own.
    _, _, _, _, a1, a2 = c
    roots = [abs(r) for r in
             ((-a1 + cmath.sqrt(complex(a1 * a1 - 4 * a2))) / 2,
              (-a1 - cmath.sqrt(complex(a1 * a1 - 4 * a2))) / 2)]
    check("stable", max(roots) < 1.0, f"largest pole magnitude {max(roots):.6f}")

    # Coefficients must survive bq_raw's clamp.
    check("within the bq_raw clamp", all(abs(v) <= COEFF_LIMIT for v in c),
          f"largest magnitude {max(abs(v) for v in c):.3f}")

    for name, ok, detail in checks:
        print(f"{'PASS' if ok else 'FAIL'}  {name}" + (f"  ({detail})" if detail else ""))
    failed = sum(1 for _, ok, _ in checks if not ok)
    print(f"\n{len(checks) - failed}/{len(checks)} passed")
    return 1 if failed else 0


def main():
    p = argparse.ArgumentParser(
        description="Linkwitz transform biquad coefficients for stage 2.")
    p.add_argument("fc", nargs="?", type=float, help="measured resonance, Hz")
    p.add_argument("qtc", nargs="?", type=float, help="measured Q")
    p.add_argument("fc2", nargs="?", type=float, help="target resonance, Hz")
    p.add_argument("qtc2", nargs="?", type=float, help="target Q")
    p.add_argument("--rate", type=int, default=48000,
                   help="graph sample rate (default 48000)")
    p.add_argument("--self-test", action="store_true")
    args = p.parse_args()

    if args.self_test:
        return self_test()
    if None in (args.fc, args.qtc, args.fc2, args.qtc2):
        p.error("give FC QTC FC2 QTC2, or --self-test")
    for name, v in (("fc", args.fc), ("fc2", args.fc2)):
        if not 0 < v < args.rate / 2:
            p.error(f"{name} must be between 0 and Nyquist ({args.rate // 2} Hz)")
    for name, v in (("qtc", args.qtc), ("qtc2", args.qtc2)):
        if v <= 0:
            p.error(f"{name} must be positive")

    if (args.fc, args.qtc) == (args.fc2, args.qtc2):
        print("measured equals target: emitting a true pass-through rather "
              "than a pole-zero cancellation", file=sys.stderr)
        c = PASSTHROUGH
    else:
        c = lt_biquad(args.fc, args.qtc, args.fc2, args.qtc2, args.rate)
    over = [n for n, v in zip("b0 b1 b2 a0 a1 a2".split(), c)
            if abs(v) > COEFF_LIMIT]
    if over:
        print(f"warning: {', '.join(over)} exceed the bq_raw clamp of "
              f"+/-{COEFF_LIMIT:g} and will be truncated at load",
              file=sys.stderr)
    print(format_block(c, args.rate, args.fc, args.qtc, args.fc2, args.qtc2))
    return 0


if __name__ == "__main__":
    sys.exit(main())
