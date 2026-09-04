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
| 8 | Sum | `s8sum_*` | builtin `mixer` | HF, LF and harmonics | **crossfade engaged**, `Gain 2 = 0.45`, `Gain 3 = 0.06` — deepened 4 Sep 2026; the chain's biggest **displacement** lever | CN115442709B |
| 9 | M/S widening | `s9*` | explicit M/S matrix | `s9swid` `Gain 1` = bass width, `Gain 2` = above 300 Hz | **bass mono**, `Gain 1 = 0` | US8660271B2 |
| 9b | Upper-bass lift | `s9blift_*` | builtin `bq_peaking` | 200 Hz, Q 1.2, **Gain +3 dB** | **active** — added 4 Sep 2026 at 0 dB and taken to +3 the same day on an A/B. Aimed at a measured 14 dB gap against an iPhone 13 at 160–250 Hz, the band a phone's bass actually lives in. Sits **before** GOTT, unlike 10b/10c: the compression it provokes pulls down the 25–63 Hz content that moves the cone, so displacement *falls* as this rises | — |
| 10 | Multiband compressor | `s10mbc` | **LSP GOTT Compressor** | 120/1000/6000 Hz, `ebe = 1`, `mode = 1`, **`lkahead = 0`**, downward thresholds −20/−15/−9/−9 dB, `g_out` +16.26 dB, `mk_2` **0.00 dB**, `mk_3` −3.17 dB, `mk_4` −6.15 dB | **active** — the only loudness lever, and now the only voicing control too. `mk_3`/`mk_4` carry the 14 Aug −1.5 dB **tilt** correction plus a further matched −4.65 dB, taken in four steps on 1 and 4 Sep 2026 to hold the tilt through stage 11 going multiband and through `g_out` 3.80 → 4.25 → 5.50 → 6.50 — **sized at the listening level, not at unity**, see *The tilt correction is level-dependent*; `mk_2` was **removed** 14 Aug 2026, its job handed to stage 10b. `lkahead` was defaulting to 5 ms and costing the whole latency budget | US12342139B2 |
| 10b | Resonance notch | `s10rbp_*`, `s10rdyn_*`, `s10rneg_*`, `s10rsum_*` | builtin `bq_bandpass` + LSP `compressor_mono` + `invert` + `mixer` | branch 760 Hz Q 1.4262 → **Qbp 2.4245**, anchor **−5.5 dB** (`Gain 2` = 0.4691156), `cr` **1.0** | **active** — since 14 Aug 2026 the *second and last* instrument aimed at the 761 Hz resonance, after stage 2. **Rebuilt as a parallel bandpass 2 Sep 2026 and deepened −3.7 → −5.5**, which is where the frozen Qbp runs out and close to the 4.7 dB residual the A/B measured. The branch compressor is a **wire, by measurement** — both directions were swept and neither has a job, because stages 11–12's give-back is keyed on broadband level, not on 760 Hz | — |
| 10c | Presence lift | `s10pbp_*`, `s10pdyn_*`, `s10psum_*` | builtin `bq_bandpass` + LSP `compressor_mono` + builtin `mixer` | 2650 Hz, Q 1.4262 branch, `cr` 4.0, `al` −20 dBFS, `rt` 300 ms, branch gain 0.5849 | **active, and dynamic since 1 Sep 2026** — a parallel bandpass with a compressed branch, which is exactly a `bq_peaking` Q 1.2 whose Gain moves between about +2.3 and +4.0 dB. Anchored at the *fitted* +4.0 rather than frozen at the +3.0 the static version had to accept. Delivers **+0.73 dB** more at 2500 Hz than the static bell **and 22% less two-tone IMD**, confirmed on hardware | — |
| 11 | Excursion limiter | `s11hx_*`, `s11xcur` | `bq_lowpass` estimate → **LSP sidechain MULTIBAND comp** | Hx = lowpass 761 Hz Q 2.63; threshold −3 dBFS on the estimate, **band 0 only, split 1 kHz** | **active**, works on ordinary music, and the `Hx` shape is now confirmed acoustically — 800 Hz is the only frequency where the drivers compress. **Multiband since 1 Sep 2026**: a cone has one displacement and it is a low-frequency quantity, so ducking 3 kHz was collateral, not protection | US12445775B2, CN115442709B |
| 12a | Band limit | `s12lp_*` | builtin `bq_lowpass` | 22 kHz, Q 0.707 | **active** — buys 0.66 dB of true peak for 0.10 LU on pink | — |
| 12 | Brickwall | `s12brick` | LSP Limiter | −1.01 dBFS sample → **−0.2 dBFS true peak** (`ovs = 22`), `lk = 1` | **always on** — `th` pays for the sweep so `g_out` can spend | — |
| 13 | A/B trim | `s13trim_*` | builtin `linear` | static gain from the loudness match | **unity** — tuned deliberately left hot, by **6.52 LU** as re-measured at `g_out` 6.50 / `Gain 2` 0.45 / stage 9b +3 | ITU-R BS.1770 |

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
                                +10.63 dB makeup: returns stage 0, then
                                buys loudness the hardware cannot.
                                The only loudness lever in the chain, and
                                via mk_2/mk_3 a voicing control too:
                                -1.01 dB at 120-1k, +2.98 dB at 1-6k
        [10b] resonance notch   parallel bandpass, anchor -5.5 dB
                                branch compressor inert (cr = 1.0)
        [10c] presence lift     parallel bandpass, +2.3 to +4.0 dB
                                branch compressor live (cr = 4.0)
                                both from the iPhone 13 A/B, both after
                                GOTT so no band makeup can drift them
         [11] excursion limit   sidechain = Hx displacement estimate
                                (low-pass 761 Hz Q2.63), -3 dBFS 6:1
        [12a] band limit        low-pass 22 kHz Q0.707 -- first unblocked g_out
         [12] brickwall         -0.2 dBFS TRUE peak, never bypassed
         [13] A/B trim          unity; tuned ran 3.44 LU hot at g_out 2.40
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
             │           ebe = 1  <- WITHOUT THIS IT RUNS THREE BANDS
             │                       and every _4 control is inert
             │           be_1..4 = 1, ru_ = 1 (upward comp off, and it
             │                                 has to stay off -- see below)
             │           g_out +10.63 dB, returning stage 0's trim
             │           mk_2 = 0.89 (-1.01 dB), mk_3 = 1.41 (+2.98 dB)
             │                                 -- voicing, from the iPhone A/B
             │
             ● s10rbp_l/r   bq_bandpass 760 Hz Q 2.4245
             ● s10rdyn_l/r  compressor_mono  cr 1.0 -- a wire, measured
             ● s10rneg_l/r  invert
             ● s10rsum_l/r  mixer  dry 1.0 - branch 0.4691156
             │                                 761 Hz cone resonance,
             │                                 -5.5 dB, delivering 2.8-4.0
             ● s10pbp_l/r   bq_bandpass 2650 Hz Q 1.4262
             ● s10pdyn_l/r  compressor_mono  cr 4.0  al -20 dBFS  rt 300 ms
             ● s10psum_l/r  mixer  dry 1.0 + branch 0.5849
             │                                 presence, same A/B, now
             │                                 level-dependent: +2.3 to +4.0 dB
             │           fixed corrections, after GOTT so no band makeup
             │           can drift them, before 11 so its detector sees
             │           them, before 12 so the brickwall keeps the ceiling
             │
             ├─ ● s11hx_l/r  bq_lowpass 761 Hz Q 2.63  displacement estimate
             │                                 ↓
             └→ ● s11xcur   LSP sc_mb_compressor_stereo   band 0 only
                │                              ↑ external sidechain, peak,
                │                                max of the two channels
                │                                threshold -3 dBFS, 6:1
                │                                split 1 kHz; above it the
                │                                estimate has no energy, so
                │                                band 1 is off and the mids
                │                                no longer duck with the bass
                │
                ● s12brick  LSP limiter_stereo   true peak, never bypassed
                │
                ● s13trim_l/r  linear  Mult 1.0        unity, see stage 13
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

### Bluetooth reconnects the slow way, and a clean disconnect does not help

A reconnect to the Logitech receiver fails for about a minute and a half before
it works. The shape is always the same:

```
SetConfiguration: Connection timed out (110)
avdtp_connect_cb() connect: Device or resource busy (16)
SET_CONFIGURATION request rejected: Stream End Point in Use (19)
a2dp.c:invalidate_remote_cache() Invalidating Remote SEP from cache
a2dp.c:load_remote_sep() Unable to load LastUsed: rseid 1 not found
                                            ... and then the sink appears
```

Three episodes on record -- 28 Aug 2026 19:06, 29 Aug 11:26 and 29 Aug 12:18 --
and every one of them recovers on the line after `invalidate_remote_cache()`.
BlueZ caches the remote's stream endpoints and reconnects straight into
SetConfiguration on the cached SEID; the receiver rejects it as in use; BlueZ
drops the cache, runs Discover again and succeeds. The wait is that round trip,
not the device waking up. Pairing again is a shortcut to the same place, because
removing the device deletes the cached endpoints with it -- it is not repairing
the pairing.

The pairing is provably not the problem. Measured while it was refusing to
connect at all: an L2CAP channel to PSM 25 opens and negotiates security level
2, so the link key still authenticates AND encrypts, and SDP answers on that
very PSM with

```
Service Class ID List:    "Audio Sink" (0x110b)
Protocol Descriptor List: "L2CAP" PSM: 25, "AVDTP" 0x0102
```

Restarting bluetooth.service, `bluetoothctl power off/on` and restarting the
whole PipeWire stack change none of it.

There is a worse state past this one, and it is a different fault, not a longer
version of the same one: an AVDTP Discover written straight down a raw socket --
bypassing bluetoothd, WirePlumber and PipeWire alike -- goes unanswered, so the
device answers SDP and ignores AVDTP entirely. That one never heals. Restarting
bluetooth.service, `bluetoothctl power off/on`, restarting the whole PipeWire
stack and POWER-CYCLING THE RECEIVER ITSELF all leave it exactly as it was; only
re-pairing cleared it. Assuming a power cycle would do -- both are "resetting the
device" -- was wrong, and cost two reboots to find out.

**Which of the two you get depends on whether the device was connected when the
host went down**, and the shutdown log says which:

```
12:23:55  connected at shutdown -- "device_disconnected: 21"   -> next boot dead
12:43:40  disconnected by hand first -- no such line           -> next boot clean
```

The clean boot had no AVDTP errors at all and the receiver came back on its own.

Note what that does *not* say. The trigger measured here is the **host going
down** with a session open, and suspend is covered by the same teardown on
reasoning rather than its own measurement. Restarting PipeWire or WirePlumber
has never been shown to cause either fault -- a stack restart appears above only
in the list of things that fail to *fix* one. Do not extend the rule to
restarts without measuring it; `speaker-dsp-bt-disconnect` is armed for
shutdown and suspend, and deliberately not for anything else.
So `files/55-bt-disconnect` closes the session first: `ExecStop` on
speaker-dsp-bt-disconnect.service, ordered After bluetooth.service so it runs
while bluetoothd is still alive, and the same script as a sleep hook before a
suspend. Nothing reconnects on the way up, because nothing needs to.

The shutdown half is the measured one. The suspend half is the same teardown and
is covered on that reasoning alone.

Confirmed over one full cycle on 29 Aug 2026. Shutdown at 12:52:06: the unit
stopped two seconds before bluetooth.service, bluetoothd logged "No matching
connection for device", and there was no `device_disconnected: 21`. The boot
after it came up connected with the sink in place.

The unit carries `RefuseManualStop=yes` for a reason worth knowing. It is
oneshot with RemainAfterExit, so ExecStop only runs while it is ACTIVE, and
`systemctl stop` therefore disarms it silently until the next boot -- with the
next shutdown being the thing it was armed for. That is not hypothetical: the
"test ExecStop in isolation" step suggested here first left it inactive, one
reboot away from proving nothing.

### The login screen flickers, and that one is Ubuntu's

Between bluetoothd starting and someone logging in, BlueZ has NO A2DP endpoints
registered, because WirePlumber is what registers them and Ubuntu does not run
it for the greeter:

```
systemd[2123]: wireplumber.service ... skipped, unmet condition check ConditionGroup=!gdm
```

The greeter gets pipewire and pipewire-pulse and no session manager. So a
receiver reconnecting at the login screen finds a host with no audio profile,
its connect attempts get nowhere, and the shell's Bluetooth icon flickers.
All 21 endpoints appear at the instant the user's WirePlumber starts, and the
sink follows.

Nothing to fix here, and nothing to worry about: no A2DP session is ever
established before login, so there is no stream endpoint left stale, which is
what the dead end above is made of.

An earlier version of this was a sleep hook that ALSO reconnected, and it was
reverted for being worse than nothing: its bounded attempts gave up inside the
ninety-second window, and it was written before any of this was measured.

So: if the sink has not appeared within ninety seconds, it is the second fault,
and it wants a re-pair. `bluetoothctl remove <addr>` and pair again. Before
that, one cheap thing is worth trying -- query SDP and connect immediately after
it answers, which is what broke the deadlock once:

```sh
sdptool search --bdaddr 88:C6:26:FD:EE:68 A2SNK && bluetoothctl connect 88:C6:26:FD:EE:68
```

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

## Channel count is pinned too — multichannel is downmixed before the graph

`capture.props` advertises `audio.position = [ FL FR ]`, and the sink cannot be
anything else: every stage is duplicated per channel and stage 9 crosses the
two. A 5.1 source is converted in the client adapter *upstream* of the filter
chain, so the graph only ever sees two channels. This matters for streaming
video, and none of it was documented until 13 Aug 2026.

**The downmix matrix, measured.** A 5.1 probe carrying one distinct tone per
channel, played to the virtual sink and tapped twice — at
`effect_input.speaker-tuning`'s monitor (post-downmix, pre-graph) and at the
hardware monitor (post-graph). One tone per channel means each coefficient is
read directly off its own DFT bin, with no matrix to solve:

| source channel | → L | → R |
|---|---|---|
| FL, FR | **1.0000** | — |
| FC | 0.7071 (−3.01 dB) | 0.7071 |
| BL, BR | 0.7071 | — |
| LFE | 0.3536 (−9.03 dB) | 0.3536 |

Front channels pass at **unity**. PipeWire 1.6.2 defaults `channelmix.normalize`
to false and nothing on this machine overrides it, so there is no protective
scaling: the L coefficients sum to 2.768, which is **+8.84 dB** were every
channel coherent and **+3.27 dB** as a power sum for uncorrelated content. That
gain lands in exactly the place the volume keys land — ahead of GOTT, the
excursion limiter and the brickwall.

**It does not bite, and the reason is level, not headroom.** Film and television
are mastered far below music; Netflix's delivery spec is −27 LKFS dialog-gated,
which for a full mix puts integrated programme somewhere near −24 to −26 LUFS.
Add the downmix gain and it reaches the graph at roughly **−21 to −23 LUFS** —
inside the region where this chain's voicing has stopped moving, though near its
upper edge, so call it within a few tenths of a dB of fully settled rather than
deep inside it. *Volume dependence* measures that region. Streaming therefore
gets very nearly the chain's **linear** voicing, stable regardless of content and
about 3.5 dB bassier in the bottom two octaves than a loud music master gets. The
risk runs the opposite way to the one the coefficient sum suggests, and it is
benign.

**Two second-order effects, both real and both small.** LFE folds in at −9.03 dB
and then meets stage 2's Linkwitz boost, whose measured gain at 60 Hz is
**+5.99 dB** — so LFE reaches the drivers quieter than it sat in the mix, not
louder. And the surround channels arrive **hard-panned** (BL only to L, BR only
to R), which makes them pure side content, where stage 9's bass-mono acts on
them. Measured against centred content of the same frequency: a hard-panned tone
is **4.24 dB down at 300 Hz**, 1.26 dB at 500 Hz, 0.86 dB at 1250 Hz. Correct
behaviour for a laptop speaker — but surround-only bass effects lose more of
themselves than centre bass does.

**A cross-validation worth keeping.** Chain gain measured on hardware and
predicted offline agree to **0.04 dB at 60 Hz and 0.00 dB at 200 Hz** — but only
once the virtual sink's 94% (−1.61 dB) is added *between* the two taps. That
agreement is an independent confirmation that the sink volume is applied after
the monitor tap and before the graph, by a route not used elsewhere in this file.
The 800 Hz tone is **not** part of that evidence: it sits on the 760 Hz notch,
where a tone and a third-octave band average legitimately disagree.

**What actually reaches this sink is probably always stereo.** Netflix and
Hotstar in a Linux browser deliver stereo AAC; multichannel and Atmos need their
Windows or macOS apps. That is not verified here and cannot be from this machine,
so check rather than assume — while something is streaming:

```sh
pactl list sink-inputs | grep -E "Channel Map|application.name"
```

`front-left,front-right` means none of the above ever engages. The path that
would engage it is a local 5.1 file in mpv or VLC. Bitstream passthrough
(Dolby, DTS) cannot traverse a filter chain at all, which is moot for internal
speakers.

**Untested, and worth watching:** `alsa_card.pci-0000_04_00.1` is the HDMI audio
card, currently `off` with no display attached. The virtual sink carries
`priority.session = 900` against the raw sink's 100, so when a display is
plugged in it is not known whether an HDMI sink outranks it or whether audio
stays on the internal speakers. Needs a cable to settle.

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
| Stage 11 LSP multiband crossover, `mode = 1` (Modern), **measured** | 0 |
| Stage 10 LSP GOTT, `lkahead = 0`, group delay **measured** | **0.3 ms** |
| Stage 12 LSP limiter, true-peak oversampling + `lk = 1` | **3.6 ms** |
| **Total added by the stages** | **3.9 ms** |
| Virtual sink quantum, 1024 @ 48 kHz (already present in the pass-through) | 21.3 ms |
| **Virtual path total, against playing straight to hardware** | **25.2 ms** |

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
to pay for the oversampler's 2.16 ms. The path then sat at 29.9 ms of the 30 ms
budget, with no room left for another latency-bearing stage.

**And 5 ms of that was a port default nobody had written.** Reviewing the
plugin against what it can actually do, 1 Sep 2026: GOTT's `lkahead` defaults
to **5 ms**, and that default was the whole of stage 10's measured group delay.

| `lkahead` | impulse peak out |
|---|---|
| 5 ms (the default, and what was shipping) | **5.00 ms** |
| 2 ms | 2.00 ms |
| 1 ms | 1.00 ms |
| **0 (now set explicitly)** | **0.33 ms** |

The crossover costs almost nothing; the lookahead cost all of it. So the two
compromises the budget forced — the limiter's lookahead cut from 5 ms to 2, and
then from 2 to 1 — were both paid to a port that was never in the config.

It buys nothing on any signal in the battery:

| signal | `lkahead = 5` | `lkahead = 0` |
|---|---|---|
| music1 | −10.57 LUFS | **−10.55** |
| music2 | −8.50 | −8.50 |
| square100 | −8.64 | −8.64 |

True peak identical to 0.001 dB on all three — `square100` included, and that is
the transient case a lookahead exists for. **That is the third time this plugin
has hidden behaviour behind a default**, after `ru_* = 1.0` being the port's
minimum rather than neutral and `tm_*` defaulting equal to `tu_*`. Write every
port a stage depends on, including the ones you want at zero.

**The freed 4.7 ms is banked, not spent.** Giving the limiter its lookahead back
was the obvious use and it measures *worse* — longer lookahead is quieter for no
distortion benefit, so `lk = 1` was never the compromise it was recorded as:

| `lk` | music1 | music2 | square100 | THD 90 Hz | THD 400 Hz |
|---|---|---|---|---|---|
| **1 ms (shipped)** | **−10.35** | **−8.18** | **−10.24** | 6.99 % | 1.46 % |
| 3 ms | −10.43 | −8.37 | −11.54 | 6.99 % | 1.46 % |
| 5 ms | −10.46 | −8.43 | −11.84 | 6.99 % | 1.46 % |

The path now sits at **25.2 ms**, so there is 4.8 ms of room for a
latency-bearing stage where there was none. Note what that does *not* buy: the
quantum is 21.3 ms of the 25.2, so the DSP is no longer the expensive part of
this budget and never was by much.

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

### GOTT runs three bands unless you tell it not to

`ebe` — "Enable extra band" — **defaults to 0**, and at 0 this plugin is a
three-band compressor. `sf3 = 6000` splits nothing, band 3 runs from 1 kHz to
Nyquist, and `td_4`, `rd_4`, `ta_4`, `tr_4`, `be_4` and `mk_4` are all inert.
Every one of those was set in the config from the day stage 10 was built, and
none of them ever did anything. **This chain ran three bands for its entire
history while both the config and this file described four.**

It surfaced only because the `mk_3` voicing lift arrived, and the lift showed
up an octave and a half above where it was aimed. Applying +2.98 dB to one
makeup control at a time, third-octave, against the same render at unity:

| band | `mk_3` alone | `mk_4` alone |
|---|---|---|
| 2 kHz | +2.69 dB | 0.00 dB |
| 5 kHz | +2.60 | 0.00 |
| 8 kHz | +2.60 | 0.00 |
| 16 kHz | +2.61 | 0.00 |

`mk_4` moves nothing anywhere. `mk_3` reaches the top octave. With `ebe = 1`
the lift lands where it is aimed — +3.0 to +3.6 dB across 1.26–4 kHz, down to
+0.5 dB by 8 kHz, which is `g_out` alone.

It costs 0.06 LU and it *buys* peak margin: −0.928 → −0.951 dBTP on the
segment, and on the sweep — the one signal that has ever bound this chain —
the whole voicing change becomes free, −0.398 dBTP against a −0.398 baseline.

The lesson generalises past this plugin. A control that is *set* is not a
control that is *doing something*, and nothing in the config, the journal or
the self-test can tell the difference. Only measuring what a parameter moves
can. Note the same class of footgun is already recorded below for Calf's
`bypass0..3`; this is that footgun in the plugin chosen to avoid it.

### The tilt, and why nothing here had found it

Reported by the listener on 14 Aug 2026 — *treble louder than bass* — and it is
real. The chain's own transfer, measured on programme, third-octave, output over
input:

| 50 Hz | 100 Hz | 250 Hz | 800 Hz | **2500 Hz** | 6.3 kHz | 16 kHz |
|---|---|---|---|---|---|---|
| +1.64 dB | +4.75 | +5.76 | −4.07 | **+11.75** | +8.30 | +6.99 |

**10.1 dB more gain at 2.5 kHz than at 50 Hz**, and 5.65 dB of it is `mk_3`
(+2.87 measured) and stage 10c (+2.78) — both added within the last week, each
to close a presence deficit against the iPhone.

**Four reasons this repo could not see it**, and they generalise:

- **The reference cannot measure a tilt.** The iPhone A/B licenses 250 Hz to
  4.5 kHz — below that the phone is under its own knee, above it the in-chassis
  mic alternates sign. A tilt *is* the relationship between below-250 and
  above-1.6k: exactly the two regions the reference is unable to compare. A
  phone has no bass, so matching its presence region says nothing about whether
  your treble is right relative to *your* bass.
- **Detrending removes a tilt by construction.** Session D fits a smooth trend
  and subtracts it to expose local features. A broadband slope *is* that trend.
  The instrument was built to discard precisely this class of finding.
- **Nothing ever took the sum.** `mk_3` and 10c were each measured alone, each
  justified alone, each nearly free alone. Both push the same direction and
  their total was never computed.
- **No whole-chain instrument existed.** Every offline tool answers *what did
  this one parameter move* (`--sweep`) or *what is the level, peak and THD*
  (`--measure`). None plotted the chain's transfer across the band. That gap is
  why a listener found this before the measurements did.

**The fix is a matched cut to `mk_3` and `mk_4`.** Those are GOTT bands 3 and 4,
so together they are everything above 1 kHz, and cutting both by 1.5 dB is a
flat shelf rather than a reshaping:

| | 630 Hz | 1 kHz | 1.25 k | 2.5 k | 6.3 k | 16 k |
|---|---|---|---|---|---|---|
| delivered | +0.01 | −0.67 | −1.23 | **−1.43** | −1.42 | −1.45 |

Bass is untouched: **50 Hz moves 0.02 dB**. Cutting `mk_3` alone would have left
6 kHz+ standing and made the top octave relatively *more* prominent — the
opposite of the complaint.

**Verified on hardware before shipping.** Built as a `-TEST` sink at matched
volume, the same excerpt played through each chain and captured at the hardware
monitor: **−1.47 dB over 1.6–12.5 kHz** against −1.41 predicted offline, and
**−0.03 dB over 50–400 Hz**. Then A/B'd by ear and kept.

It is a cut, so by the rule in *What a boost costs that a cut does not* only
headroom needed testing — but it improves distortion too. THD identical to two
decimals at 90/400/2650 Hz at −12 and −3 dBFS; true peak improves on every
signal; SMPTE 60 + 2650 Hz IMD at −3 dBFS falls **8.18% → 4.38%**, and at
−6 dBFS back to 0.145%, its value before 10c went in. Costs 0.3–0.5 LU.

**The tilt is level-dependent**, which no measurement here had recorded either:
7.65 dB at unity input, settling to 5.85–5.91 dB below −6 dB and flat from
there. At the 82 % the listener actually uses it is ~5.9 dB, so the figure that
matters is the settled one.

#### What else the audit turned up

Asked to look for gaps of the same shape before shipping, four more:

| finding | verdict |
|---|---|
| **`mk_2` taxes 160–630 Hz by 0.5–0.7 dB** to fix a narrow 761 Hz excess that stage 10b now handles with a bell. Its own comment calls a flat band cut "blunt", and the region it taxes is one the same A/B records as *deficient* (iPhone +5.2 to +9.8 dB at 157–250 Hz) | **closed and shipped.** `mk_2 = 1.0` with `s10res` deepened to **−3.7 dB** holds 800 Hz to +0.06 dB on music1 and +0.01 on music2 while returning the low-mid. Hardware through a `-TEST` sink: **+0.79 dB over 160–630 Hz, 800 Hz held to +0.25**. A/B'd by ear and kept. Costs ~0.2 dB at 40–100 Hz — see *The low-mid the band cut was taking* |
| **Stage 8's `Gain 2` was optimised in one direction only** — 0.60/0.45/0.30 were swept and 0.60 kept, but 0.7–1.0 were never tried. "Deepening is a loss in both directions" is a claim about deepening | **closed by measurement, 0.60 stays.** Swept upward: it is the largest bass lever here (+2.59 dB at 40 Hz, +2.22 at 100 by `Gain 2 = 1.0`) and still refused — the chain's *own* THD at 90 Hz goes 0.48% → 0.89% and IMD rises 32%, and that is only the part offline can see. See the node comment |
| **Stage 9 applies no widening at all.** `Gain 2 = 1.0` is unity; measured side-minus-mid moves −0.53 to +0.17 dB above 400 Hz. The bass-mono half works (−28.7 dB at 40 Hz) | **closed as a doc bug, deliberately not shipped.** Quantified at the node: 1.5 buys 3.5 dB more side energy for 8 mdB of true peak, costing 0.9 dB of mono-sum. Taste, not a defect |
| **No whole-chain instrument existed** — the root cause of all of this | **closed** — `offline-chain.py --bands` prints the third-octave transfer and the bass-to-presence tilt, with three self-test checks. Run it before shipping a voicing change |
| **`mk_4` is not inert.** See the node comment: the "moves nothing" table was taken at `ebe = 0`, when band 4 did not exist | corrected in the config; it is now load-bearing |

Three things came back **clean**, worth recording so they are not re-opened: the
three instruments aimed at 761 Hz (stage 2, `mk_2`, 10b) are additive at 800 Hz
with no hidden stacking; the channels are **bit-identical** on a mono input; and
the 1.8 dB dip at 50 Hz is programme-dependent, absent on pink, so it is GOTT
band 1 compressing where the music has energy rather than a defect.

#### The low-mid the band cut was taking

`mk_2` was the second gap and the only one that shipped. It was −1.01 dB flat
across GOTT's band 2, 120–1000 Hz, installed to hold down the residual 761 Hz
resonance. Two things were wrong with it, and this file had already written both
down without joining them:

- **It is the wrong instrument, by this repo's own conclusion.** *"A band makeup
  is the wrong place for a fixed acoustic correction; a bell after the
  compressor is the right one."* Stage 10b **is** that bell — but 10b was sized
  against the residual *after* `mk_2`, and `mk_2` was then never removed.
- **Its collateral lands where the chain is already short.** The flat cut buys
  −0.46 dB of useful work at 800 Hz and costs **−0.5 to −0.7 dB across
  160–630 Hz** — a region the same iPhone A/B records as *deficient*, the phone
  reading +5.2 to +9.8 dB louder at 157–250 Hz.

**The swap:** `mk_2` to 1.0, `s10res` from −3.0 to −3.7 dB. The bell absorbs
what the band cut was doing at the resonance, and the low-mid is returned.

`s10res` is a **historical node name** and will not be found in the current
config. It was the single `bq_peaking` bell this section was measured against;
on 2 Sep 2026 stage 10b was rebuilt as the parallel bandpass branch
(`s10rbp_*` + `s10rdyn_*` + `s10rneg_*` + `s10rsum_*`) and deepened from
−3.7 dB to **−5.5 dB**. The measurements below stand as taken; the depth and
the node names have moved on. See the stage table at the top.

| | 160 Hz | 250 | 400 | 630 | **800** |
|---|---|---|---|---|---|
| offline, music1 | +0.51 | +0.67 | +0.67 | +0.53 | **+0.06** |
| **hardware, `-TEST` sink** | **+0.73** | **+0.80** | **+0.80** | **+0.67** | **+0.25** |

−3.7 was chosen over −3.6 by fitting **both** tracks rather than one: the 800 Hz
residual is +0.06 dB on music1 and +0.01 on music2. On hardware 800 Hz holds to
+0.25 dB, inside the 1.4 dB re-setup repeatability, so the resonance correction
survives intact. The hardware column reads about 0.18 dB high throughout because
the capture is a 20 s excerpt and GOTT compresses it differently from the full
file — a uniform offset, not a disagreement about shape.

**The cost is real and it is in the deep bass:** about **0.2 dB at 40–100 Hz**,
GOTT redistributing once band 2 stops being held down. Warmth up, sub very
slightly down. A/B'd on a `-TEST` sink at matched volume and kept.

With both changes in, the chain reads **+6.08 dB of tilt** against the +7.66 it
started the day at, and the low-mid is +6.05 dB against a bass of +3.38.

### Voicing against a reference speaker

Everything else in this chain is set from this machine's own measurements.
Five values are not: `g_out` 3.40, `mk_2`, `mk_3`, stage 10b and stage 10c. They come
from acoustic A/Bs against an iPhone 13, and they are the only numbers here
chosen by comparison with another speaker.

**What makes an uncalibrated in-chassis mic able to answer this.** Both
devices are captured on the same Mic2 at the same position, so the mic's own
unknown response *cancels in the ratio*. Absolute curves from these captures
mean nothing; differences between two captures mean a great deal. The phone
stays physically in place for both takes so the room geometry is identical and
only the emitting device changes.

| | Session A, 12 Aug 2026 | Session B, 13 Aug 2026 |
|---|---|---|
| programme | trailer, −10.26 LUFS | *Bum Baa Diga Diga*, −5.7 LUFS, LRA 3.2 |
| chain state | before `mk_2`/`mk_3` | after them |
| set from it | `mk_2`, `mk_3`, `g_out` 3.40 | stages 10b and 10c |
| repeatability | sd 1.4 dB, worst 3.5 (cross-session) | sd 0.77, worst 2.2 (split-half) |

**Session B is what confirms session A.** The 2–3.2 kHz presence deficit that
`mk_3` was built to fill went from **+6.2 dB to +3.4 dB** against the phone,
measured on a master with nothing in common with the one the fix was tuned on.
That is the change landing where it was aimed, on material it never saw.

**Stage 10c finishes that one.** What `mk_3` left is still +4.5 dB at 2520 Hz
and +3.5 at 3175, and four criteria say it is safe to act on where 5–10 kHz is
not: it is inside the licensed window, it is twice the worst-case
repeatability, it holds one sign across four adjacent bands, and dividing the
chain's own contribution out leaves the *driver* 7.6 dB down with the chain
already adding 3.0 back. `mk_3` is aimed correctly and too shallow, which is
the same position stage 10b was in. The instrument is a bell rather than more
`mk_3` because GOTT band 3 runs to 6000 Hz: buying +3 dB at 2520 through the
makeup costs the same +3 dB at 5040, in the region three sessions have now
declined to touch, and another +3 dB at 1000 Hz where the chain is already too
hot. See *What a boost costs that a cut does not*, below — the gain shipped is
below the gain the fit wants, and distortion is why.

**And it found one thing left.** At 794 Hz the chain reads 6.5 dB *hotter* than
the phone. Most of that is the phone rolling off below 1 kHz — its own speaker
running out, not this one misbehaving — so the number acted on is not 6.5. Fit
a smooth trend over 397 Hz–4 kHz, remove it, and **4.7 dB** survives as
narrowband: the 761 Hz resonance, third time it has been measured here. Stage
10b is the answer, and its centre was fitted independently at 740–760 Hz
against `tools/lt-coeffs.py`'s sweep-derived 761 Hz Q 2.63.

**Why `mk_2` was not enough.** It went in at session A and the gap got *worse*.
The resonance is excited by content, not gain; this master is dense through
600–900 Hz where the trailer was not. And GOTT gives back 2.8 dB more broadband
on dense material, unevenly across its bands (−3.4/−3.3/−4.4/−5.0). A band
makeup is the wrong place for a *fixed* acoustic correction; a bell after the
compressor is the right one.

> **Correction, 13 Aug 2026.** This paragraph used to carry a third reason —
> that the stage 5–8 harmonic branch lands at 490–1008 Hz, that this master's
> energy peaks below 60 Hz, and that the branch therefore "works far harder
> here and lands straight on the resonance". **Measured, and false.** Isolating
> the branch by difference (`Gain 3` at 0.06 minus `Gain 3` at 0) puts it
> **20.5 dB below** the chain's own output at 630 Hz on this master and
> **14.2 dB below** on the trailer — so it works *less* hard on the bass-heavy
> master, not more, and either way it cannot account for a 4.7 dB excess. See
> *What the harmonic branch actually contributes*. Stage 10b is unaffected: it
> was sized from the measured residual, not from this explanation.

**What neither session licenses.** Nothing above 4.5 kHz. The phone reads
5.4–7.7 dB brighter across 5–10 kHz and then the sign *flips* to −1.8 and −4.5
at 12.7 and 16 kHz. Alternating sign across adjacent bands is a path artefact's
signature, and this mic is inside the chassis — it reproduces every session,
which establishes it is real for the speaker-to-*internal-mic* path and says
nothing about what reaches a listener. Settling it needs a mic at the listening
position. Also nothing below 250 Hz, where this chain's capture sits
0.5–5.6 dB above the room floor.

### Session D — both stages confirmed, and one proposal rejected by ear

13 Aug 2026, Crab Rave, 156 s of programme with the **same file on both
devices**. That is the methodological step: every capture aligns to the source,
so the comparison runs over identical music, and `driver = laptop − source −
chain` separates the driver from the chain for the first time. Alignment is
ground-truthed — the capture script sleeps exactly 6.00 s before playing and
alignment recovered 6.15 s.

Both shipped stages confirmed, on material neither was tuned on:

| | driver, re its own 1.6–4 kHz plateau | chain does | result vs iPhone |
|---|---|---|---|
| **10b** notch @ 761 Hz | **+7.8 dB peak at 800 Hz** | −12.8 dB | −0.2 dB |
| **10c** bell @ 2650 Hz | flat | +5.4 dB | +0.2 dB at 2500 |

The driver's resonance is measurably where 10b was aimed, and the presence gap
10c was built for is closed. Read both as "matched" — they are inside the
re-setup repeatability of 1.4 dB, not resolved to 0.2 dB.

**The remaining large difference is not a defect.** The iPhone reads 6–12 dB
quieter across 400–630 Hz (worst −12.1 dB at 561 Hz, 1/6 octave). The driver has
no local resonance at 500 Hz and both devices' curves are clean rolloffs; only
the knee differs, ours near 400 Hz and the phone's near 800. Cutting it would
discard real low-mid this speaker has and a phone physically cannot produce.

That was then **tested rather than argued**. A −5 dB bell at 500 Hz Q 1.6
(delivering −2.9 dB acoustically, verified end to end, nothing above 1.25 kHz
moving, no headroom cost) was built as a separate `-TEST` sink and A/B'd against
the installed chain. The uncut chain won. **Do not re-propose cutting
400–630 Hz — it has been tried and rejected by ear, not just by argument.**

#### How it was measured

Put the same file on **both** devices and align every capture to *it*, rather
than to each other. Arrange this deliberately — it is what makes the driver
separable, and sessions A–C could not do any of it.

Three details, each of which produced a wrong answer first:

- **Linear envelope, not log.** A log envelope lets the silent lead-in dominate
  the correlation; it locked onto the silence, r fell to 0.49 and the lag came
  out negative.
- **Match several 40 s chunks and take the median.** A repetitive track
  false-locks one chunk 61 s from the truth. Envelope r only reaches ~0.7 even
  when correct, so **r is not the confidence measure — agreement between chunks
  is.** The phone's chunks agreed to 0.01 s.
- **Ground-truth it.** The capture script sleeps exactly 6.00 s before playing;
  alignment recovered 6.15 s.

Noise came from a dedicated 32 s floor capture, never the head of a music
capture. This room's floor is tonal, not hiss — 45.4 Hz, a 52–56 Hz cluster at
+20 dB, and new this session, discrete components at **402.8 and 439.5 Hz at
+14–16 dB**, sitting inside the band under investigation. Every band was gated
on measured SNR, and below 125 Hz nothing cleared it for either device.

Repeatability by interleaved analysis blocks: **sd 0.10 dB, worst 0.38**. That
is the noise floor of one setup and *not* the confidence bound — re-setup
repeatability is 1.4 dB sd, and that is what a difference has to beat.

#### What the chain is not doing

The listener reported the iPhone better on bass weight, clarity and openness
simultaneously and level-independently. That combination usually means
compression or distortion. Both were measured; both came back clean, and the
negatives are worth keeping so they are not re-investigated.

**Time coherence.** Group delay from a −46 dBFS impulse — low enough that
nothing in the dynamics path engages, so the result is the chain's linear
behaviour — is flat within **2.2 ms from 50 Hz to 12.5 kHz**. The one excursion
is −1.3 ms at 800 Hz, which is stage 10b's notch. Impulse energy spreads 5%–95%
in **0.1 ms**. There is no transient smearing here.

**Cross-band ducking** — the kick pulling the midrange down on every beat, which
is what makes a multiband chain sound flat:

| band | its own gain sd | correlation with bass content |
|---|---|---|
| 40–120 Hz | 3.13 dB | −0.79 (−2.9 dB per 10 dB) |
| 120 Hz–1 kHz | 2.57 dB | **−0.04** |
| 1–6 kHz | 3.50 dB | −0.17 |
| 6 kHz+ | 4.48 dB | −0.17 |

The bass band compresses itself, which is its job; the midrange is not ducked by
it at all. **Gate per band or this measurement lies.** Gated only on broadband
level it read sd 4.4 dB with a 14–17 dB swing — an empty bass band measuring
noise in the passages where the track has none.

What the chain does do is remove **3.2–4.2 dB** of short-term dynamic range
(50 ms and 400 ms windows, source against output). No pumping, just flatter.
Whether that is right for a laptop speaker is taste, not physics.

#### The 5–6.3 kHz dip — closed, and not the way the test intended

Session D left one thing open: a ~6 dB dip at 5–6.3 kHz, consistent across five
adjacent bands, sitting in the band this chassis mic is least able to read. The
control for it is **lid angle** — the mic is in the display bezel and the
speakers are on the deck, so the lid is the one part of the speaker→mic geometry
that can be varied without moving the mic relative to the room. Three captures
of the same excerpt, everything else held: same file, same sink, same 100%
operating point, same room.

| | normal vs upright | all three angles |
|---|---|---|
| 5 kHz | **0.1 dB** | **9.0 dB** |
| 6.3 kHz | 0.5 | 3.3 |
| 4 kHz | 0.6 | 7.5 |
| 8 kHz | 2.4 | 8.0 |
| mean, 4 kHz and up | 1.17 | 6.10 |
| mean, 200 Hz–2.5 kHz | 1.57 | 3.37 |

**The result is not the clean one the test was designed for.** Two angles agree
at 5 kHz to 0.1 dB; the third disagrees with both by 9 dB, more than the dip
itself. SNR was 26–30 dB above the floor in all three, so noise subtraction is
not producing it. That ambiguity cannot be resolved with this microphone,
because it cannot be moved independently of the drivers — normal and upright
agreeing may mean the dip belongs to the driver, or only that two similar
geometries are similar.

**The decision does not need it resolved.** A band whose measured level moves
9 dB with lid angle cannot be corrected by a fixed filter aimed at what this mic
hears: the listener sits at a third position, and under either reading the
correction would be wrong there. No EQ, and the question is closed on that
ground rather than on a verdict about the driver.

What the test is worth beyond its own question: it is the first measurement of
**how much of any acoustic result here belongs to the geometry rather than to
the speaker** — ±1.6 dB in the midrange between two ordinary lid angles, ±3.4 dB
across the full range. That arrives next to the 1.4 dB re-setup repeatability by
a completely independent route, and it is the bar a finding must clear before it
is a property of the speaker at all.

It also sorts session D's own results retroactively. 10b's **+7.8 dB** driver
peak at 800 Hz against 2.1 dB of path variability survives. The 400–630 Hz
excess at **6–12 dB** against 3.4–4.6 dB survives. The 5–6.3 kHz dip at
**6–8 dB** against 9.0 dB does not — and it was the one finding already declined
on the strength of the note that this mic cannot read above 4.5 kHz.

### What the harmonic branch actually contributes

Stages 5–8 are the largest structure in this graph — 60-odd nodes, most of the
node count — and until 13 Aug 2026 nobody had measured how much of the output
they are responsible for on real programme. The answer is: **very little, and
far less than every explanation in this file assumed.**

Isolate the branch by difference — render with `s8sum Gain 3 = 0.06`, render
again at `0`, subtract — and measure the branch's own output against the chain
total in the bands it lands in:

| material | 200 Hz | 250 | 315 | 400 | 500 | 630 | 800 |
|---|---|---|---|---|---|---|---|
| hot master (−5.4 LUFS, sub-heavy) | −20.7 | −19.6 | −22.3 | −22.5 | −18.2 | −20.5 | −25.6 |
| music1 | −20.4 | −16.9 | −21.7 | −23.2 | −18.8 | −14.2 | −24.5 |
| music2 | −22.3 | −24.0 | −24.8 | −25.5 | −20.1 | −18.3 | −22.6 |
| **25–150 Hz sweep** | **−0.0** | **−0.2** | **−0.4** | **−1.1** | **+0.0** | **−0.6** | **−0.4** |

dB of branch relative to the chain's total in that band. On music the branch is
0.5–4% of the power, so switching it **off entirely** moves the 490–1008 Hz
total by −0.01 dB (hot), −0.02 (music1), +0.00 (music2). On a pure bass sweep
it is the entire output above 200 Hz, and switching it off drops that region by
**20.0 dB**.

That single contrast explains a class of error. Every stimulus that makes this
branch visible is one real programme does not resemble, because real programme
already has its own content in 490–1008 Hz and drowns it. Two consequences:

- **The branch cannot be tuned from an acoustic A/B on music, and it cannot be
  blamed for anything measured on one.** Both the session B explanation
  corrected above and the first reading of session C attributed real excesses
  to it. Neither survives.
- **A synthetic stimulus can make a stage look 20 dB more important than it
  is.** This is the *Test material must match programme* lesson again, one
  level up: the material was not too quiet this time, it was too *pure*.

What this does not settle is whether the branch is audible. It adds harmonics
locked to the bass line, which is a different perceptual cue from uncorrelated
energy at the same level, and −20 dB of correlated harmonic is not −20 dB of
noise. Band power cannot tell those apart. `Gain 3` was left at 0.06.

Cost of moving it, for whenever that gets decided by ear: across 0.00 to 0.12,
loudness moves at most 0.04 LU on any of four signals, worst sample peak stays
pinned at −1.012 dBFS and worst true peak at −0.912 dBTP, and the real low end
(50–125 Hz, which stage 8's `Gain 2` owns and this does not) moves under
0.11 dB. It is a free knob in every respect this file can measure.

### What a boost costs that a cut does not

Stage 10b was free. Stage 10c is a boost of similar size in the same slot, and
the naive expectation is that it costs true peak. It does not — stage 12 was
already the binding stage, so a pre-limiter boost turns into density, and the
sweep's true peak actually *improves* from −0.396 to −0.447 dBTP with it in.

What it costs instead is **intermodulation**, and single-tone THD cannot see
it. SMPTE 60 + 2650 Hz at 4:1, sidebands to the fifth order, this graph against
the one before it:

| stimulus peak | before | **+3.0 shipped** | +4.0 fitted | +2.0 |
|---|---|---|---|---|
| −12 dBFS | 0.008 % | 0.008 | 0.008 | 0.008 |
| −9 | 0.069 | 0.071 | 0.072 | 0.070 |
| −6 | 0.142 | **0.329** | 1.988 | 0.143 |
| −3 | 1.320 | **8.135** | 9.876 | 5.644 |

The knee is stage 12, not the squaring branch — muting stage 8's `Gain 3`
leaves it unchanged at 2.085 and 9.847. A 60 Hz sine carrying 80% of the
amplitude drives the limiter into periodic gain reduction at 60 Hz, which
amplitude-modulates everything else present, and raising 2650 Hz gives it more
to modulate.

**Real programme does not do this, and that is what licensed shipping it.**
Take `music2`, renormalise to −6.3 LUFS and clip it at 0 dBFS — harder than
anything that plays here — band-pass 2–4 kHz, and measure the gain the chain
applies to that band moment to moment on 5 ms envelopes:

| graph | mean | sd | p95−p5 |
|---|---|---|---|
| before | +4.52 dB | 4.786 | 13.159 |
| **+3.0 shipped** | **+5.95** | **4.850** | **13.410** |
| +4.0 fitted | +6.44 | 4.879 | 13.529 |

1.3% more gain modulation for 1.4 dB more presence. Music is broadband and
never hands the limiter one dominant bass sine, so the two-tone knee is a
stress result rather than a defect — but it is a real régime, the master this
was measured on does peak below 60 Hz, and +3.0 sits six times lower on it than
+4.0 for 0.5 dB less delivered gain. That is a cheap margin, so it was taken.

The general rule this leaves: **in a chain that ends in a limiter, test a boost
for intermodulation and a cut for headroom.** Each is nearly free on the other's
measurement, which is exactly how one of them gets shipped unmeasured.

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

**The package is gone, and that takes down all audio on old commits.**
`calf-plugins` was uninstalled on 20 Aug 2026. Nothing in the shipped chain
referenced it — every remaining "Calf" in this file and in
`files/50-speaker-tuning.conf` is prose explaining this swap. But `0a8dc2b`, and
anything before `e291531` (6 Aug 2026), loads
`http://calf.sourceforge.net/plugins/MultibandCompressor` at stage 10.

Install one of those and the failure is not local to this sink. `filter-chain`
is loaded as a **mandatory** module, so a plugin it cannot resolve aborts
context creation and `pipewire` itself refuses to start — every sink gone,
`pactl` answering "Connection failure: Connection terminated". Verified 20 Aug
2026, both on the live session and in a throwaway daemon.

The log does name the culprit, but only if you read the right log. `systemctl
--user status pipewire` shows nothing but `Dependency failed`; the useful lines
come from the daemon:

```
[W] plugin_lv2.c: can't load plugin http://calf.sourceforge.net/plugins/MultibandCompressor
[E] filter-graph.c: can't load graph: Invalid argument
[E] conf.c: could not load mandatory module "libpipewire-module-filter-chain"
[E] pipewire.c: failed to create context: Invalid argument
```

Fix is `sudo apt install calf-plugins`, not debugging the config. The general
lesson outlives Calf: **any** unresolvable plugin in this graph is a total audio
outage, not a degraded chain, so probe a new plugin in a throwaway daemon
(`PIPEWIRE_CONFIG_DIR` + `XDG_RUNTIME_DIR` to a scratch path) before it ever
reaches `/etc`.

### Testing a structural change without sudo, and without breaking anything

`pw-cli set-param` covers control values, but adding or rewiring *nodes* needs
the graph rebuilt, and `install.sh` needs sudo. There is a way to measure such
a change before it ever touches `/etc`, and one wrong turn on the way there.

**The wrong turn:** dropping a same-named copy in
`~/.config/pipewire/pipewire.conf.d/` does **not** shadow the one in
`/etc/pipewire/pipewire.conf.d/`. PipeWire **merges** `conf.d` across config
dirs rather than replacing by filename, so this yields *two* filter chains both
claiming `effect_input.speaker-tuning` — verified, two sinks appeared. Back it
out with `rm` and a restart.

**What works** is to give the test copy its own identity, so both graphs run
side by side and the real one is untouched:

```sh
sed -e 's/effect_input\.speaker-tuning"/effect_input.speaker-tuning-TEST"/' \
    -e 's/effect_output\.speaker-tuning"/effect_output.speaker-tuning-TEST"/' \
    -e 's/priority.session = 900/priority.session = 1/' \
    files/50-speaker-tuning.conf \
    > ~/.config/pipewire/pipewire.conf.d/99-speaker-tuning-test.conf
systemctl --user restart pipewire pipewire-pulse wireplumber
```

Dropping `priority.session` keeps the test sink from stealing the default. Both
feed the same hardware sink, so rendering the same file through each and
capturing the hardware monitor gives an old-against-new comparison with the
session, the hardware and the room all held fixed — a better control than
comparing against a capture from a previous day. This is how stage 10b's
0.13 dB out-of-band figure was taken. Delete the file and restart to clean up,
and check `pactl list sinks short` shows one sink again.

Note this leaves a user-level config that will keep shadowing your work if you
forget it — it is loaded *in addition to* `/etc`, so a stale copy silently adds
a second chain every boot.

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

Short answer: this is it, plus 1.61 dB that was sitting unclaimed in the one
control nothing here measures, plus another 0.78 LU that was being withheld on
the say-so of a test signal nobody listens to. The amplifier is at its
electrical maximum and the chain takes what is left of the digital ceiling; the
drivers, measured separately at the end of this section, turn out not to be the
binding constraint anywhere the chain actually operates.

Read this section in order — it is three rounds, and each one moved the ceiling
for a different reason. The band limit (*The ceiling was one signal*) bought
`g_out` 2.40 → 2.60. The `th` trade (*part two*) bought 2.60 → 3.00. The driver
measurement (*What the drivers actually take*) bought nothing at all, and is
the reason the other two are known to be safe.

**The ALSA mixer is already at 0 dB.** On card 1 -- card 0 is a different
codec and has no speaker controls at all -- `Master`, `Speaker` and `PCM` all
sit at their maximum with 0.00 dB of attenuation. Turning them up in
`alsamixer` does nothing because there is nothing above 0 dB to reach.

**That was true of the ALSA controls and false of the speakers.** The
PipeWire hardware sink was found at **94%, 1.61 dB down**, with `Speaker` one
step off its maximum to match, and everything below tuned as though it were
not. Nothing in `tools/` could have caught it: that control sits *after* the
monitor tap every capture is taken from, so a null test, a loudness match and
a true-peak check all read identically at 94% and at 100%. The tooling is
blind to the one level you actually hear.

It gets there on its own — `speaker-dsp off` copies the virtual sink's level
onto it, a volume key moves it, and PipeWire has been seen returning to 94%
after a restart. `speaker-dsp status` now says so, and `warn_hardware_volume`
in `tools/common.sh` is there for scripts.

So the first 1.61 dB of "how loud can it go" was free, and taking it is safe
by a wide margin — see **What the drivers actually take** below. Confirmed
acoustically rather than trusted from `pactl`: 94% → 100% measured **+1.79 dB
at 1 kHz and +1.49 dB at 8 kHz** on the internal mic, against the +1.61 dB
`pactl` reports.

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
exact band-limited reconstruction at 16× (`tools/true-peak.py`):

| `g_out` | no band limit | with 18 kHz LP | binding signal |
|---|---|---|---|
| 2.05 | −0.54 dBTP | −1.25 | square100 |
| 2.20 | −0.54 | −1.25 | square100 |
| 2.40 | −0.39 | −1.10 | sweep |
| **2.60** | +0.30 — clips | **−0.41** | **sweep — current** |
| 2.80 | +0.49 — clips | −0.22 | sweep, 0.02 dB of margin |

**Confirmed on hardware**, captured back to back in one session at unity sink
volume, `g_out` switched live between the two halves so nothing else moved:

| | Predicted | Measured |
|---|---|---|
| pink, ΔLU for 2.40 → 2.60 | +0.68 | **+0.70** |
| sweep, true peak at 2.60 | −0.94 dBTP | **−0.925** |
| sweep, true peak at 2.40 *with* the band limit | −1.620 | **−1.620** |
| worst true peak, any signal | under −0.20 | **−0.621**, square100, 0.42 dB spare |

The third row is the band limit's own prediction — the offline figure for an
18 kHz lowpass applied to the 2.40 sweep capture — and it came back exact.

**Read the first row carefully: it is not the net gain.** Both halves of that
comparison have the band limit in them, so +0.70 LU is what `g_out` gave, before
paying for the filter that allowed it. Against the original chain — 2.40, no
band limit — pink went from −14.02 to −13.74, which is **+0.28 LU net** at an
18 kHz corner. `tools/loudness-match.sh` says the same independently: the
tuned-versus-raw offset moved 3.44 → 3.71 LU, +0.27. Two measurements, one
answer, and less than half the headline.

That is what sent the corner from 18 kHz to 22 kHz. **Confirmed on hardware**,
against the original chain — `g_out` 2.40 with the band limit moved to 23.9 kHz,
which is bypass-equivalent at 48 kHz — both halves live-switched in one session:

| signal | LUFS before | LUFS after | ΔLU | TP before | TP after | ΔTP |
|---|---|---|---|---|---|---|
| **pink** | −14.01 | −13.41 | **+0.60** | −4.388 | −5.074 | **−0.686** |
| sweep | −1.09 | −0.41 | +0.68 | −1.037 | −0.874 | +0.163 |
| square100 | −9.12 | −9.21 | −0.09 | −0.537 | −0.571 | −0.034 |

+0.60 LU on pink against a predicted +0.60, and the baseline reads −14.01
against the −14.02 measured for the same configuration in an earlier session,
so the two sessions are on the same absolute level and this is a fair
comparison rather than a lucky one.

**Pink got 0.60 LU louder and its true peak went down 0.69 dB.** That is the
whole point of the exercise stated in one line: the band limit removes
overshoot that was costing headroom without making sound, and `g_out` spends
what it frees. Worst true peak on any signal is now −0.571 (square100),
0.37 dB inside the ceiling.

square100 loses 0.09 LU because it is pinned by the limiter rather than by
level — it is the one signal that cannot benefit, and it is also the one that
now binds.

Pink remains the worst case for this filter; music carries far less ultrasonic
energy, so expect better on it once there is music to measure.

The null residual is the sharper evidence. A pure gain change of 0.695 dB nulls
to 21.58 dB below the baseline peak, and that is what it does:

| | Baseline peak | Predicted residual | Measured |
|---|---|---|---|
| pink | −6.0 dBFS | −27.58 | **−27.6** |
| sweep | −1.6 | −23.18 | **−23.2** |
| square100 | −0.8 | −22.38 | −24.2 — 1.8 dB low, the limiter absorbing part of the change, which is also why its ΔLU is only +0.10 |

Two signals to 0.02 dB. Whatever else the band limit did, it did nothing that is
not a gain change. (`null-test.sh` reports these as FAIL, correctly — it asks
whether anything changed, and something was changed on purpose.)

**The sweep is no longer the binding signal.** square100 is, at −0.621 dBTP, and
it is pinned there by the limiter rather than by true peak. On the measured
numbers 2.80 would put the sweep at −0.281 and square100 at about 0.0 — at the
ceiling rather than through it. It is still not taken, and the reason is no
longer a measurement: 2.80 is roughly 1.75× the average power of 2.40 into a
2 W driver already at its electrical maximum. That cost is thermal, and shows
up as compression and strain over minutes that no capture here is long enough
to see.

**That last sentence stopped being true on 4 Sep 2026, and the objection did
not survive being measured.** `tools/thermal.sh` holds the speaker at programme
level for minutes and watches it, which nothing here could do before. Four
minutes at **−10.30 dBFS RMS** — music2, the densest real master, rendered
through the shipped chain, reproduced as a stationary signal matched in level,
crest *and* spectrum:

| minute | level | vs cold |
|---|---|---|
| 0 | 65.58 dB | −0.02 |
| 1 | 65.52 | −0.09 |
| 2 | 65.49 | −0.12 |
| 3 | 65.45 | **−0.16** |

**0.17 dB of compression over four minutes**, against 0.02 dB of
window-to-window scatter — so it is real and it is negligible. 45 % of it came
back after 90 s of silence, which is consistent with thermal whose cooling
constant is longer than the cooldown (the magnet and basket hold heat after the
coil sheds it) but does not separate that from amplifier heating or slow drift.
It does not matter which: 0.17 dB is far below the 1 dB criterion used
everywhere else here, and below audibility.

**Two more runs the same night, and they overturn the first conclusion.** What
was written here after the pilot was *thermal is not the blocker*. That was
premature, and it is left visible rather than deleted because the way it failed
is the point.

The second run repeated the soak at the level `g_out` 5.00 delivers — measured,
not extrapolated: **−9.93 dBFS RMS**, which is 0.38 dB and **9 %** more average
power than the shipped level, not the 15 % first guessed. It lost **0.41 dB**,
against the pilot's 0.17. The third run was a control: the same soak at the
shipped level again, immediately afterwards, on a **bit-identical stimulus**.

| run | start | drop over 4 min | cold reference |
|---|---|---|---|
| pilot, shipped level | cold | 0.17 dB | 65.61 dB |
| `g_out` 5.00 level | warm | **0.41 dB** | 65.12 |
| control, shipped level | warm | 0.23 dB | **64.56** |

Two separate effects, and the control separates them.

**Level scaling is real but smaller than it looked.** Warm against warm, 0.23 →
0.41 dB for 9 % more power. Residual heat explains only 0.06 dB of the gap. That
is still superlinear, which plain coil heating should not be — a voltage-driven
coil is self-limiting, since heating raises Re and *reduces* current. Something
scaling that way points at the amplifier rather than the cone.

**But the bigger number is in the last column, and nothing was looking at it.**
The control's cold reference is **1.05 dB below the pilot's** on a bit-identical
stimulus, with the mic and sink volumes verified unchanged at 100 %. Roughly
1 dB was lost across about 25 minutes of intermittent testing and did not come
back in the gaps between runs — gaps of several minutes, far longer than a voice
coil's cooling constant.

**`thermal.py` is structurally blind to that**, and this is a design limitation
worth stating rather than a bug: it takes its own cold reference from the first
windows of each run, so it measures the drop *within* a soak and cannot see
accumulation *across* soaks. Every within-run number above is correct and every
one of them understates what the session did.

**So the honest state is: unresolved, and 1.05 dB is over the 1 dB criterion
used everywhere else here.** It is not yet known whether that is the driver, the
amplifier, the codec, or the mic — which sits inside the same warming chassis.
The test that separates them is idle recovery: leave everything silent for
20–30 minutes and replay the identical stimulus. If the cold reference returns
to 65.61 it is thermal and reversible; if it does not, something drifted and
none of these numbers are driver properties. **Do not read `g_out` headroom off
this section until that run exists.**

#### Recovery: four readings, and the trap in taking them

The idle run was attempted and cut short twice, so what exists is a recovery
*curve* rather than the single long-idle endpoint the paragraph above asks for.
All four use a **bit-identical stimulus**, with the mic and raw-sink volumes
verified unchanged at 100 %:

| reading | cold reference | vs the pilot |
|---|---|---|
| pilot, session start | **65.61 dB** | — |
| control, straight after the 5.00 soak | 64.56 | −1.05 |
| after ~6 min of silence | 64.61 | −1.00 |
| after ~11 min of silence | **64.62** | **−0.99** |

**No recovery at all in eleven minutes**, where a voice coil's cooling constant
is tens of seconds.

**And the method has a trap that this walked into.** Every recovery reading
costs a 60 s burst, so each one re-heats what it is measuring; the 11-minute
point is eleven minutes *containing one of these measurements*, not eleven
minutes of undisturbed cooling. More readings cannot fix that — they are the
problem. The only clean version is a long silence with **one** measurement at
the end, which is the run that keeps not happening.

**There is a reading of all of it that is not drift.** The within-run drops, in
order: 0.17, 0.41, 0.23, 0.30, **0.08**. They have collapsed. That is what
arriving at a warm equilibrium looks like — the early drops were the transient
toward it, and once there, little is left to fall. On that reading the ~1 dB is
thermal with a time constant well over eleven minutes and has simply never been
left alone long enough to return. Nothing here separates that from genuine
drift, and the reason is that the idle was cut short, not that the question is
hard.

**What is true either way:** the loss is **stable, not progressive** — 64.56,
64.61, 64.62 across three readings. It fell about 1 dB early in the session and
has not moved since. Nothing is running away, and `g_out` stays at 4.25.

### The ceiling was one signal, and it was avoidable

`g_out` sat at 2.40 because a single test signal said so. Music, pink and the
square were all clear at 2.60; only the full-scale log sweep broke, at
+0.30 dBTP. The overshoot is inter-sample, it lives in the sweep's last two
seconds above 17 kHz, and it is there because near Nyquist there are barely two
samples per cycle for the reconstruction filter to work with. `ovs = 22`
measures that correctly. Nothing in the limiter can make it go away.

Removing the band removes the problem. Measured on the committed capture
`tests/captures/gout/sweep.current.wav`, filtered offline:

| filter | sample peak | true peak | cost at 10 kHz |
|---|---|---|---|
| none | −1.144 | −0.908 | — |
| LP 18 kHz Q 0.707 | −1.620 | −1.620 | −0.04 dB |
| LP 16 kHz Q 0.707 | −1.655 | −1.654 | −0.16 dB |
| LP 16 kHz Q 0.707 ×3 | −1.700 | −1.699 | −0.49 dB |

One builtin biquad at zero latency — which matters, because the path is at
29.9 ms of a 30 ms budget and has no room for a stage that costs any.

**Choosing the corner, and a cost this table hides.** "−0.04 dB at 10 kHz" is a
response figure, not a loudness one. On pink noise — energy all the way to
Nyquist, K-weighted upward — an 18 kHz corner costs **0.42 LU**, which is most
of what raising `g_out` had just bought. The overshoot lives at 22–24 kHz and
the loudness lives across 18–22, so the true peak recovered is nearly flat in
corner frequency while the cost is not:

| corner | pink cost | TP recovered | at 16 kHz | at 18 kHz |
|---|---|---|---|---|
| 18 kHz | −0.42 LU | 0.712 dB | −1.02 dB | −3.01 dB |
| 20 kHz | −0.25 | 0.684 | −0.20 | −0.70 |
| **22 kHz** | **−0.10** | **0.661** | **−0.01** | **−0.04** |

**22 kHz is the setting**: 93 % of the benefit for a quarter of the cost, and
−0.01 dB at 16 kHz retires the audibility question that 18 kHz's −1.02 dB
legitimately raised. Going lower or steeper is the wrong direction — 16 kHz
Q 0.707 ×3 recovers only 0.08 dB more than 18 kHz for −0.49 dB at 10 kHz.

It goes *before* the limiter. After it, it would reshape the waveform the
limiter had just clamped and put the overshoot back; before it, the limiter
sees band-limited audio and its true-peak detector has an easier job.

At a 22 kHz corner the audibility claim is close to trivial — 0.01 dB down at
16 kHz, 0.25 dB at 20 kHz, into 2 W micro-speakers. If you disagree, delete
`s12lp_*` and put `g_out` back to 2.40.

2.80 then lands at −0.22 dBTP, 0.02 dB inside the ceiling, and is **not** taken:
it is roughly 1.75× the average power of 2.40 into a driver already at its
electrical maximum, past which the cost is thermal as much as dynamic, and
0.02 dB is not a margin.

**Neither ffmpeg meter can gate this.** Both are fine until exactly the case
they are needed for. Measured with `tools/true-peak.py --compare`:

| signal | exact | loudnorm | ebur128 |
|---|---|---|---|
| pink.current | −5.551 | −5.520 | −5.500 |
| square100.current | −0.540 | −0.580 | −0.600 |
| **sweep.current** | **−0.908** | **−1.140** | **−1.100** |

Within 0.06 dB on pink and the square, then both drop about 0.2 dB low on the
sweep, reading back roughly the sample peak. 0.2 dB is comparable to the whole
margin the ceiling leaves. *An earlier version of this section said loudnorm
reads 1.4 dB high and ebur128 low by about as much; neither the direction nor
the magnitude reproduces on the committed captures, and both meters lean the
same way. It was measured on something that is no longer in the repo, which is
the whole argument for the harness below.*

**Stage 13 is left at unity rather than matched.** The loudness match asks for
`Mult = 0.6847` to bring the tuned path back down to the raw path's level.
Applying it would hand back the only loudness available, so it is not applied.
The cost is that `speaker-dsp ab` now favours tuned by 3.29 dB — exactly the
bias the loudness match exists to remove. For an honest comparison, level it
for the duration and put it back after:

```sh
ID=$(pactl list sinks short | awk '/effect_input/{print $1}')
pw-cli set-param $ID Props '{ params = [ "s13trim_l:Mult" 0.6847 "s13trim_r:Mult" 0.6847 ] }'
# ... compare ...
pw-cli set-param $ID Props '{ params = [ "s13trim_l:Mult" 1.0 "s13trim_r:Mult" 1.0 ] }'
```

Measure that figure on **music, not pink**. It was 3.44 LU on pink at `g_out`
2.40; it is 3.29 LU on a real master at `g_out` 3.00 — the offset went *down*
while `g_out` went *up* two steps, because music is limiter-pinned and pink is
not, so the chain cannot add to music what it adds to pink. Pink overstates the
offset, and this trim exists to make an A/B honest.

### The ceiling was one signal, part two: it still was

The band limit above bought `g_out` 2.40 → 2.60 and the sweep went back to
binding at 2.80. That looked like the end of it. It was not — the sweep was
still the only thing objecting, and there was a second, cheaper way to pay it.

**On programme material, true peak does not respond to `g_out` at all.** The
limiter absorbs the whole increase:

| `g_out` | music LUFS | ΔLU | music true peak |
|---|---|---|---|
| 2.60 | −12.28 | — | −0.633 |
| 2.80 | −11.84 | +0.44 | −0.625 |
| 3.00 | −11.45 | +0.83 | −0.625 |
| 3.20 | −11.11 | +1.17 | −0.625 |

Flat peak, rising loudness. Only the full-scale sweep ever breached, and it
breached because the limiter holds its *sample* peak at `th` while the
inter-sample peak overshoots past it.

**`th` is loudness-neutral on music and is not on the sweep.** That asymmetry
is the whole trick. Swept across its usable range on a real master, `th` moves
integrated loudness by **+0.02 LU total** — it only ever catches rare
transients — while moving the sweep's overshoot one-for-one:

| `th` | music LUFS | ΔLU | music TP | sweep TP at `g_out` 3.00 |
|---|---|---|---|---|
| 0.8900 | — | — | −0.997 | **−0.398** |
| 0.9290 | −12.28 | — | −0.633 | −0.009 — clips |
| 0.9550 | −12.27 | +0.01 | −0.393 | — |
| 0.9700 | −12.27 | +0.01 | −0.258 | — |
| 0.9800 | −12.26 | +0.02 | −0.168 | — |

So `th` pays for the sweep and `g_out` collects the loudness. **`th` 0.9290 →
0.8900 costs music nothing and buys `g_out` 2.60 → 3.00.** They are one
setting; move them together.

**Confirmed on hardware**, both halves live-switched in one session at unity
sink volume, with two real masters in the set:

| signal | ΔLU | TP before | TP after | margin |
|---|---|---|---|---|
| **music1** — trailer music, −14.76 LUFS | **+0.78** | −0.633 | −0.999 | 0.799 |
| **music2** — dialogue, −11.25 LUFS | **+0.61** | −0.563 | −0.936 | 0.736 |
| pink | +1.24 | −5.074 | −3.831 | 3.631 |
| square100 | −0.10 | −0.571 | −0.943 | 0.743 |
| sweep | −0.08 | −0.874 | −0.663 | **0.463** |

`music2` is the one that matters. It is the hardest material in the repo —
trailer audio with dialogue over music, arriving at **+0.634 dBTP**, already
clipping before the chain sees it, and 3.5 LU hotter than `music1`. It drives
the limiter hardest and had the most room to go wrong. Hardware reproduced the
offline true peak to the third decimal on both sides of the A/B.

**The worst-case margin improved.** Before: 0.371 dB, on square100. After:
0.463 dB, on the sweep. This is louder *and* further from the ceiling, which is
the only kind of loudness change worth making. Both synthetic signals give up a
tenth of a LU; neither is programme, and both are limiter-pinned.

**What bounds `g_out` now is limiter workload, not peak.** At 3.00 the limiter
absorbs about 0.45 dB of the 1.25 dB `g_out` adds; by 3.80 it absorbs 1.35 dB
and the cost is audible density rather than a number on a meter. Offline, the
sweep holds about −0.40 dBTP all the way to 3.80 with `th` at 0.8900 — peak
will not stop you. 3.40 is a further +0.63 LU and is available if you want it.
Past 3.00, listen before believing the meter.

The drivers are not in this conversation at all: the tightest band still sits
about 12.8 dB under where they start to compress. See **What the drivers
actually take**.

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
| 8 | Deepen the crossfade for headroom | **Reversed 4 Sep 2026.** Net loss against *true peak*, which no longer binds. Against **displacement** it is the best lever in the chain: `Gain 2` 0.45 frees 1.21 dB of cone for 0.16 LU. See below. |
| 8 | More harmonic injection | `Gain 3` 0.10 buys +0.02 LU for +65 % THD. It is a bass-perception control, not a loudness one. |
| 9 | Widen above 300 Hz | `Gain 2` 1.6 = +2.32 LU, but only on fully decorrelated pink noise, and it raises peaks and moves the image. Not loudness. |
| 10 | Lower the downward thresholds | −0.09 LU. Compression without makeup is just quieter. |
| 10 | Raise `sf1`, so the hard threshold covers what actually moves the cone | **Rejected, and the port stops at 200 Hz.** +0.01 LU at matched displacement *and* tilt. See below. |
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

**And that whole paragraph measured the wrong thing, 4 Sep 2026.** It sweeps
loudness at fixed `g_out` in a regime where **true peak** was binding. It is not
any more — displacement is — and stage 8's `Gain 2` is the single biggest lever
on displacement in the chain, because 1/f⁴ weighting puts nearly all of it in
exactly the sub-350 Hz content `Gain 2` turns down. There was no displacement
metric until `offline-chain.py` grew one the same day, which is why this sat
unseen for a month.

| `Gain 2` | ΔLU | displacement | real bass 50–125 | harmonics 500–1000 |
|---|---|---|---|---|
| 0.60 | +0.00 | +0.00 dB | +0.00 | +0.00 |
| **0.45** | −0.16 | **−1.21** | −0.97 | **+0.30** |
| 0.30 | −0.29 | −3.02 | −2.31 | +0.56 |

0.45 gives back **1.21 dB of cone for 0.16 LU**, where the whole remaining
margin was about 1.0 dB. Spending that on `g_out` and holding tilt at the
listening level:

| config | ΔLU | displacement |
|---|---|---|
| `Gain 2` 0.6, `g_out` 4.25 | +0.00 | +0.00 dB |
| **`Gain 2` 0.45, `g_out` 5.50** | **+0.56** | **−0.12** |

**More level for less cone**, which `g_out` alone can never do — 4.25 bought
+0.42 LU and spent 0.52 dB. At 80 % the gain is +1.07 dB rather than +0.56, the
same level dependence the `mk` cut has. A/B'd on hardware at 80 %, level-matched
to 0.00 dB, and reported as sounding **the same** — which is what licenses it:
the voicing was judged equal, so the measurement decides.

**Two cautions.** Level-matched, this moves energy *into* 160–1000 Hz — deep
bass −1.08 dB, harmonics +0.86, presence and top −1.05. **761 Hz is in that
band** and stages 2 and 10b both exist to suppress it; if boxiness appears on
other material, look here first. And **tilt reads +0.03 across this change and
is the wrong instrument for it**: presence and deep bass fell together, so a
two-point tilt sees nothing while the middle of the band moved.

**And the lift is bigger on stationary material than the A/B showed.**
Found while re-baselining the null test after the change. New baselines against
the `g_out` 4.25 / `Gain 2` 0.6 set, level-normalised:

| signal | 50–125 | 160–400 | 500–1000 | 2–4k | 5–12.5k |
|---|---|---|---|---|---|
| pink | +0.09 | **+1.78** | **+1.81** | −0.41 | −0.43 |
| sweep_quiet | +0.09 | +1.28 | +1.52 | −0.42 | −0.44 |
| square100 | −0.50 | +0.81 | +1.25 | +0.02 | +0.04 |

On `music1` the same bands moved +0.29 and +0.86.

**Tested on sustained material, and the concern above does not survive it.** The
paragraph as first written generalised from pink to "sustained content", and
those are not the same thing. Shipped minus previous, level-normalised:

| material | ΔLU | 50–125 | 160–400 | 500–1000 | 2–4k | Δdisplacement |
|---|---|---|---|---|---|---|
| music1, transient | +0.56 | −0.65 | +0.39 | **+0.61** | −0.70 | −0.12 |
| sustained EDM, −5.14 LUFS master | +0.04 | −0.12 | +0.27 | **+0.51** | −0.12 | −0.09 |
| sustained organ chord, −11 LUFS | +0.18 | −0.65 | +0.36 | **+0.73** | −0.34 | −0.83 |
| pink | +0.42 | +0.07 | +1.76 | **+1.80** | −0.42 | −0.15 |

Real sustained music lands at **+0.51 to +0.73 dB** in the 761 Hz band, the same
range as transient music. **Pink is the outlier and pink is not sustained
music** — it is *stationary*, flat-spectrum and transient-free, so it parks the
dynamics in a steady state nothing real reaches. Sustained and stationary are
different things and conflating them produced a caveat that measurement does not
support.

Two things do fall out of that table. Dense modern masters get **almost nothing**
from the change (+0.04 LU on the EDM master) because the chain has no headroom
to give material already that limited. And the organ chord saves **0.83 dB of
displacement**, the largest cone saving in the set — sustained low content is
exactly what the crossfade is for.

**And `sf1` stays rejected once displacement is the bound, 4 Sep 2026.** That
sweep was run against *true peak*, at `g_out` 2.40, when true peak was what
bound the chain. It no longer is — see *The loudness that bought* — so the
verdict was re-taken against displacement, the bound that binds now. It comes
back the same, for two reasons that are independent of each other.

**The port stops at 200 Hz.** `sf1` is declared `hasStrictBounds`, minimum 20,
maximum 200. Values of 250, 280, 315, 350 and 400 all returned output identical
to 200 — clamped silently, no warning. The argument for moving the split wants
about 280 Hz, and **this plugin cannot go there at all.** That is the fourth
GOTT port to behave differently from what the config appeared to say, after
`ebe`, `ru_*` and `lkahead`; this one clamps rather than defaults, so the sweep
looked like a curve flattening out rather than an error.

**Inside the reachable range it converts displacement into tilt.** The mechanism
is real — `square100`, the displacement tell, gives up 1.60 dB — but on music
the return per dB of tonal damage halves at every step:

| signal | `sf1` | ΔLU | Δ displacement | Δ tilt | dB displacement per dB tilt |
|---|---|---|---|---|---|
| music1 | 160 | −0.08 | −0.19 | +0.32 | 0.59 |
| music1 | **200** | −0.14 | −0.26 | +0.52 | **0.35** |
| music2 | 160 | −0.06 | −0.18 | +0.47 | 0.38 |
| music2 | **200** | −0.12 | −0.23 | +0.73 | **0.19** |
| square100 | 200 | −0.30 | **−1.60** | +1.84 | 0.87 |

Read the last column, not the fourth. The displacement return is already
saturating by 200 Hz while the tilt cost keeps accruing linearly, so a plugin
that *could* split at 280 or 350 Hz would buy proportionally less displacement
for proportionally more tilt. **That closes the escape route**: swapping stage
10 for `mb_compressor_stereo`'s eight bands to reach past the bound is not worth
doing for this.

**Held honest on both axes it is worth nothing.** Re-spending the freed
displacement on `g_out`, then paying the tilt back with the same `mk_3`/`mk_4`
shelf the 1 Sep `g_out` move used:

| configuration | ΔLU | Δ displacement | Δ tilt |
|---|---|---|---|
| **music1** — `sf1` 120, `g_out` 3.80 (shipped) | — | — | — |
| `sf1` 200, `g_out` 4.00 — displacement matched | +0.11 | +0.00 | +0.69 |
| + `mk` shelf −0.69 dB — tilt matched too | **+0.01** | +0.02 | +0.05 |
| *for scale:* `sf1` 120, `g_out` 4.00 | **+0.23** | +0.24 | +0.20 |
| **music2** — `sf1` 120, `g_out` 3.80 (shipped) | — | — | — |
| `sf1` 200, `g_out` 4.00 | +0.06 | −0.05 | +0.88 |
| + `mk` shelf −0.88 dB — tilt matched too | **−0.09** | +0.00 | +0.16 |
| *for scale:* `sf1` 120, `g_out` 4.00 | **+0.17** | +0.16 | +0.17 |

The *for scale* rows settle it: leaving the split alone and simply raising
`g_out` beats the manoeuvre on every axis at once — more level, less tilt
damage, and its displacement bought something. True peak never moved, staying
within 0.03 dB of −0.998 on music1 and −0.905 on music2 across every row.

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

**That emulation is now `tools/offline-chain.py` and `tools/dsp_offline.py`.**
It was not in the repo for the first round of this work, which is why the
`loudnorm` figure above could be shown wrong but not explained — the thing that
produced it was gone. It parses `files/50-speaker-tuning.conf` on every run and
builds the graph from it, so it cannot drift from what is installed the way a
transcribed copy would:

```sh
tools/offline-chain.py --self-test                     # 21 checks, no hardware
tools/offline-chain.py --measure tests/material/pink.wav
tools/offline-chain.py --sweep s10mbc:g_out=2.40,2.60,2.80 tests/material/pink.wav
tools/offline-chain.py in.wav out.wav --set "s8sum_l:Gain 3=0.10"
```

`--self-test` runs without the LSP binaries at all: it checks the biquads
against closed-form magnitudes, the true-peak measurement against signals with
known answers, and then runs the whole 98-node graph with the LSP stages
bypassed, which is enough to catch a mis-wired link or a multi-channel builtin
read as mono. It does not check the LSP stages; nothing without their binaries
can.

The emulation is only worth anything if it tracks the hardware, so it was
checked against three numbers already in this file before it was used for
anything:

| Check | Hardware | Offline |
|---|---|---|
| LUFS-I, pink, chain as installed | −15.37 | −15.34 |
| `g_out` table, row-to-row deltas | 0.23 / 0.45 / 0.62 dB | 0.24 / 0.47 / 0.66 dB |
| THD at 60/90/120/150 Hz | 5.99 / 11.98 / 3.51 / 1.90 % | 5.96 / 10.50 / 3.42 / 1.97 % |

`tools/offline-chain.py --verify` re-derives all of that from the captures in
`tests/captures/gout/` — `.baseline` is the chain at `g_out` 2.05, `.current`
the same chain at 2.40, which is what makes the deltas checkable. It passes 5/5.

One figure in this file does **not** reconcile and is worth knowing about: the
`g_out` table's absolute true peaks (−0.39 at 2.40, binding signal the sweep)
are 0.5 dB below what the captured sweep reads (−0.908). They are not the same
measurement — the table was computed over five *stimuli* including a pink noise
scaled to peak at −1 dBFS, the captures are of material played at a particular
level. The deltas reconcile to 0.003 dB. Deltas are what the conclusions rest
on; treat the absolute column as relative to its own stimulus set.

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
is quieter or more stationary than programme.

`tools/make-test-material.sh --music` exists to close that. It takes 40 seconds
from 25 % into each track you give it, converts to the graph format, and prints
LUFS-I and true peak so you can see what you have:

```sh
tools/make-test-material.sh --music ~/Music/a.flac ~/Music/b.flac ~/Music/c.flac
```

It does not normalise — the master's own level is the thing being tested, and a
loud modern master is the point rather than a problem. **Three tracks with real
low-frequency content, before trusting any level-dependent result.** This is
still outstanding: the numbers in this file were taken on one music track that
is not in the repo.

### Confirming this on hardware

`g_out = 3.00`, `th = 0.8900` and the 22 kHz band limit are all confirmed; this
section is kept as the procedure for the next change. The loop below is the
whole method — two live parameter sets, two captures, one comparison — and it
takes minutes. `g_out` and `th` are both live parameters, so **the A/B needs no
reinstall and no PipeWire restart**; install only once the answer is in.

**First, check the graph loaded, and check the volume.** Both have burned a
full measurement cycle already:

```sh
sudo sh install.sh
systemctl --user restart pipewire pipewire-pulse wireplumber
sleep 3

diff /etc/pipewire/pipewire.conf.d/50-speaker-tuning.conf \
     files/50-speaker-tuning.conf && echo "config installed"
journalctl --user -b -u pipewire -u wireplumber --since '-2 min' \
    | grep -i 'filter-chain\|error'          # want nothing

pactl set-sink-volume effect_input.speaker-tuning 100%
```

`pw-cli ls Node | grep s12lp` **does not work** and will always return nothing.
The filter chain's internal nodes are not PipeWire nodes — they are Props keys
on the one filter-chain node, which is why live tuning addresses them as
`"s12lp_l:Freq"`. To see the running values:

```sh
ID=$(pactl list sinks short | awk '/effect_input.speaker-tuning/{print $1}')
pw-cli enum-params "$ID" Props | grep -E 's10mbc:g_out|s12lp_l:Freq' -A1
```

**The 100 % is not optional.** The virtual sink's volume is applied before the
graph, so a capture taken at 94 % is 1.6 dB low — and a 1.6 dB error does not
look like an error, it looks like a tuning result pointing the wrong way. That
is exactly how this change first measured as 1.34 LU *quieter*. `null-test.sh`
and `loudness-match.sh` now refuse to run unless the sink is at unity.

**Then capture, back to back, in one session.** `g_out` is a live parameter, so
both sides can be taken minutes apart at the same volume with the same graph —
which is worth much more than comparing against captures from a previous
session at an unknown level:

```sh
rm -rf tests/captures/gout260

pw-cli set-param "$ID" Props '{ params = [ "s10mbc:g_out" 2.40 ] }'
tools/null-test.sh baseline tests/captures/gout260

pw-cli set-param "$ID" Props '{ params = [ "s10mbc:g_out" 2.60 ] }'
tools/null-test.sh compare tests/captures/gout260

tools/offline-chain.py --compare-dir tests/captures/gout260
```

`null-test.sh` defaults to `pink`, `sweep_quiet` and `square100`, so there is no
material list to get wrong. Note the sweep in that list is the **quiet** one —
`sweep.wav` cannot be nulled while the limiter engages, so it is not a default. If you do pass paths from zsh, pass them as an array —
`MAT=(a.wav b.wav)` then `"${MAT[@]}"`. An unquoted `$MAT` holding several
paths arrives as a single argument, because zsh does not word-split.

Both sides have the band limit, so this isolates `g_out` alone. The last command
is the gate: LUFS and true peak for both sides with deltas, non-zero exit if
anything breaches the ceiling.

| # | Check | Predicted |
|---|---|---|
| 1 | Nothing over −0.20 dBTP | sweep about −0.94 dBTP |
| 2 | Pink gains about **+0.68 LU** | materially less means the limiter is working harder than the model expects |
| 3 | THD at 60/90/120/150 Hz unchanged | `g_out` is downstream of the harmonic branch and should not move THD at all |

To A/B the band limit itself, move its corner instead of reinstalling —
`"s12lp_l:Freq" 23900` is bypass-equivalent at 48 kHz:

```sh
pw-cli set-param "$ID" Props '{ params = [ "s12lp_l:Freq" 23900 "s12lp_r:Freq" 23900 ] }'
```

Then listen for the band limit specifically — cymbals, sibilance, close-miked
acoustic guitar. It is 0.04 dB at 10 kHz and should be inaudible; the honest
test is whether you can pick it blind, which `speaker-dsp ab` will not do for
you here because both paths have it.



### What the drivers actually take

Everything above this point bounds the chain by **true peak** — a digital
limit, measured at the sink monitor, about what the DAC will clip. It says
nothing about the drivers, because the monitor tap sits ahead of the codec's
volume control, the amplifier and the cones. The only instrument that can see
past it is the microphone.

```sh
tools/max-level.sh cap.wav --ref -18 --burst 0.5 --gap 0.6 \
    --levels -21,-12,-6,-3,0 --freqs 315,400,500,630,800,1000,1250,1600,2000,3150,5000,8000,12500
tools/max-level.py analyze cap.wav cap.schedule.json
```

Sine bursts through the **raw** sink at hardware volume 100%, read back on
Mic2. Two results, and they point in opposite directions.

**One frequency in the whole band mechanically runs out, and it is 800 Hz.**
Compression at full scale, with every test level bracketed by a −18 dBFS
reference so the figure is a difference and not a fit:

| | | | |
|---|---|---|---|
| 315 Hz | −0.06 dB | 1250 Hz | +0.31 dB |
| 400 Hz | −0.73 | 1600 Hz | +0.09 |
| 500 Hz | −0.17 | 2000 Hz | +0.34 |
| 630 Hz | −0.42 | 3150 Hz | +0.23 |
| **800 Hz** | **+2.35** | 8000 Hz | +0.12 |
| 1000 Hz | +0.82 | 12500 Hz | −0.05 |

The two reference blocks bracketing the same test agree to 0.03–0.14 dB, so
everything but 800 Hz and 1 kHz is zero. Its 1 dB point is −8.1 dBFS. 800 Hz
is the resonance — 761 Hz, measured independently from the sweep — which is
where excursion per volt peaks, and **stage 11's `Hx` estimate is a low-pass
at exactly that frequency and Q.** A displacement model built from `fc` and
`Qtc` predicted the one frequency that compresses without being told about
it. That is the strongest evidence in this repo that `Hx` is the right control
signal, and it arrived from a measurement that knew nothing about the model.

**Everywhere else there is no cliff to find.** Below 630 Hz distortion rises
smoothly with level — roughly square-law, no knee — and full scale produces no
compression at all. THD at 400 Hz reads 31% at full scale, but that number is
the driver's *response slope*, not a limit: the fundamental is 20 dB down and
the harmonics land at 800–1600 Hz where the driver is efficient, so they come
back and it does not. Which is the premise the whole virtual-bass branch rests
on, arrived at from the other end.

So "maximum without distortion" below 630 Hz is a **choice of THD budget, not
a hardware ceiling**. There is no level at which something audibly breaks.

**The chain is nowhere near any of it.** Per-band, against the measured
ceiling, on pink scaled to programme level (peak −1 dBFS in) through the whole
graph — band level converted to equivalent sine amplitude, +3.01 dB, or the
comparison is 3 dB optimistic:

| band | chain output | ceiling | margin |
|---|---|---|---|
| 500 Hz | −21.9 dBFS | −8.0 | 13.9 dB |
| 630 Hz | −25.8 | −2.5 | 23.3 |
| **800 Hz** | **−29.1** | **−8.0** | **21.1** |
| 1000 Hz | −26.2 | −0.5 | 25.7 |
| 1250 Hz | −23.8 | 0.0 | 23.8 |
| 2000 Hz | −21.9 | 0.0 | 21.9 |
| 8000 Hz | −21.4 | 0.0 | 21.4 |

21 dB of margin at the one frequency that binds. The full-scale sweep is the
only signal that gets near the drivers, and it gets near them at 315–500 Hz,
where — per above — there is nothing to break.

**What this changed at the time: the hardware volume, and nothing else.** No
stage level moved on the strength of this measurement. Stage 11's `al` stays
at 0.708 — now with a measured reason rather than an admission that `x_max` is
unknown, and measurably 2.6 dB conservative of the driver's own 1 dB point,
which is the right side to be on for a peak detector with a 5 ms attack.

`g_out` and `th` did move afterwards, for a reason that has nothing to do with
the drivers — see *The ceiling was one signal, part two*. That change spends
about 1.1 dB of the margins in the table above, leaving roughly **20 dB at
800 Hz and 12.8 dB at 500 Hz**, the tightest band. The conclusion is unchanged
and the arithmetic is not close: nothing in this chain is limited by the
speakers.

**Re-run 4 Sep 2026, on the same grid, before taking `g_out` 4.25.** 800 Hz
compresses **2.34 dB** at full scale against 2.35 here, 1 kHz **0.85** against
0.82, and the 800 Hz 1 dB point interpolates to **−8.05 dBFS** against −8.1.
The two load-bearing rows reproduce to 0.01 and 0.03 dB and the 1 dB point to
0.05, so the driver has not changed and the margin quoted throughout this file
is still the measured one. The rest of the grid moved by up to 0.37 dB, all of
it inside the per-row reference scatter, which is what that column is for.
One row is new rather than changed: **5 kHz reads 2.34 dB of compression at
full scale with 1.33 dB of reference disagreement** — the noisiest row in the
table, above scatter but not by much, and far above where displacement lives.
It is recorded rather than acted on.

**What would have to be true for this to be wrong.** The internal mic is
uncalibrated and inside the chassis, so the absolute THD percentages are
approximate. They are not load-bearing: compression is a level difference at
one frequency, which is the comparison the mic caveat explicitly permits. The
capture chain was ruled out as the source directly — at the loudest point in
the grid the mic reads −20.8 dBFS, 20 dB clear of its own ceiling, and a
constant 3700 Hz probe tone riding under a stepping test tone held still to
0.18 dB while the test tone lost 2 dB.

#### Two ways this measurement lied before it worked

Both produced clean, plausible, wrong tables. Recorded because the next
person to measure a speaker in a room will meet them.

**A rising staircase cannot measure 1 dB of compression.** It fits a
unity-slope baseline through its own quiet end, and at 500 Hz those points
scatter by 2 dB — larger than the effect. The first run reported 2–3 dB of
compression at 1 kHz that the bracketed run puts at 0.82.

**The room is in the measurement, and stepping an unbroken tone cannot
escape it.** Holding the tone on and stepping only its amplitude is the
obvious way to keep the driver and the sound field still. It fails: this room
decays slowly enough at 500 Hz that a reference block 250 ms after a loud one
is reading the *tail* of the loud one. At one drive level, −18 dBFS, the same
reference block read −47.7 dBFS after silence, −43.0 after a −6 dBFS block and
−40.1 after a 0 dBFS block — ranked perfectly by what preceded it, which is
not a property a driver has. That run reported 4.2 dB of compression at
2.5 kHz, where the truth is 0.34. Separate bursts with a 600 ms gap fix it;
the onset settling that motivated the unbroken tone (1.15 dB, and nearly
level-independent) cancels anyway, because reference and test are bursts of
the same length analysed at the same offset.

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

This changed on 3 Sep 2026 and the sweep is no longer usable as a null signal.
The old result, still true of the graph as it stood on 5 Aug:

```
compare pink    residual -inf dBFS   PASS   (62.0 s, aligned -1024 samples)
compare sweep   residual -inf dBFS   PASS   (32.0 s, aligned +1024 samples)
```

Exactly zero — bit-identical captures, no noise floor at all. That rested on a
precondition stated right here at the time: *the limiter never engages at these
levels*. It now does. The sweep's captured peak has gone from −6.0 dBFS to
−1.0 dBFS as `g_out` rose and stages 10b/10c/11 went dynamic, so the sweep now
drives the very stages whose output depends on their own history:

```
compare pink       residual  -81.8 dBFS   PASS   (62.0 s)
compare sweep      residual  -18.5 dBFS   FAIL   (32.0 s)
compare square100  residual  -70.3 dBFS   PASS   ( 7.0 s)
```

Nothing is bit-exact any more, but only the sweep fails, and it fails by 40 dB.
Three consecutive runs gave −18.5, −20.5 and −18.8 dBFS, so it is not a fluke.
What the residual looks like:

| sweep position | residual |
|---|---|
| 40 Hz – 1.3 kHz | −72 to −100 dBFS |
| **2.5 – 5 kHz** | **−21 dBFS** |
| 10 kHz | −36 dBFS |

Per-window RMS of the two captures agrees **to 0.01 dB everywhere** — same
signal, same level, differing only in fine structure.

**Re-baselined at `g_out` 4.25, 4 Sep 2026.** The stored baselines in
`tests/captures/` are captures of a specific graph, so taking `g_out` to 4.25
invalidated them; the 3.80 set was moved to `tests/captures/gout380/` rather
than overwritten, because that directory is gitignored and nothing else keeps
them. Fresh baselines, then an immediate `compare` against the same unchanged
graph — which is the only thing that proves a baseline is usable:

```
compare pink        residual  -79.8 dBFS   PASS   (62.0 s, aligned -3072)
compare sweep_quiet residual  -79.6 dBFS   PASS   (32.0 s, aligned +0)
compare square100   residual -684.8 dBFS   PASS   ( 7.0 s, aligned -1024)
```

pink and `sweep_quiet` come back about 1.5 dB noisier than the 3.80 set
(−81.8 and −81.0), which is the chain running 0.44 dB hotter into stages whose
output depends on their own history. **`square100` went the other way and is
now bit-exact**, where it was −70.3. The captures are genuinely separate files,
109 s apart, with different lengths and checksums — what is identical is the
*aligned overlap*. Driven harder, the 100 Hz square puts stage 12 into steady
periodic gain reduction instead of intermittent engagement, and a limiter that
never lets go is deterministic again.

Note all three alignments are whole quanta (−3072, 0, −1024 samples at a 1024
quantum). That is the condition under which any of this nulls at all: a
one-sample shift moves the output −21 dBFS while the limiter is working.

**Re-baselined after every change since**, because captures are graph-specific
and every voicing change invalidates them. `tests/captures/` is gitignored, so
these archives are the only copies that exist:

| directory | chain |
|---|---|
| `tests/captures/` | **current** — `Gain 2` 0.45, `g_out` 6.50, stage 9b +3 dB |
| `gout650-nolift/` | the same with stage 9b inert |
| `gout550/` | `Gain 2` 0.45, `g_out` 5.50 |
| `gout425-mk018/` | `Gain 2` 0.6, `g_out` 4.25, `mk` cut 0.18 |
| `gout425-mk044/` | the same at `mk` cut 0.44 |
| `gout380/` | `g_out` 3.80, where the day started |

Each set is verified offline against the chain rather than by a second
`compare` pass — true peak has matched the offline render to **0.000 dB** on all
three signals every time. Note that pink and `sweep_quiet` show 0.3–0.5 dB of
band movement across changes where `music1` stays inside 0.15; that is the
stationary-versus-transient effect above, not a defect.

This set was **verified offline rather than by a second `compare` pass**, which
is cheaper in test tones and answers a different question. New baselines against
the archived 0.44 set, level-normalised, is a direct check that the intended
change is the only change:

| signal | ΔLU | <125 Hz | 160–400 | 2–4k | 5–12.5k |
|---|---|---|---|---|---|
| pink | +0.20 | +0.00 | −0.00 | **+0.24** | **+0.25** |
| sweep_quiet | +0.17 | +0.00 | +0.00 | **+0.22** | **+0.25** |
| square100 | −0.10 | −0.12 | −0.12 | −0.01 | +0.01 |

Nothing below 1 kHz moved and everything above went up by the `mk` change.
`square100` reads differently because it is limiter-pinned: its HF is harmonics
of a 100 Hz square, so passing more of them makes stage 12 clamp slightly harder
and pulls the fundamental down 0.12 dB.

**What that does not establish is that these baselines null**, which only a
`compare` run against the unchanged graph can show. The set above is usable and
self-consistent; the first `compare` after any future change is also the first
proof of it, so read a surprising residual as possibly the baseline rather than
the change.

That 2.5–5 kHz band is where the *presence* lift sits, and the first reading
here blamed stage 10c's compressed branch for it. **That was wrong**, and the
isolation below is what corrects it. 2.5–5 kHz is simply the chain's
highest-gain region (`--bands` puts presence at +9.55 dB, the top of the
curve), so it is where the sweep drives the **limiter** hardest.

#### It is stage 12, and only when it engages

Reproduced offline with no hardware at all: shift the input by **one sample**,
run the chain, shift back, subtract. A chain that is block-alignment
independent gives zero.

| chain | 1-sample-shift residual |
|---|---|
| as shipped | −21.2 dBFS |
| stage 10c `cr` 4.0 → 1.0 (a wire) | −14.6 dBFS — *worse* |
| stage 11 excursion off | −22.2 dBFS — unchanged |
| **stage 12 brickwall off** | **−70.5 dBFS** |

Only stage 12 matters, and neutering 10c makes things worse rather than better
because it feeds the limiter a peakier signal. The dependence is on the limiter
*engaging*, not on any single setting of it — `ovs`, `lk` and `th` were each
swept and none removes it. Drop the input level instead, and it vanishes the
moment the limiter lets go:

| sweep in | chain out | limiter | shift residual |
|---|---|---|---|
| −6 dBFS | −1.01 dBFS | **at the ceiling** | **−21.2 dBFS** |
| −18 dBFS | −7.87 dBFS | below | −79.9 dBFS |
| −30 dBFS | −18.36 dBFS | below | −95.5 dBFS |
| −42 dBFS | −30.35 dBFS | below | −109.8 dBFS |

59 dB the instant it stops working, then roughly 1 dB per dB — ordinary
numerical noise. **Confirmed on hardware**, the two run back to back in one
session:

```
compare sweep        (-6 dBFS)  residual -20.5 dBFS  FAIL
compare sweep_quiet (-18 dBFS)  residual -80.5 dBFS  PASS
```

against an offline prediction of −79.9 dB. So the mechanism is settled: the
limiter's gain envelope comes from lookahead peak detection over a block, and
when it works on a signal whose level is *changing*, where the block boundaries
fall relative to the material changes the envelope slightly. In real time
`clock.force-quantum` is 0 and playback begins at an arbitrary offset within
the 1024-sample quantum, so every capture partitions the material differently.

That also explains the two that still pass. `pink` peaks at −1.8 dBFS, below
the −1.012 ceiling, so the limiter barely engages. `square100` sits *on* the
ceiling but is stationary, so its gain reduction reaches a steady value and
stays there — and a constant gain is shift-invariant. It is **non-stationary
material at the ceiling** that breaks, which is exactly what a sweep is.

**The chain's arithmetic is not at fault.** `offline-chain.py` run twice over
the same input is byte-identical for both pink and sweep. The graph is
deterministic; only the real-time partitioning of the input is not.

**Practically:** `null-test.sh` now defaults to `pink`, `sweep_quiet` and
`square100`. `sweep.wav` was dropped from the defaults — a default that always
fails teaches you to skim past failures, which is the one thing the script
exists to stop. It can still be passed explicitly to look at limiter behaviour;
it just cannot be nulled, and a `sweep.wav` FAIL means nothing on its own.

`pink` and `square100` are the ones that test the chain at full level.
`sweep_quiet` (−18 dBFS, nulls at −80.5 dBFS) only reaches the static
filtering, because anything quiet enough to null is too quiet to drive the
dynamics. A sweep quiet enough to null
is also too quiet to exercise the stages worth testing, so this is a genuine
loss of coverage rather than something to work around — the material that
matters most is the material the method can no longer check.

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
tools/make-test-material.sh [--dir tests/material] --music TRACK [TRACK ...]
```

Generates pink noise (60 s, −20 dBFS RMS, independently seeded channels so the
mid/side stage sees a real side signal), a 30 s log sweep from 20 Hz to 20 kHz,
and a 5 s 100 Hz square wave for harmonic-branch sanity.

`--music` adds real tracks, and it is not optional if you intend to trust any
level-dependent result: it takes 40 s from 25 % into each track, converts to
the graph format, and prints LUFS-I and true peak. It does **not** normalise —
the master's own level is the thing being tested, and a loud master is the
point rather than a problem. `--music` is terminal, so `--dir` comes first.

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

# the same sweep at FULL SCALE. Not redundant: stage 12's `th` is bound by
# this signal and by nothing else here, and sweep.wav is 6 dB too quiet to
# show it. See "The full-scale sweep is the only signal that binds th" below.
sox -n -r 48000 -c 2 -b 32 -e float sweep_fs.wav synth 30 sine 20/20000 gain 0

# the same sweep 12 dB down -- the only sweep that still nulls, because the
# stage 12 limiter never engages at this level. See "Repeatability" below.
sox -n -r 48000 -c 2 -b 32 -e float sweep_quiet.wav synth 30 sine 20/20000 gain -18

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
  sweep_fs.wav   RMS  -3.011 dBFS     (sample peak 0.000 dBFS, true peak
                                       +0.555 dBTP -- over 0 dBFS on purpose)
  sweep_quiet.wav RMS -21.011 dBFS    (peak -18.000 dBFS; the only sweep that
                                       nulls -- limiter never engages)
  square100.wav  RMS  -6.000 dBFS
```

### The full-scale sweep is the only signal that binds `th`

`sweep_fs.wav` exists because `sweep.wav` peaks at **−6.0 dBFS** and stage 12's
`th` is decided by inter-sample overshoot, which scales with level. Measured
3 Sep 2026, the same `th` sweep run against each file:

| `th` | sample | true peak, `sweep.wav` (−6 dBFS) | true peak, `sweep_fs.wav` (0 dBFS) |
|---|---|---|---|
| **0.8900** (shipped) | −1.012 | −0.791 | **−0.666** |
| 0.9400 | −0.537 | −0.480 | **−0.210** |
| 0.9450 | −0.491 | −0.434 | ❌ −0.165 |
| 0.96605 | −0.300 | −0.248 | ❌ **+0.017** |

The quiet file clears **every** row, including the one already known to clip on
hardware — it reports 0.96605 as sitting at −0.248 dBTP, comfortably inside the
ceiling, when the real answer is over it. Read against `sweep.wav` the chain
appears to have 0.59 dB of spare true-peak headroom and `th` could go to
0.9650. Against the full-scale file the real headroom is **0.470 dB**, the
ceiling is **`th` = 0.9400** with 0.010 dB to spare, and 0.9650 clips — which is
the *same* result already recorded in the stage 12 comment of
`files/50-speaker-tuning.conf` ("th = 0.96605 ... measured +0.137 dBTP on
hardware"). The quiet sweep hid that failure twice, three weeks apart.

**Use `sweep_fs.wav` for any `th` or `g_out` work, and `sweep.wav` for acoustic
response work** — `sweep-response.py` takes the latter as its `--reference`, and
that file must not change.

Raising `th` was also measured and is not worth it on its own: 0.8900 → 0.9400
buys **+0.00 to +0.50 LU** (about +0.2 on programme, against a ~1 LU JND) while
spending the entire safety margin. That is the same conclusion the stage 12
comment reaches from the other direction — `th` is set low to buy the sweep,
and the loudness that costs is collected at stage 10's `g_out`.

sox synthesises at 0 dBFS and its pink noise overshoots on three to five
samples in 5.76 million, so `synth` warns about clipping however the gain is
arranged. That does not matter here and should not be "fixed" by lowering the
level: the file is a stimulus played identically down both paths, so whatever
is clipped in it is clipped the same way in both captures and cancels exactly
in the null subtraction. Lowering the level would only move where the
level-dependent stages sit.

### Why the platform loudness gap stays open

Netflix and Hotstar play far quieter than YouTube. Nine approaches were
measured against this on 3 Sep 2026. **Several of them reach the level; none is
worth what it costs**, and two that were installed came back out within the
hour. The section exists so the tenth attempt starts from here.

**Measured on a real Netflix stream** at the hardware monitor, not on a proxy:

| | real Netflix | YouTube-level programme |
|---|---|---|
| LUFS | **−22.8** | −9.2 |
| LRA | **10.7** | 4.0 |
| crest | **24.0 dB** | ~15 dB |
| true peak | −3.78 dBFS | −0.92 dBFS |

The gap is **13.6 dB**, and the content carries a 24 dB crest with dips to
−38 dB. The stage 12 limiter is not engaging at all on it, so about 2.8 dB of
gain is free — but closing 13.6 dB would drive peaks to +9.8 dBFS and flatten
that crest into nothing.

**Root cause: it is a decoder gap, not a DSP one.** Netflix ships dialnorm and
DRC metadata (Dolby Digital Plus / xHE-AAC) stating how loud the dialogue is.
Decoders that honour it normalise to a target — Line −31 LKFS, RF −20, Portable
−11 — and MPEG-D DRC boosts low-level signals while compressing high-level ones.
That is exact because the decoder is *told* the offset. Brave and Chromium on
Linux decode to stereo and discard it, so the raw mix reaches the speaker. No
downstream processing can recover a number that was deleted upstream, which is
why a MacBook has no trouble here and this machine does.

**What was tried, and why each failed:**

| Approach | Result |
|---|---|
| LSP `autogain` — all 7 ports swept | pumps music 12–17 dB at every setting; `tgrow_l` caps at 10 s, shorter than a musical passage. `max_amp = 0` still leaves 4.4–7.7 dB because the cap limits boosting, not attenuation |
| GOTT upward (`ru_*`) | delivers loudness only by dumping 17 dB into presence: tilt +3.51 → +12.23 dB |
| `mb_limiter` / `mb_clipper` | ≤0.4 dB of crest, and `mb_limiter` overshot to +0.014 dBTP |
| Band-limited dialogue lift | does not pump (1.8–2.6 dB swing) but buys +0.81 LUFS — clarity, not level |
| Fixed offset on a routed sink | worked, and was rejected: at +13 dB crest falls 15.3 → 10.8 dB |
| Browser extension | Netflix audio is Widevine-protected; Web Audio gain cannot touch it |
| 5.1 → stereo | measured 1.2–1.4 dB, and Brave already sends stereo — not the cause |
| LADSPA (SC1–SC4, Dyson, limiters) | instantaneous detectors, same class as the above |
| **Custom LV2: BS.1770 gated integrated autogain** | **built and it works** — converged to +10.01 dB against +10.00 expected, steady-state swing 0.03 dB, music untouched (0.0–0.7 dB swing vs LSP's 12.6–14.1); +8.5 dB on hardware. A/B'd against the plain chain and judged **no audible benefit**, so it was removed |

**Why the last row is the interesting one.** EBU R128 *integrated* loudness is
the only detector in that list that is not structurally wrong for the job:
gated and averaged over minutes, so a passage cannot move it, and boost-only, so
normal-loudness music asks for no gain and has nothing to pump. EasyEffects
implements it as a background service; here it was written as an LV2 instead —
~220 lines, no service and no sudo, vendored LV2 headers, K-weighting designed
for the running rate, 400 ms blocks at 75% overlap, −70 LUFS absolute and −10 LU
relative gating over a rolling 180 s window, built to `~/.lv2`. That paragraph is
enough to rebuild it; do not re-derive it from scratch.

**And it still lost the A/B.** Which is the actual finding: closing 13.6 dB
against a fixed limiter ceiling costs crest whichever mechanism spends it —
15.3 → 12.8 dB at the +8 dB this plugin applied, 15.3 → 10.8 at the +13 dB a
fixed gain needs for parity. On a 2 W driver that trade has now lost twice by
ear. **Getting the level is not the hard part; keeping it worth listening to
is.**

**A caution recorded with it:** the crest figures above were first taken on
`music2` attenuated to −27 LUFS, which turned out to be **9 dB less dynamic than
real Netflix**. That is this repo's recurring failure — see *Test material* — and
it was walked into again here. Measure the real stream before trusting any
number about film.
### Existing material is never overwritten

`make-test-material.sh` keeps any file that already exists and prints `keep`
for it. `--force` is the only way past that, and it warns before it does
anything.

The reason is `pink.wav`. Its noise is random, `tests/captures/pink.baseline.wav`
and `pink.current.wav` are hardware captures *of one specific* `pink.wav`, and
`tests/material/` is gitignored — so a plain re-run used to replace the stimulus
with different noise and leave every null test against those captures quietly
comparing two unrelated signals. Nothing failed; the residual just stopped
meaning anything.

The synthesis is now `sox -R`, which makes the noise repeatable, so any
`pink.wav` generated from here on can be regenerated exactly:

| | regenerates identically? |
|---|---|
| `sweep.wav`, `sweep_fs.wav`, `square100.wav` | ✅ always — deterministic synth |
| `pink.wav` with `-R` | ✅ yes |
| `pink.wav` without `-R` (how the 5 Aug one was made) | ❌ different every run |

`-R` could not rescue the 5 Aug file — it predated the flag — so **the
baselines were re-taken on 3 Sep 2026 against a `-R` `pink.wav`**, and the
whole directory is now reproducible from the script. `--force` brings back
byte-identical material and the stored captures stay valid; verified by
regenerating and confirming the checksum still matches.

That checksum is `PINK_BASELINE_MD5` in the script, checked on every run,
because the audio is gitignored and it is the only link between the stored
captures and the stimulus they were made with. A plain run confirms the match;
a mismatch prints what it has and what it wants.

The keep-by-default rule stays regardless. It costs nothing, and it is the only
thing standing between a capture set and a stimulus swapped out from under it
if the synthesis is ever edited again.

## Acceptance status

Measured on the installed graph, not asserted.

**Read the dates on these.** The null, bypass and loudness-match rows were all
taken while the chain was still bypass-equivalent, or close to it. They are the
acceptance evidence for the *skeleton* — that the topology is sound and adds
nothing of its own — and none of them has been re-run against the chain as it
stands with all fourteen stages live. That is the largest gap in this file.

| Criterion | Taken against | Result |
|---|---|---|
| `effect_input.speaker-tuning` in `pactl list sinks short` | current | pass — present, 48000 Hz |
| No warnings or errors in the PipeWire journal on load | current | pass — zero filter-chain lines since the restart |
| `tools/lt-coeffs.py` standalone, self-test passes | current | pass — 15/15 |
| `tools/offline-chain.py --self-test` | current | pass — 23/23, and it re-reads the config each run |
| Null test residual below −60 dBFS above 30 Hz | **current, `g_out` 4.25** | pass — **−80.1 / −80.1 / −691.6 dBFS** above 30 Hz on `pink`, `sweep_quiet`, `square100`, re-baselined 4 Sep 2026. The loud sweep is still not a null signal; see *Repeatability*. Says nothing about the tuned chain, only that it reproduces |
| Loudness match within 0.1 LU before any trim | **skeleton + stages 0–2, 9, 10, 13** | pass — **+0.00 LU** as a skeleton, **+0.07 LU** with those stages |
| Skeleton is bypass-equivalent apart from stage 1 | **skeleton** | pass — tracked a stage-1-only prediction to **±0.01 dB** |
| Every capture under the −0.20 dBTP ceiling | `g_out` 2.40 | pass — worst −0.39 dBTP, by `tools/true-peak.py` |
| Every capture under the ceiling, `g_out` 2.60 + 22 kHz | superseded | pass — worst −0.571 dBTP (square100), 0.37 dB spare |
| Every capture under the ceiling, `g_out` 3.00 + `th` 0.8900 | superseded | pass — worst −0.663 dBTP (sweep), 0.463 dB spare, on a five-signal set including two real masters |
| Every signal under the ceiling, `g_out` 3.40 + `mk_2`/`mk_3` + `ebe` | **current** | pass — worst **−0.398 dBTP** (sweep), **0.198 dB spare**, and *identical* to the pre-change baseline: with `ebe = 1` the whole voicing change is free on the one signal that has ever bound this chain. Five signals, three of them real masters |
| Voicing change confirmed on hardware, not just offline | **current** | pass — monitor capture reads **−0.951 dBTP** against an offline-predicted **−0.951** and sample peak −1.012 against −1.012. Third-octave, hardware against the offline render: **0.075 dB sd, 0.20 dB worst** across 50 Hz–16 kHz |
| Loudness on real programme after the voicing change | **current** | pass — **+0.79 LU** (trailer segment), **+0.74 LU** (music2), **+0.69 LU** (music1). The two synthetic signals lose level because `mk_2` deliberately cuts the band both sit in |
| `mk_3` lifts only the band it is aimed at | **current** | pass — **only after `ebe = 1`**. Before it, `mk_3` reached the top octave and `mk_4` did nothing at all. See *GOTT runs three bands unless you tell it not to* |
| The change survives `install.sh` and a restart | **current** | pass — installed file byte-identical to the repo, zero filter-chain lines in the journal, and the reloaded graph re-measures **−0.951 dBTP / −1.012 sample**, the same figures the live-tuned graph gave before the restart |
| Virtual sink at unity after the restart | **current** | **fail, and it is not the graph's fault** — PipeWire restored it at **82%**, which is −5.17 dB *into* the chain on pactl's cubic scale. Restored to 100% by hand. This is the second time a restart has moved it; `assert_unity_volume` catches it in the tools but nothing catches it while listening. **Corrected 13 Aug 2026: restarts were never moving it — the volume keys were.** They target the virtual sink because it is the default, and it was watched changing 76% → 88% between two consecutive reads with no restart in between. Not a failure at all, and not something to fix: see *Volume dependence*, which had already ruled that this sink cannot be pinned to unity |
| Stage 10b changes nothing but the band it is aimed at | **current** | pass — outside 500–1300 Hz the largest third-octave change across five signals is **0.13 dB**. Measured old-against-new in one session, both graphs live at once as separate sinks |
| Stage 10b costs no headroom | **current** | pass — sample peak **−1.012 to −1.015 dBFS**, unchanged, on the four signals that reach the ceiling, and loudness moves **+0.00 LU** on all three real masters (+0.10 sweep, +0.20 square). Offline, the sweep — the only signal that has ever bound this chain — predicts **−0.396 dBTP** against a −0.398 baseline. A cut before the brickwall is free because the brickwall was already the binding stage |
| Square-wave capture peak is a capture artefact, not the chain | **current** | noted — `square100` reads −1.013 dBFS on hardware but **−1.864 offline**. The hardware peak lands at t = 1.108 s, 8 ms after audio starts: a `pw-cat` playback transient, identical in both graphs. Steady state is −2.06 (old) / −2.12 (new). Trim 0.3 s from each end before reading a level off any `pw-cat` capture |
| Stage 10b delivers what it specifies | **current** | **partial, by design and measured** — the filter is −2.81 dB over the 794 Hz third-octave but programme gets **−2.22** (hot track), **−2.05** (music2), **−1.67** (music1), **−1.33** (sweep). Stages 11–12 are dynamic and back off as the notch lowers what they see. Left at −3.0 rather than inflated to chase it, since the give-back is programme-dependent and in the useful direction |
| Stage 10c adds no distortion | **current** | pass — THD through the whole graph moves **+0.021 pp** at 400 Hz (1.049 → 1.071) and **≤ 0.001 pp** on 2650 Hz tones at −20, −12 and −3 dBFS. Intermodulation needed a separate instrument and found a real limiter knee, which is why the gain shipped is +3.0 and not the fitted +4.0 — see *What a boost costs that a cut does not* |
| Stage 10c costs no headroom | **current** | pass — sample peak **−1.012 dBFS**, unchanged, on all four signals that reach the ceiling. Worst true peak **−0.447 dBTP** (sweep) against −0.396 before, so the margin to the −0.20 ceiling *widens* from 0.196 to 0.247 dB. Loudness **+0.31** (music1), **+0.33** (music2), **+0.38** (pink); the sweep and square lose 0.08–0.10 |
| Stage 10c changes little but the band it is aimed at | **current** | pass, with one honest exception — on real programme the largest change outside 1.6–4 kHz is **0.73 dB** (music1) and **0.63** (music2), and both of those sit at 5 kHz, which is the bell's own skirt doing what it is shaped to do. Below 1 kHz nothing moves more than **0.13 dB**. The exception is `pink-prog`, which drops **0.8 dB broadband**: a stationary full-band signal makes stage 12 work harder, and that is the limiter, not the filter |
| Stage 10c delivers what it specifies | **current** | **partial, by design and measured** — ideal over the 2500 Hz third-octave is +2.88 dB; programme gets **+2.78** (music1, 97%), **+2.56** (music2, 89%), **+2.09** (pink, 73%). A boost survives the dynamic stages better than 10b's cut did, because what they take back is broadband where the correction is narrow. The sweep goes *negative* (−0.32), the same pathology 10b showed on it |
| The HF tilt correction is a shelf, not a reshaping | **current** | pass — matched −1.5 dB on `mk_3` and `mk_4` delivers **−1.43 dB at 2.5 kHz and −1.45 at 16 kHz**, flat to 0.05 dB across 1.25–16 kHz. The presence and top summaries are **unchanged** (+1.61 and −1.64 re the 1.6–10 kHz mean in every variant) — only the tilt moves |
| The tilt correction leaves bass alone | **current** | pass — **50 Hz moves +0.02 dB**, and the whole 50–400 Hz region moves +0.03 to +0.11. Confirmed on hardware through a `-TEST` sink at matched volume: **−0.03 dB over 50–400 Hz** against **−1.47 dB over 1.6–12.5 kHz**, versus −1.41 predicted offline |
| The tilt correction adds no distortion | **current** | pass, and it **reduces** it — THD identical to two decimals at 90, 400 and 2650 Hz at both −12 and −3 dBFS; SMPTE 60 + 2650 Hz IMD at −3 dBFS falls **8.18% → 4.38%** and at −6 dBFS **0.317% → 0.145%**, its value before 10c. True peak improves on all four signals. It is a cut, so this is the expected direction — measured because the constraint is explicit |
| The shipped config is what was listened to | **current** | pass — for **both** changes. The edited `files/50-speaker-tuning.conf` renders **bit-identical** (max sample difference 0.000e+00) to the variant built for the `-TEST` sink and approved by ear, checked again after every comment edit. Self-test 26/26 |
| Removing `mk_2` does not weaken the 761 Hz correction | **current** | pass — `s10res` (the pre-2-Sep bell, now the `s10r*` branch at −5.5 dB) at −3.7 dB holds 800 Hz to **+0.06 dB (music1)** and **+0.01 (music2)** offline, and **+0.25 dB** on hardware, against a re-setup repeatability of 1.4 dB. The depth was fitted to two tracks, not one; −3.6 left +0.12/+0.08 and −3.8 overshot to 0.00/−0.06 |
| Removing `mk_2` returns the low-mid it was taxing | **current** | pass — **+0.79 dB mean over 160–630 Hz** measured at the hardware monitor through a `-TEST` sink at matched volume, against +0.61 predicted offline. The uniform ~0.18 dB offset is the 20 s excerpt compressing differently from the full file |
| The `mk_2` swap's cost is known and accepted | **current** | **measured, and it is not free** — about **−0.2 dB at 40–100 Hz**, GOTT redistributing once band 2 is no longer held down. Warmth up, sub slightly down. Recorded rather than elided because it is the one thing a listener might later notice and mis-attribute |
| The 761 Hz correction reproduces across programme | **current** | pass — measured on a −5.7 LUFS master with LRA 3.2 LU, then confirmed against two trailer tracks and two synthetic signals. Split-half spread on the acoustic A/B it came from: **sd 0.77 dB, worst 2.2 dB** |
| Worst-case margin not reduced by the loudness change | **current** | pass — **0.371 → 0.463 dB**. Louder and further from the ceiling |
| Loudness on real programme material | **current** | pass — **+0.78 LU** (music1) and **+0.61 LU** (music2, dialogue at −11.25 LUFS arriving at +0.634 dBTP) |
| Offline harness predicts hardware on that change | **current** | pass — music2 true peak reproduced to the third decimal on both sides; pink ΔLU +1.24 against a predicted +1.24 |
| Net loudness against the pre-change chain | superseded | pass — pink +0.60 LU against a predicted +0.60, with true peak 0.69 dB *lower* |
| Stage 12a changes nothing but level (18 kHz corner) | superseded | pass — null residual was a pure 0.695 dB gain change on pink and sweep, to **0.02 dB** |
| Drivers not the binding constraint at the chain's own output | current | pass — **~20 dB of margin** at 800 Hz, the one frequency that compresses, on programme-level pink through the whole graph after the `g_out` 3.00 change |
| Stage 11's `Hx` centre matches where the drivers actually run out | current | pass — 800 Hz measured, `Hx` peaks at 761 Hz; threshold sits 2.6 dB conservative |
| Stage 10b is aimed at a real driver resonance | **session D, acoustic** | pass — with the source file on both devices the driver separates from the chain, and it peaks **+7.8 dB at 800 Hz** re its own 1.6–4 kHz plateau. The chain cuts 12.8 dB there and the acoustic result matches the iPhone to **−0.2 dB**. First confirmation on material 10b was not tuned on |
| Every signal under the ceiling, `g_out` 4.25 + the 2.09 dB `mk` trim + multiband stage 11 | **current** | pass — worst **−0.651 dBTP** (sweep), **0.451 dB spare**, on a seven-signal set including two real masters. True peak has **stopped being the binding constraint** — it stays flat as `g_out` rises because the brickwall pins it, and what binds now is displacement: 4.25 spends **1.16 dB** of the 2.6 dB between stage 11's threshold and the driver's measured 1 dB compression point. Confirmed on hardware at the time of the change: music1 +0.42 LU measured against +0.44 predicted, displacement +0.52 against +0.53, tilt held to 0.06 dB |
| Displacement, not peak, is what a loudness change costs | **current** | measured by `displacement_db()` in `tools/offline-chain.py`, which `--measure` and `--sweep` both print. `g_out` 4.25 was **taken 4 Sep 2026** after re-running `tools/max-level.sh` as its own comment required: the driver's 800 Hz 1 dB point came back at **−8.05 dBFS** against the −8.1 recorded, so the margin is the same one the figure was derived from. About **1.0 dB of the 2.6 dB is left**, and the next step needs a new measurement rather than this one |
| The external `lkahead` fix is live, not just written | **current** | pass — read back off the running `effect_input.tuned-wired` node: **`x2mbc:lkahead = 0.0`**, 14/14 controls matching the config. This is the *only* check that could confirm it: the harness is blind to port defaults, so the file saying `0.0` proves nothing on its own |
| The installed external config differs from the repo, and should | **current** | pass — `52-external-tuning.conf` is **generated** per device class by `gen-external-chains.py`, so the installed file carries two chains and two `x2mbc`. The template at `/usr/local/share/speaker-dsp/` is byte-identical to the repo, and **both** generated chains carry `lkahead = 0.0`. A plain `diff` against `/etc` will always look wrong here |
| An external chain with no device parks on the built-in speaker | **current** | pass, **by design** — both tuned chains link to `HiFi__Speaker__sink` when nothing external is connected. That is [52-external-target.lua](files/52-external-target.lua) working: without it PipeWire routes to the default sink, which is the *other* tuned sink, and the stream is processed twice by two differently-tuned chains |
| The external chain's audio path is confirmed end to end | — | **not run** — needs a connected external device. With none present its output lands on the internal speaker through a non-representative route, and that chain has no excursion stage. Controls are confirmed live; the audio path is not |
| Stage 10c dynamic rebuild is the same filter when disarmed | **current, offline** | pass — at `cr` 1.0 with branch gain 0.4125 the parallel construction renders **identical LUFS, sample peak and true peak on all five signals**, and the bell node itself nulls at **−99.4 dB rms**. The identity `dry + k·bandpass ≡ bq_peaking`, `k = 10^(G/20)−1`, `Q_bp = 10^(G/40)·Q_pk`, holds to **9.6e-15 dB** analytically |
| A null test cannot be run through the limiter on a full-scale sweep | **current, offline** | **noted, and it is not a defect** — the disarmed rebuild nulls at −111 to −115 dBFS on all real programme but only **−49.2 dBFS on the sweep**, all of it after t = 18 s, which is 2.6 kHz on a log sweep. A −99 dB perturbation at the bell flips gain trajectories in stages 11–12. Every *metric* is unchanged, so the residual is trajectory jitter, not a level error. Read metrics, not nulls, downstream of a limiter |
| Stage 10c dynamic beats the static bell on presence AND distortion | **current, offline + hardware** | pass — the point of the change. `b2500` on music1 **10.18 → 10.91 dB** (+0.73, i.e. 77% of the fitted +4.0's delivery) while SMPTE IMD at −3 dBFS falls **5.202% → 4.053%** and at −6 dBFS is unchanged at 0.075%. The static +4.0 buys +0.95 dB for **0.323%** at −6 dBFS, 4.3× worse. **Not every armed row passes**: `al` −18 reads 5.330%, worse than the filter it replaces, which is why the shipped value sits two steps back from it |
| The dynamic bell is keyed on 2.6 kHz, not on the bass | **current, offline** | pass, and it is why no cross-band ducking is introduced — measured branch level (5 ms RMS): the two-tone stress signals sit at **−15.3 and −12.3 dBFS** where music1's p99 is −19.7 and music2's is −14.8. A detector that only ever looks at 2.6 kHz already separates the stress case from programme by 5–12 dB, so `al` = −20 dBFS reaches it without a bass sidechain |
| The dynamic bell changes nothing but the band it is aimed at | **current, offline + hardware** | pass — on hardware, worst change **below 1 kHz is 0.08 dB** (music1) and **0.04** (music2), against an offline prediction of exactly 0.08 and 0.04. The lift itself reads +0.73 (music1) and +0.34 (music2) at 2500 Hz, offline and hardware agreeing to **0.00 and 0.01 dB** |
| The dynamic bell does not pump | **current, offline** | pass — README's gain-modulation instrument on music2 pushed to −6.8 LUFS and clipped, 2–4 kHz, 5 ms envelopes: sd **2.923 → 2.968**, p95−p5 **8.890 → 9.106**. 2.4% more spread, against the 2% the static +4.0 was accepted for — and this buys 29% *less* IMD, which that did not |
| The dynamic bell costs no headroom and no THD | **current, offline** | pass — true peak **−0.996 → −0.996** (music1), −0.917 → −0.903 (music2), −0.789 → −0.791 (sweep); sample peak unchanged. THD 90 Hz **7.05 → 7.05%**, 400 Hz 1.38 → 1.40, 1 kHz and 2650 Hz unchanged. Latency unchanged: two biquads and a mixer are 0, and `compressor_mono` at `sla = 0` measures **0.00 ms** |
| The dynamic rebuild loads in the real filter-chain module | **current** | pass — isolated `pipewire` daemon, `PIPEWIRE_DEBUG=3`: `loaded module libpipewire-module-filter-chain`, all twelve new links resolved by name, **zero errors** and no leftover `s10pres`. Then confirmed live: every control read back off the running `-TEST` node matches the config, `sla` included |
| The offline harness predicts hardware on the dynamic stage | **current** | pass, **after fixing the harness** — it fed `*_mono` plugins a duplicated stereo pair, worth 0.316 dB on a compressor. Before the fix the dynamic chain mispredicted by 0.28 dB at 2500 Hz; after it, hardware and offline agree to **0.00 dB in every third-octave band** and **−81.5 dBFS** sample residual. This also revises the 0.04 dB figure under *offline-chain matches hardware*, which was this bug all along |
| A capture pair must be alignment-gated before it is read | **current** | **noted** — one `pw-cat` pair this session cross-correlated at **0.137** and produced a spurious **0.66 dB at 50 Hz**. Re-captured it aligned at **1.000** and the same band read 0.04. Check the normalised correlation before reporting any band table taken from two separate playbacks |
| Stage 10c closes the gap it was built for | **session D, acoustic** | pass — **+0.2 dB** at 2500 Hz and +0.5 at 3150 against the iPhone. Read as "matched": both are inside the 1.4 dB re-setup repeatability, not resolved to 0.2 dB |
| The 400–630 Hz excess is not a defect | **session D, acoustic + listening** | pass, and **tested** — the iPhone reads 6–12 dB quieter there, but the driver has no resonance at 500 Hz and both curves are clean rolloffs differing only in knee. A −5 dB bell at 500 Hz Q 1.6 was built as a separate `-TEST` sink, verified end to end (delivering −2.9 dB acoustically, nothing above 1.25 kHz moving, no headroom cost) and A/B'd. **The uncut chain won.** Do not re-propose it |
| The chain is time-coherent | **session D, offline** | pass — group delay flat within **2.2 ms** from 50 Hz to 12.5 kHz on a −46 dBFS impulse, the one excursion being −1.3 ms at 800 Hz where 10b's notch is. Impulse energy spreads 0.1 ms |
| No cross-band ducking | **session D, offline** | pass — midrange gain against bass content is **r = −0.04** (0.1 dB per 10 dB). The bass band compresses itself at r = −0.79, which is its job. Gate per band: on a broadband gate this reads a spurious 14–17 dB swing |
| The harmonic branch is inaudible in band power on programme | **session D, offline** | pass — on a bass-heavy EDM master, the fourth source tested, muting stages 5–8 moves 490–1008 Hz by **+0.09 dB** at worst. See *What the harmonic branch actually contributes* |
| The 5–6.3 kHz dip is not an EQ target | **session D, acoustic** | closed — three lid angles, everything else held. 5 kHz moves **9.0 dB** across them, more than the dip, while two of the three agree to 0.1 dB. That ambiguity is unresolvable with a mic that cannot move independently of the drivers, and does not need resolving: no fixed filter can correct a band geometry moves by 9 dB |
| How much of an acoustic result is the geometry, not the speaker | **session D, acoustic** | measured — **±1.6 dB** across 200 Hz–2.5 kHz between two ordinary lid angles, **±3.4 dB** across the full range, **±6.1 dB** above 4 kHz. Independent agreement with the 1.4 dB re-setup repeatability. This is the bar a finding clears before it is a property of the speaker |
| A 5.1 source reaches the speakers intact | **current** | pass — PipeWire downmixes upstream of the graph, matrix measured exactly: fronts at **unity**, FC and surrounds **0.7071**, LFE **0.3536**, no normalisation. Nothing fails, nothing is dropped. See *Channel count is pinned too* |
| The downmix gain is not a headroom hazard | **current** | pass — worst case **+8.84 dB** coherent, **+3.27 dB** uncorrelated, landing pre-graph. Harmless because streaming arrives at −21 to −23 LUFS, in the flat voicing region, ~7 dB below the material this chain was tuned on |
| The level-dependent voicing settles | **current, offline** | measured — fixed to **0.02 dB below −26 LUFS** at the graph input, within 0.4 dB below −20 LUFS, all movement above that. Extends the 93/88/79% table, which stops exactly where the curve flattens |
| Sink volume is pre-graph — third, independent proof | **current** | pass — hardware and offline chain gain agree to **0.04 dB at 60 Hz and 0.00 dB at 200 Hz**, but only with the sink's 94% (−1.61 dB) inserted *between* the two taps. Neither the 50% reading nor the give-back test is involved |
| Capture chain not the source of the measured distortion | current | pass — mic 20 dB below its own ceiling at the loudest point; a constant probe tone held to **0.18 dB** while the test tone lost 2 dB |
| `sudo sh install.sh uninstall` reverts cleanly | — | **not run** — needs sudo. Its five removal paths were checked against what is on disk and cover it exactly, with nothing left behind |

The null baseline in `tests/captures/` was taken through the skeleton rather
than through the original pass-through, so it proves "nothing changed since
the skeleton" rather than "the skeleton matches the pass-through". The latter
is what the ±0.01 dB level check above establishes instead.

## Open questions

Two of the three that used to be here are answered, and are kept as answers
rather than deleted so that the reasoning behind the values is not lost.

- ~~**Measured `fc` and `Qtc`**~~ — **resolved.** 761 Hz, Qtc 2.63 from peak
  height, from the sweep. Stage 2 is live and transforms 761 Hz Q 2.63 → 650 Hz
  Q 0.707. See "Measured on this machine".
- ~~**`f1`**, the post-transform usable floor~~ — **resolved at 350 Hz**, up
  from the 200 Hz placeholder, because the drivers are 20 dB down by 251 Hz and
  subbands centred at 50/90/150 Hz were feeding the harmonic generator from a
  region with no output in it. Subband centres rescaled with it to
  122.5/175/252 Hz.
- ~~**`x_max`** for the excursion limiter~~ — **not resolved, and no longer
  needed.** `x_max` in millimetres is still unknown and no datasheet exists for
  these OEM drivers. But the number stage 11 actually wants is not a
  displacement, it is *the drive level at which the driver stops delivering*,
  and that is measurable from outside: 800 Hz, −8.1 dBFS for 1 dB of
  compression, by `tools/max-level.sh`. Stage 11's `al = 0.708` engages 2.6 dB
  below it. The threshold is no longer a matter of taste. See "What the drivers
  actually take".

Outstanding work, as distinct from unresolvable questions:

- ~~**`g_out` and stage 12a are not confirmed on hardware**~~ — **done.**
  `g_out = 3.00`, `th = 0.8900` and the 22 kHz band limit are all confirmed by
  live-switched A/B, on a set that now includes two real masters.
- **A third music track.** Two are in `tests/material/` now — `music1`, trailer
  music at −14.76 LUFS, and `music2`, dialogue over music at −11.25 LUFS
  arriving at +0.634 dBTP, which is the hardest thing here. Three is still the
  useful number, and a track with sustained deep bass is the gap: both current
  tracks are from the same trailer, so they share a mastering chain and are not
  really two independent samples. Note `tests/material/` is gitignored, so these
  live only on this machine. **Partly addressed by session D**, which ran on a
  −6.33 LUFS sustained-deep-bass EDM master from an unrelated mastering chain —
  the exact gap named here — but played from `~/Music`, so it is a third
  *sample* and not yet a third *fixture*.
- ~~**Whether `g_out` 3.40 is worth taking.**~~ — **taken, 12 Aug 2026.** It
  was left as a listening decision about limiter density that nothing in
  `tools/` could make. What settled it was not a tool but a *reference*: an
  acoustic A/B against an iPhone 13 on the same programme through the same
  mic, which reads about **3.5 dB denser** than this chain (400 ms level
  spread p90−p10, 300 Hz–6 kHz: phone 6.1, chain 9.6, source 9.6) while
  measuring no quieter. Density was the thing to buy. Taken together with the
  `mk_2`/`mk_3` voicing from the same measurement — see *Voicing against a
  reference speaker*.
- **`sudo sh install.sh uninstall` has never been run.**

### Volume dependence — decided: the chain sees post-volume audio

US12342139B2 selects different transform and compressor parameters per volume
level, because a static chain is only correct at one drive level.

**Measured, not inferred.** Setting the virtual sink to pactl's "50%" drops the
level at the hardware sink's monitor — which is downstream of the whole graph —
by 18.08 dB. pactl's percentage is a cubic scale, so 50% is 0.125 linear =
−18.06 dB.

> **That proof does not work, 13 Aug 2026.** The conclusion is right and the
> evidence was not: a volume applied *after* the graph lands ahead of the
> hardware monitor too, and would have produced the same 18.08 dB. The
> observation cannot tell the two apart.
>
> What does tell them apart is **give-back on loud programme**. A post-graph
> volume delivers exactly its own attenuation, always. A pre-graph one does not,
> because the dynamics stop working as hard. At 60% (−11.14 dB) on a −6.3 LUFS
> master the chain's output fell only **6.91 dB** — 4.2 dB returned by GOTT and
> the brickwall. That is only possible upstream of them. The 50% reading was
> taken at a level too low to engage the dynamics, where a pre-graph volume does
> pass through exactly; both readings are correct and only the loud one is
> diagnostic.

Keeping a single GNOME entry means that sink is the user's volume control, so
it cannot be pinned to unity: the chain necessarily sees post-volume audio.
That rules out strategy (a) and settles the question by choice rather than
leaving it open.

The consequence to design around: **tune at one representative listening
level.** Stages 7, 10 and 11 are level-dependent, so their thresholds are only
correct near the level you set them at. Note the level you tuned at in the
config next to the thresholds.

**How much it actually moves, and which level is representative.** Measured on a
−6.3 LUFS master, each column referenced to its own 1.6–10 kHz level so this is
shape and not loudness:

| re 1.6–10 kHz | 93% | 88% | 79% |
|---|---|---|---|
| 80 Hz | +0.88 | +1.55 | **+2.78** |
| 200 Hz | +0.58 | +0.83 | +0.93 |
| 800 Hz | −0.21 | −0.53 | **−1.41** |
| 10 kHz | +0.27 | +0.49 | +0.93 |

Quieter is bassier and less mid-forward — accidental loudness compensation, in
the direction hearing wants, which is an argument for leaving it alone. Percent
maps to dB as `60·log₁₀(pct)`: 88% is −3.3 dB, 76% is −7.2 dB.

**It is not a slope — it saturates, and that table stops right where it flattens.**
Measured 13 Aug 2026 by running `tests/material/music1.wav` through
`tools/offline-chain.py` at four input attenuations, silently and with no system
change. These are **transfer** figures — output band minus input band, then
referenced to their own 1.6–10 kHz level — so only the *movement across columns*
compares to the table above, not the absolute values, which carry the chain's
own shape rather than a master's:

| transfer, re 1.6–10 kHz | −14.25 LUFS | −20.24 | −26.22 | −34.22 |
|---|---|---|---|---|
| 50 Hz | −8.05 | −4.85 | −4.47 | −4.46 |
| 63 Hz | −7.76 | −4.56 | −4.28 | −4.30 |
| 80 Hz | −5.90 | −4.26 | −4.18 | −4.17 |
| 800 Hz | −13.35 | −12.93 | −12.86 | −12.85 |
| 2500 Hz | +2.35 | +2.31 | +2.31 | +2.31 |
| **absolute gain, 1.6–10 kHz** | **+9.40** | **+10.25** | **+10.29** | **+10.29** |

Everything happens in the first 6 dB. Below about **−26 LUFS at the graph input
the voicing is fixed to 0.02 dB**, and below −20 LUFS it is within 0.4 dB of
fixed. The chain also stops compressing: 0.89 dB of gain returns between the
first two columns and 0.04 dB over the remaining 14 dB.

The two tables agree where they can be compared. Over 80 Hz the first moves
**1.90 dB** across its 4.2 dB span and the second **1.64 dB** across its first
6 dB step — different material, different method, same effect. They also do not
overlap: the first spans −8.2 to −12.4 LUFS at the graph input, the second
−14.25 to −34.22. Together they cover −8 to −34 LUFS, and the movement is all
above −20.

The practical consequence is that **the representative-level caveat applies to
music and to almost nothing else.** Anything mastered quieter than about
−26 LUFS — film, television, streaming video, see *Channel count is pinned too* —
reaches the graph in the flat region and gets one fixed voicing, so a measurement
taken there needs no level caveat at all.

**This machine is listened to at 76–88%, and every acoustic measurement in this
file was taken at 100%.** That is a caveat on all of them: the voicing measured
here is 1–3 dB less bassy in the bottom two octaves than the one actually being
judged by ear. When a measurement and an impression disagree by about that much
down low, suspect this before concluding either is wrong.

`tools/common.sh` now carries both rules rather than one. `assert_unity_volume`
still hard-fails, because a **level** comparison in LUFS is destroyed by a 1.6 dB
offset. `record_operating_point` never fails and prints the volume in dB into
the graph, because a **voicing** capture is only meaningful at a level someone
actually listens at — what makes that comparison valid is that every capture in
it reports the same number, not that the number is 100%.

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
| [US12342139B2](https://patents.justia.com/patent/12342139) | Increasing low frequency extension for microspeakers using a volume dependent Linkwitz transform and multiband compressor — Microsoft | Stages 0, 2, 10. The volume-dependent parameter selection is the part most easily missed. | **Implemented — static half.** Stages 0 (`Mult = 0.6983`), 2 (761 Q2.63 → 650 Q0.707) and 10 (GOTT, `g_out` 3.00) are live. The volume-dependent half is **not** implemented and was decided against: the virtual sink's volume is applied *before* the graph, so the chain necessarily sees post-volume audio and is tuned at one representative level instead. See *Volume dependence*. |
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
- `files/54-volume-memory.conf`, `files/54-volume-memory.lua` — let every
  output keep and remember its own level, and hold the hidden headphone sink
  at unity. Replaces `54-volume-sync`, which carried one level onto all of
  them.
- `files/speaker-dsp` → `/usr/local/bin/speaker-dsp`.

The physical sink node name appears in `files/50-speaker-tuning.conf`
(`playback.props.target.object`), `files/speaker-dsp` (`RAW`) and
`tools/common.sh` (`SINK_RAW`). If `pactl list sinks short` reports a different
name, all three need updating.

## Tools

Nothing here installs anything or needs root. Everything that measures reads
the config rather than a transcription of it, so none of it can quietly drift.

| Tool | What it does |
|---|---|
| `tools/offline-chain.py` | Runs the installed graph over a wav without reinstalling. `--sweep` for parameter searches, `--measure` for LUFS / peaks / THD, both reporting **displacement**, `--self-test` for 32 checks that need no hardware. |
| `tools/dsp_offline.py` | The machinery behind it: config parser, PipeWire builtins in numpy, LSP plugins through `ffmpeg -af lv2`, and the measurement functions. Imported, not run. |
| `tools/true-peak.py` | Exact inter-sample peak, and `--compare` against the two ffmpeg meters that get it wrong. Exits non-zero above the ceiling, so it can gate a change. |
| `tools/lt-coeffs.py` | Linkwitz transform coefficients for stage 2, with `--self-test`. |
| `tools/sweep-response.py` | Response curve, `fc` and `Qtc` from a mic capture. Needs `--reference` or the numbers tilt. |
| `tools/measure-speaker.sh` | Plays the sweep and captures it on Mic2. |
| `tools/imd.py` | SMPTE intermodulation, 60 + 2650 Hz at 4:1, sidebands to the 5th order. The instrument stage 10c is sized on — single-tone THD cannot see the limiter's bass-rate pumping at all. Compare only against numbers from this script. |
| `tools/max-level.sh`, `tools/max-level.py` | Drives the raw sink with sine bursts at rising levels and reads the mic, to find where the *drivers* distort. `--ref` brackets every test level with a reference one, which is what it takes to resolve 1 dB. |
| `tools/thermal.sh`, `tools/thermal.py` | The same rig held at **one** level for minutes, to find whether the driver stays there. Varies time where `max-level` varies level, so it sees voice-coil heating that every other tool here is too short to notice. The stimulus is tiled so every window has identical input, and shaped to the chain's own output spectrum, level and crest; the recovery block after a cooldown is the control, because thermal compression is reversible and drift is not. **The one measurement here that could damage a driver** — it does not stop for ten minutes. |
| `tools/make-test-material.sh` | Synthesises pink, sweep and square; `--music` ingests your own tracks. |
| `tools/null-test.sh`, `tools/null_residual.py` | Capture both paths and measure what the chain changed. |
| `tools/loudness-match.sh` | The stage 13 trim, per ITU-R BS.1770. |

The rule the harness exists to enforce: **sweep it offline, confirm the one
value you chose on hardware.** Offline is fast enough to be exhaustive and
faithful enough to trust for differences. It cannot tell you which material to
test, and that is where every wrong answer in this file came from.

## External (Tuning): one chain for everything that is not the internal speaker

Bluetooth speakers, earbuds, wired headphones, HDMI and USB speakers share a
second, much shorter chain: `files/52-external-tuning.conf`. The internal chain
is untouched by it and the two run side by side.

### Why it is six stages and not fourteen

The internal chain is tuned to **one measured driver**. Its Linkwitz transform
comes from that driver's Fs and Q, stage 10b notches that driver's 761 Hz
resonance, and stages 3–8 synthesise harmonics to stand in for bass a sealed
micro-speaker cannot radiate. None of that transfers. Earbuds and a Bluetooth
speaker have their own responses and real low end, so those stages would not be
a correction there — they would be damage.

So this chain does not voice. It protects and controls dynamics, which are the
only things that are right on hardware you have not measured. Every GOTT makeup
is pinned at 1.0 for exactly that reason.

| stage | what | value |
|---|---|---|
| X0 | input trim | 1.0 |
| X1 | subsonic high-pass | 30 Hz, Q 0.707 |
| X2 | GOTT multiband | `sf 120/1000/6000`, `ebe = 1`, all `mk_ = 1.0`, `ru_ = 1.0` |
| X3 | band limit | 20 kHz |
| X4 | true-peak brickwall | `th = 0.8414`, `ovs = 22` |
| X5 | output trim | 1.0 |

The audible win is X4. Lossy Bluetooth codecs clip on inter-sample peaks that a
sample-peak meter never shows, and material mastered to 0 dBFS is full of them.

### Measured

Offline, on 30 s of −5.70 LUFS programme, and on hardware through a USB speaker:

| check | result |
|---|---|
| tilt (presence − bass) | **+0.34 dB** — flat, against +5.15 dB for the internal chain |
| band transfer, hardware vs offline | **mean 0.02 dB, max 0.04 dB** across 14 bands |
| sample peak / true peak | −1.500 dBFS / −1.394 dBTP, offline and hardware alike |
| THD | 0.02 % at 90 Hz, 0.00 % at 1 kHz |
| internal chain, with this loaded | −44.47 dBFS against a −44.52 baseline |

`th` was swept rather than guessed. True peak lands a consistent 0.107 dB above
`th`, and 0.8414 buys 1.4 dB of headroom for 0.25 LU — far below audibility, and
worth it because an SBC or AAC encoder can overshoot by about a decibel, which
would put the codec's own output back at clipping.

### WirePlumber smart filters link correctly and do not process

`filter.smart` is the feature built for exactly this job, and it was the first
design. WirePlumber 0.5.13 splices it correctly — `pw-link` shows
stream → `effect_input` → `effect_output` → device with no bypass link anywhere
— but **the DSP is not applied**. Found by compiling a −20 dB output trim into
the graph and capturing a 1 kHz tone off the target's monitor:

| configuration | captured | verdict |
|---|---|---|
| `filter.smart`, target via metadata | −38.05 | bypassed |
| `filter.smart`, target static in the file | −38.05 | bypassed |
| `filter.smart`, stream targeted explicitly | −38.05 | bypassed |
| no `filter.smart`, `target.object` pinned | **−58.05** | DSP runs |
| no `filter.smart` + `node.link-group`, pinned | **−58.05** | DSP runs |

Source was −38.05 dBFS, so −58.05 is exactly the 20 dB the trim asks for. The
links look identical either way, so nothing short of measuring the audio catches
this. Do not re-add `filter.smart` without repeating that measurement.

### The double-DSP hazard, and why the script is not optional

With no target resolved, PipeWire routes the external chain's playback stream to
the default sink — which is `effect_input.speaker-tuning`, the **internal
chain**. Audio would be processed twice, by two chains tuned for different
speakers. Three guards were tried:

| guard | result |
|---|---|
| `node.dont-reconnect = true` | still fell through to the internal chain |
| `node.autoconnect = false` | safe, but blocked the script's retarget too |
| placeholder `target.object` | still fell through |
| **`52-external-target.lua` sets the target** | correct target, no fallback window |

So the script is a safety component, not a convenience. `install.sh` refuses to
install the filter without it. The script never selects a node whose name starts
with `effect_` or that carries `node.link-group`, so it cannot target either
chain; verified by mis-pointing it at the internal speaker and watching it
correct itself on the next device event.

### What GNOME selects, and what `external-dsp` drives

GNOME lists the **real devices** — "OPPO Enco Buds", "Creative Stage Mini" — and
the chains are hidden. So the default sink is the device itself, and the chain
is spliced in behind it: `52-external-target.lua` moves each app stream into
`effect_input.tuned-<class>`, whose output feeds the selected device.

Nothing in `external-dsp` switches the default sink to a virtual sink. It did in
the first design, when a single "External (Tuning)" entry was what GNOME showed,
and the switch to per-class chains broke every remnant of that model without
breaking anything audible — so it went unnoticed until the commands were run:

| symptom | cause |
|---|---|
| `external-dsp on` → `Failure: No such entity` | drove `effect_input.external-tuning`, a sink that no longer exists |
| `status` → `pre-graph sink: %` and a bogus `WRONG` | volume query on that sink returned empty, and `"" != "100"` |
| `status` → `raw device, no processing` | the default sink being a real device *is* the design now; it was reading it as bypassed |
| `on` printed the tail of a note it had not started | `pactl … && echo` bound only the first of three `echo`s |
| `speaker-dsp off` on the earbuds bypassed the *internal* chain | its `external_is_active()` also tested for the vanished sink, so it never delegated |

| command | what it does |
|---|---|
| `external-dsp on` / `off` / `ab` | engage or bypass the chain **in place** — the output device never changes |
| `external-dsp status` | active chain, device, both volumes, and a stream census |
| `external-dsp devices` / `device N` | list and select; `device` sets the default sink, exactly as picking it in GNOME does |
| `external-dsp level N` | listening level, on the device, after the graph. Capped at 60 % |
| `external-dsp unity` | put every chain input back to 100 % |

Bypass raises `x2mbc:td_*` and `x4brick:th` to full scale rather than setting
`enabled = 0`, which would drop GOTT to its dry path at `g_dry = 0.0` and cost
12 dB. It is applied to **every** chain, not just the active one: bypassing only
the active one meant switching from the earbuds to the USB speaker silently
turned the DSP back on mid-comparison.

The two volumes are not interchangeable. A chain's input sink is applied
**before** the graph, so anything below 100 % starves the compressor and limiter
of the level they were sized against and switches the tuning off by stealth —
`status` reports it and `unity` repairs it. The device's volume is after the
graph, which is why the listening level lives there.

`status` also counts streams, because the failure this design exists to prevent
is silent:

```
state: Bluetooth (Tuning) -- six-stage chain
device: OPPO Enco Buds
        bluez_output.F0:BE:25:17:71:00
  level (device, after the graph):    55%   (max 60)
  chain input (before the graph):    100%   correct
  streams in the chain:                1
```

A non-zero `streams bypassing it` means `52-external-target.lua` did not
redirect and audio is reaching the device untuned — which is otherwise only
detectable by ear, on a chain deliberately tuned not to be audible.

### Stage XV: the voicing, and why it is the only stage set by ear

The five protective stages are why the chain is inaudible, and for a long time
that was the whole answer. Measured on 30 s of −10.7 LUFS programme with peaks
at −0.1 dBFS, tuned against the exact settings `external-dsp off` applies:

| | tuned | bypassed | difference |
|---|---|---|---|
| loudness | −11.09 LUFS | −10.82 LUFS | **0.27 LU** |
| true peak | −1.489 dBTP | +0.011 dBTP | 1.5 dB |
| every ⅓-octave band, 50 Hz–16 kHz | within 0.8 dB, most within 0.15 dB | | |

0.27 LU is not audible — roughly 1 LU is the threshold with instant switching,
and an A/B with a gap is harder still. Splitting it: the limiter accounts for
0.25 LU, GOTT for 0.12. That is the chain working correctly. It is insurance
against inter-sample clipping over a lossy codec, not an effect.

So stage XV exists to give it something to say. It **ships flat** — a fresh
install is identical to the chain before the stage existed, verified offline to
the same −11.09 / −1.500 dBFS / −1.489 dBTP.

| band | filter | why |
|---|---|---|
| bass | low shelf, 150 Hz, Q 0.707 | boom / weight |
| mid | peaking, 1 kHz, Q 0.9 | body, vocal forwardness |
| presence | peaking, 3.5 kHz, Q 1.2 | clarity, consonants |
| treble | high shelf, 8 kHz, Q 0.707 | air / sibilance |

It sits between X1 and X2, so GOTT still controls whatever it boosts. Placement
was measured rather than assumed: moving it after GOTT changes a +4 dB bass
shelf's delivered gain from +1.70 to +1.88 dB, which does not buy the loss of
protection.

The bass corner was swept, since a shelf's corner decides how much of the boost
lands as bass and how much as mud:

| corner | bass 50–125 Hz | low-mid 160–400 Hz |
|---|---|---|
| 110 Hz | +1.70 | −0.02 |
| **150 Hz** | **+2.10** | **+0.36** |
| 200 Hz | +2.25 | +0.93 |
| 250 Hz | +2.27 | +1.45 |
| 300 Hz | +2.25 | +1.87 |

Authority saturates by 200 Hz; everything past that is added to the low-mids.

**Set dB and delivered dB are not the same number**, because a band average is
diluted by the shelf's own transition and by X1 removing the bottom. For +4 dB:

| band | set | delivered | bleed |
|---|---|---|---|
| bass | +4 | +2.10 | low-mid +0.36 |
| presence | +4 | +2.55 | top +0.76 |
| treble | +4 | +1.92 | presence −0.03 |

Still well above the ~1 dB that is audible, which is the point.

#### No input-trim compensation, though it was built first

The expectation was that boosts would make X4 work harder and pump, so an
automatic input trim was added to hold the peak level constant. Measured, that
was wrong. Sweeping the bass shelf from 0 to +15 dB:

| bass | LUFS-I | LRA | sample peak |
|---|---|---|---|
| +0 | −11.0 | 11.9 LU | −1.5 dBFS |
| +3 | −10.2 | 11.9 LU | −1.5 dBFS |
| +6 | −9.5 | 12.4 LU | −1.5 dBFS |
| +9 | −8.8 | 12.4 LU | −1.5 dBFS |
| +12 | −8.2 | 11.9 LU | −1.5 dBFS |
| +15 | −7.6 | 12.3 LU | −1.5 dBFS |

Loudness range never collapses and the peak never moves — the limiter holds
without squashing, which is what it was sized to do. Compensating cost 4.7 LU of
level to move the tilt by 0.12 dB, so it was removed. The ±12 dB clamp in
`external-dsp eq` is a typo guard, not a safety limit.

**That sweep was measuring the wrong thing, 1 Sep 2026.** LRA and sample peak
are both blind to intermodulation, and intermodulation is what a bass boost
into a limiter actually costs. The peak really does not move — true peak sits at
−1.48 dBTP flat and under every boost tested, so the table above is not wrong,
only incomplete. SMPTE 60 + 2650 Hz at 4:1 through this chain, bass shelf only,
by `tools/imd.py`:

| bass shelf | IMD −6 dBFS | IMD −3 dBFS | preset that sets it |
|---|---|---|---|
| +0 dB | 0.000 | 7.604 | `flat` |
| **+3 dB** | **5.979** | 14.383 | **`warm`** |
| **+5 dB** | **11.327** | 17.650 | **`bass`** |
| +6 dB | 13.142 | 19.115 | — |
| +12 dB | 21.940 | 25.214 | the clamp |

Two shipped presets sit in that table. Size it honestly before acting on it: the
signal is deliberately bass-dominant, and on real stressed programme a +6 dB
shelf costs **6.0%** more gain modulation (p95−p5 12.464 → 13.213 over 2–4 kHz),
not 13%. It is a stress result, the same way the internal chain's two-tone knee
is. But it is closer to ordinary use here than there — earbuds, the `bass`
preset and bass-heavy material are the same case, and that case *is* a dominant
low sine into a limiter.

**The presence bell is clean by the same instrument**: +6 dB leaves IMD −6 dBFS
at 0.000 and IMD −3 at 9.113, and even +12 dB only reaches 10.237. So the
problem is the shelf, not the voicing surface. If the clamp is ever tightened,
tighten bass alone.

**What was NOT done, and why.** The obvious move is the internal chain's stage
10c treatment — rebuild the shelf as a parallel branch and compress it. It does
not transfer. The identity that makes that exact for a bell,
`dry + k·bandpass ≡ bq_peaking`, has no shelf counterpart: fitting
`1 + k·lowpass` against `bq_lowshelf` at 150 Hz leaves **1.2 dB** of shape error
at +3 and **1.9 dB** at +6, against machine precision for the bell. A dynamic
shelf here would need `mb_compressor` in Boost mode on a sub-120 Hz crossover
band, which replaces a shelf with a band and re-opens the "a band makeup cannot
be aimed" objection that stage 10c was built to avoid. Left alone pending a
listening decision.

#### Why this one is by ear

Every other stage in this repo is measured. This one cannot be: voicing needs a
target, an earbud's target needs an ear coupler, and this setup does not have
one — a phone mic cannot sit where the ear canal is, and the room cannot measure
below 125 Hz anyway. Presets exist because cheap true-wireless earbuds are
near-universally V-shaped, so "unbend the V" is a better first guess than flat,
but it is a guess.

```
external-dsp eq                       show the curve for the current device
external-dsp eq bass +3 treble -2     set bands live, in dB
external-dsp eq preset vocal          flat | vocal | warm | bright | bass
external-dsp eq flat                  back to no voicing
```

The curve is **live only**. PipeWire reads filter-chain controls from config at
startup and nothing runs at login to reapply them, so a restart loses it — which
is right while a curve is being auditioned. Once one is chosen it belongs in the
template as that class's shipped default, where it survives everything and needs
no machinery.

#### The external GOTT was carrying 5 ms it never used

`lkahead` was **unwritten** in `52-external-tuning.conf`, and the LV2 port
default is **5 ms**. The internal chain found the same port on the same day and
measured what it buys: nothing — LUFS and true peak identical to 0.001 dB on
every signal in the battery, `square100` included, which is the transient case a
lookahead exists for. Written as `0.0` now.

**Confirm a port default on the real module, never offline.**
`tools/offline-chain.py` cannot see this at all: an impulse through the external
chain reads **+8.58 ms either way**, because ffmpeg initialises unspecified
ports differently from PipeWire's filter-chain. The filter-chain module *does*
apply the LV2 default, and the way to prove it is to read unwritten ports back
off a live node — four unwritten GOTT ports on the internal chain each report
their TTL default exactly:

| port | live value | LV2 default |
|---|---|---|
| `kn_1` | 0.707946 | 0.707946 |
| `react` | 0.2 | 0.2 |
| `drywet` | 100.0 | 100.0 |
| `prot` | 1.0 | 1.0 |

This is a **second** divergence between the harness and the real module, after
the mono-plugin one found the same day. The rule that follows: the harness is
exact for what a config *writes*, and silent about what it *omits*.

### GOTT was running with its defining half switched off

Stage XV made the chain adjustable, and it still was not audible, because the
inaudibility was never in the voicing — it was in X2.

GOTT is an **upward and downward** compressor. The chain shipped with
`ru_* = 1.0`, which is the port's **minimum**: a 1:1 upward ratio, meaning do
nothing. The plugin's own default is 4.0. Downward ran at `rd = 2.0` against a
default of 6.0, and every makeup was pinned at 1.0. Measured contribution on
programme: **0.12 LU**. The upward half — bringing quiet detail up, which is the
reason to reach for this plugin rather than any ordinary compressor — was off.

Turning it on, measured on 30 s of −10.7 LUFS programme:

| preset | LUFS-I | LRA | THD 90 Hz | vs protect | tilt |
|---|---|---|---|---|---|
| `protect` | −11.0 | 11.9 LU | 0.01 % | +0.0 LU | +0.30 dB |
| **`gentle`** | **−8.9** | **11.3 LU** | **0.10 %** | **+2.1 LU** | **+2.41 dB** |
| `medium` | −8.4 | 10.4 LU | 0.21 % | +2.6 LU | +4.14 dB |
| `dense` | −7.9 | 9.4 LU | 0.44 % | +3.1 LU | +6.76 dB |
| `crush` | −7.2 | 8.4 LU | 0.75 % | +3.8 LU | +10.71 dB |

`gentle` is shipped, chosen by ear.

**The ladder is not tonally neutral, and the loudness numbers hide it.** Upward
compression lifts presence and top far more than bass, because quiet detail
lives up there while bass is already loud and is being pushed *down*:

| preset | bass | low-mid | presence | top |
|---|---|---|---|---|
| `protect` | −0.39 | −0.20 | −0.09 | −0.08 |
| `gentle` | +0.90 | +1.84 | +3.30 | +1.89 |
| `medium` | +1.13 | +2.14 | +5.28 | +4.22 |
| `dense` | +1.05 | +1.95 | +7.81 | +6.97 |
| `crush` | +0.55 | +1.07 | +11.26 | +10.04 |

So "density" is also a brightness control, and by `crush` it is a **+10.7 dB
tilt** — a different speaker, not a louder one. This was nearly shipped
unnoticed: the LUFS / LRA / THD sweep that chose the ladder cannot see it, and
`--bands` was run on the voicing stage but not on the ladder. That is the same
omission this repo already records once, where a 10.1 dB tilt survived four
tuning sessions because every tool asked "what did this one parameter move". Sample peak stays at −1.500 dBFS in every row — X4 holds, so
none of this clips however hard X2 is driven. Past `crush` it stops responding:
a `pulverise` row at ratio 12 and +12 dB makeup lands within 0.1 LU and 0.0 LU
of `crush`.

**The distortion is GOTT's, not the limiter's.** Checked by neutralising X4:
0.76 % with it and without. It is gain modulation inside a 90 Hz period, which
is inherent to compressing bass this hard and is what the "smearing" consists
of. Band-1 timing was swept to reduce it and plateaus — `ta 20 / tr 250` gives
0.75 %, `ta 30 / tr 500` gives 0.62 %, and slower buys nothing — so the
compressing presets use 30/500. For scale, an earbud driver's own THD at 90 Hz
is typically 0.5–2 %, so `dense` adds about what the transducer already
contributes.

```
external-dsp gott                 current preset, plus the table above
external-dsp gott dense           apply one
external-dsp gott protect         back to the original downward-only chain
```

#### A bypass that was 5.5 LU loud and clipping

`external-dsp off` neutralised `td_*` and `th` and nothing else. That was
correct while `ru` was 1.0 and every makeup was unity, and it became a fault the
moment either could be otherwise: raising the downward thresholds stops downward
compression and leaves the **upward** ratio and the makeup applied, while the
same bypass also neutralises X4.

Bypassing `crush` that way measured **−5.33 LUFS against a correct −10.82, with
true peak at +0.049 dBTP** — 5.5 LU loud and clipping, which is exactly the
distortion the chain exists to prevent. It would have been the first thing to
happen after choosing any preset. Bypass now neutralises `ru_*` and `mk_*` too.

The lesson generalises: a bypass built by neutralising *the controls that were
in use* silently stops being a bypass when a new control comes into use. It has
to neutralise everything that can produce gain.

### The headphone jack, and a card that can only do one thing at a time

Plugging headphones into the onboard jack showed nothing in GNOME. Two separate
causes, both in this repo's own design.

**WirePlumber had the card profile pinned.** The onboard card exposes the
built-in speaker and the headphone jack as *mutually exclusive* UCM profiles:

| profile | ports | priority |
|---|---|---|
| `HiFi (Headphones, Mic1, Mic2)` | Headphones | 8500 |
| `HiFi (Mic1, Mic2, Speaker)` | Speaker | 8400 |

The jack was detected — the Headphones port reported `available` — but
`~/.local/state/wireplumber/default-profile` carried

```
alsa_card.pci-0000_04_00.6=HiFi (Mic1, Mic2, Speaker)
```

and `find-preferred-profile.lua` prefers a remembered profile over the best
available one. Deleting that line and restarting WirePlumber made it select the
Headphones profile by itself, and it did **not** write the entry back — an
automatic selection is not a remembered one, so unplugging falls back to Speaker
cleanly. Nothing in the repo needs to maintain this; the stale pin was a one-off.

**And the card was hidden outright.** `hide-speaker-tuning.lua` hid
`alsa_card.pci-0000_04_00.6` because GNOME builds output entries from card ports
as well as from sinks, so the raw speaker reappeared as a port even with its
sink hidden. But the headphone jack is a port on that same card, so hiding the
card hid the jack too.

The card is now hidden **only while the Speaker profile is active**. On the
headphones profile the card is shown — its only output port is then Headphones,
which is exactly what should be listed — and `Speaker (Tuning)` is hidden
instead, because the built-in speaker is physically unavailable while the jack
is occupied. The profile arrives as a device *param*, not a property, so it is
read with `iterate_params("Profile")` and watched via `params-changed`;
permissions are restored with `"rwxm"` rather than only removed with `"-"`.

Nothing was needed for the audio path: the headphone sink is
`alsa_output.…HiFi__Headphones__sink`, which matches the wired class's
`^alsa_output%.` and is not the internal `HiFi__Speaker__sink`, so
`52-external-target.lua` pointed the wired chain at it unprompted. `external-dsp
status` named it `Ryzen HD Audio Controller Headphones` at GOTT `gentle` with no
change at all. Matching on a pattern rather than a device list is what made that
free.

#### A chain whose target vanishes falls into the default sink

Switching the profile revealed that `effect_output.speaker-tuning` — the
14-stage chain — was linked to the **headphone sink**, alongside both external
chains. Its `target.object` names `HiFi__Speaker__sink`, which ceases to exist
on the headphones profile, and PipeWire routes an unresolved chain to the
default sink. This is the same fallthrough that
`52-external-target.lua` exists to prevent for the external chains; the internal
one never had the guard because its target was assumed permanent.

That chain is a correction for one measured driver — a Linkwitz transform for
its Fs and Q, a notch at its 761 Hz resonance, harmonics synthesised for bass it
cannot radiate. Into headphones it is damage, not tuning. Hiding
`Speaker (Tuning)` closes the GNOME route; `speaker-dsp on` and `speaker-dsp
status` now refuse and explain rather than selecting a chain with no device
behind it.

#### Hiding it stopped it being chosen, not being restored

Making the jack visible opened a one-way door. Selecting the internal speaker
made WirePlumber switch the card to the Speaker profile to satisfy the chain's
`target.object`, which removed the Headphones port — and with the card then
hidden again there was no way back short of unplugging. Worse, WirePlumber
recorded that switch as a deliberate choice:

```
~/.local/state/wireplumber/default-profile
alsa_card.pci-0000_04_00.6=HiFi (Mic1, Mic2, Speaker)
```

A stored profile beats the best available one, so even unplugging and replugging
would not bring headphones back. That is the same trap that made the jack
invisible to begin with, re-created by one ordinary click.

**Showing the card was the wrong way to show the jack.** GNOME Settings builds
its output dropdown from **card ports**, not sink ports — that is how it can
offer a port belonging to an inactive profile — and this card carries
`[Out] Speaker` and `[Out] Headphones` together whatever profile is live. So
making the card visible put the raw `Speaker` port back in the list next to
`Speaker (Tuning)`: two entries for the built-in speaker, one of them bypassing
the DSP. It showed up as a duplicated name in both the shell toggle and Settings.

The card stays hidden always, as it was. What is shown instead is the headphone
**sink**, which exists only on the headphones profile and carries one port. A
sink is listed on its own, so nothing has to expose the card:

| | GNOME's client sees |
|---|---|
| card `…04_00.6` | hidden — takes the raw `Speaker` port with it |
| `HiFi__Headphones__sink` | **shown**, as "Ryzen HD Audio Controller Headphones" |
| `Speaker (Tuning)` | hidden while the jack is occupied |
| `HiFi__Speaker__sink`, all chains | hidden |

**The jack still wins.** While the Headphones route reports `available`, the card
is put back on the headphones profile. The route is the only reliable signal:
both profiles always report `available: yes`, and the Speaker *route* reports
`unknown` on this hardware, so it is the Headphones route flipping to `yes` that
says something is plugged in.

`save = false` is the whole point of that call — it changes the profile without
writing it to `default-profile`, so nothing is remembered and unplugging still
falls back to the speaker on its own. Verified by re-creating the pin by hand and
restarting: the card recovered to the headphones profile in one switch, no
oscillation, and the stale pin was left untouched in the file.

**And a second door had to be closed.** Hiding `Speaker (Tuning)` stops it being
*chosen*; it does not stop it being *restored*. WirePlumber keeps the last
explicit choice in `default.configured.audio.sink` and reinstates it at every
start, so the internal chain came back as the default output with the jack
occupied and its own target gone. So when the jack is occupied and the default
is the internal chain, the default is moved to the headphone sink.

| after the fix | |
|---|---|
| card profile | `HiFi (Headphones, Mic1, Mic2)`, stable, one switch |
| default sink | `alsa_output.…HiFi__Headphones__sink` |
| GNOME's client sees | only `HiFi__Headphones__sink` |
| a played stream lands in | `effect_input.tuned-wired`, GOTT `gentle` |

One residual, left deliberately: `effect_output.speaker-tuning` still *links* to
the headphone sink, because a chain whose target is missing is routed to the
default sink and there is no way to refuse that without also blocking the
retarget it needs when the speaker returns. It is idle — nothing can select it,
`speaker-dsp on` refuses, and it is hidden — so it carries silence.

#### Why the same output was listed twice

Three separate faults, all introduced by the rewrite that made the card
visibility profile-aware. None was in the audio path; all three were in how
permissions reached GNOME's mixer client.

**A client is not in `clients_om` when its own `object-added` fires.** The
original script passed the new client straight to `hide(client, node)`. The
rewrite replaced that with a `refresh()` that *iterates* the manager — so the
client that had just connected was skipped, and every client appearing after
start-up saw the whole graph: all three chains, the raw speaker, and the card
with its `Speaker` port. Restored to applying per client, with iteration kept
only for the case where an object appears and every existing client must be
updated.

**PipeWire reuses client ids.** Permission writes were made idempotent to stop
an event storm — `refresh()` runs about twenty times while the graph settles, and
each redundant write is a `new`/`remove` pair on the client — but the cache was
one flat table keyed `client:object`. A new client inheriting a retired id hit
the previous client's entry, the hide was skipped as already applied, and that
client saw everything. Reproducible and unmistakable once measured:

| fresh client, after a WirePlumber restart | sinks visible |
|---|---|
| t+3 s | 1 — correct |
| t+6 s and every later one | 4 + both cards |

The cache is now per client and cleared on `object-removed`.

**Deciding visibility from the profile made it flicker.** The profile changes
twice during a switch and the jack does not, so `Speaker (Tuning)` was granted
and revoked mid-transition — each one an add/remove in GNOME's list. It is keyed
off the jack now.

Measured after the fix: every client at every timing sees one output and no
onboard card, and an idle client receives **zero** events where it previously
received a storm.

Worth recording separately: two of the three only appear *after* start-up, so
any check made immediately following a restart passes. The first client is
always correct.

#### Plugging a jack changes routes, not the profile

Replugging headphones left the card on Speaker and GNOME still on the speaker.
Three faults behind it, all in the same script.

**The profile watcher listened for the wrong param.** `params-changed` was
filtered to `"Profile"`, but plugging a jack changes **Route** / **EnumRoute** —
the profile is a *consequence*, not the event. It appeared to work the first
time only because WirePlumber switched the profile on its own; once a remembered
profile kept the card on Speaker, nothing ever noticed the jack. It now listens
for `Route` and `EnumRoute` as well.

**Visibility keyed off the jack left a gap with no output at all.** With the jack
in but the card still on Speaker — exactly what a remembered profile produces —
`Speaker (Tuning)` was hidden because the jack was in, the headphone sink did not
exist because the profile was Speaker, and the raw speaker is always hidden.
GNOME was served **nothing selectable**. It is now decided by whether
`HiFi__Speaker__sink` *exists*: whichever profile is live, exactly one of the two
sinks is there, so exactly one entry is offered and the gap cannot occur.

**The saved default sink is restored late.** `release_internal_default()` ran
only when the metadata object appeared, and WirePlumber restores
`default.configured.audio.sink` well after that. So the card was corrected to
headphones and GNOME was offered the headphones while the actual default stayed
on the hidden internal chain — "plugged in, still on speaker". It now watches the
value, not just the object.

Recovery verified from the exact failing state — profile pinned to Speaker,
default sink saved as the internal chain, jack in:

| | after restart |
|---|---|
| card profile | `HiFi (Headphones, Mic1, Mic2)` |
| default sink | `alsa_output.…HiFi__Headphones__sink` |
| GNOME served | one output, "Ryzen HD Audio Controller Headphones" |
| a played stream | `effect_input.tuned-wired`, GOTT `gentle` |

#### Listing both, and why the entries are the chains rather than the devices

The card can only run one of speaker or headphones at a time, and the first
design reflected that by hiding `Speaker (Tuning)` while the jack was in. That
is not what was wanted: both should be listed, and the choice left to the
listener.

The two entries are the two **virtual chains**, not the two devices:

| entry | node | selecting it |
|---|---|---|
| Speaker (Tuning) | `effect_input.speaker-tuning` | moves the card to `HiFi (Mic1, Mic2, Speaker)` |
| Headphones / Wired (Tuning) | `effect_input.tuned-wired` | moves the card to `HiFi (Headphones, Mic1, Mic2)` |

It has to be this way round. The real headphone sink exists *only* on the
headphones profile, so it cannot be the thing you switch **back** to once the
card has moved to the speaker — the entry would have vanished. The chains always
exist, so both are always listed and the switch works in both directions. The
real headphone sink is hidden behind `tuned-wired`; listing both would be the
duplicate again.

Nothing is forced any more. An earlier version put the card back on the
headphones profile whenever the jack was occupied, which made choosing the
speaker a one-way door. The profile now simply follows the selection, with
`save = false` so no remembered profile is written — a remembered profile is
what stops jack detection working after a replug.

The wired class was renamed from "Speaker / Headphones (Tuning)" to
"Headphones / Wired (Tuning)": beside "Speaker (Tuning)" the old name read as a
duplicate of it.

### GOTT's upward half was off again, one port along

Reviewing the external chain against what the plugin can actually do, 22 Aug
2026. The chain read as though upward compression was running. It was not.

```
shipped                        LUFS -11.36   TP -1.494
upward EXPLICITLY off (ru=1)   LUFS -11.36   TP -1.494
```

`tm_*` — **Minimum threshold**, the floor of the upward window — was never set,
so it took its default of `0.03162`, which is exactly the `tu_*` the chain
writes. Upward compression acts only *between* `tm` and `tu`. Zero-width
window, nothing happens.

That is the same trap as `ru = 1.0` being the port's minimum rather than
neutral, one port along, and the second time this plugin has hidden its
defining half behind a default. Neither is visible in the config — only in a
measurement.

**And opening the window is not the fix.** Upward gain lands on whichever band
is quietest, and on programme that is nearly always the top:

| setting | LUFS | tilt |
|---|---|---|
| shipped (inert) | −11.36 | **+0.87** |
| `tm = 0.001` | −11.70 | **+8.52** |
| `tu` tapered per band | −11.61 | +1.69 |
| …and `ru = 1.5` | −11.62 | +1.45 |

None was louder. So the chain now does downward compression only, and the
density ladder in `external-dsp` carries `ru = 1.0` on every rung. That is not
a loss — more than half the tilt the ladder was recorded as having *was* the
upward compressor, bought for between 0.08 and 1.10 LU:

| preset | as shipped | with `ru = 1.0` |
|---|---|---|
| protect | −14.85, +0.19 dB | unchanged (`ru` was already 1) |
| gentle | −11.36, +0.87 dB | identical — it was inert |
| medium | −10.04, +2.98 dB | −10.12, **+1.73 dB** |
| dense | −9.06, **+6.50 dB** | −9.30, **+3.00 dB** |
| crush | −7.63, **+10.41 dB** | −8.73, **+4.45 dB** |

A chain that does not know the device it is driving cannot spend 6 dB of
balance on 1 LU.

### Envelope boost, the one free port

`envb` weights GOTT's **detector** so the four bands are judged on equal
footing rather than by raw energy, which programme material puts almost all of
in the bass. Unset — `None` — until now. Setting it to `2` (Pink MT):

| track | tilt `envb=0` → `envb=2` | LUFS |
|---|---|---|
| music1 | +0.87 → **+0.45** | −11.36 → −11.21 |
| music2 | +2.82 → **+1.37** | −9.28 → −8.98 |
| pink-prog | +0.19 → **+0.08** | −8.39 → −8.88 |

Flatter on all three, ceiling held at or below −1.436 dBTP throughout, no
latency, one port.

**Confirmed on hardware.** Both changes applied to the live chain with `pw-cli
set-param` and captured at the headphone sink's monitor, pink noise so the
analysis window does not matter:

```
TILT (presence - bass)   before -15.18   after -15.29   change -0.10 dB
offline predicted                                              -0.11 dB
```

Agreement to 0.01 dB. A first attempt with *music* could not resolve it — the
two captures differed by a uniform 0.8 dB across every band, which is capture
alignment, not spectrum. Use a stationary stimulus for a difference this small.

### Why `envb` does not transfer to the internal speaker

Asked straight after the external change landed: if Pink MT is flatter there,
should the internal chain have it too? Tested offline, then by ear. **No** — and
the reason is the reason the two chains exist separately at all.

The internal chain already runs `ru_* = 1.0`, so the upward-window trap above
was never present there. `envb` was the only transferable item, and on paper it
looked like the same win — flatter on every music track, peaks untouched,
distortion identical:

| material | LUFS | sample pk | tilt | THD |
|---|---|---|---|---|
| music1 | −10.57 → −10.36 | −1.012 → −1.012 | +6.08 → **+5.16** | — |
| music2 | −8.50 → −8.32 | −1.012 → −1.012 | +8.07 → **+6.22** | — |
| pink-prog | −4.94 → −4.94 | unchanged | +7.58 → +7.58 | — |
| sine 90 Hz | — | — | — | 0.13% → **0.13%** |
| sine 1 kHz | — | — | — | 0.07% → **0.07%** |

`square100` was the tell: **+2.49 LU**. Weighting the output spectrum by 1/f⁴,
since cone displacement for constant drive falls as 1/f²:

| material | tilt change | **displacement change** |
|---|---|---|
| music1 | −1.11 dB | **+1.39 dB** |
| music2 | −1.85 dB | **+2.41 dB** |
| square100 | −3.82 dB | **+4.26 dB** |

`envb` de-emphasises bass in GOTT's *detector*, so the bass band is compressed
less and more of it comes out. On a Bluetooth speaker with a real woofer that is
a flatter response. On a sealed micro-speaker resonating at 761 Hz it is
excursion the driver cannot turn into sound — and stage 11 exists to stop
exactly that.

**The two cannot be separated, because they are the same lever.** Clawing the
excursion back with the bass band's downward compression returns the tilt in
equal measure:

| setting | tilt (music1 / square100) | displacement |
|---|---|---|
| `envb=2` | −1.11 / −3.82 | +1.39 / +4.26 |
| `envb=2`, `td_1=.05 rd_1=5` | −0.47 / +0.17 | +0.64 / −0.18 |
| `envb=2`, `td_1=.03 rd_1=6` | +1.11 / +3.66 | −1.03 / −3.56 |

The middle row lands back on baseline for both. The "tonal improvement" *is* the
extra bass.

**And it was inaudible.** Applied to the live chain with `pw-cli set-param` and
A/B'd at a matched level on the built-in speaker: no difference heard. Which is
what the displacement number predicts — the extra energy is below where this
driver radiates, so it costs excursion and returns nothing.

Nothing else on the plugin was free either. `sc_mode` (0/1/3) and `prot`
produced **bit-identical** output — the sidechain ports are inert in the
non-`sc_` GOTT variant. `lkahead = 10 ms` was a small net negative (tilt +0.23,
LUFS −0.03).

So `envb = 0` internally and `envb = 2` externally is not an inconsistency to be
tidied up later. The chains disagree because the hardware disagrees.

**Method note.** Tilt alone would have shipped this. A bass-affecting change on a
driver that cannot radiate bass must be judged on displacement, not balance —
weight the output power spectrum by 1/f⁴ over 20–500 Hz and compare. The tilt
figures in this section come from that same script's own band aggregation and
read baseline as 6.89 where `--bands` says 6.08; they are consistent with each
other, not with the rest of this file.

**That second aggregation is gone, 4 Sep 2026.** The metric is now
`displacement_db()` in `tools/offline-chain.py`, sharing `CENTRES` and
`band_power` with `--bands` so that one chain cannot have two band tables, and
`--measure` and `--sweep` both print it. Absolute values are meaningless — the
FFT scaling and `DISP_REF` land in a constant — so it is only ever read as a
difference, which is how every figure above and below already uses it. The
figures in this section predate the tool and are left as they were measured.

**Checked against them before it was trusted.** Run over the shipped chain, the
new function reproduces the spread of the displacement table in *The loudness
that bought* to **0.05 dB** on music1→music2 and **0.17 dB** on
music1→square100. `pink-prog` and `sweep` come back 1.8–2.2 dB off, and that is
the material rather than the metric: both files were regenerated on 3 Sep 2026
when the pink noise went to `sox -R` and the null test moved to the quiet sweep,
so they are no longer the signals that table was taken on. The two real masters
are, and they agree.

### Excursion protection went multiband, and the mids stopped ducking

1 Sep 2026. Stage 11 was a broadband `sc_compressor_stereo` driven by the `Hx`
displacement estimate. Whenever a bass transient crossed its threshold it pulled
**the whole spectrum** down — vocals dipped with the kick.

A cone has one displacement and it is a low-frequency quantity. Ducking 3 kHz
does nothing mechanical. That was collateral damage, not protection.

It is now `sc_mb_compressor_stereo`, split at 1 kHz, with the broadband settings
moved onto band 0 unchanged — `scs = 5` (Max), `scm = 0` (Peak), `al = 0.708`,
`cr = 6`, `at = 5`, `rt = 100`, `kn = 0.501`, `scr` and `sla` on the same
defaults the broadband plugin had. Every port name and default matches; `sct`
(Sidechain type) is the one that does not exist on the multiband, and per-band
`sce_0 = 1` (External) replaces it.

**But the settings transferring does not make it a drop-in.** Collapsed to a
single band with every control matched, the two do *not* null, and driven with
the same signal on the bench the multiband compresses far less:

| isolated, music1 at programme level | broadband | multiband |
|---|---|---|
| gain reduction | **−6.51 dB** | **−0.41 dB** |

So equivalence cannot be argued from the settings — it has to be measured *in
the chain*, where stage 11 sees a post-GOTT signal with a very different crest
factor from anything on a bench. There the two land in the same place. All
three bypass methods (`ce_0 = 0`, `enabled = 0`, `cr_0 = 1`) agree exactly:

| loudness this stage removes | broadband | multiband |
|---|---|---|
| music1 | 0.91 dB | 0.91 dB |
| music2 | 1.05 dB | 0.95 dB |
| **square100** | 1.89 dB | **3.89 dB** |

Same depth on music, twice the depth on the signal this stage exists for. That
is an *in-situ* claim and it must stay one — a bench comparison of the two
plugins says something quite different, and it is the bench that is misleading
here, not the chain.

**The split is not a tuning choice — it is where `Hx` runs out.** Band 1 was
tested driven by the same external sidechain at the same threshold and ratio 6,
and again on `sce_1 = 2` (Link). All three measured **bit-identical** to
`ce_1 = 0`:

| band 1 setting | music1 | music2 |
|---|---|---|
| `ce_1 = 0` (shipped) | −10.35 LUFS, tilt +6.80 | −8.18, +9.54 |
| `sce_1 = 1` external, `cr_1 = 6` | −10.35, +6.80 | −8.18, +9.54 |
| `sce_1 = 2` link, `cr_1 = 6` | −10.35, +6.80 | −8.18, +9.54 |
| `sce_1 = 2` link, `cr_1 = 2` | −10.35, +6.80 | −8.18, +9.54 |

`Hx` is a 761 Hz low-pass falling 12 dB/octave, so above 1 kHz its detector
never reaches threshold however it is wired. `ce_1 = 0` states what the plugin
does anyway. **Do not move the split down**: 400–1000 Hz is where `Hx` peaks and
where the driver measurably runs out of travel, so that region must stay inside
band 0.

**Protection is not weaker, it is better placed.** `Hx` applied to the chain
*output* — the displacement the cone actually sees:

| signal | `Hx` peak | `Hx` rms | 1/f⁴ displacement |
|---|---|---|---|
| music1 | +0.21 dB | +0.05 | +0.01 |
| music2 | −0.24 | −0.08 | −0.07 |
| pink-prog | −0.17 | −0.05 | −0.07 |
| **square100** | −0.04 | **−2.32** | **−2.21** |

`square100` is the case this stage exists for, and it is 2.2 dB better
protected — all of the gain reduction now lands in the band the square's energy
is in, instead of being spread over a spectrum that was not causing the
excursion.

**Two things that had to be checked before this could ship.** The crossover is
transparent when it is not working: `mode = 1` (Modern), and two renders of a
below-threshold signal null at **−109.7 dB**. And it adds **no latency** —
0.00 ms by impulse, against the broadband plugin's 0.

**`envb = 0` is load-bearing.** This plugin defaults it to `1` (Pink BT) where
GOTT defaults it to `0`, so a drop-in arrives with envelope boost already on —
and the section above measured that weighting the detector away from bass costs
this driver 1.4–4.3 dB of excursion it cannot radiate. Wrong on any stage here,
and worst on this one.

#### It returns level as tilt, and that had to be paid for

The level comes back above 1 kHz, and how much depends on how hard the material
was driving the cone:

| track | tilt change |
|---|---|
| music1 | **+0.82 dB** |
| music2 | **+1.55 dB** |
| pink-prog | +0.19 dB |

The 14 Aug listener correction took 1.41 dB of tilt *out*. Shipping this without
a trim would have quietly put most of it back — and `--bands` is the only thing
in the harness that would have caught it, exactly as recorded in *The tilt, and
why nothing here had found it*.

Note the shape of the problem: what was removed is **dynamic** and
programme-dependent, and nothing static can put it back on all material. A flat
−1.19 dB on `mk_3`/`mk_4` lands music1 within 0.03 dB and leaves music2 +0.47
and pink-prog −0.66. That residual spread is the honest cost of the change and
it is not removable — the broadband stage had been acting as an accidental
bass-triggered tilt control.

**What it is worth even at zero loudness**: `--bands` averages over the track. A
static makeup restores the average but not the *pumping*. Same average voicing,
mids that no longer move with the bass.

##### The dynamic version was built, and a compressor cannot deliver it

Attempted 2 Sep 2026, after the same audit that produced stage 10b's rebuild.
Kept here so it is not re-proposed, because the *mechanism* checks out and only
the instrument fails — which is exactly the shape of idea that gets tried twice.

**The residual is real, and larger than the figure above.** That −0.66/+0.47
was taken at `g_out` 3.40 / −1.19 dB. At the shipped 3.80 / −1.65, measured as
the tilt each track lands at against the pre-multiband chain (broadband
`sc_compressor_stereo`, `mk_3`/`mk_4` uncut at 1.1864/0.8414):

| track | tilt now | pre-change | residual | stage 11 activity |
|---|---|---|---|---|
| pink-prog | +6.31 | +7.48 | **−1.18** | 28 |
| music1 | +6.26 | +6.73 | −0.47 | 91 |
| music2 | +8.72 | +8.19 | +0.53 | 220 |
| square100 | +3.90 | +2.99 | **+0.91** | 838 |

2.09 dB across the battery, 1.71 on real programme. "Activity" is % of 5 ms
frames the `Hx` estimate spends over stage 11's threshold, times the mean
excess. **It predicts the residual: r = +0.82, and the rank order is exact.**
So the quantity that decides how much tilt comes back is not only real, it is
already wired into the graph as stage 11's own sidechain.

**Which makes the implementation nearly free.** Stage 11's band 1 — 1 kHz and
up, the same region `mk_3`/`mk_4` trim — is already in the plugin and disabled
only because `Hx` never reaches its −3 dBFS protection threshold. Give band 1
its own lower threshold, `at_1` 500 ms / `rt_1` 2000 ms so it tracks material
rather than beats, and it is "trim the top when the cone is working hard" at
zero new nodes and zero added latency.

**It passes the safety gate and still is not worth having.** Gain the chain
applies to 2–4 kHz, 5 ms envelopes — the measure that licensed 10c:

| | music1 sd | p95−p5 | music2 sd | p95−p5 |
|---|---|---|---|---|
| static payment | 3.364 | 8.434 | 3.223 | 9.383 |
| band 1 live | 3.379 | 8.460 | 3.268 | 9.541 |

No pumping reintroduced — the slow constants work. But the best any setting
reaches is **1.47 dB of spread against 1.71**, and `music2` stays the outlier:

| `scm` | `al_1` | `cr_1` | music1 | music2 | pink-prog | square100 | spread |
|---|---|---|---|---|---|---|---|
| Peak | −23 | 3.0 | +0.80 | +0.99 | −0.83 | +0.96 | 1.81 |
| Peak | −16 | 3.0 | +1.06 | +1.83 | +0.34 | +1.17 | 1.48 |
| Peak | −16 | 6.0 | +1.06 | +1.82 | +0.34 | +1.17 | 1.48 |
| RMS | −23 | 3.0 | +0.79 | +0.93 | −0.53 | +0.99 | 1.53 |
| RMS | −16 | 6.0 | +1.06 | +1.82 | +0.34 | +1.17 | 1.47 |

**Why a compressor cannot do this job.** The correction wanted is 1.18 / 2.18 /
0.47 / 2.56 dB — a **5.4× relative range on a 1–2 dB absolute amount**. A
compressor ties those two together through its ratio, and both ends of the
trade fail:

- *Slow enough not to pump* → the detector settles near the mean level, gain
  reduction saturates, and the ratio stops being a lever at all. `cr_1` 3.0 and
  6.0 differ by 0.01 dB, and Peak and RMS give the same answer to two decimals.
- *Low enough threshold to stay engaged* → differentiation returns, but tied to
  a large absolute cut. At `al_1` −30 dB `cr_1` 4.0 the spread is **3.61** and at
  −40 dB it is **7.08**, both far worse than doing nothing:

| `al_1` | `cr_1` | music1 | music2 | pink-prog | square100 | spread |
|---|---|---|---|---|---|---|
| −30 | 2.0 | −0.60 | −1.16 | −3.19 | +0.42 | 3.61 |
| −30 | 4.0 | −1.34 | −2.63 | −4.95 | +0.01 | 4.96 |
| −40 | 2.0 | −4.78 | −5.92 | −8.43 | −1.35 | 7.08 |

So the sentence above stands, and now it stands for a stated reason rather than
for want of trying: **nothing static can put it back, and nothing dynamic that
this plugin set offers can either.** Closing the last 1.47 dB needs an
instrument whose output spread is independent of its output level — a per-track
measurement, which is a daemon, which is the same wall `loud_comp` is behind.

### The loudness that bought, and what the cone paid for it

Taken in the same change, and to be read as one setting with the trim above.

True peak **stopped being the constraint**. With the brickwall pinning it, the
worst signal in the whole battery sits at −0.789 dBTP against a −0.20 ceiling
and stays there all the way to `g_out` 4.50. What costs is displacement. Held at
matched tilt, against the chain as it stood before:

| `g_out` | `mk` cut | music1 loudness | music1 displacement | music2 loudness | music2 displacement |
|---|---|---|---|---|---|
| 3.40 | −1.19 dB | −0.03 LU | +0.07 dB | +0.09 LU | +0.00 dB |
| 3.80 | −1.65 dB | +0.52 LU | +0.64 dB | +0.43 LU | +0.42 dB |
| **4.25** | **−2.09 dB** | **+0.97 LU** | **+1.16 dB** | **+0.73 LU** | **+0.79 dB** |

Roughly **1 dB of displacement per 1 LU**, and the margin being spent is the
2.6 dB between stage 11's threshold and the driver's measured 1 dB compression
point. 3.80 spends 0.5 dB of that.

**4.25 was taken on 4 Sep 2026, and the gate was run first.** The instruction
that stood here was not to take it without re-running `tools/max-level.sh`,
because that margin is measured rather than assumed. It was re-run on the same
grid, and the driver has not moved:

| | 4 Sep 2026 | as recorded |
|---|---|---|
| 800 Hz compression at full scale | **2.34 dB** | 2.35 |
| 1 kHz | 0.85 | 0.82 |
| 800 Hz 1 dB point, interpolated | **−8.05 dBFS** | −8.1 |

Everything else in the grid sits inside its own reference scatter, as it did
before. **Confirmed on hardware**, captured at the physical sink either side of
a live `pw-cli` change so that nothing else moved:

| | predicted | measured |
|---|---|---|
| music1 loudness | +0.44 LU | **+0.42 LU** |
| music1 displacement | +0.53 dB | **+0.52 dB** |
| true peak | — | **−0.991 dBTP**, 0.791 dB inside the ceiling |
| tilt | +0.03 dB | **−0.06 dB** |

Worst true peak over a seven-signal battery is the sweep at −0.647 dBTP,
0.447 dB inside the ceiling. **This spends 1.16 dB of the 2.6, leaving about
1.0 dB — and the next step is not available on this reasoning.** Half a margin
for 1 LU was the argument against 4.25 when there were 2.1 dB in hand; at 1.0 dB
left it argues harder, not less. Anything above 4.25 needs a new measurement,
not this one.

#### The tilt correction is level-dependent, and was sized in the wrong place

The `mk` cut that pays for a `g_out` step is not one number. `mk_3`/`mk_4` are
makeup gains sitting **after** per-band compression, so how much of a change in
them reaches the output depends on how hard those bands are compressing — which
depends on drive. **A cut sized at unity is a different cut at the volume anyone
listens at.**

This was found the way this file keeps saying such things are found. The −0.44 dB
the unity measurement asked for was taken, measured to hold the tilt to 0.03 dB,
written up, installed — and then reported **dull** on a listening test at 80%.
The measurement that followed agreed:

| `mk` cut | Δ tilt at 80% | Δ tilt at unity | |
|---|---|---|---|
| **−0.44** | **−0.22** (−0.25 on hardware) | +0.02 | dull where it is actually used |
| **−0.18** | **+0.03** (+0.03 on hardware) | +0.26 | **shipped** |

**You can hold the tilt at 80% or at 100%, not both.** −0.18 is the choice to
hold it at 80%, and the ear picked it before the second measurement was taken.

The argument beyond *hold it where you listen*: this chain stops compressing
below about −20 LUFS at the graph input — see *Volume dependence*. At 80% music
arrives near −20.6 and film near −33, so nearly everything played on this
machine sits in the regime where −0.18 holds the tilt and −0.44 over-corrects.
−0.44 is only right for loud music near full volume.

**Taken again 4 Sep 2026, `g_out` 5.50 → 6.50 with the cut at 3.00 dB.** Priced
against the margin the crossfade change had just given back — 2.20 dB of the
2.6 dB still in hand — this spends 0.56 dB for **+0.48 LU on music1, +0.29 on
music2**, leaving 1.64 dB. Unlike the crossfade step it is close to a *pure*
loudness change: level-matched at 80 %, every band moves less than 0.15 dB, so
what an A/B tests here is **density, not tonality**. Reported as sounding the
same, which is what licensed it. 7.00 and 7.50 measure louder still (+0.66 and
+0.82 LU against 5.50) and were **not** taken, because they were never heard — the returns
flatten while the `mk` cut keeps growing, and by 7.50 the chain would apply
+17.5 dB of broadband makeup while pulling 1 kHz+ down 3.6 dB, which nothing
here has probed for good behaviour.

**7.00 was then tried properly, and rejected on its own numbers.** Priced
against the shipped 6.50 rather than against 5.50 — which is the comparison that
matters once 6.50 is taken — the marginal step is **+0.19 LU on music1 and
+0.08 on music2**, for 0.22 dB of displacement out of the 1.64 dB left. The
`mk` cut is 3.30 dB and the voicing barely moves: level-matched at 80 %, every
band is inside 0.13 dB.

**That is the whole reason to record it.** An A/B here cannot say anything
useful in the direction it is usually run. The two steps before this were +0.56
and +0.48 LU, where "sounds the same" meant *loudness was gained for free*. At
+0.08 LU, "sounds the same" would mean *nothing was gained and cone margin was
spent* — the same verdict licensing the opposite conclusion. **A null result is
only evidence when the effect would have been audible had it been real.** The
step was reverted before it was ever written to the config.
It costs nothing to move: the change is entirely above 1 kHz, so the 1/f⁴
displacement metric does not see it (0.00 to −0.12 dB across the battery, i.e.
unchanged or slightly less), and worst true peak goes −0.651 → −0.647 dBTP.

**The general lesson, which is not about this stage.** Every acoustic
measurement in this file was taken at 100% and this machine is listened to at
76–88% — a caveat already written down under *Volume dependence* and walked past
anyway. It bites hardest on anything implemented as a makeup gain behind a
compressor, because that is where the level dependence lives. Size a voicing
correction at the level it will be heard at, and check it at both ends.

What it costs elsewhere:

- THD at 400 Hz / −3 dBFS: 1.18 % → 1.38 %. At −12 dBFS it does not move
  (0.96 % → 0.95 %). 90 Hz: 6.86 % → 7.05 %.
- **Stationary material loses**: pink-prog −0.25 LU, pink −0.41. They pay the
  `mk` cut and collect none of stage 11's return, because pink has no bass
  transients for the old broadband stage to have been ducking on. The gain is
  transient-dependent by construction — **do not tune it on noise**.
- `square100` −1.20 LU and 1.67 dB *less* displacement. That is stage 11
  working, and it is the direction that signal should move.

#### Confirmed on hardware

Both chains run side by side through the `-TEST` sink method below, same
session, same hardware, both virtual sinks at unity, captured at the physical
sink:

| | offline predicted | hardware measured |
|---|---|---|
| music1 loudness | +0.52 LU | **+0.48 LU** |
| music1 tilt | −0.46 dB | **−0.47 dB** |
| true peak | −0.996 → −0.996 dBTP | −0.996 → −1.001 dBTP |

Agreement to 0.01 dB on tilt and 0.04 LU on loudness. The band table shows
exactly the intended shape — bass and low-mid up 0.4–0.5 dB, presence flat to
0.03 dB — which is what "louder at held voicing" is supposed to look like.

### The presence lift went dynamic, and stopped having to choose

Stage 10c shipped at **+3.0 dB when its own fit wanted +4.0**, and the reason was
never the fit — it was a two-tone knee. A 60 Hz sine carrying most of the
amplitude drives stage 12 into periodic gain reduction at 60 Hz, which
amplitude-modulates everything else present, and raising 2650 Hz gave it more to
modulate. A *static* filter has to pay that margin at every level, including the
overwhelming majority of the time when no such signal exists.

**The rebuild is an identity, not an approximation.** A parallel bandpass
reproduces a peaking filter exactly:

```
dry + k · bandpass(f0, Q_bp)  ≡  bq_peaking(f0, Q_pk, G)
      k = 10^(G/20) − 1        Q_bp = 10^(G/40) · Q_pk
```

verified to **9.6e-15 dB** at 2650/1.2/+3.0. So the branch gain *is* the bell's
Gain control, and a compressor on the branch is a dynamic EQ. `Q_bp` is frozen at
the +3.0 value (1.4262) and only `k` moves; the peak gain stays exact at every
setting and the worst shape error over +1 to +4 dB is **0.113 dB**.

**It is keyed on 2.6 kHz, not on the bass**, even though bass is what triggers
the knee. Keying on bass would be cross-band ducking, which the multiband stage
11 change exists to remove — and it is unnecessary, because the branch level
already separates the two cases:

| signal | p50 | p90 | p99 | max |
|---|---|---|---|---|
| music1 | −32.4 | −24.0 | −19.7 | −16.5 |
| music2 | −25.8 | −18.7 | −14.8 | −10.8 |
| `imd60_2650_6` | −15.3 | −15.3 | −15.3 | −15.3 |
| `imd60_2650_3` | −12.4 | −12.3 | −12.3 | −12.3 |

A bare 2650 Hz sine concentrates in this bandpass where broadband music spreads,
so the stress signals read **5 to 12 dB hotter in the branch than programme
does**. A detector that only ever looks at 2.6 kHz reaches them.

`al` and `cr` swept with the branch anchored at the fitted +4.0. `b2500` is
delivered third-octave at 2500 Hz on music1; IMD is SMPTE 60 + 2650 Hz at 4:1,
sidebands to the 5th order:

| variant | `b2500` | IMD −6 dBFS | IMD −3 dBFS |
|---|---|---|---|
| +3.0 static (what shipped) | 10.18 | 0.075 | 5.202 |
| +4.0 static (the fit) | 11.13 | 0.323 | 7.536 |
| `al` −18, `cr` 2.0 | 11.09 | 0.075 | **5.330 — fails** |
| `al` −20, `cr` 2.0 | 11.02 | 0.075 | 4.656 |
| `al` −22, `cr` 2.0 | 10.91 | 0.075 | 4.053 |
| `al` −24, `cr` 2.0 | 10.76 | 0.075 | 3.548 |

Then **`cr` and `rt` were swept too, and that changes the answer.** A higher
ratio lets the threshold go back up, because it leaves quiet material alone for
longer and clamps harder once it does engage. Modulation is p95−p5 of the
2–4 kHz gain on the clipped stress fixture — the instrument a ratio change has to
answer to, since IMD does not see pumping:

| variant | `b2500` | IMD −3 | modulation |
|---|---|---|---|
| +3.0 static | 10.18 | 5.202 | 8.895 |
| `cr` 2.0, `al` −22, `rt` 150 | 10.91 | 4.053 | 9.152 |
| `cr` 3.0, `al` −20 | 10.99 | 3.900 | — |
| `cr` 3.0, `al` −18 | 11.07 | 4.695 | — |
| `cr` 4.0, `al` −18 | 11.07 | 4.388 | — |
| `cr` 4.0, `al` −20, `rt` 150 | 10.97 | 3.581 | 9.194 |
| **`cr` 4.0, `al` −20, `rt` 300 — taken** | **10.93** | **3.580** | **9.093** |
| `cr` 6.0, `al` −18 | 11.06 | 4.119 | — |

The shipped row is the only one that improves on `cr` 2.0 in **all three columns
at once**: the same presence to 0.02 dB, 12% less intermodulation, and *less*
gain modulation than the setting it replaces — 9.093 against 9.152, where the
static filter it ultimately replaces reads 8.895. A slower release buys that
last column; `rt` 150 at the same `cr` and `al` reads 9.194, the worst of the
three. True peak is unmoved at −0.791 dBTP on the sweep.

**These are not the numbers this stage was first fitted on.** The first sweep ran
through a harness bug — see *The harness was feeding mono plugins a stereo pair*
below — which flattered every aggressive row. `al` −18 looked like it passed and
does not: at 5.330 it is *worse* than the static filter it replaces, which is the
one thing this change is not allowed to be.

With `cr` fixed at 2.0, −22 was taken over −20, because −20 sat directly against
the failing row. The ratio sweep above supersedes that: at `cr` 4.0 the
threshold returns to −20 with *lower* distortion than `cr` 2.0 reached at −22.
The shipped setting delivers 79% of the fitted gain.

The delivery is level-dependent by construction, which is visible in the band
table: music1 gets **+0.73 dB** at 2500 Hz and the louder music2 gets **+0.34**,
because its branch sits further into the compressor. The lift is spent where
there is room for it.

Note the IMD figures here are from `tools/imd.py` and do not share a scale with
the ones recorded under *What a boost costs that a cut does not* — the
comparisons above are internally consistent, not comparable across sections.

#### Confirmed on hardware

Both chains live at once through the `-TEST` sink, same session, both virtual
sinks at unity, captured at the hardware sink monitor. Third-octave, new against
old:

| | offline | hardware |
|---|---|---|
| music1, 2500 Hz | +0.73 dB | **+0.73 dB** |
| music1, worst below 1 kHz | 0.08 dB | **0.08 dB** |
| music2, 2500 Hz | +0.35 dB | **+0.34 dB** |
| music2, worst below 1 kHz | 0.04 dB | **0.04 dB** |

**Read the constants on that table.** It was taken at `cr` 2.0 / `al` −22 /
`rt` 150, before the ratio sweep moved them. What it confirms is the
*architecture* — that a parallel bandpass with a compressed branch behaves on
hardware exactly as the harness says, that the delivered bell is the intended
shape, and that nothing below 1 kHz moves. At the shipped constants the same
excerpts predict **+0.74 dB** (music1) and **+0.30** (music2) at 2500 Hz, with
0.08 and 0.03 below 1 kHz — inside the 0.23 dB capture repeatability of the
music1 pair, and a 0.04 dB move on music2.

Those predictions are not hardware-confirmed and do not need to be by capture:
the same session established that this harness reproduces the installed graph to
**0.00 dB in every third-octave band**, verified again after the install. What
is *not* covered is a listening pass — no A/B by ear has been done on this stage
at any setting, which is a gap this repo has never shipped a voicing change with
before.

Sample peak on hardware is **−1.012 dBFS** on both chains, the figure the offline
harness predicts exactly. Capture repeatability, same sink twice, is **0.00 dB**
on music2 and 0.23 dB worst on music1, so music1's numbers carry that much noise
and music2's carry none.

**Gate an alignment before trusting a capture pair.** One pair in this session
cross-correlated at 0.137 and produced a spurious 0.66 dB at 50 Hz; re-captured,
it aligned at 1.000 and the same band read 0.04. Two `pw-cat` playbacks do not
start at the same offset, and a bad alignment looks like a bass anomaly.

### The resonance notch went parallel, and the dynamics turned out to have no job

Asked 2 Sep 2026, straight after an audit of what in this chain is still a
fixed number: stage 10b was the **only static tonal correction left** in either
chain. Everything else static is structural — trims, splits, the M/S matrix,
the `Hx` detector shape, the 22 kHz band limit. So it was the one candidate,
and stage 10c had just proved the pattern for converting one.

It was converted, and the conversion was worth it. The **dynamics** were not,
and that is the more useful half of the result.

#### The identity holds for a cut, and the frozen Q reaches further than it looked

Same identity 10c documents, negative `k`:

```
dry - |k| * bandpass(f0, Qbp)  ==  bq_peaking(f0, Qpk, G)
   k   = 10^(G/20) - 1        Qbp = 10^(G/40) * Qpk
```

Verified to 4.4e-13 dB at 760/3.0/−3.7 against this file's own `_rbj` — the
same order as the 3.3e-13 already recorded for it. With `Qbp` frozen at the
−3.7 dB value, peak gain stays exact at every anchor and only the shape drifts.
**Where the shape error lands is what decides how deep the anchor can go**, and
the first pass here read the wrong column:

| anchor | \|k\| | peak got | err in 500–1300 Hz | err outside |
|---|---|---|---|---|
| −3.7 | 0.3468694 | −3.700 | 0.000 | 0.000 |
| −4.5 | 0.4043379 | −4.500 | 0.101 | 0.046 |
| −5.0 | 0.4376587 | −5.000 | 0.182 | 0.081 |
| **−5.5** | **0.4691156** | **−5.500** | 0.276 | **0.122** |
| −6.0 | 0.4988128 | −6.000 | 0.382 | 0.167 |

This chain's 0.13 dB "nothing else moves" bar was measured **out of band** — the
largest third-octave change outside 500–1300 Hz. The frozen-Q error is
overwhelmingly *inside* the notch, which is the notch coming out slightly the
wrong width rather than leaking somewhere else. Out of band the bar holds to
−5.5 and breaks at −6.0. Reading the middle column instead capped the anchor at
−4.6 for an afternoon.

#### The static value was under-correcting, not over-correcting

The note this stage carried said the give-back from stages 11 and 12 was in the
useful direction and the value should not be raised to compensate. Measuring
what the notch actually **delivers** — chain with the branch, over chain with
`Gain 2 = 0`, third-octave at 800 Hz — says the problem was the other way round:

| anchor | music1 | music2 | pink-prog | square100 | sweep | music1 LUFS | dBTP |
|---|---|---|---|---|---|---|---|
| −3.7 (was shipped) | −2.18 | −2.50 | −2.82 | −1.50 | −1.85 | −9.98 | −0.995 |
| −4.5 | −2.57 | −2.99 | −3.37 | −1.73 | −2.27 | −9.99 | −0.996 |
| **−5.5 (shipped)** | **−3.00** | **−3.58** | **−4.01** | **−1.97** | **−2.79** | **−10.00** | **−0.998** |

Against a measured acoustic residual of **4.7 dB**, −3.7 electrical was
delivering 1.85–2.82. It was short everywhere, on every signal in the battery.

And deepening it is free, which is what the file's own rule predicts: *test a
boost for intermodulation and a cut for headroom*. Headroom: true peak
−0.995 → −0.998 dBTP, sample peak pinned, 0.02 LU. Intermodulation, for
completeness: 3.580 % → 3.565 % at −3 dBFS and 0.075 % → 0.075 % at −6 dBFS —
a cut has nothing to modulate. `--bands` on music1 confirms it stays where it
was aimed, the whole change inside 500–1300 Hz:

```
    500   +4.53 -> +4.46      1250   +4.91 -> +4.84
    630   +0.69 -> +0.35      1600   +7.73 -> +7.71
    800   -3.61 -> -4.43      2000   +9.33 -> +9.32
   1000   +0.28 -> -0.03      2500  +10.93 -> +10.93
```

Largest change anywhere outside that window: **0.04 dB**. Tilt +6.29 → +6.26.

#### Both directions of dynamics were swept, and neither has a job

This is what the stage was rebuilt *for*, so it was measured properly. Anchor
−5.5 throughout, delivered depth at 800 Hz:

| branch setting | music1 | music2 | pink-prog | square100 | sweep |
|---|---|---|---|---|---|
| **`cr` = 1.0 — a wire** | −3.00 | −3.58 | −4.01 | −1.97 | −2.79 |
| compressor, −16 dBFS 4:1 | −2.71 | −2.81 | −4.01 | −1.82 | −1.45 |
| compressor, −12 dBFS 4:1 | −2.96 | −3.34 | −4.01 | −1.96 | −2.07 |
| expander `em`=1 `er`=1.5 | −3.22 | −4.26 | −4.01 | −2.07 | −4.55 |
| expander `em`=1 `er`=2.0 | −3.44 | −5.03 | −4.02 | −2.17 | −6.72 |

A compressor only hands the anchor back. An expander only runs away on the
sweep. **Neither flattens the row**, and the reason is the finding:

> What makes the delivered depth programme-dependent is stages 11 and 12
> handing part of any cut back, and their give-back is keyed on **broadband
> level**, not on how much 760 Hz is present. `square100` gets the most back
> because it drives the excursion limiter hardest — and no gain applied to a
> 760 Hz branch can reach that.

Which is also why 10c's conversion worked and this one's did not. A **boost**
costs intermodulation at high level, so backing it off buys that cost back and
the dynamics have something to trade. A **cut** has no such cost. The two
stages look symmetrical in the config and are not symmetrical at all.

The node stays, inert, for the reason the whole chain was built as a skeleton
first: if stage 11 or 12 ever changes what it hands back, this becomes a value
edit rather than a topology edit.

#### Confirmed on hardware

Both chains run side by side through the `-TEST` sink method, same session,
same hardware, both virtual sinks at 100%, captured at the physical sink's
monitor. `pink-prog` rather than music: the first attempt used `music1` and the
out-of-band bands scattered ±0.2 dB, which is capture alignment and not
spectrum — the same trap the `envb` change hit, and the same fix.

| band | hardware | offline predicted | agreement |
|---|---|---|---|
| 500 Hz | −0.11 | −0.11 | −0.00 |
| 630 | −0.45 | −0.45 | 0.00 |
| **800** | **−1.17** | **−1.19** | **0.01** |
| 1000 | −0.27 | −0.26 | −0.00 |
| 1250 | −0.09 | −0.08 | −0.00 |

Every band in the table agrees to 0.01 dB, and so does every band outside it.
Largest hardware change anywhere outside 500–1300 Hz: **0.07 dB**, against the
0.13 dB bar. The offline harness matching hardware exactly is not new — it has
done so since the mono-plugin fix — but it is worth re-recording that it does so
on a *topology* change and not only on a control value.

#### The regression gate

Set `Gain 2` to 0.3468694474, `Q` to 2.4244947873 and `cr` to 1.0, and the
chain must reproduce the `bq_peaking` it replaced. On music1: residual
**−120.0 dBFS, 106.6 dB below the signal**, worst sample difference 1.6e−05 —
under a 16-bit LSB.

Not bit-exact, and it cannot be. The branch takes one extra float32 round-trip
through ffmpeg that the numpy biquad did not, and stages 10c, 11 and 12 amplify
that at their gain decisions; `compressor_mono` at `cr` = 1.0 is otherwise
exactly a wire, checked in isolation at 1.49e−08, which is float32 epsilon on
that signal and nothing more. The harness itself is bit-deterministic — same
config twice gives `array_equal` — so that floor is the structure, not run-to-run
noise. Writing `k` and `Qbp` to four decimals rather than ten costs 7 dB of it.

### The harness was feeding mono plugins a stereo pair

Found by the hardware A/B above, which is the point of running one.
`tools/offline-chain.py` fed every `*_mono` LSP plugin a **duplicated stereo
pair** rather than one channel. ffmpeg adapts the channel count around the
plugin, the detector then sees a different level, and for a compressor that
changes the gain reduction. Measured on a real branch signal: **0.316 dB**.

It had been there all along and hid in **stage 7**, whose six `compressor_mono`
nodes enter stage 8 at `Gain 3` = 0.06, so a 0.3 dB branch error lands as about
0.01 dB at the output. It did not hide in stage 10c, whose branch enters at
0.5849 — 20 dB louder — where it showed up as the offline render under-predicting
hardware by **0.28 dB at 2500 Hz**.

The fix is to run a one-input LV2 node as true mono, and to size the output
channel count from the plugin's audio inputs instead of hardcoding 2. What it
buys is worth recording, because it revises a figure this repo has relied on:

| | before the fix | after |
|---|---|---|
| hardware vs offline, static chain | 0.00 dB mean, **sd 0.03–0.04** | 0.00 dB mean, **sd 0.00** |
| hardware vs offline, dynamic chain | +0.06 mean, **+0.28 at 2500 Hz** | 0.00, **0.00** |
| sample-level residual | — | **−81.5 dBFS** |

The 0.04 dB agreement recorded under *offline-chain matches hardware* was never
the measurement floor. It was this bug, attenuated by `Gain 3`.

### The rest of the modern-dynamics survey, and why the budget decides it

Measured 1 Sep 2026 while looking for more frequency-dependent dynamics than
GOTT's four bands give. Impulse in, peak out, 48 kHz, through the same
`ffmpeg -af lv2` path `tools/dsp_offline.py` uses. Latency is what settles most
of this, so it is the first column.

| plugin | mode | latency | verdict |
|---|---|---|---|
| `mb_compressor_stereo`, 8 bands | Modern | **0.00 ms** | viable — 8 bands, per-band sidechain filters, per-band Down/Up/**Boost** |
| `sc_mb_compressor_stereo` | Modern | **0.00 ms** | **shipped**, stage 11 |
| `mb_dyna_processor_stereo` | Modern | **0.00 ms** | viable — arbitrary per-band curve |
| `loud_comp_stereo` | **IIR** | **0.00 ms** | viable *on latency*; still blocked on plumbing |
| `mb_compressor_stereo` | Classic | 0 ms, but 20.7 ms of crossover ringing | avoid |
| `mb_compressor_stereo` | Linear Phase | 85.33 ms | ✗ |
| `mb_limiter_stereo` | Classic / Modern | 10.0 / 95.3 ms | ✗ — and already rejected on quality above |
| `clipper_stereo` | — | 25.0 ms | ✗ |
| `mb_clipper_stereo` | Classic / Modern | 37.4 / 122.8 ms | ✗ |
| `beat_breather_stereo` | default | 285.3 ms | ✗ |

**Per-band clipping is the one real loss.** It is what modern mastering reaches
for when compression has run out, and on a driver that already distorts it would
mostly hide. At 37 ms minimum it does not fit a 30 ms budget even with the
4.7 ms `lkahead` bought back. It becomes possible only if the quantum drops —
which is where the budget actually is: **21.3 ms of the 25.2 is the 1024
quantum**, and `clock.min-quantum` on this machine is 32. That, not the DSP, is
the thing to attack if a latency-bearing stage is ever wanted.

**`loud_comp_stereo`: latency was never the blocker.** Its default `mode = 0` is
FFT and costs 85.33 ms, but `mode = 1` (IIR) measures **0.00 ms** at any
`approx`, with ISO226-2023 available on `std = 4`. The objection recorded above
stands unchanged and is the only one: its `volume` port *is* an output volume, so
it cannot sit beside the existing volume control — it has to become it, and
filter-chain controls cannot be set from WirePlumber Lua. Still needs the
listening level to move onto a daemon. Worth revisiting, because the internal
chain sees post-volume audio and its voicing therefore already shifts with the
slider.

### What was measured and rejected

Kept here so it is not re-proposed. All on `music1` through the external chain.

**Linear Phase (`mode = 2`) — 94 ms of latency.** Impulse in, peak out:

| mode | peak | energy spread |
|---|---|---|
| 0 Classic | +8.67 ms | 8.60 → 21.98 ms |
| **1 Modern (shipped)** | +8.58 ms | **8.56 → 10.96 ms** |
| 2 Linear Phase | **+93.92 ms** | 93.90 → 94.85 ms |

Unusable for playback; lip-sync breaks well below that. Note the shipped
`mode = 1` already has by far the tightest impulse — that choice was right.

**`mb_limiter_stereo` as a drop-in — worse.** −11.74 LUFS (0.4 quieter) and
tilt +1.78 against +0.87. It also carries a trap: `gb` (Gain boost) defaults
**on**, the multiband twin of the `boost = 0` this chain already disables.
Without turning it off the chain measured **+0.007 dBTP** — the true-peak
ceiling, which is the entire point of stage X4, silently gone.

**`autogain_stereo` (LUFS levelling) — structurally incompatible.** It
normalises to a target loudness, so it would raise back exactly what the
pre-graph slider attenuated: a dead volume slider, for the third time. Only
safe where the slider is post-graph, which is Bluetooth and USB but not the
headphone jack.

**`loud_comp_stereo` — the real gap, blocked by plumbing.** Equal-loudness
compensation with ISO 226-2023, the current standard; the thing phones do so
that low volume still sounds full. Measured transparent at `volume = 0` (tilt
+0.85 against +0.87), so it is safe to have in the graph. But its `volume` port
*is* an output volume, −83…+7 dB — it cannot sit beside the existing volume
control, it has to **become** it, with the chain input pinned at unity. And
filter-chain controls cannot be set from WirePlumber Lua (only `pw-cli
set-param` works), so nothing can track the GNOME slider without a daemon.
Viable only if the listening level moves onto `external-dsp level`.

### A hidden sink must never be the default

The GNOME volume slider did nothing on the built-in speaker, while working
normally on headphones. Reported 22 Aug 2026.

The slider was not broken and neither was the chain. Driven directly, the
internal graph passes a level change through almost untouched — measured at the
raw sink's monitor, with the same six seconds of programme each time:

| chain input | captured RMS |
|---|---|
| 100% | −13.40 dBFS |
| 70%  | −21.38 dBFS |
| 45%  | −32.90 dBFS |

The fault was **which sink the slider was attached to**. Two different things
set two different pieces of state and nothing kept them in step:

- `hide-speaker-tuning.lua` sets *permissions* — with the jack out,
  `effect_input.tuned-wired` is hidden from GNOME.
- WirePlumber restores the *default sink* from `default-nodes`, which still
  said `effect_input.tuned-wired` from when the jack had been in.

So the default sink was a sink GNOME could not see. `pipewire-pulse` reports a
default the client is actually allowed to see, which left the two disagreeing:

```
PipeWire default : effect_input.tuned-wired      <- audio really played here
GNOME sees       : effect_input.speaker-tuning
GNOME's default  : effect_input.speaker-tuning   <- and the slider drove this
```

Audio kept playing because the wired class matches `^alsa_output%.`, which with
the jack out matches the built-in speaker — so the wired chain was feeding the
speaker. The slider, meanwhile, moved a chain with no stream in it. Nothing was
silent and nothing logged an error; the slider simply had no effect. Headphones
worked because there the visible sink and the default were the same node.

`release_hidden_default()` closes the gap: whenever the default sink is one of
the nodes being hidden, the selection is handed back to
`effect_input.speaker-tuning`. It writes `default.configured.audio.sink`, not
`default.audio.sink` — the configured key is the selection, and WirePlumber
recomputes the other from it. Writing only `default.audio.sink` is undone on the
next pass.

The hidden set is now expressed once, in `hidden_from_gnome()`, so the
permission pass and the default-release pass cannot drift apart again.

### A level per output, remembered

`files/54-volume-memory.lua`.

Every output keeps its own level and remembers it. Nothing is copied from one
output to another. WirePlumber already stores a level per output; the job of
this file is now to stay out of the way of that, and to hold at unity the one
node in the chain that has no slider anywhere.

Where each level actually lives, because it is not one place:

| output | the node GNOME's slider drives | remembered in |
|---|---|---|
| built-in speaker | `effect_input.speaker-tuning` | `stream-properties`, keyed by `media.name` |
| headphone jack | `effect_input.tuned-wired` | `stream-properties`, keyed by `media.name` |
| a Bluetooth device | `bluez_output.<MAC>` | `default-routes`, keyed by **card** and route |
| a USB speaker | `alsa_output.usb-…` | `default-routes`, keyed by **card** and route |

The virtual chain sinks land in `stream-properties` because they have no device
routes — `node/state-stream` restores exactly that case — and both carry
`state.restore-props = true` for it. The chains that are only ever plumbing
carry `false` and come up at unity every time.

Keying the real devices by *card* is what makes two Bluetooth speakers two
levels rather than one.

Measured 30 Aug 2026, after the carry was removed:

| step | Speaker (Tuning) | Logitech BT Receiver |
|---|---|---|
| start | 41% | 41% |
| select the speaker, set 55% | **55%** | 41% |
| select the receiver, set 25% | 55% | **25%** |
| select the speaker | **55%** | 25% |
| select the receiver | 55% | **25%** |
| `restart pipewire pipewire-pulse wireplumber` | **55%** | **25%** |

The second Bluetooth device, which was not connected during any of this, still
held its own `0.300740` in `default-routes` throughout.

#### It used to carry one level onto every output, and that was the bug

Until 30 Aug 2026 this file did the opposite. On each selection change it read
the level off the sink being left and wrote it onto the sink being chosen, so
one slider position meant one loudness wherever you listened. That was asked
for on 22 Aug 2026, when nothing carried a level at all and each output drifted
to wherever it was last left: **Speaker (Tuning) at 65% beside the wired chain
at 28%**, a 22 dB jump on a slider nobody had touched.

What carrying it *both ways* actually means only showed up in use: there is
then only ever **one level in the whole system**. Every output is overwritten by
whichever one you listened to last, so no output can be set to its own level and
none can remember one. Measured 30 Aug 2026, with the receiver selected at 41%:

```
$ pactl set-sink-volume effect_input.speaker-tuning 55%
$ pactl get-sink-volume effect_input.speaker-tuning     # 55%
$ pactl set-default-sink effect_input.speaker-tuning
$ pactl get-sink-volume effect_input.speaker-tuning     # 41%
```

The built-in speaker was set to 55% and was back at 41% a second later, because
selecting it carried the receiver's level onto it. Reported as *"master volume
same for all connected devices and internal speaker — it should be separate for
each device, and remembered for each device"*.

The **60% clamp** went with it. It existed because a level copied *onto*
headphones or a powered speaker is a level nobody chose. Nothing is copied onto
anything now — every level on every output is one the listener put there — so
there is nothing to clamp. `external-dsp level` still enforces
`EXTERNAL_DSP_MAX_LEVEL` for the levels it writes itself.

The two behaviours are exact opposites and both have been asked for. If one
slider position meaning one loudness is ever wanted again, it needs a
*different* mechanism — a per-output offset applied on top of a shared level —
not a copy that destroys the value it lands on.

#### Still shared: the wired chain stands in two roles

Not fixed by this, and worth knowing. `effect_input.tuned-wired` matches
`^alsa_output%.`, which is both the onboard headphone sink **and** a USB
speaker. For the jack it is the listening level; for USB it is plumbing that
should be at unity. It cannot be both, so a level set on headphones is still
applied to the USB path — before the graph, where it also starves the
compressor, and on top of the USB device's own level.

Bluetooth is unaffected: `effect_input.tuned-bluetooth` carries
`state.restore-props = false`, comes up at unity, and is never the selected
output.

The fix is to split the wired class in two — one chain for the jack, one for
USB — so that no chain input is ever a listening level and plumbing at
different times. Pinning it to unity when USB is selected is *not* the fix: it
would let unity be saved as the jack's remembered level, and the jack coming
back at 100% is the hazard recorded two sections down.

#### `external-dsp on` was pinning the master volume to 100%

The same routing change caught the other helper. `pin_pregraph_unity()` sets
every `effect_input.tuned-*` to unity, on the reasoning that a chain input sits
*before* the graph, so a level there is not a listening level — it just starves
the compressor.

That was true when every chain input was invisible plumbing behind a device
GNOME listed itself. It stopped being true the moment the headphone jack was
listed as its own output, because **that entry *is* the chain**: GNOME's slider
drives `effect_input.tuned-wired`. So `external-dsp on` threw the master volume
to 100% — and with the headphone sink now pinned at unity, that is full scale
into someone's ears.

`level_node()` now decides which of the two arrangements is live, from what
GNOME has selected:

| default sink | the listener's level is | the other one is |
|---|---|---|
| `effect_input.tuned-*` | that chain input, before the graph | the device, held at unity |
| a raw device (`bluez_output.*`, USB) | the device, after the graph | the chain input, held at unity |

`pin_pregraph_unity`, `level` and `status` all read it, so `on` leaves the
selected output alone and says why, `level N` writes to whichever node actually
carries the level, and `status` stops calling the headphone sink *ABOVE THE CAP*
when it is deliberately at unity, or the chain input *WRONG* when it is the
slider. Verified both ways in one pass: with headphones selected, `unity` pins
`tuned-bluetooth` 50% → 100% and leaves `tuned-wired` at 35%.

This is the third time a routing change has broken a control script while the
audio path kept working.

#### …and it did not remember the level either

`state.restore-props = false` in the chain's `capture.props`, for the same
reason: a remembered value on a plumbing node switches the DSP off by volume.
Measured — set `effect_input.tuned-wired` to 40%, restart, back at 100%.

The wired class alone is now generated with `state.restore-props = true`, since
it is the one class GNOME lists as an output in its own right. Every other class
keeps `false`.

Worth knowing when testing this: **the save is deferred.** Setting
`effect_input.speaker-tuning` (which has always had the default) to 37% and
restarting immediately brought back the *previous* value, 52%; the same change
with twenty seconds before the restart came back at 37%. An immediate restart is
not a test of whether a value is remembered. The value does not appear in
`stream-properties` either way.

#### The 21 dB nobody could reach

`alsamixer` showed the onboard **Headphone** element at −21 dB while the speaker
sat at unity. Reported 22 Aug 2026, and it was not the mixer's doing —
`~/.local/state/wireplumber/default-routes` held it:

```
alsa_card.pci-0000_04_00.6:output:[Out] Speaker    = {"channelVolumes":[1.000000, …]}
alsa_card.pci-0000_04_00.6:output:[Out] Headphones = {"channelVolumes":[0.085177, …]}
```

`0.085177` linear is **−21.39 dB**. The headphone sink is hidden from GNOME —
the wired chain stands in front of it — so no slider anywhere in the system
could put that back. It was pure loss, stacked underneath the −17.04 dB the
GNOME slider was already applying: −38.43 dB total, with 21 dB of it invisible.
Only headphones were affected, because the speaker's route happened to be
stored at unity.

`pin_unity()` holds the headphone sink at 1.0, so the GNOME slider on
`effect_input.tuned-wired` is once again the only level that matters.

Two details make it work:

- **The write must be re-asserted, not made once.** WirePlumber restores a
  route's stored volume *after* `object-added`, so a single write at that moment
  is overwritten a beat later and the sink is quietly back at −21 dB. Connecting
  to the node's own `params-changed` is what makes it stick. Measured: seeded
  back to 44%, restart, and it comes up at 100% / 0.00 dB and stays there —
  three reads a second apart, WirePlumber at 0.7% CPU, so it is not
  ping-ponging. The read-back inside `pin_unity()` is what prevents that, and
  once written WirePlumber saves `1.000000` and stops restoring the old value.
- **The speaker sink is deliberately not pinned.** `speaker-dsp` writes its
  volume to level-match the bypass A/B, and holding it at unity would silently
  break that comparison.

**Setting a volume from Lua works, but in one form only.** This corrects what
this repo previously recorded as impossible:

| call | result |
|---|---|
| `node:set_param("Props", …)` | accepted, does nothing |
| `mixer:call("set-volume", id, Json.Object { volume = v })` | **returns false** |
| `mixer:call("set-volume", id, { volume = v })` | works |

Only the middle one reports its own failure. The volume is linear, while pactl
and GNOME show a cubic percentage — 60% on the slider is `0.6³ = 0.216` linear,
so the two cannot be compared by eye.
