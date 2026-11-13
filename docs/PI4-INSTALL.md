# Raspberry Pi 4 and 5 installation notes

Target: Raspberry Pi 4B, 4 GB; original 800×480 DSI touchscreen; Debian 13/trixie; DDJ-FLX4.

Use the root `install-rx3.sh` as described in the README. `--fresh` builds a new runtime; `--update` requires an existing runtime and never calls the runtime builder, preserving settings. Use a separate checkout when updating a trial installation. Both modes leave activation to a full reboot.

## Board and display setup

The installer checks the board, 64-bit host and ARM32 application support
before replacing installed RX3 files. An update uses the built runtime, so
a new checkout does not need its own copy of the extracted firmware. If your
old checkout has local settings, copy `rx3-handoff/rx3.conf` and, if present,
`rx3-handoff/rx3-display.conf` into the new checkout before updating.

| Setup | Installer option | Hardware status |
| --- | --- | --- |
| Original 7-inch DSI, 800×480 | Default or `--display dsi` | Existing Pi 4 baseline tested with automatic display selection |
| Raspberry Pi Touch Display 2 on Pi 5 | `--display dsi --rotate 270 --touch auto` for the tested mounting orientation | Existing install switched from HDMI. RX3 started upright and SOURCE and BROWSE touch alignment passed. |
| Other OS-supported DSI panels | `--display dsi`, with `--rotate 90` or `270` if needed | Trial |
| HDMI monitor or HDMI panel with USB touch | `--display hdmi` | Trial |
| Specific framebuffer | `--framebuffer /dev/fb1`, using the device your Pi reports | Trial |

Configure panel overlays and resolutions in Raspberry Pi OS. The RX3 installer
uses the framebuffer size reported by Linux. If multiple connector types share
a framebuffer, boot with only the desired screen enabled or choose the
framebuffer explicitly. For USB touch, leave `--touch auto` or pass a stable
`--touch /dev/input/by-id/…` or `by-path` event device. Use `--touch mouse`
to prefer a USB mouse. Touch input and the presenter share the same rotation.
Installer choices are saved in `rx3-handoff/rx3-display.conf`. `--display auto`
resets framebuffer selection, `--rotate auto` restores rotation detection and
`--touch auto` restores input detection.

To switch an existing Pi 5 install from HDMI to Touch Display 2, boot with the DSI panel attached and HDMI unplugged. From the installer checkout, run `bash install-rx3.sh --update --display dsi --rotate 270 --touch auto` and reboot after it succeeds. The hardware test applied the equivalent settings directly and restarted RX3. Rotation applies to the RX3 interface, so Linux boot text may still appear sideways.

For further Pi 5 validation, boot with the chosen panel attached and use a spare system
image for a fresh install. Check that the display and touch logs agree on
framebuffer resolution and rotation. Test controls at the four corners,
then verify startup, both decks, master and headphone output, and update mode.
Repeat on Pi 4 with the original DSI screen to check for regressions.

## Verification after reboot

Check SOURCE, BROWSE, USB1/USB2, native SEARCH and keyboard touch alignment. Check short taps and existing shortcut holds, the left-to-right hold fill, and POWER cancellation by releasing early or moving outside the button. A completed POWER hold shuts down the Pi.

Check FLX4 BROWSE-knob push from the main deck (must open the library), rotary track scrolling in BROWSE, and rotary push on a highlighted track (must open the load/deck-selection menu). This is the Pi-tested two-area detector: firmware white-pixel counts were deck 75/75 and library 204/0; the old additional regions were 0/0 on deck and caused a false negative. Check FLX4 playback, both audio channels/headphones, 4-beat loop and exit, Gate Cue and Beat FX channel selection. Confirm waveform behaviour and latency with wired audio. The combined fresh-install path is pending this hardware test.

## Mapping detail

The archived controller bridge is retained. Normal headphone CUE remains headphone cue; SHIFT + headphone CUE maps to per-deck QUANTIZE. The proposed change to make unshifted headphone CUE control QUANTIZE is not part of this archived implementation.

## Display timing

The preserved Pi-tested DRM VBlank implementation tries `/dev/dri/card1` and CRTC 92, then falls back to the configured software timer if unavailable. Different kernels may assign other IDs; inspect `~/rx3-present.log` if DRM timing is unavailable. No firmware renderer or audio algorithm is changed by the new top controls or keyboard colours.

## Backup and recovery

Before changing installed files, the combined installer saves host helper executables, the existing runtime shim, systemd service and RX3 udev rules in the printed `RX3-INSTALL-BACKUP-*` folder. Keep the original checkout too. If installation fails, do not reboot until the reported error is resolved or the saved files are restored. No automatic service restart or reboot is performed by the combined entry point.

The shared installer builds on the upstream Pi 5 runtime and installer in
[mutlisensor/Rx3-flx4](https://github.com/mutlisensor/Rx3-flx4). The board checks,
display selection and update path are changes in this fork.

## Checks completed for this consolidation

Both host C helpers compiled and linked on the build host, with implicit-function declarations treated as errors. Python bridge syntax and changed shell scripts passed syntax checks. A compiled layout check confirmed six non-overlapping button hit targets within 800×480 and the complete firmware viewport at 788×435, position (6,42). These checks do not replace ARM/Pi hardware testing.
