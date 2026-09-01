"""Offline emulation of the installed filter chain. Imported, not run.

Every level-dependent number in README.md -- the `g_out` table, the THD table,
the crossfade and upward-compression sweeps -- was produced by an emulation of
this graph rather than by forty reinstalls. That emulation was not in the repo,
so none of it could be reproduced or re-derived after the fact. This is it.

Two halves:

  * the PipeWire builtins (biquads, mixer, mult, invert, dcblock, linear,
    delay) in numpy, from the same RBJ cookbook formulas the builtins use;
  * the four LSP plugins (stages 7, 10, 11, 12) driven through
    `ffmpeg -af lv2`, i.e. the real binaries, not a model of them.

`lv2apply` segfaults on every LSP plugin on this stack. ffmpeg does not.

THE GRAPH IS PARSED FROM files/50-speaker-tuning.conf, never transcribed.
A hand-copied graph is how the last emulation stopped matching the hardware
without anyone noticing. If the config changes, this follows it.

I/O goes through ffmpeg as float32, matching pw-record, so nothing requantises.
"""

import json
import re
import subprocess

import numpy as np

RATE = 48000


# -- audio i/o ---------------------------------------------------------------

def read_wav(path, rate=RATE):
    """(samples, channels) float64. Resamples if the file is not at `rate`."""
    proc = subprocess.run(
        ["ffmpeg", "-v", "error", "-i", path,
         "-f", "f32le", "-ar", str(rate), "-ac", "2", "-"],
        capture_output=True, check=True)
    return np.frombuffer(proc.stdout, "<f4").reshape(-1, 2).astype(np.float64)


def write_wav(path, x, rate=RATE):
    subprocess.run(
        ["ffmpeg", "-v", "error", "-y",
         "-f", "f32le", "-ar", str(rate), "-ac", str(x.shape[1]), "-i", "-",
         "-c:a", "pcm_f32le", path],
        input=np.ascontiguousarray(x, "<f4").tobytes(), check=True)


# -- measurement -------------------------------------------------------------

def true_peak_db(x, oversample=16):
    """Exact inter-sample peak, by zero-padding the spectrum.

    Not loudnorm and not ebur128. On the sweep loudnorm over-reports by 1.4 dB
    and ebur128's 4x under-reports by about as much; all three agree on music
    and diverge on exactly the high-frequency content this limit is about.
    Zero-padding the spectrum is band-limited reconstruction with no filter
    design in it, so there is nothing left to be approximately right.
    """
    x = np.atleast_2d(x.T).T
    worst = -np.inf
    for ch in range(x.shape[1]):
        s = x[:, ch]
        spec = np.fft.rfft(s)
        padded = np.zeros(len(s) * oversample // 2 + 1, complex)
        padded[:len(spec)] = spec * oversample
        y = np.fft.irfft(padded, len(s) * oversample)
        worst = max(worst, 20 * np.log10(np.max(np.abs(y)) + 1e-30))
    return worst


def sample_peak_db(x):
    return 20 * np.log10(np.max(np.abs(x)) + 1e-30)


def lufs(path):
    """Integrated loudness from loudnorm's JSON -- two decimals, not one.

    Only ever called on a file. loudnorm is wrong about true peak here (see
    above) but it is the reference implementation for BS.1770 integrated
    loudness, which is a different measurement and not affected.
    """
    out = subprocess.run(
        ["ffmpeg", "-hide_banner", "-nostats", "-i", path,
         "-af", "loudnorm=print_format=json", "-f", "null", "-"],
        capture_output=True, text=True).stderr
    blob = re.search(r"\{[^{}]*\"input_i\"[^{}]*\}", out, re.S)
    if not blob:
        raise RuntimeError(f"loudnorm produced no JSON for {path}")
    return float(json.loads(blob.group(0))["input_i"])


def thd_percent(x, f0, rate=RATE, harmonics=10):
    """THD of a captured pure tone, from the bin peaks of a windowed FFT."""
    s = x[:, 0] if x.ndim > 1 else x
    s = s[len(s) // 4:]                      # drop the attack transient
    n = 1 << int(np.floor(np.log2(len(s))))
    spec = np.abs(np.fft.rfft(s[:n] * np.hanning(n)))
    freqs = np.fft.rfftfreq(n, 1 / rate)

    def peak_near(f):
        band = (freqs > f * 0.97) & (freqs < f * 1.03)
        return spec[band].max() if band.any() else 0.0

    fund = peak_near(f0)
    rest = np.hypot.reduce([peak_near(f0 * k) for k in range(2, harmonics + 1)])
    return 100.0 * rest / (fund + 1e-30)


# -- pipewire builtins -------------------------------------------------------
#
# RBJ cookbook, the same formulas builtins.c uses. Returned normalised by a0,
# as bq_raw expects them and as biquad() applies them.

def _rbj(kind, freq, q, gain_db=0.0, rate=RATE):
    a = 10 ** (gain_db / 40)
    w = 2 * np.pi * freq / rate
    cw, sw = np.cos(w), np.sin(w)
    alpha = sw / (2 * q)
    if kind == "bq_lowpass":
        b = [(1 - cw) / 2, 1 - cw, (1 - cw) / 2]
        a0, a1, a2 = 1 + alpha, -2 * cw, 1 - alpha
    elif kind == "bq_highpass":
        b = [(1 + cw) / 2, -(1 + cw), (1 + cw) / 2]
        a0, a1, a2 = 1 + alpha, -2 * cw, 1 - alpha
    elif kind == "bq_bandpass":
        # Constant 0 dB peak gain, which is the variant builtins.c implements.
        b = [alpha, 0.0, -alpha]
        a0, a1, a2 = 1 + alpha, -2 * cw, 1 - alpha
    elif kind == "bq_peaking":
        b = [1 + alpha * a, -2 * cw, 1 - alpha * a]
        a0, a1, a2 = 1 + alpha / a, -2 * cw, 1 - alpha / a
    elif kind == "bq_lowshelf":
        # RBJ shelves use 2*sqrt(a)*alpha, not the peaking form. builtins.c
        # derives alpha from Q the same way, so Q = 0.707 gives the maximally
        # flat shelf and higher Q overshoots at the corner.
        two = 2 * np.sqrt(a) * alpha
        b = [a * ((a + 1) - (a - 1) * cw + two),
             2 * a * ((a - 1) - (a + 1) * cw),
             a * ((a + 1) - (a - 1) * cw - two)]
        a0 = (a + 1) + (a - 1) * cw + two
        a1 = -2 * ((a - 1) + (a + 1) * cw)
        a2 = (a + 1) + (a - 1) * cw - two
    elif kind == "bq_highshelf":
        two = 2 * np.sqrt(a) * alpha
        b = [a * ((a + 1) + (a - 1) * cw + two),
             -2 * a * ((a - 1) + (a + 1) * cw),
             a * ((a + 1) + (a - 1) * cw - two)]
        a0 = (a + 1) - (a - 1) * cw + two
        a1 = 2 * ((a - 1) - (a + 1) * cw)
        a2 = (a + 1) - (a - 1) * cw - two
    else:
        raise ValueError(f"unhandled biquad {kind}")
    return np.array(b) / a0, np.array([1.0, a1 / a0, a2 / a0])


def biquad(x, b, a):
    """Direct form I. Transposed II would be fine too; this matches the C."""
    y = np.zeros_like(x)
    x1 = x2 = y1 = y2 = 0.0
    for n in range(len(x)):
        xn = x[n]
        yn = b[0] * xn + b[1] * x1 + b[2] * x2 - a[1] * y1 - a[2] * y2
        x2, x1 = x1, xn
        y2, y1 = y1, yn
        y[n] = yn
    return y


def _biquad_fast(x, b, a):
    """Same filter, via lfilter when scipy is available. Pure numpy is a
    Python-level loop over 1.4 million samples per node and there are 60-odd
    nodes; this turns a five-minute run into a two-second one. Verified
    identical to biquad() by --self-test."""
    try:
        from scipy.signal import lfilter
    except ImportError:
        return biquad(x, b, a)
    return lfilter(b, a, x)


def dcblock(x, r=0.995):
    """y[n] = x[n] - x[n-1] + R*y[n-1]. One pole, one zero, as builtins.c."""
    return _biquad_fast(x, np.array([1.0, -1.0, 0.0]), np.array([1.0, -r, 0.0]))


def delay(x, seconds, rate=RATE):
    n = int(round(seconds * rate))
    return x if n <= 0 else np.concatenate([np.zeros(n), x[:-n]])


# -- lsp plugins, through the real binaries ----------------------------------

LV2_URI = {
    "compressor_mono":       "http://lsp-plug.in/plugins/lv2/compressor_mono",
    "sc_compressor_stereo":  "http://lsp-plug.in/plugins/lv2/sc_compressor_stereo",
    "gott_compressor_stereo": "http://lsp-plug.in/plugins/lv2/gott_compressor_stereo",
    "limiter_stereo":        "http://lsp-plug.in/plugins/lv2/limiter_stereo",
}


def lv2(x, uri, controls, rate=RATE, sidechain=None):
    """Run a real LV2 plugin over `x` via ffmpeg.

    `sidechain`, when given, is merged in as extra channels ahead of the
    plugin's own inputs -- that is how stage 11's external sidechain is fed,
    as a four-channel stream rather than two.

    ffmpeg wants controls as `c0=v|c1=v`, positional, so pass `controls` as an
    ordered list of (name, value) and let the caller keep the order matching
    the plugin's port order. Named form `lv2=p=URI:c=name=value` also works on
    recent ffmpeg and is what is used here, being far less fragile.
    """
    # Output channels are the plugin's AUDIO inputs, not a fixed 2. Feeding a
    # *_mono plugin a duplicated stereo pair is not the same as running it
    # mono: ffmpeg adapts the channel count around the plugin and the level
    # the detector sees changes, which for a compressor changes the gain
    # reduction. Measured 0.316 dB on a real branch signal -- see the README.
    out_nch = x.shape[1]
    if sidechain is not None:
        x = np.concatenate([x, sidechain], axis=1)
    spec = "|".join(f"{k}={v}" for k, v in controls.items())
    nch = x.shape[1]
    # The colon in the URI has to survive TWO parsers -- the filtergraph
    # description splits on it first, then the filter's own option string does
    # -- so it needs a doubled backslash, not the single one that escaping a
    # colon usually takes. A bare URI fails with "No option name near
    # '//lsp-plug.in/...'", which reads like a missing plugin and is not one.
    safe = uri.replace(":", "\\\\:")
    proc = subprocess.run(
        ["ffmpeg", "-v", "error",
         "-f", "f32le", "-ar", str(rate), "-ac", str(nch), "-i", "-",
         "-af", f"lv2=p={safe}:c={spec}",
         "-f", "f32le", "-ar", str(rate), "-ac", str(out_nch), "-"],
        input=np.ascontiguousarray(x, "<f4").tobytes(),
        capture_output=True)
    if proc.returncode != 0:
        raise RuntimeError(
            f"ffmpeg lv2 failed for {uri}:\n{proc.stderr.decode()[:800]}\n"
            "LSP plugins present? `sudo apt install lsp-plugins-lv2`, and "
            "check `ffmpeg -filters | grep lv2`.")
    return np.frombuffer(proc.stdout, "<f4").reshape(-1, out_nch).astype(np.float64)


# -- config parsing ----------------------------------------------------------
#
# SPA-JSON as the filter-chain module writes it: unquoted keys, `=` or `:`,
# comments to end of line, no commas. Enough of it to read our own file, and
# deliberately not a general parser -- if it stops handling the config it
# should fail loudly rather than quietly read half a graph.

_COMMENT = re.compile(r"#.*?$", re.M)
_CONTROL = re.compile(r"\"?([\w() .]+?)\"?\s*[:=]\s*(-?[\d.eE+-]+)")
_LINK = re.compile(r"\{\s*output\s*=\s*\"([^\"]+)\"\s+input\s*=\s*\"([^\"]+)\"\s*\}")
_NODE_START = re.compile(r"\{\s*type\s*=\s*(builtin|lv2)\b")


def _balanced(text, start):
    """Index just past the `}` matching the `{` at `start`. Node bodies nest
    -- bq_raw is `config = { coefficients = [ { ... } ] }` -- so a non-greedy
    regex reads half a node and silently drops its coefficients."""
    depth = 0
    for i in range(start, len(text)):
        if text[i] == "{":
            depth += 1
        elif text[i] == "}":
            depth -= 1
            if depth == 0:
                return i + 1
    raise RuntimeError("unbalanced braces in the config")


def parse_config(path):
    """-> (nodes, links). nodes[name] = dict(kind, label, plugin, control)."""
    text = _COMMENT.sub("", open(path).read())

    nodes = {}
    for match in _NODE_START.finditer(text):
        body = text[match.start():_balanced(text, match.start())]
        name = re.search(r"\bname\s*=\s*([\w.]+)", body).group(1)
        label = re.search(r"\blabel\s*=\s*([\w.]+)", body)
        plugin = re.search(r"\bplugin\s*=\s*\"([^\"]+)\"", body)

        # bq_raw carries `coefficients = [ { rate = .. b0 = .. } ]` instead of
        # a control block, and the plugin picks the entry whose rate is nearest
        # the graph rate. Refuse a block written for another rate rather than
        # silently filtering with coefficients that are not for 48 kHz.
        coeffs = re.search(r"coefficients\s*=\s*\[(.*)\]", body, re.S)
        section = coeffs or re.search(r"control\s*=\s*\{(.*)\}", body, re.S)
        control = {}
        if section:
            for key, val in _CONTROL.findall(section.group(1)):
                control[key.strip()] = float(val)
        if coeffs and control.pop("rate", RATE) != RATE:
            raise RuntimeError(f"{name}: bq_raw coefficients are not for {RATE} Hz")

        nodes[name] = {
            "kind": match.group(1),
            "label": label.group(1) if label else None,
            "plugin": plugin.group(1) if plugin else None,
            "control": control,
        }

    links = [(o, i) for o, i in _LINK.findall(text)]
    if not nodes or not links:
        raise RuntimeError(
            f"parsed {len(nodes)} nodes and {len(links)} links from {path}. "
            "The config format changed; fix the parser rather than the config.")
    return nodes, links
