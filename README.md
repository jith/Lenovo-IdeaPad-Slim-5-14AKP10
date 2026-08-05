# Speaker DSP

A fourteen-stage PipeWire filter chain (stages 0–13) for the Lenovo IdeaPad
Slim 5 14AKP10 speakers, installed as **Speaker (Tuning)**, a virtual stereo
sink in front of the hardware sink.

It was built as a skeleton first — every stage a real node, unmeasured stages
set to bypass-equivalent values — so that coefficients could be dropped in one
stage at a time without ever debugging topology and tuning at once. Each stage
was then enabled and verified on hardware individually.

**All fourteen stages are live.** Every frequency in the chain comes from the
sweep measurement rather than a placeholder. The two settings that remain
matters of taste are stage 8's `Gain 3` (how much virtual bass) and stage 11's
threshold (how hard the excursion limiter bites); both are documented at their
nodes with the measurements behind their starting values.

## System and speakers

| Item | Details |
|---|---|
| Laptop | Lenovo IdeaPad Slim 5 14AKP10 (83HX), aluminum chassis |
| Audio hardware | Conexant/Senary SN6140 HDA codec with integrated stereo Class-D amplifier (`snd_hda_intel`, AMD Ryzen HDA controller `04:00.6`) |
| Speakers | Two unbranded OEM micro-speakers, 2 W each, sealed, front-firing |
| System | Ubuntu 26.04 LTS, Linux 7.0.0-29-generic |
| Audio stack | PipeWire 1.6.2, WirePlumber 0.5.13 |
| Physical sink | `alsa_output.pci-0000_04_00.6.HiFi__Speaker__sink` |
| Virtual sink | `effect_input.speaker-tuning` |
| Graph rate | 48000 Hz, pinned (see below) |

## Stages

Node names follow `s<stage><role>_<channel>`. Left and right are structurally
identical and mechanically mirrored; only stage 9 crosses channels.

| # | Stage | Nodes | Implementation | Parameters | State as installed | Source |
|---|---|---|---|---|---|---|
| 0 | Headroom trim | `s0trim_*` | builtin `linear` | −3.12 dB, returned by stage 10's `level_out` | **active**, `Mult = 0.6983` | US12342139B2 |
| 1 | Subsonic high-pass | `s1sub_*` | builtin `bq_highpass` | 20 Hz, Q 0.707 | **active** | US12445775B2 |
| 2 | Linkwitz transform | `s2lt_*` | builtin `bq_raw`, one per channel | **numerator = measured (fc, Qtc); denominator = target (fc′, Qtc′)** — 761 Hz Q 2.63 → 650 Hz Q 0.707 | **active** | US12342139B2 |
| 3 | HF path | `s3neg_*`, `s3hf_*`, `s3dly_*` | `invert` + `mixer` + `delay` | HF = input − LF | **active**, delay 0 — see below | CN115442709B |
| 4 | Subband split | `s4lp_*`, `s4bp1..3_*` | `bq_lowpass` + 3× `bq_bandpass` | **f1 = 350 Hz**; centres 122.5 / 175 / 252 Hz, Q 2.0 | **active** | CN115442709B |
| 5 | Harmonic generation | `s5pre1..3_*`, `s5h<band>x<order>_*` | `linear` pre-gain + `mult`, order n = x^n | pre-gain ×5, then orders 4/5/6, 3/4/5, 2/3/4 → 490–1008 Hz | **active** | CN115442709B, US5930373A |
| 6 | Harmonic weighting | `s6w<band>x<order>_*`, `s6sum<band>_*` | `bq_peaking` per order | gain = ln(n)·R(f) scaled to +12 dB max | **active**, +1.9 to +12 dB | CN115442709B |
| 7 | Gain K | `s7dc_*`, `s7k1..3_*`, `s7sum_*` | `dcblock` + LSP compressor per band | −20 dBFS, 20:1 — levels the n-th power law | **active** | CN115442709B, US10382857 |
| 8 | Sum | `s8sum_*` | builtin `mixer` | HF, LF and harmonics; `Gain 2`/`Gain 3` are the crossfade | **active**, `Gain 3 = 0.25` | CN115442709B |
| 9 | M/S widening | `s9*` | explicit M/S matrix | `s9swid` `Gain 1` = bass width, `Gain 2` = above 300 Hz | **bass mono**, `Gain 1 = 0` | US8660271B2 |
| 10 | Multiband compressor | `s10mbc` | Calf MultibandCompressor | 120/1000/6000 Hz, `mode = 0`, thresholds −20/−15/−9/−9 dB, `level_out` +4.11 dB | **active** | US12342139B2 |
| 11 | Excursion limiter | `s11hx_*`, `s11xcur` | `bq_lowpass` estimate → LSP sidechain comp | Hx = lowpass 761 Hz Q 2.63; threshold −3 dBFS on the estimate | **active** | US12445775B2, CN115442709B |
| 12 | Brickwall | `s12brick` | LSP Limiter | −0.3 dBFS, no makeup, ALR and boost off | **always on** | — |
| 13 | A/B trim | `s13trim_*` | builtin `linear` | static gain from the loudness match | **−0.07 dB**, `Mult = 0.991973` | ITU-R BS.1770 |

## Signal flow

Node-for-node as wired in `files/50-speaker-tuning.conf`. Every node is now
live (**●**); nothing in the graph is bypass-equivalent any more.

### Per channel — stages 0 to 8

Left shown; right is `_r` throughout and mechanically identical.

```
in_L
 │
 ● s0trim_l    linear        Mult 0.6983             -3.12 dB headroom
 ● s1sub_l     bq_highpass   20 Hz Q 0.707           subsonic
 ● s2lt_l      bq_raw        761 Q2.63 -> 650 Q0.707 Linkwitz
 │
 ├──────────────────────────────────────────────┐  dry, for the subtraction
 │                                              │
 ● s4lp_l      bq_lowpass  f1 = 350 Hz          │      LF = LP(f1)
 │                                              │
 ├─ ● s3neg_l  invert ────────────────────────┐ │
 │                                            │ │
 │                          ● s3hf_l  mixer ──┴─┘      HF = s2lt - LF
 │                               │  Gain 1,2 = 1
 │                          ● s3dly_l  delay  0 s      see note below
 │                               │
 │                               └────────────────────────────────┐
 ├────────────────────────────────── LF straight through ─────────┤
 │                                                                │
 ├─ ● s4bp1_l  bandpass 122.5 Hz Q2 ─┐                            │
 ├─ ● s4bp2_l  bandpass 175.0 Hz Q2 ─┤ 0.35 / 0.50 / 0.72 x f1    │
 └─ ● s4bp3_l  bandpass 252.0 Hz Q2 ─┘                            │
                    │                                             │
       ● s5preN_l   linear      Mult 5   <- without this the rest  │
                    │                       of the branch is dead  │
       ● s5hNxM_l   mult        x^n, orders 4/5/6, 3/4/5, 2/3/4    │
       ● s6wNxM_l   bq_peaking  at n x centre, +1.9 to +12 dB      │
       ● s6sumN_l   mixer       sums the 3 orders of a band        │
       ● s7dc_l     dcblock     one port per band, kills x^even DC │
       ● s7kN_l     compressor  -20 dBFS 20:1, levels the n-th     │
                    │           power law                          │
       ● s7sum_l    mixer       sums the 3 bands                   │
                    │                                              │
                    └──────────────── harmonics ───────────────────┤
                                                                   │
                                      ● s8sum_l  mixer ────────────┘
                                         Gain 1 = 1     HF
                                         Gain 2 = 1     LF     <- the crossfade:
                                         Gain 3 = 0.25  harmonics  2 against 3
```

The generated harmonics land between 490 and 1008 Hz, chosen so the speaker
can actually reproduce them — see the `f1` note in the config header.

### Shared — stages 9 to 13

Stage 9 is the only place the channels meet. Every mixer gain is positive
because the builtin `mixer` clamps to [0, 10], so each subtraction goes
through an `invert`.

```
  s8sum_l ─┬──────────────────────→ ● s9mid    mixer 0.5 / 0.5   M = (L+R)/2
  s8sum_r ─┼──────────────────────↗
           │
  s8sum_l ─┼──────────────────────→ ● s9side   mixer 0.5 / 0.5   S = (L-R)/2
  s8sum_r ─┴─ ● s9negr  invert ───↗
                                         │
                     ┌───────────────────┴───────────────────┐
              ● s9slp  bq_lowpass 300 Hz          ● s9shp  bq_highpass 300 Hz
                     │                                       │
                     └────────→ ● s9swid  mixer ←────────────┘
                                  Gain 1 = 0  below 300 Hz   <- BASS MONO
                                  Gain 2 = 1  above 300 Hz   <- widen here
                                        │  = S'
                        ┌───────────────┴───────────────┐
                        │                        ● s9negs  invert
                        │                               │
              ● s9outl  mixer  M + S'         ● s9outr  mixer  M - S'
```

Stages 10 to 13 are plain stereo in series.

```
  s9outl ─┐
  s9outr ─┴→ ● s10mbc    Calf MultibandCompressor
             │           120 / 1000 / 6000 Hz, mode 0
             │           thresholds -20 / -15 / -9 / -9 dB
             │           bypass0..3 = 0   (they default to 1 -- see below)
             │           level_out +4.11 dB, returning stage 0's trim
             │
             ├─ ● s11hx_l/r  bq_lowpass 761 Hz Q 2.63  displacement estimate
             │                                 ↓
             └→ ● s11xcur   LSP sc_compressor_stereo
                │                              ↑ external sidechain, peak,
                │                                max of the two channels
                │                                threshold -3 dBFS, 6:1
                │
                ● s12brick  LSP limiter_stereo   -0.3 dBFS, never bypassed
                │
                ● s13trim_l/r  linear  Mult 0.991973   -0.07 dB A/B trim
                │
                └→ alsa_output.pci-0000_04_00.6.HiFi__Speaker__sink
```

Two structural notes that are easy to misread from the diagram.

**The two splits use different filters on purpose.** The f1 split at stage 3/4
is complementary — `HF = input − LP(f1)` — so the pair reconstructs the input
exactly while the harmonic branch is muted. Stage 9's side split uses a real
`bq_lowpass`/`bq_highpass` pair instead, because the complementary form makes a
poor high-pass once you turn one side down: 6 dB/octave and a +1.8 dB bump at
the corner. That difference is measured, not stylistic — see the stage 9 notes.

**Stage 3's delay is 0 on purpose.** It exists to align the harmonic branch
with the HF path, but the three subbands have group delays of 5.2, 3.6 and
2.5 ms, so no single value matches all of them. Adding ~4 ms would also push
the total path latency past the 30 ms budget, for an alignment that is
inaudible on bass envelopes. Left at 0 and documented rather than set to a
number that only looks principled.

**The pre-gain in stage 5 is load-bearing, not a trim.** `x^n` collapses a
quiet signal: a 122 Hz band of pink noise peaks at −19.5 dBFS, so `x⁴` lands
at −77.9 dBFS and `x⁶` at −116.8. The stage 7 compressor meant to level that
has a threshold floor of −60 dBFS and would never open. `Mult = 5` lifts the
band into range first. Remove it and the whole branch goes silent on anything
but a full-scale tone.

### Where this departs from the stage table it was specified from

Five places. Each is a decision, not an accident.

1. **Stage 0 is at unity, and the headroom it should take is deferred.** It
   exists to make room for the Linkwitz transform's boost, with stage 10's
   makeup returning it. Stage 2 needs −3.12 dB on paper — sized on the 100 Hz
   square, not the filter's frequency-domain peak of +2.73 dB, because a
   transient sees the filter's phase as well as its magnitude.

   But stage 10 is bypassed, so taking that headroom is 3.1 dB of pure loss
   with nothing to give it back. Measured on hardware rather than assumed:
   at unity, dense pink at −1 dBFS peak comes out at −2.35 dBFS and never
   touches the limiter, and the 100 Hz square lands at exactly −0.30 dBFS —
   the stage 12 ceiling — while still keeping the full +3.15 dB of RMS. The
   brickwall handles the one case that needs handling, which is what it is
   for. Set stage 0 back to `0.6983` when stage 10's makeup goes live.

2. **The f1 split is complementary, not two independent filters.** `HF = input
   − LP(f1)` via `invert` + `mixer`, rather than an independent `bq_highpass`.
   A Butterworth low-pass and high-pass pair does not sum to unity, so an
   independent pair would put a crossover-shaped error into the skeleton and
   there would be no null test to pass. Complementary subtraction sums to
   exactly the input. A non-zero stage 3 delay breaks that, which is expected —
   by then the LF branch is live and exact complementarity is no longer the
   goal.

3. **The Linkwitz transform has the measured parameters in the numerator.** The
   stage table this was specified from said numerator = target, denominator =
   measured. That is backwards. The filter that makes a measured response
   behave like a target one is `H_target / H_measured`; both are second-order
   high-passes, so the `s²` terms cancel and what survives is

   ```
   H(s) = (s² + (wm/Qm)s + wm²)     <- MEASURED (fc,  Qtc)
          -------------------------
          (s² + (wt/Qt)s + wt²)     <- TARGET   (fc', Qtc')
   ```

   Putting the target on top inverts the correction and cuts the low end
   instead of extending it. The stage table above, the comment in
   `files/50-speaker-tuning.conf` and `tools/lt-coeffs.py` all carry the
   corrected form; the tool's `--self-test` asserts that the result actually
   boosts (`+15.2 dB at 60 Hz` for its test case), which is the check that
   would catch the inversion.

4. **Stage 2 is one biquad per channel, not two in series.** A Linkwitz
   transform is a single second-order section. Splitting it into separate
   numerator and denominator biquads is not implementable: the denominator
   alone is `1/H_measured`, a double integrator with poles at DC.

5. **Stage 7 is one compressor per subband, not one per harmonic order.**
   CN115442709B derives `K = min` over orders of `(threshold_n / level_n)`.
   The LSP LV2 ports expose no per-order gain signal to take a minimum over,
   and PipeWire's builtins offer `max` but no `min`. So the minimum is applied
   as the choice of each band's threshold rather than as a runtime reduction.
   If you want the per-order runtime version, it needs three sidechain
   compressors per band with the band sum as input and each order as sidechain
   — 18 LV2 instances instead of 6, giving a product of gains that only
   approximates the minimum.

## Install

```sh
cd ~/speaker-dsp
sudo sh install.sh
systemctl --user restart pipewire pipewire-pulse wireplumber
speaker-dsp on
```

Verify:

```sh
pactl list sinks short | grep speaker-tuning
journalctl --user -u pipewire -b --no-pager | tail -30
```

`effect_input.speaker-tuning` must appear. If it does not, the graph failed to
load and the journal has the reason. Remove with `sudo sh install.sh uninstall`.

## Use

```sh
speaker-dsp on       # Speaker (Tuning), the 13-stage chain
speaker-dsp off      # raw hardware speaker
speaker-dsp ab       # toggle, carrying the level across
speaker-dsp status
```

`ab` is the one to use for listening comparisons: it copies the current level
onto the sink it switches to and applies the raw-path trim, so switching does
not change loudness. Set the trim in dB with `SPEAKER_DSP_RAW_TRIM_DB` from
what `tools/loudness-match.sh` reports, or edit the default in
`files/speaker-dsp`. It is 0.0 here, because the two paths already match.

### GNOME's slider is inert in raw mode

By design, GNOME shows one output entry — `hide-speaker-tuning.lua` hides the
raw sink from `org.gnome.VolumeControl` so there is no duplicate speaker in
the list. Confirmed by asking as that client:

```
plain pactl                          -> effect_input.speaker-tuning, alsa_output...Speaker__sink
identifying as org.gnome.VolumeControl -> effect_input.speaker-tuning only
```

The consequence is that `speaker-dsp off` switches the default to a sink GNOME
cannot see. Audio really does move — a playing stream follows — but GNOME
keeps showing "Speaker (Tuning)" as selected and its slider now drives a sink
that is no longer in the path, so the slider does nothing until you switch
back. `speaker-dsp` prints a note whenever raw is selected. Set the level in
raw mode with `pactl set-sink-volume <raw-sink> <n>%`, or just switch back.

Note also that `speaker-dsp` does **not** pin the virtual sink to unity. With
one entry in GNOME that sink is your volume control, and forcing it to 100%
would jump the level to full every time you switched on.

## Sample rate is pinned

Stages 2 and 11 use `bq_raw`, which takes raw biquad coefficients. Those are
rate-specific — unlike `bq_lowpass` and friends, which recompute from a `Freq`
control. The rate is pinned to 48000 in both `capture.props` and
`playback.props`, and every coefficient block is tagged `rate = 48000`.

`bq_raw` selects the coefficient block whose rate is closest to the graph rate.
If the graph ever runs at another rate, a stale 48000 block is used silently
and stage 2 is quietly wrong. Regenerate with `tools/lt-coeffs.py --rate` and
add a second block rather than replacing the first.

`bq_raw` also clamps every coefficient to ±10 at load and at runtime.
`tools/lt-coeffs.py` warns when a value would be truncated.

## Headroom budget

Kept in a comment block at the top of `files/50-speaker-tuning.conf`. Keep it
balanced when enabling a stage. As installed the net is 0.0 dB. The float32
graph will not clip internally; the hand-off to ALSA will, which is what stage
12 prevents.

## Latency

| Contributor | Added |
|---|---|
| All builtin nodes (biquads, mixers, `mult`, `invert`, `dcblock`, `linear`) | 0 |
| Stage 3 `delay`, at `Delay (s) = 0` | 0 |
| Calf MultibandCompressor (`lv2info`: has latency, no) | 0 |
| Stage 7 and 11 LSP compressors (`sla = 0`) | 0 |
| Stage 12 LSP limiter lookahead (`lk = 5`) | **5 ms** |
| **Total added by the 13 stages** | **≈5 ms** |
| Virtual sink quantum, 1024 @ 48 kHz (already present in the pass-through) | 21.3 ms |
| **Virtual path total, against playing straight to hardware** | **≈26 ms** |

Under the 30 ms budget, but not by much, and the quantum rather than the DSP is
what dominates. If you need headroom there, lower `clock.quantum` rather than
touching the chain. Raising the stage 3 delay above about 4 ms would put the
total over budget.

## Building the chain up, one stage at a time

Never stack two unverified stages.

1. Edit one stage in `files/50-speaker-tuning.conf`. Edit both channels.
2. `sudo sh install.sh`
3. `systemctl --user restart pipewire pipewire-pulse wireplumber`
4. `pactl list sinks short | grep speaker-tuning` — gone means the graph failed
   to load; the journal says why.
5. `journalctl --user -u pipewire -b --no-pager | tail -30` — no warnings.
6. `tools/null-test.sh compare tests/captures` against the stored baseline.
7. Commit, naming the stage and its source ID.

**Stop and report if any test produces audible buzzing, rattling or scraping.**
These are 2 W sealed micro-speakers and boosted sub-bass damages them
mechanically. Stage 12 stays on for every test without exception.

### Calf's per-band bypass defaults to ON

`bypass0`, `bypass1`, `bypass2` and `bypass3` on Calf's MultibandCompressor all
default to **1.0**, while the master `bypass` defaults to 0.0. Clearing only
the master leaves every band inactive, and the plugin loads, reports no error,
and does nothing at all — measured at 0.06 dB of gain reduction on material
that should have been flattened. With them set to 0 the same settings gave
−7.71 dB on the LF band.

If a compressor stage appears to have no effect, check the per-band bypasses
before touching thresholds. `solo0..3` are pinned to 0 in the config for the
same reason.

### Tuning live, without reinstalling

Every graph control can be set on the running chain, which is far faster than
edit → install → restart for finding a value. Find the sink's node id with
`pactl list sinks short`, then:

```sh
pw-cli set-param 40 Props '{ params = [ "s13trim_l:Mult" 0.25 "s13trim_r:Mult" 0.25 ] }'
```

Verified: that command measured −34.10 dBFS at the monitor against −22.12 with
`Mult = 1.0`, a 11.98 dB drop where 20·log10(0.25) is 12.04. It really takes
effect.

Three caveats, the last one important.

The values do **not** read back — `pw-dump` shows no graph controls in Props,
so this is write-only and the config file remains the only record of what a
stage is set to. Nothing is persisted either: a PipeWire restart reverts
everything to the file. Find the value live, then write it into
`files/50-speaker-tuning.conf` and reinstall.

**Never set `bq_raw` coefficients this way.** Controls are applied one at a
time, so a partially-applied set is a filter nobody designed — and it can
easily be unstable. Setting `a1 = -1.9` while `a2` was still 0 put the poles
outside the unit circle, the biquad diverged to NaN within milliseconds, and
the chain output silence. Resetting the coefficients does *not* fix it,
because the NaN is in the filter's delay line, not its coefficients. It
recovers only when the sink suspends and the graph is re-initialised, which
takes a few seconds of idle. Stage 2 and stage 11 go through
`install.sh` and a restart. Scalar controls — gains, `Mult`, thresholds,
`enabled` — are safe live.

This is also the quickest way to confirm the A/B switch works at all, since
the skeleton is deliberately inaudible — set `s13trim_*:Mult` to `0.25`, and
`speaker-dsp ab` becomes obvious.

### Enabling individual stages

| Stage | To enable |
|---|---|
| 0 | `s0trim_*` `Mult` → `0.5012` |
| 2 | replace both `s2lt_*` coefficient blocks with `tools/lt-coeffs.py` output |
| 3 delay | `s3dly_*` `Delay (s)` → LF branch group delay, in seconds |
| 4 | `s4lp_*` `Freq` → f1, and `s4bp<n>_*` `Freq` → 0.25/0.45/0.75 × f1 |
| 5–7 | `s8sum_*` `Gain 3` up from 0, `Gain 2` down from 1 — this is the crossfade |
| 6 | `s6w<band>x<order>_*` `Gain`, from `ln(n) · R(f)` |
| 7 | `s7k<band>_*` `enabled` → 1, then set `al` (threshold) per band |
| 9 | `s9swid` `Gain 1` → 0 for mono bass (done); `Gain 2` above 1 to widen |
| 10 | `s10mbc` `bypass` → 0 **and `bypass0..3` → 0**, lowest `threshold0`, `level_out` recovers stage 0 (done) |
| 11 | `s11xcur` `enabled` → 1, `s11hx_*` coefficients from the Hx estimate |
| 13 | `s13trim_*` `Mult` from `tools/loudness-match.sh` |

Stage 9 and stages 5–7 interact. Harmonic generation tends to collapse the
stereo image, which stage 9 then fights. If widening sounds wrong once the bass
branch is live, that is the cause and not a stage 9 misconfiguration — the fix
is to preserve interaural level differences during harmonic generation
(US11102577B2), not to widen harder.

## Measuring fc and Qtc

```sh
tools/measure-speaker.sh tests/captures/sweep-mic.wav
tools/sweep-response.py tests/captures/sweep-mic.wav
```

`sweep-response.py` locates the sweep in the capture, prints a 1/6-octave
response curve relative to the 1.3–2.4 kHz mean, and estimates `fc` and `Qtc`.

### Measured on this machine

Stage 9 confirmed on the installed chain — side energy removed, by band,
against the same measurement on the source material:

| band | measured | predicted offline |
|---|---|---|
| 40–150 Hz | **−20.1 dB** | −20.1 dB |
| 150–300 Hz | **−6.7 dB** | −6.6 dB |
| 300–600 Hz | **−1.2 dB** | −1.1 dB |
| 600–1200 Hz | −0.1 dB | −0.1 dB |
| 1.2–4 kHz | −0.0 dB | −0.0 dB |

Every band within 0.1 dB of the model. Note this is an *electrical* result,
taken from the sink monitor: it says the filter does what it should, not that
you can hear it. Below 300 Hz these drivers are more than 15 dB down, so bass
mono here buys excursion headroom rather than an audible change.

```
  resonance      fc = 761 Hz, +8.4 dB above passband
  -3 dB points   604 .. 854 Hz (bandwidth 250 Hz)
  Qtc            3.04 from bandwidth, 2.63 from peak height
  output is 10 dB down by 427 Hz
  output is 20 dB down by 381 Hz
```

A useful consistency check: a second-order resonance of Q 2.63 peaks
20·log10(2.63) = 8.40 dB above its passband, and 8.4 dB is what was measured.
The driver really does behave like a second-order high-pass at this fc and Q,
which is what makes a Linkwitz transform the right tool.

**These numbers superseded an earlier, wrong set** (734 Hz, Q 4.14–5.10,
+12.3 dB). A log sweep spends less time per hertz as it climbs, so a
fixed-window FFT reads a *flat* system as a curve sloping about 1 dB/octave.
`sweep-response.py` did not divide that out, and the tilt inflated the peak by
~4 dB and Q by ~1.5. It now normalises against the stimulus by default, and
reads the source sweep back as flat to 0.0 dB. If you ever see it warn that no
`--reference` was given, the numbers are not trustworthy.

Two things follow, and both matter more than the numbers themselves.

**These speakers produce nothing usable below about 250 Hz.** Output is 20 dB
down by 251 Hz and buried in the room noise floor below ~240 Hz — the sweep
simply does not come back on the microphone there. That is the justification
for the whole virtual-bass branch, and it also means the placeholder
frequencies in stage 4 are in the wrong place: `f1 = 200 Hz` with subband
centres at 50 / 90 / 150 Hz feeds the harmonic generator from a region the
speaker cannot reproduce, and stage 6 then places the harmonics at 200–600 Hz,
much of which is still in the dead zone. Both need rescaling upward once you
decide the target, and the harmonics want to land at or above the resonance
where there is actually output.

**A Linkwitz transform from 734 Hz is not a small ask.** Extending to even
400 Hz means roughly +20 dB of boost into a 2 W sealed driver at the frequency
where it is already least able to move air. Work up to it, keep stage 12 on,
and stop at the first sign of mechanical noise.

The two `Qtc` figures disagree (5.10 vs 4.14) because each assumes an ideal
second-order resonance and this is not one. Take the range. And note that a Q
of 4–5 is sharp for a driver in a sealed box — a good part of that peak is
plausibly chassis cavity resonance, which the caveat below is precisely about.

Feed the result, plus the target you want, to:

```sh
tools/lt-coeffs.py FC QTC FC2 QTC2 [--rate 48000]
tools/lt-coeffs.py --self-test
```

It prints both `s2lt_l` and `s2lt_r` blocks ready to paste, warns if any
coefficient would hit the ±10 clamp, and reports the peak boost — which is the
number stage 0 has to make room for.

### The microphone caveat

**Mic1 is broken on this machine.** `alsa_input.pci-0000_04_00.6.HiFi__Mic1__source`
returns full-scale samples with about a dozen distinct values whatever the
room is doing, through both `pw-record` and `parecord` — so it is the source,
not the recorder. **Mic2 is the working internal microphone**; a quiet room
reads around −60 dBFS through it, and it is what `tools/measure-speaker.sh`
uses by default. There is also an `acppdmmach` card (the AMD ACP digital mic
array) that PipeWire is not currently exposing as a source.

The tools call `assert_sane_capture` on every capture and refuse to report
numbers from one that is railed or silent, because a railed capture produces a
perfectly ordinary-looking WAV and every measurement taken from it is
meaningless.

**Even on Mic2, the internal microphone is not a measurement microphone.** It
is uncalibrated and sits inside the chassis, so it hears case resonance and its
own arbitrary response along with the speaker.

Valid uses: locating the resonance peak, estimating its Q, and relative
before/after comparison with the mic and laptop in the same position at the
same level.

Not valid: any absolute claim about frequency response. A dip at 4 kHz in that
capture is as likely to be the microphone or the chassis as the speaker. Do not
build a correction curve from it.

## Loudness matching

Do this before any subjective comparison. An unmatched A/B is worthless — the
louder path wins regardless of whether it is better.

```sh
tools/loudness-match.sh tests/material/pink.wav
```

It plays the same file through the tuned and raw paths, capturing both from the
monitor of the *physical* sink — the same node either way, post-DSP in tuned
mode and unprocessed in raw mode, so the comparison is exact. It measures
integrated loudness to ITU-R BS.1770 / EBU R128 and prints the trim.

**Capturing a sink monitor needs the `stream.capture.sink` property**, not the
`.monitor` node name:

```sh
pw-record -P 'stream.capture.sink=true' --target=<sink-name> out.wav   # correct
pw-record --target=<sink-name>.monitor out.wav                         # garbage
```

`<sink>.monitor` is the name `pactl` prints, but it is not a native PipeWire
node. The target silently fails to resolve and `pw-record` writes full-scale
noise instead of erroring, which is exactly the kind of failure that produces
confident, wrong numbers. `parecord --device=<sink>.monitor` also works if you
prefer the PulseAudio tools.

**Measured on this machine**, 60 s of pink noise:

| chain state | tuned | raw | delta |
|---|---|---|---|
| skeleton (all bypass-equivalent) | −17.45 | −17.45 | **+0.00 LU** |
| stage 2 live | −17.58 | −17.45 | **−0.13 LU** |
| stages 2 and 9 live | −18.20 | −17.45 | **−0.75 LU** |

Raw is the louder path, so raw is the one attenuated — `speaker-dsp` defaults
to `SPEAKER_DSP_RAW_TRIM_DB=-0.75`. The 0.13 is the Linkwitz transform's cut
around the 761 Hz resonance, where K-weighting is most sensitive; the further
0.62 is bass mono removing side energy below 300 Hz.

That 0.62 is a **worst case**: pink noise here has fully decorrelated
channels, so half its low-frequency energy is in the side signal. Most records
are cut with near-mono bass. Repeating the measurement on material whose bass
is already mono gives −0.52 LU instead. The 0.23 dB between them is well below
audibility, but the figure that matters is the one measured on what you listen
to — drop a few tracks into `tests/material/` and re-run the match against
them.

Worth understanding why that is 0.00 and not the 1.18 dB that stage 1 takes
out of the unweighted RMS: BS.1770 is K-weighted, and K-weighting rolls off
hard below about 100 Hz. A 20 Hz high-pass is nearly invisible to it. The two
figures are both correct and measure different things — use RMS to check what
a stage did to the signal, and LUFS to check what it did to perceived
loudness.

Two rules the tool follows and you should too:

- **The louder path is attenuated at its own output. Never boost the quieter
  one.** Tuned louder → stage 13. Raw louder → the hardware sink's volume.
- **Never trim the chain input to match loudness.** Stages 7, 10 and 11 are
  level-dependent, so changing what they see changes their behaviour and you
  are no longer comparing the same processing.

While it runs you will hear the material twice. Set a comfortable level with
the **hardware** sink's volume: it sits after the monitor tap and does not
affect the measurement. Verified — the same 3 s of pink noise captured at
100% / 40% / 15% hardware volume reads −21.378 / −21.444 / −21.444 dBFS, so a
16 dB change in volume moves the measurement by 0.07 dB, which is
capture-start jitter rather than level.

The virtual sink's volume is a different matter: it is software, it sits
*before* the filter graph, and changing it does change what the
level-dependent stages see. Leave it at 100%.

## Null test

The measurement behind "nothing else changed".

```sh
tools/make-test-material.sh                       # once
tools/null-test.sh baseline tests/captures        # BEFORE changing the graph
# ... edit a stage, reinstall, restart ...
tools/null-test.sh compare tests/captures
```

The stored baseline in `tests/captures/` was taken through the skeleton as
installed, so it already contains stage 1. That is the right reference for
everything that follows: from here on, any residual is the stage you just
edited. It is *not* a capture of the original pass-through — that would have
had to be taken before the graph was installed, and the window for it has
passed. What the skeleton is bypass-equivalent to the pass-through rests on
instead is the level check below, which is a stronger result anyway.

`compare` sample-aligns against the baseline by cross-correlation, inverts,
sums, and reports the residual peak split at 30 Hz. A constant latency
difference — the limiter's lookahead, for instance — is removed by the
alignment. A gain difference is not, and is meant not to be. Every item is
measured even if an earlier one fails.

### Is the skeleton really bypass-equivalent?

Measured, not argued. Take the source material, apply stage 1 alone offline,
correct for the silence either side of the capture, and compare against what
the installed chain actually produced:

| Material | Source | After 20 Hz HP | + silence pad | Predicted | **Captured** | Delta |
|---|---|---|---|---|---|---|
| pink | −20.00 | −21.18 | −0.14 | −21.32 | **−21.31** | **+0.01 dB** |
| sweep | −9.01 | −9.12 | −0.29 | −9.41 | **−9.41** | **−0.00 dB** |

All figures dBFS RMS. The chain reproduces a stage-1-only prediction to within
0.01 dB, which is what "every other stage is bypass-equivalent" means in
numbers. That also satisfies the loudness criterion with room to spare.

### Repeatability

**Measured on this machine**, skeleton against skeleton with the graph
unchanged:

```
compare pink    residual -inf dBFS   PASS   (62.0 s, aligned -1024 samples)
compare sweep   residual -inf dBFS   PASS   (32.0 s, aligned +1024 samples)
```

Exactly zero — the two captures are bit-identical. Nothing in the path
resamples, the graph is deterministic, and the limiter never engages at these
levels, so the method has no noise floor at all here. A −60 dBFS threshold has
enormous margin; anything that shows up later is real.

**`--pre-stage1` compensates a baseline that predates stage 1.** By default
neither side is touched, which is what you want when the baseline came through
this same graph. Pass it only when the baseline is a genuine pass-through
capture from before stage 1 existed: stage 1's magnitude is flat to within
0.01 dB above 50 Hz but its *phase* is not, and at 1 kHz a 20 Hz high-pass
still rotates the signal enough that the raw difference reaches only −31 dBFS,
with pink noise landing near −25 dBFS. That is phase, not error, and
subtraction cannot tell them apart — so against a pre-stage-1 baseline a
−60 dBFS null is unreachable however correct the chain is. Passing it when the
baseline *already* contains stage 1 high-passes that side twice and reports a
fictitious ~−17 dBFS residual.

`tools/null_residual.py` was checked against an exact stage-1 match (−81.9 dBFS
above 30 Hz, pass), a 0.2 dB gain error (caught), and a 5 ms delay (removed by
alignment, pass).

## Test material

```sh
tools/make-test-material.sh [dir]     # default tests/material/
```

Generates pink noise (60 s, −20 dBFS RMS, independently seeded channels so the
mid/side stage sees a real side signal), a 30 s log sweep from 20 Hz to 20 kHz,
and a 5 s 100 Hz square wave for harmonic-branch sanity. Add three music tracks
with known low-frequency content alongside them.

`tests/material/` and `tests/captures/` are gitignored — do not commit audio.

sox synthesises the signals; ffmpeg measures them, so the RMS reported is the
same measurement the rest of the tooling uses rather than sox's slightly
different definition of the same word. The exact commands:

```sh
# pink noise -- two pinknoise specs, not one: with a single spec sox writes
# the same noise to both channels, the side signal is exactly zero and stage 9
# goes untested. Level is set by a second pass, below.
sox -n -r 48000 -c 2 -b 32 -e float pink.tmp.wav synth 60 pinknoise pinknoise gain -6
sox pink.tmp.wav pink.wav gain <correction>

# log sweep -- `/` is sox's smooth exponential sweep, a fixed number of
# semitones per second. `:` would give a linear one.
sox -n -r 48000 -c 2 -b 32 -e float sweep.wav synth 30 sine 20/20000 gain -6

# 100 Hz square
sox -n -r 48000 -c 2 -b 32 -e float square100.wav synth 5 square 100 gain -6
```

`<correction>` is measured, not assumed: the script reads the RMS back with
ffmpeg and applies the difference from −20 dBFS. Note that `gain -20` would
attenuate *by* 20 dB, which is not the same thing as landing *at* −20 dBFS RMS.

As generated and checked:

```
  pink.wav       RMS -20.000 dBFS     (L−R RMS 0.142, so stage 9 has a side signal)
  sweep.wav      RMS  -9.011 dBFS     (log sweep verified: 117 / 645 / 3627 Hz
                                       at t = 7.5 / 15 / 22.5 s)
  square100.wav  RMS  -6.000 dBFS
```

sox synthesises at 0 dBFS and its pink noise overshoots on three to five
samples in 5.76 million, so `synth` warns about clipping however the gain is
arranged. That does not matter here and should not be "fixed" by lowering the
level: the file is a stimulus played identically down both paths, so whatever
is clipped in it is clipped the same way in both captures and cancels exactly
in the null subtraction. Lowering the level would only move where the
level-dependent stages sit.

## Acceptance status

Measured on the installed graph, not asserted. The null and bypass rows were
taken while the whole chain was still bypass-equivalent; they are the
acceptance evidence for the skeleton, not a claim about the chain as it stands
now with stage 2 live.

| Criterion | Result |
|---|---|
| `effect_input.speaker-tuning` in `pactl list sinks short` | pass — present, 48000 Hz |
| No warnings or errors in the PipeWire journal on load | pass — zero filter-chain lines since the restart |
| Null test residual below −60 dBFS above 30 Hz | pass — **−inf dBFS**, captures bit-identical |
| Loudness match within 0.1 LU before any trim | pass — **+0.00 LU** as a skeleton; **+0.07 LU** with stages 0–2, 9, 10 and 13 live, trimmed at stage 13 |
| Skeleton is bypass-equivalent apart from stage 1 | pass — tracked a stage-1-only prediction to **±0.01 dB** |
| `tools/lt-coeffs.py` standalone, self-test passes | pass — 15/15 |
| `sudo sh install.sh uninstall` reverts cleanly | not run — needs sudo. Its five removal paths were checked against what is on disk and cover it exactly, with nothing left behind |

The null baseline in `tests/captures/` was taken through the skeleton rather
than through the original pass-through, so it proves "nothing changed since
the skeleton" rather than "the skeleton matches the pass-through". The latter
is what the ±0.01 dB level check above establishes instead.

## Open questions

Values that cannot be resolved from the machine. Left at bypass rather than
guessed.

- **Measured `fc` and `Qtc`** of the sealed enclosure. Unknown until the sweep
  is run. Stage 2 stays at identity.
- **`f1`**, the post-transform usable floor. Follows from `fc'` and the
  excursion ceiling, so it depends on the above. 200 Hz is a placeholder;
  subband centres are fixed fractions of it and rescale together.
- **`x_max`** for the excursion limiter. No datasheet exists for these OEM
  drivers.

### Volume dependence — decided: the chain sees post-volume audio

US12342139B2 selects different transform and compressor parameters per volume
level, because a static chain is only correct at one drive level.

**Measured, not inferred.** Setting the virtual sink to pactl's "50%" drops the
level at the hardware sink's monitor — which is downstream of the whole graph —
by 18.08 dB. pactl's percentage is a cubic scale, so 50% is 0.125 linear =
−18.06 dB. The match confirms the virtual sink's volume is applied *inside* the
DSP path, before the graph.

Keeping a single GNOME entry means that sink is the user's volume control, so
it cannot be pinned to unity: the chain necessarily sees post-volume audio.
That rules out strategy (a) and settles the question by choice rather than
leaving it open.

The consequence to design around: **tune at one representative listening
level.** Stages 7, 10 and 11 are level-dependent, so their thresholds are only
correct near the level you set them at. Note the level you tuned at in the
config next to the thresholds.

If that turns out to matter audibly, the remaining option is what
US12342139B2 actually describes — watch the sink volume and retune at runtime
with `pw-cli set-param`, which is verified working below.

## References

Read the claims, not the abstract — the abstract describes the idea, the claims
describe what was granted, and the description carries the implementable
detail.

### Primary

| ID | Title / holder | Covers |
|---|---|---|
| [US12342139B2](https://patents.justia.com/patent/12342139) | Increasing low frequency extension for microspeakers using a volume dependent Linkwitz transform and multiband compressor — Microsoft | Stages 0, 2, 10. The volume-dependent parameter selection is the part most easily missed. |
| [CN115442709B](https://patents.google.com/patent/CN115442709B/en) | Audio processing method, virtual bass enhancement system — Honor | Stages 3–8, 11. Figs 3–6 are four VBE variants, fig 7 the system split, fig 8 the frame flow, figs 9–10 the harmonic generator. The `RR(f,n) ∝ ln(n)·R(f)` derivation and the `K = min(...)` formula are in the description, not the claims. |
| [US12445775B2](https://patents.justia.com/patent/12445775) | Processing a digital audio signal to improve rendering of low frequencies — Faurecia Clarion | Stages 1, 11. Fully open-loop: high-pass, low-shelf boost, excursion estimate, gain backoff. The most directly portable of the set. |
| [US8660271B2](https://patents.google.com/patent/US8660271B2/en) | Stereo image widening system | Stage 9. Drops HRTFs for acoustic dipole features, aimed at closely spaced laptop speakers at low CPU cost. |

### Secondary — consult when a stage misbehaves

| ID | Relevance |
|---|---|
| [US11102577B2](https://patents.justia.com/patent/11102577) | Stereo virtual bass — preserves per-channel loudness and interaural level differences under harmonic enhancement. Read if stages 5–7 collapse the image. |
| [US10382857](https://patents.justia.com/patent/10382857) | Automatic level control for psychoacoustic bass — normalises the input to the harmonics generator and reapplies the gain after. Read if harmonic character shifts with level. |
| [US9319789B2](https://patents.justia.com/patent/9319789) | Bass substitution filter with variable gain and bandwidth — the no-harmonics alternative to stages 5–7, avoids intermodulation. Fallback if squaring proves too dirty. |
| [US5930373A](https://patents.google.com/patent/US5930373A/en) | The original missing-fundamental patent (Waves). Expired. Foundational for stage 5. |
| [US6134330A](https://patents.google.com/patent/US6134330A/en) | Ultra bass (Philips). Expired. Alternative nonlinear generator topology. |
| [US20090086982A1](https://patents.google.com/patent/US20090086982A1/en) | Crosstalk cancellation for closely spaced speakers. Alternative to stage 9. |
| [US12041433B2](https://patents.google.com/patent/US12041433B2/en) | Audio crosstalk cancellation and stereo widening — boost before the XTC stage. Relevant if stage 9 moves. |

### Not applicable

These solve the same problems with telemetry the SN6140 does not expose. Do not
attempt to port them: Apple US12604139 (resonance detection from electrical
characteristics), Alps Alpine US12501215 (measured cone displacement), Cirrus
Logic US12425767 (voice-coil temperature).

CN115442709B itself assumes a Smart PA feedback loop for exactly the parameters
stage 11 needs. Only its feed-forward half is portable here: the SN6140 exposes
no I/V sense, no coil temperature and no excursion telemetry, so every adaptive
stage derives its control signal from the audio itself.

Any Google Patents document is reachable at
`https://patents.google.com/patent/<ID>/en`. The patentimages PDFs are
image-only scans with no text layer — use the HTML page for searchable text.

## What is installed

- `files/50-speaker-tuning.conf` — the graph.
- `files/50-hide-speaker-tuning.conf`, `files/51-speaker-sink-priority.conf`,
  `files/hide-speaker-tuning.lua` — keep **Speaker (Tuning)** as the single
  laptop-speaker entry GNOME shows. The raw sink stays available to PipeWire
  and `pactl`.
- `files/speaker-dsp` → `/usr/local/bin/speaker-dsp`.

The physical sink node name appears in `files/50-speaker-tuning.conf`
(`playback.props.target.object`), `files/speaker-dsp` (`RAW`) and
`tools/common.sh` (`SINK_RAW`). If `pactl list sinks short` reports a different
name, all three need updating.
