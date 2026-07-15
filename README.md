# Speaker Tuning DSP — Lenovo IdeaPad Slim 5 14AKP10

Measurement-driven speaker enhancement for Linux: corrective EQ + psychoacoustic
bass + loudness drive for the laptop's 2 W × 2 front-firing speakers, deployed
as a selectable PipeWire sink. Built and verified with digital signal captures
(not by ear) on 2026-07-15.

| | |
|---|---|
| Laptop | Lenovo IdeaPad Slim 5 14AKP10 (83HX) |
| Codec | Conexant/Senary SN6140 (`snd_hda_intel`, card 1) |
| OS / stack | Ubuntu 26.04, PipeWire 1.6.2, WirePlumber 0.5.13, GNOME 50.1 |
| Dependency | none beyond stock pipewire/wireplumber (chain is all-builtin) |

## The two outputs

| GNOME output | What it is | Volume |
|---|---|---|
| **Speaker (Tuned)** — default | DSP sink (`effect_input.speaker-tuning`) | Use at/near **100%** (see bug #2/#3 below: virtual-sink volume has a steep nonlinear taper) |
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

1. High-pass 270 Hz — remove the inaudible-distortion band
2. Body +2.5 dB @ 560 Hz — lowest octave the driver actually plays
3. Box cut −5.5 dB @ 800 Hz — flatten the measured hump (clarity)
4. Presence +3 dB @ 2.6 kHz — fill the measured dip
5. Metal cut −3.5 dB @ 10.5 kHz — tame the measured peak
6. Psychoacoustic bass: mono <250 Hz → x² + x³ harmonics → band-passed to
   350–650 Hz (where the driver is audible) → mixed back in
7. Static drive +4 dB (`Mult = 1.585`)

Tuning knobs are documented at the top of the conf; edit, then
`systemctl --user restart pipewire wireplumber`.

## Platform bugs found on PipeWire 1.6.2 / WirePlumber 0.5.13 (all measured)

1. **`filter.smart = true` silently bypasses the DSP graph** — streams route
   through the filter nodes but audio is bit-exact passthrough. Never use
   smart filters on this stack without capture-verifying.
2. **Volume ≠ 100% on a graph-hosting virtual sink corrupts processing**
   (LADSPA nodes skipped, volume applied multiple times). Hence: all-builtin
   graph + "use at 100%".
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
sudo rm /etc/pipewire/pipewire.conf.d/50-speaker-tuning.conf \
        /usr/local/share/wireplumber/scripts/hide-speaker-tuning.lua \
        /etc/wireplumber/wireplumber.conf.d/50-hide-speaker-tuning.conf \
        /usr/local/bin/speaker-dsp
systemctl --user restart pipewire pipewire-pulse wireplumber
```
