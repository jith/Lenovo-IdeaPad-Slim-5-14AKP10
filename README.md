# Speaker Tuning DSP — Lenovo IdeaPad Slim 5 14AKP10

Measurement-driven speaker enhancement for Linux: corrective EQ + psychoacoustic
bass + loudness drive for the laptop's 2 W × 2 front-firing speakers, deployed
as a selectable PipeWire sink. Built and verified with digital signal captures
(not by ear) on 2026-07-15.

| | |
|---|---|
| Laptop | Lenovo IdeaPad Slim 5 14AKP10 (83HX), aluminum chassis |
| Speakers | 2 × 2 W front-firing stereo (unbranded OEM micro-drivers; Lenovo spec: "stereo speakers, 2W x2", Dolby-processed on Windows only) |
| Amp/codec | Conexant/Senary SN6140 HDA codec, integrated stereo Class-D amp (`snd_hda_intel`, card 1, AMD Ryzen HDA controller 04:00.6) |
| OS / stack | Ubuntu 26.04, PipeWire 1.6.2, WirePlumber 0.5.13, GNOME 50.1 |
| Dependency | `lsp-plugins-lv2` (LSP Limiter Stereo); everything else is PipeWire builtins |

## The two outputs

| GNOME output | What it is | Volume |
|---|---|---|
| **Speaker (Tuned)** — default | DSP sink (`effect_input.speaker-tuning`) | Any volume. The sink's steep cubic taper (bug #2/#3 below) is measured by the `speaker-loudness` service, which compensates the tonal side with the ISO 226 contour |
| **Speaker** | Raw hardware sink | Normal hardware volume — use for quiet listening |

Switch anytime: `speaker-dsp on` / `speaker-dsp off` / `speaker-dsp status`
(or pick in GNOME Settings → Sound). `on` also resets the DSP sink to 100%.

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

## DSP chain (files/50-speaker-tuning.conf, all PipeWire builtins)

0. **Volume-aware loudness contour** (LSP Loudness Compensator, ISO 226,
   IIR mode): the `speaker-loudness-follow` daemon (systemd user service)
   tracks the volume knob and live-updates the contour — at low volume the
   EQ shifts to keep bass/treble perceptually balanced, exactly like
   phone-speaker DSPs. 1 kHz stays at unity (the sink's own cubic-taper
   attenuation is compensated inside the plugin, verified); defaults are
   flat so audio is unaffected if the daemon is down.
1. High-pass 270 Hz — remove the inaudible-distortion band
2. Body +3.5 dB @ 560 Hz — lowest octave the driver actually plays
3. Box cut −5.5 dB @ 800 Hz — flatten the measured hump (clarity)
4. Presence +3 dB @ 2.6 kHz — fill the measured dip
5. Metal cut −6 dB @ 10.5 kHz (wide) — tame the measured peak; the aluminum
   chassis makes this region dominate if left hot
6. Psychoacoustic bass: mono <250 Hz → x² + x³ harmonics → band-passed to
   350–650 Hz (where the driver is audible; sub-300 Hz residue removed by a
   cascaded high-pass — it's inaudible and would pump the limiter) → mixed in
7. **Dynamic bass** (dynamic EQ): the harmonic branch's own envelope
   (`abs → LP 5 Hz → clamp/log/exp` gain computer) gently ducks the
   harmonics on loud passages — punchy at normal levels, never piles up
8. Makeup drive +8 dB (`Mult = 2.5`) into **LSP Multiband Limiter Stereo**
   (LV2): 4 bands — bass <650 Hz, vocals 650–2500, presence 2500–8000, air
   >8000 — each true-lookahead limited independently with **unequal
   ceilings** (bass −4.4 dB, vocals −2 dB, presence −4 dB, air −9 dB), then
   a final −1 dBFS brickwall on the sum. Unequal on purpose: with equal
   ceilings the energy-heavy bass/mids limit constantly while treble never
   does, so loud music tilts metallic (measured). Vocals get the most
   headroom (clarity priority) and the 10–11 kHz band gets a hard dynamic
   cap. Dynamic separation: a bass peak compresses only the bass band
   (measured: 3 kHz output bit-identical beside a full-scale 500 Hz tone at
   the band stage). ALR and gain-boost are off everywhere (ALR measured to
   over-regulate sustained content ~11 dB; `envb` envelope tilt off —
   measured to over-limit mids ~5 dB). The DAC never hard-clips.

LV2-in-graph safety was verified by measurement (2026-07-16): LSP keeps
processing at 100 %/50 %/25 % sink volume — the LADSPA skip bug (#2 below)
does not apply to LV2. Sink volume is applied *before* the graph.

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

## Troubleshooting

- **GNOME shows no Speaker entry at all** → the DSP sink failed to load,
  most likely because `lsp-plugins-lv2` was removed (the limiter needs it).
  Confirm with `journalctl --user -u pipewire -b | grep -i filter`, then
  reinstall the package. Audio itself keeps working meanwhile: run
  `speaker-dsp off` to use the raw sink (it is only hidden from the GNOME
  mixer, not from pactl/players).
- **No sound after suspend/resume or a PipeWire package update** →
  `systemctl --user restart pipewire pipewire-pulse wireplumber`.
- **`pw-dump`/`pw-cli e` shows all DSP params as 0.000** → the node is
  suspended; suspended filter-chain nodes enumerate params as zeros (values
  are intact and sets still apply). Play any audio and re-read.

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
        /usr/local/bin/speaker-dsp \
        /usr/local/bin/speaker-loudness-follow \
        /etc/systemd/user/speaker-loudness.service
systemctl --user restart pipewire pipewire-pulse wireplumber
```
