#!/usr/bin/env python3
"""SMPTE intermodulation distortion, the instrument stage 10c is sized on.

    tools/imd.py FILE.wav [FILE.wav ...]

60 Hz + 2650 Hz at 4:1, sidebands around the carrier to the 5th order,
reported as a percentage of the carrier. Single-tone THD cannot see this:
the mechanism is stage 12 pumping at the bass rate and amplitude-modulating
whatever else is present, so it needs two tones to appear at all.

Feed it a render of tests/material/imd60_2650_{6,3}.wav through the chain --
the source files themselves measure 0.000%.

The absolute scale depends on the sideband window and order count, so compare
only numbers taken with this script, never against a figure from elsewhere.
"""
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from dsp_offline import RATE, read_wav


def imd_percent(x, f_lo=60.0, f_hi=2650.0, orders=5, half_width=8.0):
    y = x[:, 0] if x.ndim > 1 else x
    y = y[int(0.3 * RATE):]                 # drop the playback start transient
    n = (len(y) // RATE) * RATE
    if n == 0:
        return float("nan")
    y = y[:n] * np.hanning(n)
    spec = np.fft.rfft(y)
    freq = np.fft.rfftfreq(n, 1 / RATE)

    def amp(target):
        m = (freq > target - half_width) & (freq < target + half_width)
        return np.sqrt(np.sum(np.abs(spec[m]) ** 2)) if m.any() else 0.0

    carrier = amp(f_hi)
    if carrier <= 0:
        return float("nan")
    side = np.sqrt(sum(amp(f_hi + k * f_lo) ** 2 + amp(f_hi - k * f_lo) ** 2
                       for k in range(1, orders + 1)))
    return 100.0 * side / carrier


if __name__ == "__main__":
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    for path in sys.argv[1:]:
        print(f"{imd_percent(read_wav(path)):8.3f} %  {path}")
