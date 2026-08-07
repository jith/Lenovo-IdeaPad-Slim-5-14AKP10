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
| 0 | Headroom trim | `s0trim_*` | builtin `linear` | −3.12 dB, returned by stage 10's `g_out` | **active**, `Mult = 0.6983` | US12342139B2 |
| 1 | Subsonic high-pass | `s1sub_*` | builtin `bq_highpass` | 20 Hz, Q 0.707 | **active** | US12445775B2 |
| 2 | Linkwitz transform | `s2lt_*` | builtin `bq_raw`, one per channel | **numerator = measured (fc, Qtc); denominator = target (fc′, Qtc′)** — 761 Hz Q 2.63 → 650 Hz Q 0.707 | **active** | US12342139B2 |
| 3 | HF path | `s3neg_*`, `s3hf_*`, `s3dly_*` | `invert` + `mixer` + `delay` | HF = input − LF | **active**, delay 0 — see below | CN115442709B |
| 4 | Subband split | `s4lp_*`, `s4bp1..3_*` | `bq_lowpass` + 3× `bq_bandpass` | **f1 = 350 Hz**; centres 122.5 / 175 / 252 Hz, Q 2.0 | **active** | CN115442709B |
| 5 | Harmonic generation | `s5pre1..3_*`, `s5h<band>x<order>_*` | `linear` pre-gain + `mult`, order n = x^n | pre-gain ×5, then orders 4/5/6, 3/4/5, 2/3/4 → 490–1008 Hz | **active** | CN115442709B, US5930373A |
| 6 | Harmonic weighting | `s6w<band>x<order>_*`, `s6sum<band>_*` | `bq_peaking` per order | gain = ln(n)·R(f) scaled to +12 dB max | **active**, +1.9 to +12 dB | CN115442709B |
| 7 | Gain K | `s7dc_*`, `s7k1..3_*`, `s7sum_*` | `dcblock` + LSP compressor per band | −20 dBFS, 20:1 — levels the n-th power law | **active** | CN115442709B, US10382857 |
| 8 | Sum | `s8sum_*` | builtin `mixer` | HF, LF and harmonics | **crossfade engaged**, `Gain 2 = 0.6`, `Gain 3 = 0.06` | CN115442709B |
| 9 | M/S widening | `s9*` | explicit M/S matrix | `s9swid` `Gain 1` = bass width, `Gain 2` = above 300 Hz | **bass mono**, `Gain 1 = 0` | US8660271B2 |
| 10 | Multiband compressor | `s10mbc` | **LSP GOTT Compressor** | 120/1000/6000 Hz, `mode = 1`, downward thresholds −20/−15/−9/−9 dB, `g_out` +7.60 dB | **active** | US12342139B2 |
| 11 | Excursion limiter | `s11hx_*`, `s11xcur` | `bq_lowpass` estimate → LSP sidechain comp | Hx = lowpass 761 Hz Q 2.63; threshold −3 dBFS on the estimate | **active**, and it works on ordinary music | US12445775B2, CN115442709B |
| 12 | Brickwall | `s12brick` | LSP Limiter | −0.64 dBFS sample → **−0.2 dBFS true peak** (`ovs = 22`), `lk = 1` | **always on** | — |
| 13 | A/B trim | `s13trim_*` | builtin `linear` | static gain from the loudness match | **unity** — tuned deliberately left 3.44 LU hot | ITU-R BS.1770 |

## Signal flow

### At a glance

All fourteen stages and what each one is for. Node-level detail follows below.

```
                            app audio (48 kHz float32)
                                      │
     ┌────────────────────────────────┼────────────────────────────────┐
     │                    PER CHANNEL │ (L and R independent)          │
     │                                ▼                                │
     │   [0]  headroom trim      -3.12 dB, returned at stage 10        │
     │   [1]  subsonic high-pass 20 Hz Q0.707                          │
     │   [2]  Linkwitz transform 761 Q2.63 -> 650 Q0.707               │
     │            measured resonance    corrected target               │
     │                                │                                │
     │                    split at f1 = 350 Hz                         │
     │            ┌───────────────────┴───────────────────┐            │
     │            ▼                                       ▼            │
     │   [4] LF = LP(350)                    [3] HF = input - LF       │
     │            │                              delay 0 ms            │
     │            ├── real bass, turned down 4.4 dB ─┐    │             │
     │            ▼                                 │    │             │
     │   [4] 3 subbands  122.5 / 175 / 252 Hz       │    │             │
     │   [5] pre-gain x5, then x^n                  │    │             │
     │            orders 4/5/6, 3/4/5, 2/3/4        │    │             │
     │   [6] weight  ln(n) x R(f), up to +12 dB     │    │             │
     │   [7] level   -20 dBFS 20:1  <- tames x^n    │    │             │
     │            │                                 │    │             │
     │            └── harmonics, 490-1008 Hz ───┐   │    │             │
     │                                          ▼   ▼    ▼             │
     │   [8]  sum        harmonics 0.06 : LF 0.6 : HF 1.0              │
     └────────────────────────────────┬────────────────────────────────┘
                                      │  L and R meet from here on
                                      ▼
         [9]  mid/side          bass mono below 300 Hz
         [10] multiband comp    GOTT; 120/1k/6k, lowest threshold on LF,
                                +7.60 dB makeup: returns stage 0, then
                                buys loudness the hardware cannot.
                                The only loudness lever in the chain
         [11] excursion limit   sidechain = Hx displacement estimate
                                (low-pass 761 Hz Q2.63), -3 dBFS 6:1
         [12] brickwall         -0.2 dBFS TRUE peak, never bypassed
         [13] A/B trim          unity; tuned runs 3.44 LU above raw
                                      │
                                      ▼
                     alsa_output...HiFi__Speaker__sink
```

Reading it in one line: **flatten the 761 Hz resonance, stand in for the bass
the driver cannot make with harmonics it can, collapse the stereo image where
it carries no information, then control dynamics and guard the cone.**

The crossfade is engaged: stage 8's `Gain 2 = 0.6` turns the real sub-350 Hz
content down 4.4 dB with the harmonics standing in for it. That content is
17 dB or more below the passband acoustically, so little is heard to go — and
it pays for itself, since energy that costs peak headroom without making sound
is exactly what stops stage 10 pushing harder.

### Node by node

Every node as actually wired in `files/50-speaker-tuning.conf`, with its real
control values. All of them are live; nothing in the graph is
bypass-equivalent any more.

#### Per channel — stages 0 to 8

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
                                         Gain 3 = 0.06  harmonics  2 against 3
```

The generated harmonics land between 490 and 1008 Hz, chosen so the speaker
can actually reproduce them — see the `f1` note in the config header.

#### Shared — stages 9 to 13

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
  s9outr ─┴→ ● s10mbc    LSP GOTT Compressor
             │           120 / 1000 / 6000 Hz, mode 1 (Modern)
             │           thresholds -20 / -15 / -9 / -9 dB
             │           be_1..4 = 1, ru_ = 1 (upward comp off, and it
             │                                 has to stay off -- see below)
             │           g_out +7.60 dB, returning stage 0's trim
             │
             ├─ ● s11hx_l/r  bq_lowpass 761 Hz Q 2.63  displacement estimate
             │                                 ↓
             └→ ● s11xcur   LSP sc_compressor_stereo
                │                              ↑ external sidechain, peak,
                │                                max of the two channels
                │                                threshold -3 dBFS, 6:1
                │
                ● s12brick  LSP limiter_stereo   true peak, never bypassed
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

1. **Stage 0 takes its headroom and stage 10 gives it back.** It exists to make
   room for the Linkwitz transform's boost. Stage 2 needs −3.12 dB — sized on
   the 100 Hz square, not the filter's frequency-domain peak of +2.73 dB,
   because a transient sees the filter's phase as well as its magnitude.

   The trim was deferred while stage 10 was still bypassed, since taking it then
   would have been 3.1 dB of pure loss with nothing to return it. Both are live
   now: `Mult = 0.6983` here, `g_out = 2.40` there. Do not treat stage 0 as a
   loudness control — raising it to 1.0 gains exactly the 3.12 dB it removes,
   but it does so *before* stages 7, 10 and 11 rather than after, so it changes
   what all three of them see. `g_out` is the lever; this is not.

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
| Stage 7 and 11 LSP compressors (`sla = 0`) | 0 |
| Stage 10 LSP GOTT, group delay **measured** | **5.0 ms** |
| Stage 12 LSP limiter, true-peak oversampling + `lk = 1` | **3.6 ms** |
| **Total added by the stages** | **8.6 ms** |
| Virtual sink quantum, 1024 @ 48 kHz (already present in the pass-through) | 21.3 ms |
| **Virtual path total, against playing straight to hardware** | **29.9 ms** |

This table was wrong until the GOTT swap. Calf's `lv2info` says "has latency:
no", so stage 10 was recorded as 0 — but measured against the unprocessed
sweep it delayed 3.7 ms, which put the real total at 30.0 ms rather than the
26 ms previously claimed. GOTT delays 5.0 ms, which would have taken it to
31.3 ms and over budget, so the limiter's lookahead came down from 5 ms to 2.

That costs nothing: the ceiling is held at exactly −0.300 dBFS at 5, 2 and even
1 ms of lookahead, and stage 10 keeps peaks clear of the limiter anyway. GOTT's
`mode 0` (Classic) is equally transparent but delays 13.5 ms, so `mode 1`
(Modern) is the one to use.

Enabling true-peak limiting later took lookahead down again, from 2 ms to 1,
to pay for the oversampler's 2.16 ms. The path sits at 29.9 ms of the 30 ms
budget — there is no room left for another latency-bearing stage.

### The brickwall must limit true peak, not sample peak

With `ovs = 0` the LSP limiter controls **sample** peaks only. Measured on the
chain output with the limiter actively clamping: samples at exactly
−0.300 dBFS, reconstructed waveform at **+1.785 dBFS**. The codec's DAC
reconstructs that and clips it — analog clipping into a 2 W driver, on exactly
the loud transients where it is audible.

| `ovs` | sample pk | true pk | latency | |
|---|---|---|---|---|
| 0 | −0.300 | **+1.438** | 2.00 ms | DAC clips |
| 11 / 15 / 19 (`Full xN`) | **+1.8 to +2.0** | +1.9 to +2.3 | ~1.6 ms | **ceiling broken** |
| 21 (True Peak/16) | −0.300 | +0.425 | 1.42 ms | still clips |
| **22 (True Peak/24)** | **−0.300** | **−0.020** | 3.58 ms | **clean** |

The `Full xN` modes do not hold the sample ceiling at all — measured, not
assumed. Only 21 and 22 work, and only 22 gets under 0 dBFS.

**The threshold then had to come down on hardware.** The offline plugin test
suggested a −0.3 dB sample ceiling was enough, but in the real chain the
limiter sees post-GOTT content with different inter-sample behaviour and it
measured +0.137 dBFS — still clipping. Measured on the running chain:

| `th` | sample | true peak | |
|---|---|---|---|
| 0.96605 | −0.300 | +0.137 | clips |
| 0.9440 | −0.501 | −0.061 | clean, no margin |
| **0.9290** | **−0.640** | **−0.199** | **0.2 dB of margin** |
| 0.9120 | −0.800 | −0.357 | |

0.21 dB of output RMS buys a 0.2 dB true-peak margin. That is inaudible; DAC
clipping is not. It is also a reminder that plugin behaviour measured in
isolation does not always survive contact with the signal the chain actually
produces.

**CPU**, measured with `pw-top` while playing: the filter chain uses 1.3 ms of
a 21.3 ms period — about 6%, with no xruns. True-peak oversampling is the most
expensive thing in the graph and there is still plenty of headroom.

**x42's Digital Peak Limiter was measured as an alternative and is not better
here.** Its true-peak mode has to back the threshold off to −0.6 dB to control
inter-sample peaks, costing 0.54 dB of output RMS; LSP holds −0.3 and still
lands true peak at −0.020. DPL's `truepeak` control also defaults to **0**,
i.e. off — the same silent-default trap as Calf's per-band bypass. DPL's one
advantage is latency, 1.33 ms against LSP's 3.58.

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

### Why stage 10 is GOTT and not Calf

Both are four-band multiband compressors. GOTT wins on two measurements and
one footgun.

**Crossover transparency.** Compression disabled, sweep against the
unprocessed source:

| band | Calf (mode 0) | **GOTT** |
|---|---|---|
| 40–150 Hz | +0.99 dB | **0.00 dB** |
| 150–400 Hz | +0.85 dB | 0.00 dB |
| 800–1300 Hz | −0.57 dB | 0.00 dB |
| 1.3–3 kHz | −0.36 dB | 0.00 dB |
| **worst** | **0.99 dB** | **0.00 dB** |

GOTT's Linkwitz-Riley sections sum flat. Calf's colour the 40–400 Hz region by
about a decibel, and it cannot be tuned away — mode 1 is worse (1.46 dB notch
at the freq1 crossover), and moving the crossovers is worse still (2.23 dB).

**The footgun.** Calf's `bypass0..3` default to **1.0** (bypassed) while its
master `bypass` defaults to 0.0, so it can load, report no error, and do
nothing — measured at 0.06 dB of gain reduction on material that should have
been flattened. GOTT's `be_1..4` default to 1 (enabled).

**Upward compression.** GOTT has `tu_`/`ru_` alongside the downward pair, so it
can lift quiet passages rather than only taming loud ones. Held at `ru_ = 1.0`
(off), and it has to stay there: it was measured as the next loudness lever and
it is not one — it fights the volume control, because the virtual sink's volume
is applied before this graph. The numbers are under "Where the loudness is, and
where it is not". Treat this as a reason to prefer GOTT over Calf only if the
volume dependence is ever solved.

The costs: about 1.3 ms more group delay (5.00 ms against Calf's 3.67), taking
the path to roughly 27 ms of the 30 ms budget; and `ta_`/`tr_` **must** be set
explicitly, because GOTT defaults to 2 ms attack and 3.5 ms release — fast
enough to modulate gain inside a bass cycle and manufacture distortion.

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
| 10 | `s10mbc` `be_1..4` → 1, lowest `td_1`, `g_out` recovers stage 0 and then buys the loudness (done) |
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
| all stages, `level_out` 1.605 | −17.75 | −17.46 | **−0.29 LU** |
| all stages, `level_out` 1.75 | −16.61 | −17.46 | **+0.85 LU** |
| + crossfade, `g_out` 2.05 | −15.55 | −17.46 | +1.91 LU |
| + GOTT, `Gain 3` 0.06 | −15.37 | −17.46 | +2.09 LU |
| **+ `g_out` 2.40** | **−14.02** | −17.46 | **+3.44 LU** |

The last row is where it is left, on purpose — see "How loud can it go".
Raw does not move between rows, which is the check that the tool is measuring
the chain and not the room.

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

## Distortion, and where it comes from

The virtual bass branch synthesises harmonics — it *is* distortion by
construction, and the only question is how much. Measured electrically at the
sink monitor with pure tones at −6 dBFS, so this is the DSP's own output and
not the driver's:

| configuration | 60 Hz | 90 Hz | 120 Hz | 150 Hz |
|---|---|---|---|---|
| harmonic branch muted | 0.66% | **0.28%** | 0.11% | 0.09% |
| branch and stage 10 both out | **0.00%** | 0.00% | 0.00% | 0.00% |
| Calf, `Gain 3` 0.25 | 10.37% | 34.16% | 15.71% | 8.15% |
| GOTT, `Gain 3` 0.25 | 25.05% | 48.62% | 13.34% | 6.74% |
| **GOTT, `Gain 3` 0.06** | **5.99%** | **11.98%** | **3.51%** | **1.90%** |

Three things worth taking from that.

**Every bit of it is stage 5–7.** With the branch muted the chain measures
0.28% at 90 Hz, and 0.00% with stage 10 out as well. Nothing else in fourteen
stages contributes measurably.

**Stage 10 cannot fix it, and GOTT made it worse.** Swapping Calf for GOTT
raised 90 Hz from 34% to 49% at the same injection. A compressor downstream
cannot remove harmonics synthesised upstream — it only reshapes their
envelope. GOTT is still the right choice at stage 10 for its crossover, but
not for this.

**Band selectivity cannot substitute for injection level.** Raising band 1's Q
from 2 to 6 cut 60 Hz from 25% to 11% but left 90 Hz at 46%, because stage 7's
20:1 leveller makes up whatever the bandpass takes away. Only `Gain 3` moves
it, and it does so perfectly linearly.

`Gain 3 = 0.06` puts the worst frequency at 12%, which is where commercial
virtual bass runs. 0.10 gives more bass at about 20%.

## How loud can it go

Short answer: this is it. The hardware is at its electrical maximum and the
chain now takes everything that is left.

**The ALSA mixer is already at 0 dB.** On card 1 -- card 0 is a different
codec and has no speaker controls at all -- `Master`, `Speaker` and `PCM` all
sit at their maximum with 0.00 dB of attenuation. Turning them up in
`alsamixer` does nothing because there is nothing above 0 dB to reach.

**`alsamixer`'s Master and PipeWire's hardware sink are the same control,
linked both ways.** Measured:

| action | Master | PipeWire sink |
|---|---|---|
| start | 100% | 100% |
| set Master to 50% in alsamixer | 50% | 24% — follows it |
| PipeWire sets 100% | 100% — snaps back | 100% |

So a manual `alsamixer` change is not ignored, it is *adopted* by PipeWire and
then overwritten the next time anything sets the volume — a volume key, a
stream starting, a route change. That is why it looks intermittent. Set the
level from PipeWire (GNOME's slider, `pactl`, `speaker-dsp`) and leave the ALSA
controls at maximum, which is where they already are.

**Beyond the hardware, stage 10's `g_out` is the only lever left**, and what
bounds it is **true peak**, not how hard the brickwall works. Stage 12 clamps
sample peaks; on content with energy well up the band the reconstructed
waveform still overshoots, and that overshoot is what the DAC clips.

Worst true peak across all five pieces of test material — pink, pink scaled to
peak at −1 dBFS, a music track, the sweep and the 100 Hz square — measured by
exact band-limited reconstruction at 16×:

| `g_out` | worst true peak | binding signal | |
|---|---|---|---|
| 2.05 | −0.54 dBTP | square100 | the old value; 0.34 dB left unused |
| 2.20 | −0.54 | square100 | |
| **2.40** | **−0.39** | **sweep** | **current** |
| 2.60 | **+0.30** | sweep | clips |
| 2.80 | +0.49 | sweep | clips |

2.40 is the largest value that holds the −0.20 dBTP ceiling on every shipped
test signal. It is worth **+1.37 LU** on pink and **+1.07 LU** on music, with
THD unchanged (5.96 % at 60 Hz against 5.96 %) and the brickwall working on
0.5 % of frames.

2.60 and 2.80 are safe on music, pink and the square, and break only on the
full-scale 20 kHz sweep. If you decide that constraint is not real they are
worth another +1.6 and +2.0 LU — but 2.80 is roughly 1.75× the average power of
2.40 into a 2 W driver already at its electrical maximum, and past there the
cost is thermal as much as dynamic.

**Do not measure true peak with `loudnorm` here.** On the sweep it over-reports
by 1.4 dB and `ebur128`'s 4× oversampling under-reports by about as much. All
three meters agree on music and diverge on high-frequency content — which is
exactly the case this limit is about. The numbers above come from zero-padding
the spectrum, which is exact.

**Stage 13 is left at unity rather than matched.** The loudness match asks for
`Mult = 0.672977` to bring the tuned path back down to the raw path's level.
Applying it would hand back the only loudness available, so it is not applied.
The cost is that `speaker-dsp ab` now favours tuned by 3.44 dB — exactly the
bias the loudness match exists to remove. For an honest comparison, level it
for the duration and put it back after:

```sh
ID=$(pactl list sinks short | awk '/effect_input/{print $1}')
pw-cli set-param $ID Props '{ params = [ "s13trim_l:Mult" 0.6730 "s13trim_r:Mult" 0.6730 ] }'
# ... compare ...
pw-cli set-param $ID Props '{ params = [ "s13trim_l:Mult" 1.0 "s13trim_r:Mult" 1.0 ] }'
```

### Where the loudness is, and where it is not

Every stage was swept for it. Thirteen of the fourteen have nothing to give,
and three ideas that looked obviously right are measurably wrong. Recorded here
so they are not tried again.

| Stage | Idea | Measured |
|---|---|---|
| 0 | Give back the headroom trim | `Mult` 1.0 = +3.01 LU, which is exactly the 3.12 dB it removes. Pure gain, and it moves the operating point of stages 7, 10 and 11 rather than leaving it alone. |
| 1 | Raise the subsonic corner — the driver makes nothing down there anyway | **Net loss.** 80 Hz costs 0.45 LU and frees 0.43 dB of peak. Spending that on makeup gives +1.15 LU where leaving stage 1 alone and using the same makeup gives +1.57. |
| 2 | Ease the Linkwitz target | Tonal, not loudness. It costs 0.13 LU by design, at the frequency K-weighting is most sensitive to. |
| 5–7 | Push the harmonic branch harder | Stage 7's 20:1 leveller absorbs it. That is what it is for. |
| 8 | Deepen the crossfade for headroom | **Net loss** — see below. |
| 8 | More harmonic injection | `Gain 3` 0.10 buys +0.02 LU for +65 % THD. It is a bass-perception control, not a loudness one. |
| 9 | Widen above 300 Hz | `Gain 2` 1.6 = +2.32 LU, but only on fully decorrelated pink noise, and it raises peaks and moves the image. Not loudness. |
| 10 | Lower the downward thresholds | −0.09 LU. Compression without makeup is just quieter. |
| 10 | Per-band makeup instead of global | `mk_2,3` 1.6 = +2.42 LU with a −1.0/+3.3 dB tilt. It buys loudness by cutting bass, not for free. |
| 10 | Upward compression | **Rejected — it fights the volume control.** See below. |
| 12 | Raise the brickwall threshold | LUFS moves 0.01 dB across `th` 0.929 to 0.966. It is a ceiling, not a lever. |
| 13 | Anything | Already at unity. |

**Upward compression is not the next loudness lever.** An earlier note here said
it was, on the reasoning that lifting quiet passages buys level without pushing
peaks. It does buy about +1.9 LU. But the virtual sink's volume is applied
*before* this graph, so upward compression lifts precisely what the volume
control just lowered. Measured on music, as the error between the volume change
asked for and the output change delivered:

| volume | `ru_` = 1 (off) | `ru_` 1.5 | `ru_` 2.0 |
|---|---|---|---|
| −6 dB | +0.64 dB | +2.82 | +3.41 |
| −12 dB | +0.59 | **+4.29** | **+5.41** |
| −30 dB | +0.59 | +4.47 | +5.65 |

Turning it down 30 dB gets you 24. This is the volume dependence
US12342139B2 is actually about, and the answer to it is per-volume parameters —
not a static upward compressor.

**The crossfade does not pay for itself in headroom at these settings.** That
claim held in the regime it was measured, where the brickwall was working hard
enough for the relief to be worth having. Here it works on 0.1 % of frames, so
there is nothing to relieve and removing the energy simply removes it:

| `Gain 2` | with `g_out` 2.40 | with `g_out` 2.80 |
|---|---|---|
| 0.60 | +1.07 LU | +2.00 LU |
| 0.45 | +0.88 | +1.81 |
| 0.30 | +0.78 | +1.72 |

The same is true of every other way of freeing low-frequency headroom: raising
stage 1, raising GOTT's `sf1` to 200 Hz, turning its band 1 down. All swept, all
negative.

**Stage 11 is working on ordinary music**, which the note at its node used to
deny. Its extremes were all taken on the shipped test material, and
`tests/material/pink.wav` is −20 dBFS RMS — about 12 dB below anything you
actually listen to. On music at a real level the Hx estimate peaks at
**+4.41 dBFS**, 7.4 dB over threshold, and the stage removes 0.39 dB, rising to
0.68 dB at `g_out` 2.40. It is left alone: it is the only thing between a
boosted bass transient and a 2 W cone, `x_max` is unknown, and raising `al` to
1.0 recovers only 0.5 LU. That it clamps the 100 Hz square to +0.31 LU across a
change that gains pink 1.37 is the stage doing its job.

### How this was measured

The sweep was done offline first, on an emulation of the whole chain — numpy for
the PipeWire builtins, `ffmpeg -af lv2` driving the real LSP binaries for stages
7, 10, 11 and 12, including stage 11's external sidechain as a four-channel
input. `lv2apply` segfaults on every LSP plugin on this stack; ffmpeg does not.

That emulation is only worth anything if it tracks the hardware, so it was
checked against three numbers already in this file before it was used for
anything:

| Check | Hardware | Offline |
|---|---|---|
| LUFS-I, pink, chain as installed | −15.37 | −15.34 |
| `g_out` table, row-to-row deltas | 0.23 / 0.45 / 0.62 dB | 0.24 / 0.47 / 0.66 dB |
| THD at 60/90/120/150 Hz | 5.99 / 11.98 / 3.51 / 1.90 % | 5.96 / 10.50 / 3.42 / 1.97 % |

and then again on the change itself, against a fresh capture of the running
chain:

| | Predicted | Measured on hardware |
|---|---|---|
| pink, ΔLU for 2.05 → 2.40 | +1.37 | **+1.37** |
| pink, true peak at 2.40 | −5.55 dBTP | **−5.55** |
| square100, ΔLU | +0.20 | +0.31 |
| null residual against the 2.05 capture | a 1.36 dB gain change | −22.6 dBFS against a −7.2 dBFS baseline, which *is* 1.36 dB |

**The one thing offline could not have told you** is which material to use.
`tests/material/pink.wav` peaks at −6.8 dBFS, so it is not the "dense material
peaking at −1 dBFS" the old `g_out` table was measured on, and it is far quieter
than anything you listen to. Every wrong conclusion above — upward compression,
the crossfade, stage 11's threshold — comes from a number taken on material that
is quieter or more stationary than programme. Add real music to
`tests/material/` before trusting any level-dependent result.



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

**Every reference below has work left in it.** References whose implementation
is complete are not listed here at all — they are cited at their own nodes in
`files/50-speaker-tuning.conf` and in the Source column of the stage table.

So each Primary entry is live in the graph but has one specific part that was
deliberately left out, and the Status column says which. Nothing in Secondary
is built.

### Primary

| ID | Title / holder | Covers | Status |
|---|---|---|---|
| [US12342139B2](https://patents.justia.com/patent/12342139) | Increasing low frequency extension for microspeakers using a volume dependent Linkwitz transform and multiband compressor — Microsoft | Stages 0, 2, 10. The volume-dependent parameter selection is the part most easily missed. | **Implemented — static half.** Stages 0 (`Mult = 0.6983`), 2 (761 Q2.63 → 650 Q0.707) and 10 (GOTT, `g_out` 2.40) are live. The volume-dependent half is **not** implemented and was decided against: the virtual sink's volume is applied *before* the graph, so the chain necessarily sees post-volume audio and is tuned at one representative level instead. See *Volume dependence*. |
| [CN115442709B](https://patents.google.com/patent/CN115442709B/en) | Audio processing method, virtual bass enhancement system — Honor | Stages 3–8, 11. Figs 3–6 are four VBE variants, fig 7 the system split, fig 8 the frame flow, figs 9–10 the harmonic generator. The `RR(f,n) ∝ ln(n)·R(f)` derivation and the `K = min(...)` formula are in the description, not the claims. | **Implemented — feed-forward half.** Stages 3–8 and 11 are live; `RR(f,n) ∝ ln(n)·R(f)` is stage 6's peaking gains, +1.9 to +12 dB. Two parts are not literal: `K = min(...)` is applied as the choice of each band's stage 7 threshold rather than as a runtime minimum (departure 5), and the Smart PA feedback loop the patent assumes is unportable — the SN6140 exposes no I/V sense. |
| [US8660271B2](https://patents.google.com/patent/US8660271B2/en) | Stereo image widening system | Stage 9. Drops HRTFs for acoustic dipole features, aimed at closely spaced laptop speakers at low CPU cost. | **Implemented as structure; widening itself not engaged.** The M/S matrix and the 300 Hz side split are live and bass mono is on (`s9swid` `Gain 1 = 0`), but `Gain 2 = 1.0` is unity side gain above 300 Hz — the image is passed at its original width, not widened. The patent's dipole-feature synthesis is not ported; stage 9 is a plain band-split M/S matrix, which is what the null test needed and what the excursion argument for bass mono actually requires. |

### Secondary

Alternatives and fallbacks, none of them built. Read one when the stage it
relates to misbehaves.

| ID | Relevance | Why it is not built |
|---|---|---|
| [US11102577B2](https://patents.justia.com/patent/11102577) | Stereo virtual bass — preserves per-channel loudness and interaural level differences under harmonic enhancement. Read if stages 5–7 collapse the image. | Stages 5–7 already run per channel and independently, which is the precondition; stage 9 then collapses the side signal below 300 Hz on purpose. An image collapse traceable to the harmonic branch has to show above 300 Hz to be worth acting on. |
| [US9319789B2](https://patents.justia.com/patent/9319789) | Bass substitution filter with variable gain and bandwidth — the no-harmonics alternative to stages 5–7, avoids intermodulation. Fallback if squaring proves too dirty. | Mutually exclusive with stages 5–7 as built, and squaring has not proved too dirty: at the shipped `Gain 3 = 0.06` measured THD is 12 % at its worst frequency, in the range commercial virtual bass runs at. |
| [US6134330A](https://patents.google.com/patent/US6134330A/en) | Ultra bass (Philips). Expired. Alternative nonlinear generator topology. | Alternative to the stage 5 generator. |
| [US20090086982A1](https://patents.google.com/patent/US20090086982A1/en) | Crosstalk cancellation for closely spaced speakers. Alternative to stage 9. | Alternative to stage 9. |
| [US12041433B2](https://patents.google.com/patent/US12041433B2/en) | Audio crosstalk cancellation and stereo widening — boost before the XTC stage. Relevant if stage 9 moves. | Stage 9 has not moved. |

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
