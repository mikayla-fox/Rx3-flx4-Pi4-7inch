# Combined Pi 4 installation notes

Target: Raspberry Pi 4B, 4 GB; original 800×480 DSI touchscreen; Debian 13/trixie; DDJ-FLX4.

Use the root `install-rx3.sh` as described in the README. `--fresh` builds a new runtime; `--update` requires an existing runtime and never calls the runtime builder, preserving settings. Use a separate checkout when updating a trial installation. Both modes leave activation to a full reboot.

## Verification after reboot

Check SOURCE, BROWSE, USB1/USB2, native SEARCH and keyboard touch alignment. Check short taps and existing shortcut holds, the left-to-right hold fill, and POWER cancellation by releasing early or moving outside the button. A completed POWER hold shuts down the Pi.

Check FLX4 BROWSE-knob push from the main deck (must open the library), rotary track scrolling in BROWSE, and rotary push on a highlighted track (must open the load/deck-selection menu). This is the Pi-tested two-area detector: firmware white-pixel counts were deck 75/75 and library 204/0; the old additional regions were 0/0 on deck and caused a false negative. Check FLX4 playback, both audio channels/headphones, 4-beat loop and exit, Gate Cue and Beat FX channel selection. Confirm waveform behaviour and latency with wired audio. The combined fresh-install path is pending this hardware test.

## Mapping detail

The archived controller bridge is retained. Normal headphone CUE remains headphone cue; SHIFT + headphone CUE maps to per-deck QUANTIZE. The proposed change to make unshifted headphone CUE control QUANTIZE is not part of this archived implementation.

## Display timing

The preserved Pi-tested DRM VBlank implementation tries `/dev/dri/card1` and CRTC 92, then falls back to the configured software timer if unavailable. Different kernels may assign other IDs; inspect `~/rx3-present.log` if DRM timing is unavailable. No firmware renderer or audio algorithm is changed by the new top controls or keyboard colours.

## Backup and recovery

Before changing installed files, the combined installer saves host helper executables, the existing runtime shim, systemd service and RX3 udev rules in the printed `RX3-INSTALL-BACKUP-*` folder. Keep the original checkout too. If installation fails, do not reboot until the reported error is resolved or the saved files are restored. No automatic service restart or reboot is performed by the combined entry point.

The old `INSTALL.md`, `STATUS.md` and `ROADMAP.md` retain upstream research history; the root README and this file describe the combined Pi 4 install.

## Checks completed for this consolidation

Both host C helpers compiled and linked on the build host, with implicit-function declarations treated as errors. Python bridge syntax and changed shell scripts passed syntax checks. A compiled layout check confirmed six non-overlapping button hit targets within 800×480 and the complete firmware viewport at 788×435, position (6,42). These checks do not replace ARM/Pi hardware testing.
