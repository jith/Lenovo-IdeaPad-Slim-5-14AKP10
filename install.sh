#!/bin/sh
# Installer for the IdeaPad speaker tuning DSP (see README.md).
# Run from this directory:  sudo sh install.sh
set -e
[ "$(id -u)" = "0" ] || { echo "run with sudo"; exit 1; }
cd "$(dirname "$0")/files"

# The limiter in the DSP chain is LSP Limiter Stereo (LV2).
[ -d /usr/lib/lv2/lsp-plugins.lv2 ] || \
    echo "WARNING: lsp-plugins-lv2 not found - install it (apt install lsp-plugins-lv2) or the DSP sink will fail to load."

install -D -m644 50-speaker-tuning.conf      /etc/pipewire/pipewire.conf.d/50-speaker-tuning.conf
install -D -m644 fir-correction.wav          /usr/local/share/speaker-dsp/fir-correction.wav
install -D -m644 hide-speaker-tuning.lua     /usr/local/share/wireplumber/scripts/hide-speaker-tuning.lua
install -D -m644 50-hide-speaker-tuning.conf /etc/wireplumber/wireplumber.conf.d/50-hide-speaker-tuning.conf
install -D -m644 51-speaker-sink-priority.conf /etc/wireplumber/wireplumber.conf.d/51-speaker-sink-priority.conf
install -D -m755 speaker-dsp                 /usr/local/bin/speaker-dsp
install -D -m755 speaker-loudness-follow     /usr/local/bin/speaker-loudness-follow
install -D -m644 speaker-loudness.service    /etc/systemd/user/speaker-loudness.service
install -D -m644 speaker-dsp-powersave.conf  /etc/modprobe.d/speaker-dsp-powersave.conf
systemctl --global enable speaker-loudness.service >/dev/null 2>&1 || true

# P1 (2026-08-02). modprobe.d only applies at module load, so write the value
# now for the already-loaded module or the fix waits for the next reboot.
[ -w /sys/module/snd_hda_intel/parameters/power_save ] \
    && echo 15 > /sys/module/snd_hda_intel/parameters/power_save 2>/dev/null || true

# CRITICAL on Ubuntu 26.04: `tuned` is the power manager (NOT tlp or
# power-profiles-daemon), and its *_powertop profiles contain a [sysfs] stanza
# that writes /sys/module/snd_hda_intel/parameters/power_save=1 AFTER boot -
# silently undoing both modprobe.d and any direct write. Point the everyday
# profiles at 15. powersave_powertop is deliberately left at 1: choosing that
# profile is an explicit request to trade quality for battery.
for p in balanced_powertop balanced-battery_powertop; do
    f="/etc/tuned/profiles/$p/tuned.conf"
    [ -f "$f" ] || continue
    grep -q '^/sys/module/snd_hda_intel/parameters/power_save=1$' "$f" || continue
    cp -n "$f" "$f.bak-speaker-dsp" 2>/dev/null || true
    sed -i 's|^/sys/module/snd_hda_intel/parameters/power_save=1$|/sys/module/snd_hda_intel/parameters/power_save=15|' "$f"
done
command -v tuned-adm >/dev/null 2>&1 && tuned-adm profile "$(tuned-adm active 2>/dev/null | sed 's/.*: //')" >/dev/null 2>&1 || true

# Remove user-level copies so nothing double-loads or shadows the system
# files (user pipewire conf fragments MERGE with /etc -> two DSP sinks!).
U="${SUDO_USER:-sreejith}"
H=$(getent passwd "$U" | cut -d: -f6)
rm -f "$H/.config/pipewire/pipewire.conf.d/50-speaker-tuning.conf" \
      "$H/.config/wireplumber/wireplumber.conf.d/51-speaker-sink-priority.conf" \
      "$H/.local/share/wireplumber/scripts/hide-speaker-tuning.lua" \
      "$H/.local/bin/speaker-dsp" \
      "$H/.local/bin/speaker-loudness-follow" \
      "$H/.config/systemd/user/speaker-loudness.service"

echo "Installed system-wide. Each logged-in user should now run:"
echo "  systemctl --user restart pipewire pipewire-pulse wireplumber"
echo "  systemctl --user daemon-reload && systemctl --user restart speaker-loudness"
