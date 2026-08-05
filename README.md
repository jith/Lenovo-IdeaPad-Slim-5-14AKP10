# Speaker DSP starter

A clean PipeWire baseline for the Lenovo IdeaPad Slim 5 14AKP10 speakers.
It creates **Speaker (Tuning)** as a virtual stereo sink, but it currently
does no processing: each channel passes through an explicit `copy` node. Use
this as the known-good starting point for building and verifying filters from
scratch.

## What is installed

- `files/50-speaker-tuning.conf` creates the pass-through virtual sink and
  routes it to the physical laptop speaker.
- `files/50-hide-speaker-tuning.conf`,
  `files/51-speaker-sink-priority.conf`, and
  `files/hide-speaker-tuning.lua` keep **Speaker (Tuning)** as the one
  laptop-speaker entry shown by GNOME. The raw speaker remains available to
  PipeWire and `pactl`.
- `files/speaker-dsp` switches the default output between the virtual and raw
  speaker sinks.

## Install

```sh
cd ~/speaker-dsp
sudo sh install.sh
systemctl --user restart pipewire pipewire-pulse wireplumber
speaker-dsp on
```

`install.sh` installs the system-wide starter configuration and helper.

## Use the speaker helper

```sh
speaker-dsp on       # Speaker (Tuning): current pass-through starter
speaker-dsp off      # raw hardware speaker
speaker-dsp status
```

GNOME hides the raw speaker to avoid a duplicate output entry. If you run
`speaker-dsp off`, use `speaker-dsp on` to return to the virtual sink.

## Verify

```sh
pactl list sinks short
speaker-dsp status
paplay /usr/share/sounds/freedesktop/stereo/complete.oga
```

`effect_input.speaker-tuning` should appear in `pactl list sinks short` and
audio should pass through unchanged. If it does not appear, inspect the
current-user PipeWire log:

```sh
journalctl --user -u pipewire -b --no-pager
```

## Build filters from scratch

Edit `files/50-speaker-tuning.conf`, reinstall, then restart PipeWire. Add
one matched left/right stage at a time and verify that the graph loads before
adding another. The `left` and `right` `copy` nodes are the baseline to
replace or extend.

The configuration and helper both use this physical speaker node name:

```text
alsa_output.pci-0000_04_00.6.HiFi__Speaker__sink
```

If `pactl list sinks short` reports a different name on your machine, update
both `playback.props.target.object` in `files/50-speaker-tuning.conf` and
`RAW` in `files/speaker-dsp`.

## Remove

```sh
sudo sh install.sh uninstall
```

Then run the three user-level `systemctl` commands shown in the install step.
