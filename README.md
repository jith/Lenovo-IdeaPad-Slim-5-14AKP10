# Speaker Tuning DSP — Lenovo IdeaPad Slim 5 14AKP10

Dolby-style speaker enhancement for Linux: EQ + loudness maximizer that makes
the internal speakers noticeably louder and clearer, while GNOME Settings
keeps showing a single, clean **Speaker** output device.

Set up 2026-07-13 with Claude Code. Installed **system-wide** — applies to
every user account on this machine.

## System

| | |
|---|---|
| Laptop | Lenovo IdeaPad Slim 5 14AKP10 (83HX) |
| Speakers | Stereo 2 W × 2, front-firing, "optimized with Dolby Audio" (Windows-only DSP — this setup replicates it) |
| Codec | Conexant/Senary SN6140 (ALSA card 1, `snd_hda_intel`) |
| OS | Ubuntu 26.04 LTS, kernel 7.0, GNOME Shell 50.1 |
| Audio stack | PipeWire 1.6.2, WirePlumber 0.5.13 |
| Dependency | `swh-plugins` (LADSPA Fast Lookahead Limiter), `pipewire`/`wireplumber` stock |

The hardware mixer path (Master / Speaker / PCM) maxes out at 0 dB with no
positive gain available, so all loudness improvement is done in DSP.

## How it works

1. **Smart filter DSP** (`50-speaker-tuning.conf`): a PipeWire filter-chain
   with `filter.smart = true`. WirePlumber automatically inserts it between
   every application stream and the physical Speaker sink. It never applies
   to headphones, USB or Bluetooth outputs (`filter.smart.target` is pinned
   to the internal speaker sink). Signal chain per channel:

   | Stage | Setting | Purpose |
   |---|---|---|
   | High-pass | 105 Hz, Q 0.707 | Remove sub-bass the drivers can't play; frees headroom |
   | Peaking | 220 Hz, Q 1.1, +2.5 dB | Warmth/body |
   | Peaking | 3.2 kHz, Q 1.6, +2.0 dB | Dialog/vocal presence |
   | High-shelf | 8.5 kHz, Q 0.707, +2.5 dB | Air/detail |
   | Limiter (swh 1913) | +6.5 dB drive, −0.3 dB ceiling, 90 ms release | Loudness maximizer, no clipping |

   Net effect: ~+7–9 dB perceived loudness on typical content, ~5 ms latency.

2. **GNOME single-device view** (`hide-speaker-tuning.lua` +
   `50-hide-speaker-tuning.conf`): a WirePlumber script that revokes
   visibility of the two internal DSP nodes (`effect_input/output.speaker-tuning`)
   from the GNOME mixer connections only — identified by
   `application.id = org.gnome.VolumeControl` **and**
   `application.icon-name = multimedia-volume-control`. GNOME Settings and
   the shell volume menu show only the physical Speaker; volume keys control
   real hardware volume.

   ⚠️ **Never widen the hiding to all pulse clients.** A pulse client whose
   playback stream is linked to a node it cannot see times out
   (`mod.protocol-pulse: timeout on stream`) → silent audio and GNOME
   Settings crashes. `pactl`/`pavucontrol` intentionally still see the DSP
   sink — that is required and harmless.

3. **Toggle** (`speaker-dsp`): instant live A/B bypass via the WirePlumber
   `filters` metadata (`filter.smart.disabled`). State resets to *DSP active*
   on reboot.

## Installed file locations

| File | Purpose |
|---|---|
| `/etc/pipewire/pipewire.conf.d/50-speaker-tuning.conf` | DSP chain definition |
| `/usr/local/share/wireplumber/scripts/hide-speaker-tuning.lua` | GNOME hiding script |
| `/etc/wireplumber/wireplumber.conf.d/50-hide-speaker-tuning.conf` | Loads the script |
| `/usr/local/bin/speaker-dsp` | A/B toggle command |

Note: WirePlumber loads Lua scripts only from **data** dirs
(`/usr/local/share/wireplumber/scripts`, `~/.local/share/wireplumber/scripts`).
Putting the script under `/etc/wireplumber/scripts/` or
`~/.config/wireplumber/scripts/` makes WirePlumber fail at startup
(exit 78/CONFIG) — learned the hard way, twice.

## Installation (fresh machine / after OS reinstall)

```sh
sudo apt install swh-plugins        # limiter plugin (ladspa)
cd ~/speaker-dsp
sudo sh install.sh
systemctl --user restart pipewire pipewire-pulse wireplumber   # per user
```

## Usage

```sh
speaker-dsp status   # show current state (no sudo needed)
speaker-dsp off      # instant raw speaker (A/B comparison)
speaker-dsp on       # back to tuned
```

Adjust loudness: edit `"Input gain (dB)"` in
`/etc/pipewire/pipewire.conf.d/50-speaker-tuning.conf`
(0 = no boost, 6.5 = default, ~10 = maximum useful), then restart the stack.

## Verification

```sh
wpctl status                 # Filters: one effect_input/output.speaker-tuning pair
pactl list sinks short       # both sinks listed (pulse view; GNOME shows one)
paplay /usr/share/sounds/freedesktop/stereo/complete.oga
pw-link -l | grep -A1 effect_input.speaker-tuning   # stream routed via DSP while playing
journalctl --user -u pipewire-pulse | grep -c timeout   # must be 0
```

GNOME Settings → Sound → Output should list exactly one device: **Speaker**.

## Uninstall

```sh
sudo rm /etc/pipewire/pipewire.conf.d/50-speaker-tuning.conf \
        /usr/local/share/wireplumber/scripts/hide-speaker-tuning.lua \
        /etc/wireplumber/wireplumber.conf.d/50-hide-speaker-tuning.conf \
        /usr/local/bin/speaker-dsp
systemctl --user restart pipewire pipewire-pulse wireplumber
```
