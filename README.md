# RX3 on Raspberry Pi 4 + original 7-inch touchscreen

Pioneer XDJ-RX3 firmware research build for a **Raspberry Pi 4B (4 GB)**, the **original Raspberry Pi 7-inch 800×480 DSI touchscreen**, and a **Pioneer DDJ-FLX4**. Based on [mutlisensor/Rx3-flx4](https://github.com/mutlisensor/Rx3-flx4).

## v1.3.0

The shared installer supports Pi 4 and Pi 5 with automatic, DSI or HDMI display selection and optional framebuffer, rotation and touch overrides. The Pi 4 DSI update and Pi 5 HDMI fresh install were tested. See the [installation guide](docs/PI4-INSTALL.md) for options.

On the DDJ-FLX4, **4 BEAT/EXIT** sends the native LOOP IN hold event immediately. Both decks passed playback loop entry, exit, re-entry and length adjustment on Pi 4. The cue-standby change also lets a stopped deck arm a four-beat loop and lets the jog rim and top reposition the playhead. The Deck 1 diagnostic verified stopped loop arming, loop playback and saved CUE recall. Full two-deck regression testing of the combined cue-standby update and Pi 5 controller testing are pending.

The FLX4 changes extend the controller bridge from [mutlisensor/Rx3-flx4](https://github.com/mutlisensor/Rx3-flx4), whose mapping references [Mixxx controller mappings](https://github.com/mixxxdj/mixxx/tree/main/res/controllers). The cue-standby transition follows the behavior observed in the RX3 firmware's own Beat Jump path.

## Included controller mappings

| Controller | Mapping status |
|---|---|
| Pioneer DDJ-FLX4 | Tested on the Raspberry Pi 4B with this build. |
| Pioneer DDJ-400 | **Untested on DDJ-400 hardware in this build.** |
| Pioneer DDJ-GRV6 | Experimental two-deck profile. **Untested on GRV6 hardware in this build.** |
| Pioneer DDJ-FLX6 | Experimental two-deck profile. **Untested on FLX6 hardware in this build.** |

### GRV6 and FLX6 trial

With one controller connected before startup, RX3 selects the profile and ALSA
card automatically. The trial maps play/cue, load, browsing, tempo, basic mixer
controls, loop in/out/reloop, and Hot Cue, Beat Loop and Beat Jump pads on
decks 1 and 2. The GRV6 trial also maps basic Beat FX controls. It uses
the reference 256-frame period and 1024-frame buffer. Both route master to
USB playback channels 1/2 and headphone cue to 3/4.

Jogs, controller LED feedback, decks 3/4, FLX6 Beat FX and controller-specific
performance modes are outside this first trial. Test one controller at a time
and check master and headphones at low volume before exercising the mappings.

The profile behavior and audio routing were informed by
[mortalinstrument's RX3 Pi 4 project](https://github.com/mortalinstrument/xdj-rx3-pi4).
FLX6 input addresses use the
[Pioneer MIDI message list](https://www.pioneerdj.com/-/media/pioneerdj/software-info/controller/ddj-flx6/ddj-flx6_midi_message_list_e1.pdf).
The trial uses the existing RX3 bridge and requires no external mapping XML.

### DDJ-FLX4 mapping update — 8 November 2026

**4 BEAT/EXIT** uses the RX3 firmware’s native four-beat loop. Press once to start a loop and again to exit. The current pad mode stays selected, including Gate Cue. Tested on the Raspberry Pi with a DDJ-FLX4.

## Host UI and browse-knob update — 5 November 2026

The previously separate host-side updates are now included in the source and installer:

- Six raised top buttons: **SOURCE · BROWSE · USB1 · USB2 · SEARCH · POWER**.
- Full-width firmware display below the button row, with matching touch coordinates.
- Silver bevels, charcoal button faces, softer blue lettering and left-to-right hold progress.
- Native SEARCH on finger release, with the working v9b navy recolour of the native letter keys. Auxiliary keyboard keys retain their native appearance.
- Continuous three-second POWER hold; releasing or leaving the button cancels.
- Startup repaint, AA display filtering and the Pi-tested DRM VBlank path with timer fallback.
- FLX4 Shift + Hot Cue Gate Cue toggle and indicator, plus Beat FX CH1/CH2/both selection from the archived installer bridge.
- **Tested FLX4 BROWSE-knob fix:** pressing the knob on the main deck screen opens the library; turning it scrolls tracks, and pressing it in the library selects the highlighted track. Deck detection now uses the two measured stable firmware label regions (deck 75/75 versus library 204/0), avoiding the former four-region false negative.
- Pi 4 ARMv7 shim build, original DSI unblanking and BCM2711 USB-hub protection.

The v9b navy keyboard and the two-region FLX4 BROWSE-knob mapping were tested working on the user's Pi. **The controller update was tested on the Pi with the FLX4 using the update installer. A fresh installation has not yet been tested.** Keyboard styling can be refined later. Audio latency remains under investigation; this update does not claim a new audio fix. DDJ-400 compatibility is unverified for this combined build.

## Screenshots

Screenshots from the Pi trials on the original 800×480 display. The main, SOURCE and BROWSE views show v6 button styling. The SEARCH screenshot shows the native grey keyboard before the later v9b navy recolour.

### Main display

![RX3 main display with dual waveforms, deck information and six top-row buttons](docs/screenshots/main-display.png)

### SOURCE

![RX3 SOURCE screen with USB device selection and device information](docs/screenshots/source.png)

### BROWSE

![RX3 BROWSE screen showing folders and tracks on USB](docs/screenshots/browse.png)

### SEARCH keyboard

![RX3 native SEARCH screen with results and the on-screen keyboard before the v9b navy recolour](docs/screenshots/search-keyboard.png)

## Install

Use 64-bit Raspberry Pi OS or Debian 13 (trixie) on a Pi 4 or Pi 5. The Pi 4 with the original DSI touchscreen is the hardware-tested baseline. Pi 5 and other screen combinations are available for testing. Run as your normal user:

```bash
git clone https://github.com/mikayla-fox/Rx3-flx4-Pi4-7inch.git ~/Rx3-flx4
cd ~/Rx3-flx4
bash install-rx3.sh --fresh
```

The installer installs dependencies, recovers the firmware from its upstream sources, builds the runtime and host helpers, and enables RX3 at boot. When it finishes, activate it with `sudo reboot`. It does not reboot automatically.

### Existing installation

Keep your current checkout, and use a **separate new checkout** so local trial edits and old sources remain available:

```bash
git clone https://github.com/mikayla-fox/Rx3-flx4-Pi4-7inch.git ~/Rx3-flx4-v9b
cd ~/Rx3-flx4-v9b
bash install-rx3.sh --update
```

Copy any local `rx3.conf` and `rx3-display.conf` from the old checkout’s `rx3-handoff` directory before updating. Update mode preserves the existing runtime and firmware settings, saves the old host binaries, shim and service/rule files, and configures RX3 to use the new checkout. It prints the backup location. Activate with a full reboot when ready; do not apply while performing a DJ set. Keep the previous checkout and backup until the combined install is verified.

See [the Pi 4 and Pi 5 installation notes](docs/PI4-INSTALL.md), [controller key map](KEYMAP.md), and [upstream detailed installation reference](INSTALL.md).

### Display options

The default detects the framebuffer as in the original Pi 4 setup. To choose
DSI or HDMI, add `--display dsi` or `--display hdmi` to either install mode.
The screen must be enabled by Raspberry Pi OS and connected at boot. Add
`--rotate 90`, `180` or `270` if needed, and use `--framebuffer /dev/fb1`
when selecting a specific framebuffer. A USB mouse works with a non-touch screen.
See the [board and display setup](docs/PI4-INSTALL.md#board-and-display-setup)
for touchscreen selection and testing.

## Optional Pi cleanup

On a Raspberry Pi OS Desktop installation dedicated to RX3, you can remove unused desktop apps such as Chromium, LibreOffice, and printing tools. From the repository root, preview what APT would remove:

```bash
./provision.sh --packages
```

If the list matches what you want to remove, run `./provision.sh --apply-packages` and review APT's confirmation. The helper checks for unexpected removals and skips automatic dependency removal. It runs separately from the RX3 installer. Cleanup was tested on the RX3 Pi, and a fresh SSH connection worked afterward.

See the [optional provisioning guide](INSTALL.md#optional-pi-provisioning) for details. Credit to **ghztomash** and [StandaloneMixxx](https://github.com/ghztomash/StandaloneMixxx) for the provisioning workflow this helper builds on.

## Firmware is not included

No Pioneer code, firmware image, decryption key, or patched player binary is in this repository, and
none should ever be committed to it — they are Pioneer/AlphaTheta property. `.gitignore` blocks them.

You supply them yourself, from the official sources:

- Firmware: the official XDJ-RX3 v1.19 update package from AlphaTheta support downloads.
- GPL source distribution: Pioneer DJ's open-source code distribution page, which is where the
  per-sector AES key comes from.

`rx3-handoff/ASTRA-PROMPT.md` lists the exact URLs and the recovery sequence, and
`rx3-handoff/recover-firmware.py` plus `firmware_image.py` perform the extraction. Place the results
in `rx3-handoff/extracted/` and `build-rootfs.sh` will assemble the chroot from them.

## Source layout

`rx3-handoff/` contains the presenter, touch bridge, controller bridge, firmware-recovery tools, runtime builder and service installer. `install-rx3.sh` is the combined Pi 4 entry point. Paths are resolved from the checkout owner rather than a fixed username.

## Credits and scope

Upstream emulation/interoperability work: [mutlisensor/Rx3-flx4](https://github.com/mutlisensor/Rx3-flx4). Pi 4/original 7-inch integration and host UI trials: this fork. Pioneer/AlphaTheta firmware remains separate and is not distributed in this repository.
