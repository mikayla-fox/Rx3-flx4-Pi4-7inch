#!/usr/bin/env bash
# Pi 4 + original Raspberry Pi 7-inch display, combined v9b + Pi-tested browse-knob fix installation.
set -Eeuo pipefail
repo="$(cd "$(dirname "$0")" && pwd)"
cd "$repo/rx3-handoff"
. ./rx3-env.sh
mode="${1:---fresh}"
case "$mode" in --fresh|--update) ;; *) echo 'Usage: bash install-rx3.sh [--fresh|--update]' >&2; exit 2;; esac
[ "$(id -u)" != 0 ] || { echo 'Run as your normal Pi user, not sudo bash.' >&2; exit 1; }
if [ "$mode" = --fresh ] && [ -e "$RX3_ROOT/root/pdj/rbp" ]; then
 echo 'An RX3 runtime already exists. Use --update to preserve it.' >&2; exit 1
fi
if [ "$mode" = --update ] && [ ! -e "$RX3_ROOT/root/pdj/rbp" ]; then
 echo 'No existing RX3 runtime found. Use --fresh.' >&2; exit 1
fi
sudo -v
# Keep the old installation recoverable. A separate checkout also preserves old sources.
backup="$(mktemp -d "$RX3_USERHOME/RX3-INSTALL-BACKUP-XXXXXXXX")"
mkdir -p "$backup/binaries" "$backup/runtime" "$backup/config"
for f in rx3-fb-present rx3-touch-bridge; do
 [ ! -e "$RX3_BINDIR/$f" ] || cp -p "$RX3_BINDIR/$f" "$backup/binaries/"
done
[ ! -e "$RX3_ROOT/lib/fbshim.so" ] || cp -p "$RX3_ROOT/lib/fbshim.so" "$backup/runtime/"
for f in /etc/systemd/system/rx3.service /etc/udev/rules.d/9*-rx3*.rules; do
 [ ! -f "$f" ] || cp -p "$f" "$backup/config/"
done
echo "Backup: $backup"
trap 'echo "Installation stopped at line $LINENO. Backup retained: $backup. No reboot was requested." >&2' ERR
bash ./install.sh deps
# Build host helpers before any installed executable is replaced.
stage="$(mktemp -d)"
trap 'rm -rf "$stage"' EXIT
root_define="-DRX3_ROOT_PATH=\"$RX3_ROOT\""
gcc -O3 -march=native -Werror=implicit-function-declaration "$root_define" \
 $(pkg-config --cflags freetype2 libdrm) -o "$stage/rx3-fb-present" fb-present.c \
 $(pkg-config --libs freetype2 libdrm) -lm
gcc -O2 -Werror=implicit-function-declaration "$root_define" -o "$stage/rx3-touch-bridge" touch-bridge.c
python3 -m py_compile controller-bridge.py
if [ "$mode" = --fresh ]; then
 python3 recover-firmware.py
 python3 extract_cramfs.py
 bash ./build-rootfs.sh
fi
# install.sh replaces helper binaries and the shim by rename, without restarting RX3.
bash ./install.sh
sudo systemctl mask getty@tty1.service
sudo systemctl enable rx3.service
printf '\nCombined v9b + browse-knob fix files installed. A full reboot is required to activate them.\n'
printf 'When ready: sudo reboot\nBackup: %s\n' "$backup"
