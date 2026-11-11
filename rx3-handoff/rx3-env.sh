# Resolve the RX3 install layout. Sourced by every script in this directory:
#   . "$(dirname "$(readlink -f "$0")")/rx3-env.sh"
#
# Nothing here is hardcoded to a particular username. RX3_HOME is wherever this
# file lives; the account that owns it is the account the player runs as, and
# that account's home directory holds the chroot, the USB overlays and the logs.
# Every value can be overridden by exporting it before the script runs.
RX3_HOME="${RX3_HOME:-$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)}"
RX3_USER="${RX3_USER:-$(stat -c %U "$RX3_HOME" 2>/dev/null)}"
: "${RX3_USER:=$(id -un)}"
RX3_USERHOME="${RX3_USERHOME:-$(getent passwd "$RX3_USER" 2>/dev/null | cut -d: -f6)}"
: "${RX3_USERHOME:=$(dirname "$RX3_HOME")}"
RX3_ROOT="${RX3_ROOT:-$RX3_USERHOME/rx3-rootfs}"     # the ARM32 chroot
RX3_USB="${RX3_USB:-$RX3_USERHOME/rx3-usb}"          # USB copy-on-write layers
RX3_LOGDIR="${RX3_LOGDIR:-$RX3_USERHOME}"            # rx3-*.log
RX3_BINDIR="${RX3_BINDIR:-$RX3_USERHOME}"            # rx3-fb-present, rx3-touch-bridge
# Numeric identity of that account, and the groups the firmware needs inside the chroot
# (audio for ALSA, video for the framebuffer, input for the event devices). Resolved by name,
# because the numbers differ between distributions and between machines.
RX3_UID="${RX3_UID:-$(id -u "$RX3_USER" 2>/dev/null || echo 1000)}"
RX3_GID="${RX3_GID:-$( getent group video 2>/dev/null | cut -d: -f3)}"; : "${RX3_GID:=44}"
rx3_gid_of(){  getent group "$1" 2>/dev/null | cut -d: -f3; }
RX3_GROUPS="${RX3_GROUPS:-$(printf '%s,%s,%s' "$(rx3_gid_of audio)" "$(rx3_gid_of video)" "$(rx3_gid_of input)")}"
# Optional per-machine settings (RX3_FB, RX3_ROTATE, RX3_FONT ...): see INSTALL.md "Display".
[ -f "$RX3_HOME/rx3.conf" ] && . "$RX3_HOME/rx3.conf"
# Installer-managed display choices can override the existing rx3.conf defaults.
[ ! -f "$RX3_HOME/rx3-display.conf" ] || . "$RX3_HOME/rx3-display.conf"
RX3_DISPLAY="${RX3_DISPLAY:-auto}"
RX3_TOUCH_DEVICE="${RX3_TOUCH_DEVICE:-auto}"
rx3_board(){
  local compatible="${1:-/proc/device-tree/compatible}"
  if grep -aq 'brcm,bcm2711' "$compatible" 2>/dev/null; then
    echo pi4
  elif grep -aq 'brcm,bcm2712' "$compatible" 2>/dev/null; then
    echo pi5
  else
    echo unknown
  fi
}
RX3_BOARD=$(rx3_board)
rx3_pick_fb(){
  local graphics="${1:-/sys/class/graphics}" drm="${2:-/sys/class/drm}" devices="${3:-/dev}"
  local fb device card card_device connector status matches other
  for fb in "$graphics"/fb[0-9]*; do
    [ -e "$devices/${fb##*/}" ] || continue
    if [ "$RX3_DISPLAY" = auto ]; then
      case "$(cat "$fb/name" 2>/dev/null)" in *dsi*) echo "$devices/${fb##*/}"; return;; esac
      continue
    fi
    device=$(readlink -e "$fb/device") || continue
    for card in "$drm"/card[0-9]*; do
      [[ ${card##*/} =~ ^card[0-9]+$ ]] || continue
      card_device=$(readlink -e "$card/device") || continue
      if [ "$card_device" != "$device" ] && [ "$(readlink -e "$card")" != "$device" ]; then
        continue
      fi
      matches=0; other=0
      for connector in "$drm/${card##*/}"-*; do
        [ -r "$connector/status" ] || continue
        read -r status < "$connector/status"
        [ "$status" = connected ] || continue
        case "$RX3_DISPLAY:${connector##*/}" in
          dsi:*-DSI-*|hdmi:*-HDMI-*) matches=1;;
          *) other=1;;
        esac
      done
      if [ "$matches" = 1 ] && [ "$other" = 0 ]; then
        echo "$devices/${fb##*/}"
        return
      fi
    done
  done
  if [ "$RX3_DISPLAY" = auto ]; then
    for fb in "$graphics"/fb[0-9]*; do
      [ ! -e "$devices/${fb##*/}" ] || { echo "$devices/${fb##*/}"; return; }
    done
  fi
  return 0
}
RX3_FB="${RX3_FB:-$(rx3_pick_fb)}"
RX3_ROTATE="${RX3_ROTATE:-}"          # 0/90/180/270 clockwise; empty = portrait panels 90, landscape 0
RX3_FPS="${RX3_FPS:-}"                # presenter rate; empty = 60, synced to the panel's vertical blank
RX3_FILTER="${RX3_FILTER:-}"          # "nearest" to trade picture quality for CPU on slow boards
# Heat: the firmware redraws its whole screen ~54 times a second. When nothing has changed for 10 frames, redraw at
# RX3_FW_IDLE_FPS instead (0 = never slow down); RX3_FW_FPS caps every frame (empty = the firmware's own rate).
# RX3_CPU_MAX_MHZ caps the CPU clock while the player runs (lower clock, lower voltage: a Pi 5 playing a deck draws
# about a fifth less core power at 2000 than at 2400); 0 leaves the clock alone.
RX3_FW_IDLE_FPS="${RX3_FW_IDLE_FPS:-20}"
RX3_FW_FPS="${RX3_FW_FPS:-}"
RX3_CPU_MAX_MHZ="${RX3_CPU_MAX_MHZ:-2000}"
# QUANTIZE on both decks once the sticks are attached: off, on, or "firmware" (keep what the player/stick settings say).
RX3_QUANTIZE="${RX3_QUANTIZE:-off}"
# Restart the player if it exits or its audio stops (rx3-watchdog.sh); 0 to leave it alone.
RX3_AUTO_RESTART="${RX3_AUTO_RESTART:-1}"
export RX3_FB RX3_ROTATE RX3_FPS RX3_FILTER RX3_FW_IDLE_FPS RX3_FW_FPS RX3_CPU_MAX_MHZ RX3_QUANTIZE RX3_AUTO_RESTART

# A clone made with sudo leaves this directory owned by root, which would put the chroot somewhere
# like /root/rx3-rootfs. Judge that by the account's home directory rather than by uid, because the
# first-user uid differs between systems (1000 on Debian, 501 on macOS).
rx3_is_system_home(){ case "$1" in ''|/|/root|/nonexistent|/usr/sbin|/bin|/dev/null|/var/*|/run/*) return 0;; *) return 1;; esac; }
if { [ "${RX3_UID:-1000}" = 0 ] || rx3_is_system_home "$RX3_USERHOME"; } && [ -z "${RX3_ALLOW_SYSTEM_USER:-}" ]; then
  echo "WARNING: $RX3_HOME is owned by '$RX3_USER', whose home is $RX3_USERHOME," >&2
  echo "         so the chroot would be built at $RX3_ROOT." >&2
  echo "         Fix with:  sudo chown -R \$(id -un):\$(id -gn) \"$RX3_HOME\"" >&2
  echo "         Or set RX3_ALLOW_SYSTEM_USER=1 if this is deliberate." >&2
fi

export RX3_HOME RX3_USER RX3_USERHOME RX3_ROOT RX3_USB RX3_LOGDIR RX3_BINDIR RX3_UID RX3_GID RX3_GROUPS
