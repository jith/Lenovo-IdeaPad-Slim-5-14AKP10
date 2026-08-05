# Speaker DSP

A thirteen-stage PipeWire filter chain for the Lenovo IdeaPad Slim 5 14AKP10
speakers, installed as **Speaker (Tuning)**, a virtual stereo sink in front of
the hardware sink.

It ships as a **skeleton**: every stage exists as a real node in the graph, but
each stage whose coefficients have not been measured yet sits at a
bypass-equivalent value. The point is a graph that loads cleanly end to end, so
measured values can be dropped in one stage at a time without ever debugging
topology and tuning at once.

Only stage 1 (a 20 Hz subsonic high-pass) and stage 12 (the brickwall limiter)
do anything as installed.

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
| 0 | Headroom trim | `s0trim_*` | builtin `linear` | −6 dB, recovered at stage 10 makeup | **unity** — set to `Mult = 0.5012` when stage 2 goes live | US12342139B2 |
| 1 | Subsonic high-pass | `s1sub_*` | builtin `bq_highpass` | 20 Hz, Q 0.707 | **active** | US12445775B2 |
| 2 | Linkwitz transform | `s2lt_*` | builtin `bq_raw`, one per channel | **numerator = measured (fc, Qtc); denominator = target (fc′, Qtc′)** | identity | US12342139B2 |
| 3 | HF path | `s3neg_*`, `s3hf_*`, `s3dly_*` | `invert` + `mixer` + `delay` | HF = input − LF; delay matches LF branch group delay | high-pass on, delay 0 | CN115442709B |
| 4 | Subband split | `s4lp_*`, `s4bp1..3_*` | `bq_lowpass` + 3× `bq_bandpass` | centres 0.25 / 0.45 / 0.75 × f1, Q 2.0; top edge 0.96 × f1 | placeholder f1 = 200 Hz | CN115442709B |
| 5 | Harmonic generation | `s5h<band>x<order>_*` | `mult`, order n = x^n | low band 4/5/6, mid 3/4/5, upper 2/3/4 | live but muted at stage 8 | CN115442709B, US5930373A |
| 6 | Harmonic weighting | `s6w<band>x<order>_*`, `s6sum<band>_*` | `bq_peaking` per order | gain ∝ ln(n)·R(f), f = band centre | 0 dB | CN115442709B |
| 7 | Gain K | `s7dc_*`, `s7k1..3_*`, `s7sum_*` | `dcblock` + LSP compressor per band | threshold per band from K = min over orders | bypass (`enabled = 0`) | CN115442709B, US10382857 |
| 8 | Sum | `s8sum_*` | builtin `mixer` | HF, LF and harmonics; `Gain 2`/`Gain 3` are the crossfade | HF + LF unity, harmonics muted | CN115442709B |
| 9 | M/S widening | `s9*` | explicit M/S matrix | mono below ~300 Hz via `s9swid` `Gain 1` | unity (exact identity) | US8660271B2 |
| 10 | Multiband compressor | `s10mbc` | Calf MultibandCompressor | lowest threshold on the LF band | bypass (`bypass = 1`) | US12342139B2 |
| 11 | Excursion limiter | `s11hx_*`, `s11xcur` | `bq_raw` estimate → LSP sidechain comp | Hx(s) displacement estimate on the sidechain; x_max unknown | bypass (`enabled = 0`) | US12445775B2, CN115442709B |
| 12 | Brickwall | `s12brick` | LSP Limiter | −0.3 dBFS, no makeup, ALR and boost off | **always on** | — |
| 13 | A/B trim | `s13trim_*` | builtin `linear` | static gain from the loudness match | 0 dB | ITU-R BS.1770 |

Signal flow:

```
input → s0 trim → s1 subsonic HP → s2 Linkwitz
      → split at f1
          ├── HF = input − LF  → s3 delay ────────────────┐
          └── LF = LP(f1) ──────────────────── unity ─────┤
                    └→ 3 bandpasses → s5 harmonics        │
                       → s6 weighting → s7 dcblock + K ───┤
      ← ────────────────────────────── s8 sum ────────────┘
      → s9 M/S widening → s10 multiband → s11 excursion
      → s12 brickwall → s13 trim → hardware sink
```

### Where this departs from the stage table it was specified from

Five places. Each is a decision, not an accident.

1. **Stage 0 ships at unity, not −6 dB.** The −6 dB exists to make room for the
   Linkwitz transform's boost, and stage 10's makeup returns it. With stage 2
   at identity and stage 10 bypassed, applying −6 dB would leave the skeleton
   6 dB below the baseline and fail the loudness-match criterion. The value is
   in the config, commented, next to the stage that consumes it.

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
speaker-dsp ab       # toggle, with the loudness trim applied
speaker-dsp status
```

`ab` is the one to use for listening comparisons: it applies the raw-path trim
so switching does not change loudness. Set the trim with
`SPEAKER_DSP_RAW_TRIM` (a percentage) from what `tools/loudness-match.sh`
reports, or edit the default in `files/speaker-dsp`.

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
| 9 | `s9swid` `Gain 1` → 0 for mono bass; `Gain 2` above 1 to widen |
| 10 | `s10mbc` `bypass` → 0, lowest `threshold0`, `makeup0` recovers stage 0 |
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
ffmpeg -i tests/captures/sweep-mic.wav -lavfi 'showspectrumpic=s=1600x800:legend=1' spectrum.png
```

`fc` is the peak frequency of the enclosure resonance. `Qtc` is `fc` divided by
the −3 dB bandwidth around that peak. Feed both, plus the target you want, to:

```sh
tools/lt-coeffs.py FC QTC FC2 QTC2 [--rate 48000]
tools/lt-coeffs.py --self-test
```

It prints both `s2lt_l` and `s2lt_r` blocks ready to paste, warns if any
coefficient would hit the ±10 clamp, and reports the peak boost — which is the
number stage 0 has to make room for.

### The microphone caveat

**The internal microphone is not a measurement microphone.** It is
uncalibrated and sits inside the chassis, so it hears case resonance and its
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

Two rules the tool follows and you should too:

- **The louder path is attenuated at its own output. Never boost the quieter
  one.** Tuned louder → stage 13. Raw louder → the hardware sink's volume.
- **Never trim the chain input to match loudness.** Stages 7, 10 and 11 are
  level-dependent, so changing what they see changes their behaviour and you
  are no longer comparing the same processing.

While it runs you will hear the material twice. Set a comfortable level with
the **hardware** sink's volume: it sits after the monitor tap and does not
affect the measurement. The virtual sink's volume is before the filter graph
and does.

## Null test

The measurement behind "nothing else changed".

```sh
tools/make-test-material.sh                       # once
tools/null-test.sh baseline tests/captures        # BEFORE changing the graph
# ... edit a stage, reinstall, restart ...
tools/null-test.sh compare tests/captures
```

`compare` sample-aligns against the baseline by cross-correlation, inverts,
sums, and reports the residual peak split at 30 Hz. A constant latency
difference — the limiter's lookahead, for instance — is removed by the
alignment. A gain difference is not, and is meant not to be.

**The baseline is high-passed before subtraction, and that is deliberate.**
Stage 1 is a 20 Hz biquad and it is active. Its magnitude is flat to within
0.01 dB above 50 Hz, but its *phase* is not: at 1 kHz a 20 Hz high-pass still
rotates the signal enough that the raw difference only reaches −31 dBFS, and
against pink noise the broadband residual sits near −25 dBFS. That is phase,
not error, but subtraction cannot tell them apart — so a −60 dBFS null against
an unfiltered baseline is unreachable with stage 1 on, no matter how correct
the rest of the chain is. Applying the same high-pass to the baseline first
isolates the question actually worth answering: is every *other* stage
bypass-equivalent. `--hp 0` shows the uncompensated figure, which is also
printed either way.

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

### Volume dependence — needs a decision

US12342139B2 selects different transform and compressor parameters per volume
level, because a static chain is only correct at one drive level. The skeleton
assumes strategy (a): the virtual sink stays at unity and user volume acts on
the hardware sink, so the chain always sees full scale.

**That assumption is implementable here but is not what happens today.** What
was verified on this machine:

- `effect_input.speaker-tuning` carries `softVolumes` and no `HARDWARE` flag —
  its volume is software, applied by the capture stream, which is *before* the
  filter graph. `libpipewire-module-filter-chain`'s `capture.volumes` option
  exists precisely to redirect that into a graph control port, which confirms
  it is not in the graph by default.
- `alsa_output.pci-0000_04_00.6.HiFi__Speaker__sink` reports
  `HW_VOLUME_CTRL` — it has real hardware volume, so it can carry user volume.

The catch: GNOME's slider drives the *default* sink, which is the virtual sink.
Pinning it to unity makes that slider dead — the exact failure that commit
2e18532 fixed. So this is not something to change silently. `speaker-dsp` sets
the virtual sink to 100% when selecting it, which keeps the chain at full scale
whenever you switch through the helper, but nothing stops the slider from
moving it afterwards.

Three ways forward, none picked:

1. Leave it. The chain sees post-volume audio; tune at one representative
   level and accept drift elsewhere.
2. Pin the virtual sink at unity and move user volume to the hardware sink,
   with a WirePlumber rule so GNOME's slider follows the hardware sink.
3. Watch the volume and retune coefficients at runtime with `pw-cli set-param`,
   which is what US12342139B2 actually describes.

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
