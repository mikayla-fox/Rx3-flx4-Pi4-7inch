#!/usr/bin/env bash
# Shared Raspberry Pi 4 and 5 installer.
set -Eeuo pipefail
version=v1.3.2
if [[ "${1:-}" == --version && "$#" -eq 1 ]]; then
 printf "RX3 installer %s\n" "$version"
 exit 0
fi
repo="$(cd "$(dirname "$0")" && pwd)"
cd "$repo/rx3-handoff"
. ./rx3-env.sh
usage(){
 cat <<'USAGE'
Usage: bash install-rx3.sh [--fresh|--update] [display options]
  --version                Print the installer version
  --display auto|dsi|hdmi   Select the display connection (default auto)
  --framebuffer /dev/fbN    Select a specific framebuffer
  --rotate auto|0|90|180|270
  --touch auto|mouse|/dev/input/eventN|/dev/input/by-id/...
USAGE
}
mode=--fresh
declare -A display_options=()
while [ "$#" -gt 0 ]; do
 case "$1" in
  --fresh|--update) mode=$1; shift; continue;;
  -h|--help) usage; exit 0;;
  --display|--framebuffer|--rotate|--touch)
   [ "$#" -ge 2 ] || { usage >&2; exit 2; }
   case "$1:$2" in
    --display:auto|--display:dsi|--display:hdmi)
      display_options[RX3_DISPLAY]=$2;;
    --framebuffer:*)
      [[ $2 =~ ^/dev/fb[0-9]+$ ]] || { usage >&2; exit 2; }
      display_options[RX3_FB]=$2;;
    --rotate:auto) display_options[RX3_ROTATE]='';;
    --rotate:0|--rotate:90|--rotate:180|--rotate:270) display_options[RX3_ROTATE]=$2;;
    --touch:auto|--touch:mouse) display_options[RX3_TOUCH_DEVICE]=$2;;
    --touch:*)
      [[ $2 =~ ^/dev/input/(event[0-9]+|by-(id|path)/[^/]+)$ ]] || { usage >&2; exit 2; }
      display_options[RX3_TOUCH_DEVICE]=$2;;
    *) usage >&2; exit 2;;
   esac
   shift 2;;
  *) usage >&2; exit 2;;
 esac
done
if [[ -v display_options[RX3_DISPLAY] && ! -v display_options[RX3_FB] ]]; then
 display_options[RX3_FB]=''
fi
[ "$(id -u)" != 0 ] || { echo 'Run as your normal Pi user, not sudo bash.' >&2; exit 1; }
case "$RX3_BOARD" in
 pi4|pi5) ;;
 *) echo 'This installer requires a Raspberry Pi 4 or 5.' >&2; exit 1;;
esac
if [ "$(uname -m)" != aarch64 ] || [ "$(getconf LONG_BIT)" != 64 ]; then
 echo 'Install a 64-bit Raspberry Pi OS or Debian system first.' >&2
 exit 1
fi
if [ "$mode" = --fresh ] && [ -e "$RX3_ROOT/root/pdj/rbp" ]; then
 echo 'An RX3 runtime already exists. Use --update to preserve it.' >&2; exit 1
fi
if [ "$mode" = --update ] && [ ! -x "$RX3_ROOT/root/pdj/rbp-pi" ]; then
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
# Check that the running kernel can execute the same ARM32 ABI as the player.
arm-linux-gnueabi-gcc -march=armv7-a -nostdlib -static -x assembler -o "$stage/arm32-check" - <<'ASM'
.global _start
_start:
 mov r0, #0
 mov r7, #1
 svc #0
ASM
if ! "$stage/arm32-check"; then
 echo 'This kernel could not run an ARM32 program. RX3 requires 32-bit ARM application support.' >&2
 exit 1
fi
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
if [ "$mode" = --update ]; then
 bash ./install.sh update
else
 bash ./install.sh
fi
if [ "${#display_options[@]}" -gt 0 ]; then
 # Keep settings from earlier installer runs and replace only the chosen keys.
 config=rx3-display.conf
 next_config=$(mktemp .rx3-display.XXXXXXXX)
 if [ -f "$config" ]; then
  while IFS= read -r line; do
   key=${line%%=*}
   case "$key" in
    RX3_DISPLAY|RX3_FB|RX3_ROTATE|RX3_TOUCH_DEVICE)
     [[ -v display_options[$key] ]] || printf '%s\n' "$line";;
   esac
  done < "$config" > "$next_config"
 fi
 for key in "${!display_options[@]}"; do
  printf '%s=%q\n' "$key" "${display_options[$key]}" >> "$next_config"
 done
 mv -f "$next_config" "$config"
fi
sudo systemctl mask getty@tty1.service
sudo systemctl enable rx3.service
printf '\nRX3 files installed for %s. A full reboot is required to activate them.\n' "$RX3_BOARD"
printf 'When ready: sudo reboot\nBackup: %s\n' "$backup"
