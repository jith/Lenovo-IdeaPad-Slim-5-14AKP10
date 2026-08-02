# Speaker Tuning DSP — Lenovo IdeaPad Slim 5 14AKP10

Measurement-driven speaker enhancement for Linux: corrective EQ + psychoacoustic
bass + input-adaptive dynamics + loudness drive for the laptop's 2 W × 2
up-firing speakers, deployed as a selectable PipeWire sink. Built 2026-07-15,
dynamics/loudness overhaul 2026-07-21, iPhone-gap pass 2026-07-23 (FIR
ripple correction + level-aware bass + thermal guard), **gain-structure and
adaptive pass 2026-08-02** — every change verified with digital signal captures
(level ramps, burst+tail, pink-noise spectra) and, for the FIR pass, a 3-position
acoustic re-measurement.

**Measured end to end (2026-08-02):** tuned vs raw speaker, same source, same
analog level, same mic position, EBU R128 integrated — **−38.6 → −29.8 LUFS,
i.e. +8.8 dB acoustic.** Peak pinned at −1 dBFS; total added latency from the
2026-08-02 pass is 1.29 ms.

| | |
|---|---|
| Laptop | Lenovo IdeaPad Slim 5 14AKP10 (83HX), aluminum chassis |
| Speakers | 2 × 2 W **up-firing** stereo, either side of the keyboard (unbranded OEM micro-drivers; Lenovo spec: "stereo speakers, 2W x2", Dolby-processed on Windows only) |
| Amp topology | **Dumb, open-loop.** HDA pin `0x17` with EAPD — a single on/off enable line. Audited 2026-08-02: no smart amp exists on this board (SoundWire bus empty, no audio I²C client, and the only non-standard NXP ACPI entry is `\_SB_.I2CA.NFC1`, an NFC stub with `_STA = 0`). **There is no I/V sense, so no excursion or coil-temperature telemetry is possible at any layer** — every protection stage here is open-loop and must assume worst case. No driver or kernel option changes this |
| Amp/codec | Conexant/Senary SN6140 HDA codec, integrated stereo Class-D amp (`snd_hda_intel`, card 1, AMD Ryzen HDA controller 04:00.6) |
| OS / stack | Ubuntu 26.04, PipeWire 1.6.2, WirePlumber 0.5.13, GNOME 50.1 |
| Dependency | `lsp-plugins-lv2` (loudness compensator, MB compressor, GOTT leveler, MB limiter — all LV2); everything else is PipeWire builtins |

## The two outputs

| GNOME output | What it is | Volume |
|---|---|---|
| **Speaker (Tuned)** — default | DSP sink (`effect_input.speaker-tuning`) | Any volume. The sink's steep cubic taper (bug #2/#3 below) is measured by the `speaker-loudness` service, which compensates the tonal side with the ISO 226 contour |
| **Speaker** | Raw hardware sink | Normal hardware volume — use for quiet listening |

Switch anytime: `speaker-dsp on` / `speaker-dsp off` / `speaker-dsp status`
(or pick in GNOME Settings → Sound). `on` keeps your current volume (it
used to force 100%; that's obsolete — LV2 processes correctly at any
volume and the loudness service compensates the taper).

Two visible sinks is **deliberate** — every single-visible-sink design failed
on this PipeWire version (see Platform bugs).

## The measured speaker (why the chain looks like this)

Stepped-tone measurement (90 Hz–11.2 kHz, raw speaker → internal mic):

- Output **collapses below ~450 Hz** (−18 dB @360 Hz, −25 @260, −35 @110; THD
  5–90%). Sub-300 Hz content is inaudible distortion + wasted headroom.
- Boxy hump **+7..+10 dB @ 710–1000 Hz** — the vocal masker.
- Presence dip −3..−6 dB @ 2.5–2.8 kHz.
- Harsh peak **+9..+11 dB @ 10–11 kHz** — the "metallic" sound.
- Interference nulls 5–7 kHz (position-dependent; left uncorrected).

## DSP chain (files/50-speaker-tuning.conf, in graph order — PipeWire builtins + LSP LV2)

0. **Volume-aware loudness contour** (LSP Loudness Compensator, ISO 226,
   IIR mode): the `speaker-loudness-follow` daemon (systemd user service)
   tracks the volume knob and live-updates the contour — at low volume the
   EQ shifts to keep bass/treble perceptually balanced, exactly like
   phone-speaker DSPs. 1 kHz stays at unity (the sink's own cubic-taper
   attenuation is compensated inside the plugin, verified); defaults are
   flat so audio is unaffected if the daemon is down.
   **Level-aware bass extension (2026-07-23)** — the same daemon also moves
   the excursion-protection HP corner with the knob (software stand-in for
   a smart amp's excursion model): 270 Hz is a worst-case (100 % volume)
   figure; with the cubic taper cutting 13–30 dB of drive at lower knob
   values the driver can safely play lower. Measured basis: THD at
   150–220 Hz is 4–8 % at −5 dBFS drive and falls with level. Map:
   ≥75 % → 270 Hz | 60–74 → 240 | 45–59 → 210 | 30–44 → 190 | <30 → 170.
   Verified by live param readback at 25/40/58/85 % and by tone capture
   (200 Hz gains +3.7 dB relative at the lowered corner). Conf default
   stays 270 — safe if the daemon is down.
1. **Stereo widener** (mid/side delta, builtin): adds `w_g × HP350(side)` to
   L and subtracts it from R. Center (mono) content — vocals, dialog — has
   zero side signal and passes **bit-identical** (verified); the mono sum
   L+R is unchanged; bass stays untouched. `w_g "Mult"`: 0 = exact bypass,
   0.3 default, 0.6 wide.
2. **Corrective EQ** (per channel, from the stepped-tone measurement):
   - High-pass 270 Hz — remove the inaudible-distortion band
   - Body +5 dB @ 560 Hz — lowest octave the driver actually plays
   - Box cut −3.5 dB @ 800 Hz — flatten the measured hump (an extra
     *dynamic* 2:1 cut of this band lives in the switchable mbc stage,
     see 4; the default GOTT stage levels the region downward above
     −5 dBFS instead)
   - Presence +3 dB @ 2.6 kHz — fill the measured dip
   - Metal cut −6 dB @ 10.5 kHz (wide) — tame the measured peak; the
     aluminum chassis makes this region dominate if left hot
   - **Fine-ripple FIR correction (2026-07-23)**: min-phase 2048-tap FIR
     (PipeWire builtin `convolver`, IR at
     `/usr/local/share/speaker-dsp/fir-correction.wav`) designed from a
     1/12-octave 3-pass acoustic re-measurement (both-speakers + L-only +
     R-only at three lid angles, power-averaged to reject mic-position
     combing). Corrects only the ripple *between* the coarse biquad points
     toward the chain's own broad voicing trend — voicing unchanged. Key
     fixes: extra −7 dB @ 670–800 Hz (box hump still rode ~+7 dB over the
     mid plateau), **−7 dB @ ~9 kHz — the true metallic-peak center the
     10.5 kHz biquad partially missed**, +1..2 dB fills at 1.1–1.4 kHz,
     capped +3 dB into the 5.4–6.4 kHz null region. Caps: boost ≤+4 dB
     (0 above 9 kHz — the metallic band is never boosted), cut ≥−8 dB;
     flat <300 Hz and >14 kHz. Min-phase → no latency, no pre-echo.
     Verified: deployed convolver matches design within 0.05 dB (digital
     capture); acoustic re-check moved box hump +6.4→+3.1, 9 kHz peak
     +5.8→−2.8, 1.2 kHz hole −2.2→+1.1 dB vs trend.
3. **Psychoacoustic bass with dynamic ducking**: mono <250 Hz → x² + x³
   harmonics (2nd-harmonic-weighted: octave-up warmth = "vocal bass" chest
   feel) → band-passed ~300–800 Hz where the driver is audible (sub-300 Hz
   residue removed by a cascaded high-pass — inaudible, would pump the
   limiter) → the branch's own envelope (`abs → LP 5 Hz → clamp/log/exp`)
   ducks the harmonics on loud passages → mixed into both channels.
4. **Adaptive dynamics — GOTT two-sided leveler (LSP, default since
   2026-07-21, user pick after measured A/B)**: per band (650/2500/8000
   splits) a "comfort zone" — quiet content is upward-compressed from below
   −18 dBFS, hot content downward-compressed above −5, with a −25 dB floor
   that bounds reverb-tail runaway (measured: unbounded, tails gained +7 dB
   and climbing; floored, the swell converges at +3.5 dB/600 ms). Air band
   >8 kHz is downward-only so the metallic 10–11 kHz region is never
   lifted. Linear-phase crossovers, 400 ms releases (see anti-echo notes
   below). Measured vs the alternative mbc stage: **+0.8 dB louder,
   +4.5 dB more quiet-bass lift, +6.5 dB more quiet vocal detail**; cost:
   reverb tails sit ~4 dB hotter.
   **Alternative (in the graph, bypassed, swap commands in the conf): a
   5-band LSP Multiband Compressor** with capped Boost-mode lifts — bass
   <650 Hz +4 dB when quiet, box 650–1100 Hz *downward* 2:1 (cuts the vocal
   masker only when hot), vocal core 1100–2500 Hz +2 dB, presence +1 dB,
   all → exact unity above −13 dBFS (ramp-verified). Drier tails than GOTT,
   less detail retrieval — the choice for echo-sensitive listening.
   **Anti-echo rules (apply to both stages, learned by measurement)**:
   crossovers must run *linear-phase* (minimum-phase recombination combs
   the vocal region when band gains differ = metallic sheen); releases slow
   (400–800 ms) and lifts capped, so post-word gain recovery is a slow
   drift, not a bloom — burst+tail capture: swell +4.9 dB/250 ms (audible
   echo) → +1.4 dB/300 ms (inaudible drift) on the mbc tune.
5. **Makeup drive +11 dB** (`Mult = 3.6`) into **LSP Multiband Limiter
   Stereo**: 4 bands — bass <650 Hz, vocals 650–2500, presence 2500–8000,
   air >8000 — each true-lookahead limited independently with **unequal
   ceilings** (bass −2.5 dB, vocals −3 dB, presence −4 dB, air −9 dB),
   then a final −1 dBFS brickwall on the sum.
   **2026-07-22 fix (the "ears hurt at high frequencies" bug)**: the
   original gap-indexed split layout (`se_2/se_4/se_6`) silently mis-mapped
   the band params — vocals were actually bound to `th_3`, and **nothing
   above 2500 Hz was band-limited at all** (proven: 5 kHz and 10.5 kHz
   tones passed at linear level with every `th` at −20 dB; only the
   brickwall caught treble). With +11 dB drive that let 2.5–11 kHz ride
   ~2–7 dB hotter than the ceilinged bass/vocals on loud songs. Splits are
   now consecutive (`se_1/2/3` — unambiguous mapping), bass/vocal ceilings
   carried over unchanged, presence/air finally capped. Measured after
   fix: loud 5 kHz pinned at −4 dB, 10.5 kHz −2 dB quieter, pink spectrum
   3–10.5 kHz down ~1 dB with 120–2200 Hz within ±0.2 dB, total loudness
   −0.3 dB. Unequal on purpose: with
   equal ceilings the energy-heavy bass/mids limit constantly while treble
   never does, so loud music tilts metallic. Bass and vocals keep the most
   headroom; the higher the band, the harder its cap — treble density is
   what reads as painful on micro-drivers pushed loud.
   Dynamic separation: a bass peak compresses only the bass band
   (measured: 3 kHz output bit-identical beside a full-scale 500 Hz tone at
   the band stage). ALR and gain-boost are off everywhere (ALR measured to
   over-regulate sustained content ~11 dB; `envb` envelope tilt off —
   measured to over-limit mids ~5 dB). The DAC never hard-clips.
6. **Thermal guard (2026-07-23)**: a second LSP limiter instance in ALR
   mode after the brickwall — the MB limiter is peak-based and happily
   passes *sustained* −1 dBFS content that 2 W coils shouldn't eat for
   long under +11 dB drive. ALR (the very behavior deliberately banned in
   the loudness limiter) is slowed to its maximum (alr_at 200 ms, alr_rt
   1000 ms), the peak side neutralized (th = 0 dBFS; upstream brickwall
   already caps at −1), knee tuned by measured sweep to 1.25: a pinned
   full-scale sine trims −1.65 dB (~32 % less coil power) over ~1 s while
   loud pink program loses only 0.34 dB in its very loudest sustained
   windows. Getting here found platform bugs #10/#11: LSP
   `compressor_stereo` won't instantiate in filter-chain at all, and a
   second `mb_compressor` instance loads but its band compression is
   silently dead (crush-test verified) — a second `limiter_stereo` works.

Net loudness across the 2026-07-21 passes: **+4.5 dB RMS** (pink noise)
over the original +8 dB tune, peaks always caught at −1 dBFS.

LV2-in-graph safety was verified by measurement (2026-07-16): LSP keeps
processing at 100 %/50 %/25 % sink volume — the LADSPA skip bug (#2 below)
does not apply to LV2. Sink volume is applied *before* the graph.

## The 2026-08-02 pass (gain structure + adaptive layer)

Nine changes, each gated on measurement. Two proposed stages were **measured and
rejected** — recorded here because "we tried it and here is the number" is worth
more than silence.

| # | Change | Measured result |
|---|---|---|
| **S0** | Reclaim discarded analog output: hardware sink pinned to 0 dB, `drive` 3.6 → 2.5 | The chain drove to −1 dBFS and the analog mixer then threw away **7.00 dB**. Both sinks share one hardware control, so any level left behind by quiet listening on the raw sink silently attenuated the tuned path. Net **+4.4 dB** vs the old tune |
| **S1** | Thermal guard re-tuned, `knee` 1.25 → 0.85 | **Mandatory after S0.** The guard is digital and cannot see the analog change: at the old knee, sustained content would have delivered **+7.1 dB more coil power**, roughly double what was intended. 0.85 lands it at +3.9 dB for 0.7 dB off loud pink |
| **S2a** | Staggered second HP section at 0.75 × the corner | **−10.3 dB at 110 Hz for −0.2 dB at 400 Hz.** One 12 dB/oct section was the only excursion protection |
| **S2b** | Overboost `body` +5 → +8 dB, clawed back by `mbc` band 0 (Down mode) | **+1.98 dB when quiet, −0.09 mid, +0.03 loud.** Ratio matters far more than threshold — anything above `cr` 1.5 removes more than the boost and makes mid-level content *quieter* than before |
| **S4** | Limiter `ovs` 0 → 6; bass release 10 → 60 ms, vocal 5 → 20 ms | 10 ms was ~3 periods of 300 Hz content, so the bass band tracked the waveform rather than the programme. Latency cost **1.29 ms** |
| **S5** | Shaped shuffler: side path +5 dB @ 1.8 kHz → LP 8 kHz | Side gain was flat above 350 Hz; widening now peaks where ITD/ILD cues live. Adds no L/R asymmetry |
| **S6** | Static treble cut −6 → −3 dB, GOTT band 4 deepened | **Quiet +1.7/+2.4/+3.0/+2.4 dB at 8/9/10.5/12 kHz; loud +0.1/−0.3 dB.** Subjectively near-indistinguishable — kept because there is no measured downside and the lookahead hard cap (`lim th_4`) is untouched |
| **S7** | Split-band harmonic generation for the psycho-bass | **IMD-to-harmonic ratio −1.4 → −10.8 dB.** The fix for "kick and bassline turn to mush" |
| **S8** | Loudness normalization across sources (`autogain_stereo`) | **18 dB source difference → 2.4 dB at the output.** Dynamics preserved — the block envelope is identical at `max_amp` 12/8/6, proving it is not chasing within-track level |
| **P1** | `snd_hda_intel power_save` 1 → 15 s | Stops EAPD dropping the amp ~6 s into silence (pop + truncated first note). **Not** `power_save=0`, and **not** `suspend-timeout-seconds=0` — keeping the sink RUNNING makes the graph process silence forever, costing far more battery than the codec it would protect |

### Measured and rejected

| Stage | Why it is not enabled |
|---|---|
| **S3** crest clipper | Works — but `ct` is inert without `thresh` + `boost`. Once driven properly: **+0.56 dB for 26.7 % THD** at the gentlest setting, +1.13 dB for 38.6 %. Quiet content is untouched at every setting, so the level-dependence is correct; the trade simply is not worth it on a distortion-limited driver. Left in-graph, bypassed (`ce = 0`), for A/B |
| **S2c** Linkwitz Transform | The driver falls **20.6 dB from 700 → 420 Hz**. Flattening that needs ~+20 dB at 420 Hz, far past the excursion budget. The region is **excursion-limited, not filter-limited** — a matched filter cannot fix a limit that is not in the filters. A single-pass fit also could not identify Q (flat error surface from 2.5 to 3.8) |
| **S9** per-content profiles | **Impossible on this system.** Chromium routes every tab through one audio process: a movie stream and a music stream are byte-identical — same PID, `media.name = "Playback"` on both, no `media.role`, no `media.category`. There is no signal to classify on |
| **P2** realtime priority | A no-op here: `pipewire.service` already ships `LimitRTPRIO=95` and `LimitMEMLOCK=infinity`, `RestrictRealtime=no`, and the running process really has `RLIMIT_RTPRIO 95/95`. Threads are nevertheless `SCHED_OTHER`; RTKit caps at 20 while PipeWire requests 88, but forcing 20 did not help either. **Root cause unresolved — costs nothing today** (zero xruns, low single-digit % of one core) |
| **P3** 96 kHz graph rate | Existed to reduce `mb_clipper` aliasing, which died with S3. The remaining benefit was latency, now measured at 1.29 ms — nothing to fix. The negotiated quantum (2048) dominates latency anyway and is the cheaper lever |

## Feature status — iPhone-style DSP checklist

| Feature | Status | Where |
|---|---|---|
| Advanced real-time DSP | ✔ | full chain, low single-digit % of one core; ~5 ms limiter lookahead + a few ms from the two linear-phase FFT stages |
| Dynamic EQ that adjusts with volume | ✔ | ISO 226 loudness contour + `speaker-loudness` volume follower |
| Multi-band compression keeping vocals clear | ✔ | 4-band limiter, ceilings −2.5/−3/−4/−9 dB (bass/vocal/presence/air) — treble capped hardest so loudness never turns piercing |
| Upward compression lifting quiet vocals/detail | ✔ | GOTT two-sided leveler (default): ~+8.5 dB quiet bass/vocal detail, unity when loud; capped 5-band mbc stage kept switchable |
| Dynamic EQ cutting the vocal masker only when needed | ✔ | −3.5 dB static box cut always on; the extra dynamic 2:1 cut lives in the bypassed mbc stage (GOTT covers the region with downward leveling above −5 dBFS) |
| Bass enhancement (deeper-bass illusion) | ✔ | psycho-acoustic harmonics placed in the driver's ~300–800 Hz band, dynamically ducked |
| Intelligent distortion limiting | ✔ | per-band lookahead limiting + −1 dBFS brickwall (DAC never hard-clips) + HP270 excursion protection |
| Stereo widening / spatial | ✔ | vocal-safe mid/side widener (side-only, >350 Hz) |
| Loud without harsh | ✔ | +11 dB drive with peaks caught cleanly instead of clipping (2026-07-21 passes: +4.5 dB RMS total vs the old +8 dB tune, pink-noise measured) |
| Balanced response (clear bass / natural mids / smooth treble) | ✔ | measured corrective EQ + unequal band ceilings pinning the 10–11 kHz metallic peak |
| High-resolution correction between EQ points (per-unit calibration style) | ✔ 2026-07-23 | 1/12-octave 3-pass measurement → min-phase FIR convolver; box-hump and true 9 kHz peak fixed |
| Excursion-modeled dynamic bass (bass depth follows playback level) | ✔ 2026-07-23 | volume-follower moves the HP corner 270→170 Hz as the knob drops; THD-vs-level measured |
| Thermal power protection | ✔ 2026-07-23 | slow ALR guard post-brickwall: −1.65 dB on pinned content, ≤0.34 dB on music |

Tuning knobs are documented at the top of the conf; edit, then
`systemctl --user restart pipewire wireplumber`.

## Platform bugs found on PipeWire 1.6.2 / WirePlumber 0.5.13 (all measured)

1. **`filter.smart = true` silently bypasses the DSP graph** — streams route
   through the filter nodes but audio is bit-exact passthrough. Never use
   smart filters on this stack without capture-verifying.
2. **Volume ≠ 100% on a graph-hosting virtual sink corrupts LADSPA
   processing** (LADSPA nodes skipped, volume applied multiple times).
   LV2 nodes are NOT affected (verified by measurement at 100/50/25 %
   volume, 2026-07-16) — hence LADSPA stays banned but LSP LV2 is used.
3. **Stacked virtual sinks cascade volume multiplicatively** (~4× in dB) — a
   front "volume sink" feeding a DSP sink is unusable.
4. `channelmix.lock-volumes=true` makes the adapter reject volume updates
   outright (GNOME slider snaps back); `channelmix.disable` doesn't stop the
   cascade.
5. **Hiding a node from pulse clients (permissions) breaks any client whose
   playback stream links to it** (`timeout on stream`, silence, GNOME
   Settings crash). Only the DSP's internal output stream is hidden, and only
   from GNOME's mixer connections (libgvc: `application.id =
   org.gnome.VolumeControl` + icon `multimedia-volume-control`).
6. Builtin port names: `bq_*`/`copy`/`linear` use `In`/`Out`; `mixer`/`mult`
   use `In 1..8`; `dcblock` uses `In 1`/`Out 1`. `linear` controls:
   `Mult`/`Offset`. WirePlumber Lua scripts load only from *data* dirs
   (`/usr/local/share/wireplumber/scripts`, `~/.local/share/...`) — config
   dirs make WirePlumber exit 78.
7. Verify DSP with digital capture, never ears:
   `pw-record -P stream.capture.sink=true --target <sink> --format s16 out.wav`
   (stop with SIGINT). Plain pulse monitor captures get volume-scaled.
8. **LSP multiband band params mis-map with gap-indexed splits** — enabling
   crossover splits non-consecutively (`se_2/se_4/se_6`) binds bands to
   unexpected param indices (measured: vocals on `th_3` not `th_2`) and can
   leave whole regions with NO active band processing (>2500 Hz was never
   limited); runtime `th`/`on` sets on structurally-inactive bands are
   silently ignored. Always enable splits consecutively from `se_1` and
   verify each band's ceiling with a tone capture.
9. **One output port drives one link** — fanning a node's output to several
   links can silently time-skew the copies (measured: an M/S widener fed
   from an LV2 node's fanned output produced a phantom 90°-shifted side
   signal that broke mono cancellation; the engine logs "already used by
   link, use copy" only in some arrangements). Always fan out through
   explicit `copy` nodes.
10. **LSP `compressor_stereo` does not instantiate inside filter-chain** —
   the whole sink fails to load with only `invalid message id:2 op:2`
   (Invalid argument) in the journal. Same graph loads fine the moment the
   node is swapped for `limiter_stereo`; mbc/gott/loud_comp also fine.
11. **A second `mb_compressor_stereo` instance is silently non-functional**
   — it loads, passes audio, `g_wet` works, but band compression does
   NOTHING (crush-test al 0.01 / cr 100 / at 5 = zero effect on any band,
   with or without conf-built splits, both crossover modes; the first
   instance's bands measurably work). Also: with no splits enabled at
   graph build, a lone band 0 never compresses, and runtime `cbe_*` split
   enables are structural = silently ignored (bug #8 family). A second
   `limiter_stereo` instance works — used for the thermal guard.
12. **Default-sink fallback silently prefers the raw sink over a virtual sink**
   — WirePlumber scores candidates in bands (`scripts/default-nodes/`):
   configured default `30000 + prio`, selection history
   `20001 + prio − position`, plain fallback `prio`. A history position is
   worth only ±1, so the stock 1000 vs the DSP sink's 900 decides everything
   below the 30000 band: losing the configured default (unplugging headphones
   that were last selected) put audio on raw at 20998 over the DSP sink's
   20899, bypassing the whole chain — and with the raw sink hidden from
   GNOME's mixer, left the GNOME slider adjusting an idle node. Fixed by
   demoting raw to `priority.session = 100`
   (`files/51-speaker-sink-priority.conf`); raising the DSP sink above 1000
   instead would also outrank an explicit `speaker-dsp off`.

13. **Capturing the DSP sink's own monitor gives you PRE-processing audio** —
   `pw-record -P stream.capture.sink=true --target effect_input.speaker-tuning`
   returns what was *written into* the sink, not what the graph produced. Every
   parameter looks inert. This cost hours on 2026-08-02 and nearly got two
   working plugins declared dead. **Capture the monitor of the sink the chain
   outputs TO** (`alsa_output.…Speaker__sink`) — that is the graph's output.
   Always control-test the rig first with a parameter that *must* work
   (`g_out` on any LSP node): if that does not move the measurement, the
   measurement is wrong, not the plugin.
14. **LSP clipper `ct` does nothing on its own** — the sigmoid threshold reads
   back correctly and is completely inert: 0.9/0.7/0.5/0.3 measured
   bit-identical. The real controls are **`thresh` (dB) plus `boost` = 1**;
   with `thresh = 0` the clipper never engages whatever `ct` says. Applies to
   `clipper_stereo` and `mb_clipper_stereo` alike.
15. **filter-chain reports ZERO latency** — both `Latency` and `ProcessLatency`
   enumerate as zeros regardless of what the hosted plugins actually add
   (measured: `lim ovs=6` costs a real 1.29 ms). So plugin latency is never
   advertised to applications and **cannot be compensated for lip-sync** — it
   simply has to stay small. Budget accordingly rather than relying on
   PipeWire to declare it.
16. **Chromium-family browsers expose no per-stream classification** — Brave
   (and Chrome/Chromium) route every tab through one shared audio process.
   Two simultaneous streams, one a movie and one music, are byte-identical:
   same `application.process.id`, `media.name = "Playback"` on both, no
   `media.role`, no `media.category`, not even the tab title. Any
   content-aware profile switching keyed on stream metadata is impossible on
   such a system; only a manual toggle can work.

## Troubleshooting

- **GNOME shows no Speaker entry at all** → the DSP sink failed to load,
  most likely because `lsp-plugins-lv2` was removed (the limiter needs it).
  Confirm with `journalctl --user -u pipewire -b | grep -i filter`, then
  reinstall the package. Audio itself keeps working meanwhile: run
  `speaker-dsp off` to use the raw sink (it is only hidden from the GNOME
  mixer, not from pactl/players).
- **GNOME's volume slider does nothing but `alsamixer` still works** → audio is
  on the raw sink while GNOME's mixer can only see the DSP sink, so the slider
  is adjusting an idle node; `alsamixer` drives the codec's hardware mixer,
  downstream of the whole graph. Confirm with `speaker-dsp status` (reports
  `RAW`), fix with `speaker-dsp on`. If it returns on its own after unplugging
  headphones, `51-speaker-sink-priority.conf` is missing from
  `/etc/wireplumber/wireplumber.conf.d/` — see platform bug #12.
- **Highs hurt / piercing treble on bright songs** → the 2026-07-22 fix
  capped presence/air (`lim th_3/th_4`); if still too hot, lower `th_3`
  (0.63 → 0.56 = −5 dB) / `th_4` (0.355 → 0.32), or weaken the GOTT
  presence up-lift (`ru_3`, `tu_3`). All dynamic — quiet detail unaffected.
- **Echo-like swell / washy-roomy vocals** → the adaptive stage is lifting
  reverb tails too much or too fast. On the default GOTT stage: raise the
  `tm_*` floor (less tail lift) or slow `tr_*`; or switch to the drier
  capped mbc stage (swap commands in the conf). On the mbc stage: keep
  `mode = 2` (linear phase — mode 1 combs = metallic), releases `rt_*` at
  400–800 ms, lifts `bsa_*` ≤ ~1.6; see the ECHO WARNING knob note in the
  conf. (If lipsync ever bothers you in video, `mode = 1` trades a few ms
  latency for a slight metallic tint.)
- **No sound after suspend/resume or a PipeWire package update** →
  `systemctl --user restart pipewire pipewire-pulse wireplumber`.
- **`pw-dump`/`pw-cli e` shows all DSP params as 0.000** → the node is
  suspended; suspended filter-chain nodes enumerate params as zeros (values
  are intact and sets still apply). Play any audio and re-read. **This is by
  far the easiest trap in the whole project to fall into** — it looks exactly
  like "the daemon isn't writing" or "readback is broken", and it re-caught us
  on 2026-08-02. Confirmed working while RUNNING: `drive_l:Mult 2.5`,
  `lim:th 0.891`, `lim:ovs 6.0`, `body_l:Gain 8.0`, `hp_l:Freq 240.0`
  (the daemon's live corner map). Check the sink state *first*:
  `pactl list sinks short | grep speaker-tuning`.

## Known hardware issues (unrelated to DSP)

- **Mic1 "Digital Microphone" is broken** (kernel/firmware DMIC fault —
  outputs full-scale digital garbage). Mic2 "Stereo Microphone" works, but
  its jack is misreported as unplugged, so WirePlumber keeps reverting the
  default to Mic1. **Manually select "Stereo Microphone" in GNOME Settings →
  Sound → Input.** Real fix needs a kernel/UCM quirk.

## Install (system-wide, all users)

```sh
cd ~/speaker-dsp
sudo sh install.sh          # installs to /etc + /usr/local, removes user-level copies
systemctl --user restart pipewire pipewire-pulse wireplumber   # per logged-in user
```

`install.sh` also writes `power_save=15` straight to `/sys` (P1), because
`modprobe.d` only takes effect at module load and `snd_hda_intel` is already
up — otherwise the pop fix would silently wait for the next reboot.

**Not installed, deliberately:** a realtime-priority drop-in. See platform bug
#12b/P2 above — the limits it would set are already set, so it would be a
placebo. Revisit only if xruns ever appear.

## Verify after install

```sh
pactl list sinks short        # both sinks listed, exactly one effect_input
speaker-dsp status
paplay /usr/share/sounds/freedesktop/stereo/complete.oga
journalctl --user -u pipewire -b | grep -ci error    # 0
```

## Uninstall

```sh
systemctl --user disable --now speaker-loudness 2>/dev/null
sudo rm /etc/pipewire/pipewire.conf.d/50-speaker-tuning.conf \
        /usr/local/share/wireplumber/scripts/hide-speaker-tuning.lua \
        /etc/wireplumber/wireplumber.conf.d/50-hide-speaker-tuning.conf \
        /etc/wireplumber/wireplumber.conf.d/51-speaker-sink-priority.conf \
        /etc/modprobe.d/speaker-dsp-powersave.conf \
        /usr/local/bin/speaker-dsp \
        /usr/local/bin/speaker-loudness-follow \
        /etc/systemd/user/speaker-loudness.service
echo 1 | sudo tee /sys/module/snd_hda_intel/parameters/power_save   # restore stock idle timeout
sudo rm -r /usr/local/share/speaker-dsp
systemctl --user restart pipewire pipewire-pulse wireplumber
```
