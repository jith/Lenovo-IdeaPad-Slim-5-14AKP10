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
| 10 | Multiband compressor | `s10mbc` | **LSP GOTT Compressor** | 120/1000/6000 Hz, `ebe = 1`, `mode = 1`, downward thresholds −20/−15/−9/−9 dB, `g_out` +10.63 dB, `mk_2` −1.01 dB, `mk_3` +2.98 dB | **active** — the only loudness lever, and now the only voicing control too | US12342139B2 |
| 10b | Resonance notch | `s10res_*` | builtin `bq_peaking` | 760 Hz, Q 3.0, −3.0 dB | **active** — third instrument aimed at the 761 Hz resonance, after stage 2 and `mk_2`. Delivers −2.2 dB on programme; stages 11–12 hand the rest back | — |
| 10c | Presence lift | `s10pres_*` | builtin `bq_peaking` | 2650 Hz, Q 1.2, +3.0 dB | **active** — finishes what `mk_3` started against the iPhone 13. Delivers +2.6 to +2.8 dB on programme. Sized below its own fit (+4.0) for two-tone IMD margin | — |
| 11 | Excursion limiter | `s11hx_*`, `s11xcur` | `bq_lowpass` estimate → LSP sidechain comp | Hx = lowpass 761 Hz Q 2.63; threshold −3 dBFS on the estimate | **active**, works on ordinary music, and the `Hx` shape is now confirmed acoustically — 800 Hz is the only frequency where the drivers compress | US12445775B2, CN115442709B |
| 12a | Band limit | `s12lp_*` | builtin `bq_lowpass` | 22 kHz, Q 0.707 | **active** — buys 0.66 dB of true peak for 0.10 LU on pink | — |
| 12 | Brickwall | `s12brick` | LSP Limiter | −1.01 dBFS sample → **−0.2 dBFS true peak** (`ovs = 22`), `lk = 1` | **always on** — `th` pays for the sweep so `g_out` can spend | — |
| 13 | A/B trim | `s13trim_*` | builtin `linear` | static gain from the loudness match | **unity** — tuned deliberately left hot, by 3.44 LU as measured at `g_out` 2.40 | ITU-R BS.1770 |

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
        [10b] resonance notch   bq_peaking 760 Hz Q3.0 -3.0 dB
        [10c] presence lift     bq_peaking 2650 Hz Q1.2 +3.0 dB
                                both fixed, both from the iPhone 13 A/B,
                                both after GOTT so no makeup can drift them
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
             ● s10res_l/r   bq_peaking  760 Hz Q 3.0  -3.0 dB
             │                                 761 Hz cone resonance
             ● s10pres_l/r  bq_peaking 2650 Hz Q 1.2  +3.0 dB
             │                                 presence, same A/B
             │           fixed corrections, after GOTT so no band makeup
             │           can drift them, before 11 so its detector sees
             │           them, before 12 so the brickwall keeps the ceiling
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

`null-test.sh` defaults to all three shipped signals, so there is no material
list to get wrong. If you do pass paths from zsh, pass them as an array —
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
| Null test residual below −60 dBFS above 30 Hz | **skeleton** | pass — **−inf dBFS**, captures bit-identical. Says nothing about the tuned chain |
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
| The 761 Hz correction reproduces across programme | **current** | pass — measured on a −5.7 LUFS master with LRA 3.2 LU, then confirmed against two trailer tracks and two synthetic signals. Split-half spread on the acoustic A/B it came from: **sd 0.77 dB, worst 2.2 dB** |
| Worst-case margin not reduced by the loudness change | **current** | pass — **0.371 → 0.463 dB**. Louder and further from the ceiling |
| Loudness on real programme material | **current** | pass — **+0.78 LU** (music1) and **+0.61 LU** (music2, dialogue at −11.25 LUFS arriving at +0.634 dBTP) |
| Offline harness predicts hardware on that change | **current** | pass — music2 true peak reproduced to the third decimal on both sides; pink ΔLU +1.24 against a predicted +1.24 |
| Net loudness against the pre-change chain | superseded | pass — pink +0.60 LU against a predicted +0.60, with true peak 0.69 dB *lower* |
| Stage 12a changes nothing but level (18 kHz corner) | superseded | pass — null residual was a pure 0.695 dB gain change on pink and sweep, to **0.02 dB** |
| Drivers not the binding constraint at the chain's own output | current | pass — **~20 dB of margin** at 800 Hz, the one frequency that compresses, on programme-level pink through the whole graph after the `g_out` 3.00 change |
| Stage 11's `Hx` centre matches where the drivers actually run out | current | pass — 800 Hz measured, `Hx` peaks at 761 Hz; threshold sits 2.6 dB conservative |
| Stage 10b is aimed at a real driver resonance | **session D, acoustic** | pass — with the source file on both devices the driver separates from the chain, and it peaks **+7.8 dB at 800 Hz** re its own 1.6–4 kHz plateau. The chain cuts 12.8 dB there and the acoustic result matches the iPhone to **−0.2 dB**. First confirmation on material 10b was not tuned on |
| Stage 10c closes the gap it was built for | **session D, acoustic** | pass — **+0.2 dB** at 2500 Hz and +0.5 at 3150 against the iPhone. Read as "matched": both are inside the 1.4 dB re-setup repeatability, not resolved to 0.2 dB |
| The 400–630 Hz excess is not a defect | **session D, acoustic + listening** | pass, and **tested** — the iPhone reads 6–12 dB quieter there, but the driver has no resonance at 500 Hz and both curves are clean rolloffs differing only in knee. A −5 dB bell at 500 Hz Q 1.6 was built as a separate `-TEST` sink, verified end to end (delivering −2.9 dB acoustically, nothing above 1.25 kHz moving, no headroom cost) and A/B'd. **The uncut chain won.** Do not re-propose it |
| The chain is time-coherent | **session D, offline** | pass — group delay flat within **2.2 ms** from 50 Hz to 12.5 kHz on a −46 dBFS impulse, the one excursion being −1.3 ms at 800 Hz where 10b's notch is. Impulse energy spreads 0.1 ms |
| No cross-band ducking | **session D, offline** | pass — midrange gain against bass content is **r = −0.04** (0.1 dB per 10 dB). The bass band compresses itself at r = −0.79, which is its job. Gate per band: on a broadband gate this reads a spurious 14–17 dB swing |
| The harmonic branch is inaudible in band power on programme | **session D, offline** | pass — on a bass-heavy EDM master, the fourth source tested, muting stages 5–8 moves 490–1008 Hz by **+0.09 dB** at worst. See *What the harmonic branch actually contributes* |
| The 5–6.3 kHz dip is not an EQ target | **session D, acoustic** | closed — three lid angles, everything else held. 5 kHz moves **9.0 dB** across them, more than the dip, while two of the three agree to 0.1 dB. That ambiguity is unresolvable with a mic that cannot move independently of the drivers, and does not need resolving: no fixed filter can correct a band geometry moves by 9 dB |
| How much of an acoustic result is the geometry, not the speaker | **session D, acoustic** | measured — **±1.6 dB** across 200 Hz–2.5 kHz between two ordinary lid angles, **±3.4 dB** across the full range, **±6.1 dB** above 4 kHz. Independent agreement with the 1.4 dB re-setup repeatability. This is the bar a finding clears before it is a property of the speaker |
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
| `tools/offline-chain.py` | Runs the installed graph over a wav without reinstalling. `--sweep` for parameter searches, `--measure` for LUFS / peaks / THD, `--self-test` for 23 checks that need no hardware. |
| `tools/dsp_offline.py` | The machinery behind it: config parser, PipeWire builtins in numpy, LSP plugins through `ffmpeg -af lv2`, and the measurement functions. Imported, not run. |
| `tools/true-peak.py` | Exact inter-sample peak, and `--compare` against the two ffmpeg meters that get it wrong. Exits non-zero above the ceiling, so it can gate a change. |
| `tools/lt-coeffs.py` | Linkwitz transform coefficients for stage 2, with `--self-test`. |
| `tools/sweep-response.py` | Response curve, `fc` and `Qtc` from a mic capture. Needs `--reference` or the numbers tilt. |
| `tools/measure-speaker.sh` | Plays the sweep and captures it on Mic2. |
| `tools/max-level.sh`, `tools/max-level.py` | Drives the raw sink with sine bursts at rising levels and reads the mic, to find where the *drivers* distort. `--ref` brackets every test level with a reference one, which is what it takes to resolve 1 dB. |
| `tools/make-test-material.sh` | Synthesises pink, sweep and square; `--music` ingests your own tracks. |
| `tools/null-test.sh`, `tools/null_residual.py` | Capture both paths and measure what the chain changed. |
| `tools/loudness-match.sh` | The stage 13 trim, per ITU-R BS.1770. |

The rule the harness exists to enforce: **sweep it offline, confirm the one
value you chose on hardware.** Offline is fast enough to be exhaustive and
faithful enough to trust for differences. It cannot tell you which material to
test, and that is where every wrong answer in this file came from.
