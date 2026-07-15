#!/bin/sh
# Installer for the IdeaPad speaker tuning DSP (see README.md).
# Run from this directory:  sudo sh install.sh
set -e
[ "$(id -u)" = "0" ] || { echo "run with sudo"; exit 1; }
cd "$(dirname "$0")/files"

install -D -m644 50-speaker-tuning.conf      /etc/pipewire/pipewire.conf.d/50-speaker-tuning.conf
install -D -m644 hide-speaker-tuning.lua     /usr/local/share/wireplumber/scripts/hide-speaker-tuning.lua
install -D -m644 50-hide-speaker-tuning.conf /etc/wireplumber/wireplumber.conf.d/50-hide-speaker-tuning.conf
install -D -m755 speaker-dsp                 /usr/local/bin/speaker-dsp

# Remove user-level copies so nothing double-loads or shadows the system
# files (user pipewire conf fragments MERGE with /etc -> two DSP sinks!).
U="${SUDO_USER:-sreejith}"
H=$(getent passwd "$U" | cut -d: -f6)
rm -f "$H/.config/pipewire/pipewire.conf.d/50-speaker-tuning.conf" \
      "$H/.local/share/wireplumber/scripts/hide-speaker-tuning.lua" \
      "$H/.local/bin/speaker-dsp"

echo "Installed system-wide. Each logged-in user should now run:"
echo "  systemctl --user restart pipewire pipewire-pulse wireplumber"
