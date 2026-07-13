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

echo "Installed. Each logged-in user should now run:"
echo "  systemctl --user restart pipewire pipewire-pulse wireplumber"
