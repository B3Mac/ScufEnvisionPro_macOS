# ScufBridge

ScufBridge is a macOS menu-bar app that makes the **SCUF Envision Pro** controller fully usable and remappable on a Mac. It works like iCUE does on Windows.

SCUF lists the Envision Pro as Windows-only. It does work on a Mac over USB, but macOS treats it as a vendor device. Games and emulators such as Astris never see it, and none of the extra buttons can be mapped. ScufBridge reads the controller directly, applies your profile, and sends the result to your games and apps.

> Personal project. Not affiliated with SCUF Gaming or Corsair.

## What it does

- **A 3D mapping page.** Drag the controller to turn it, flip it over to reach the paddles, and click any button to map it. Buttons light up as you press them.
- **Every input is remappable**, including all 11 extras: **G1–G5**, paddles **P1–P4** and both **SAX** buttons, plus every standard button and both triggers.
- **Actions** you can assign to any input:
  - a gamepad button (with optional turbo)
  - a key or shortcut, held for as long as the button is held
  - typed text
  - a **macro**, recorded or built step by step, played once, while held, or toggled
  - a **shell script** on press and/or release
  - open an app or URL
  - a media key
  - a mouse click
  - switch profile
- **Profiles**, with automatic switching when a linked app comes to the front. The controller's Profile button cycles through them.
- **Sticks and triggers:** inner and outer dead zones, response curves, inversion, stick swapping, trigger range, and a hair-trigger option. Live previews show the raw position next to what the game receives.
- **Output modes** per profile:
  - **Virtual gamepad.** Games see an Xbox-layout controller with full analog input. This needs an Apple entitlement; see [Virtual gamepad](#virtual-gamepad).
  - **Keyboard mode.** Buttons and stick directions press keys. It works with any game today. The defaults match Astris's own keyboard layout.
  - **Actions only.** Only the non-gamepad actions run.
- **Controller monitor** with every input, sticks, triggers, the output state and the raw report bytes.

## Install

**Beta.** You need macOS 15 or later, on an Apple Silicon or Intel Mac.

1. Download the latest **ScufBridge-x.y.z.dmg** from [Releases](https://github.com/B3Mac/ScufEnvisionPro_macOS/releases), open it, and drag ScufBridge into Applications.
2. Open ScufBridge. Beta builds aren't signed by a registered Apple developer yet, so macOS refuses the first time. Go to **System Settings → Privacy & Security**, scroll down, and click **Open Anyway** next to ScufBridge. Or run this in Terminal:
   ```bash
   xattr -dr com.apple.quarantine /Applications/ScufBridge.app
   ```
3. Plug the controller in by USB. A controller icon appears in the menu bar.

ScufBridge checks GitHub once a day for a newer release and shows it in the menu. It never downloads or installs anything on its own, and you can turn the check off under **Setup & Permissions**. After updating a beta, macOS may ask for Accessibility again.

### Build from source

You need Xcode or the Xcode Command Line Tools.

```bash
git clone https://github.com/B3Mac/ScufEnvisionPro_macOS.git ~/Developer/ScufEnvisionPro_macOS
cd ~/Developer/ScufEnvisionPro_macOS && scripts/build_app.sh --install
```

This builds the app, copies it to `/Applications`, and launches it. To update later, run `git pull && scripts/build_app.sh --install`.

On first launch, grant these under **System Settings → Privacy & Security**. The app's **Setup & Permissions** page has buttons that open each one.

| Permission | Needed for |
|---|---|
| Accessibility | Sending keys, text, media keys, clicks, and Keyboard mode |
| Input Monitoring | Recording macros, and stopping G2–G4 from changing the volume on their own |

If you have an *Apple Development* signing certificate, the build script uses it. Adding a free Apple ID in Xcode creates one, and with it, permissions persist across rebuilds. Without one the app is signed ad hoc, and macOS may ask for Accessibility again after a rebuild.

## Using it with Astris

Until the virtual gamepad is available:

1. In ScufBridge, open the **Astris (keyboard mode)** profile, go to **Profile → Add Running App**, and pick Astris. From then on, the profile turns on whenever Astris is in front.
2. In Astris, open **Settings → Input → Player 1** and set **Input Device** to **Keyboard**. ScufBridge's default key layout matches Astris's defaults, so nothing else needs mapping.

Face buttons map by position, the way a Switch controller is laid out. The bottom button is Switch **B** and the right button is Switch **A**. In keyboard mode, sticks are 8-way digital.

## Scripts

Scripts run with `zsh -l`. These environment variables are set:

| Variable | Value |
|---|---|
| `SCUF_INPUT` | The input that ran the script, e.g. `g3` or `p1` |
| `SCUF_EVENT` | `press` or `release` |
| `SCUF_PROFILE` | The active profile's name |

Output is written to `~/Library/Logs/ScufBridge/scripts.log`. The **Test Run** button shows the output inline.

## Virtual gamepad

Getting full analog control in games means creating a virtual HID game controller, and macOS only allows that for apps signed with the `com.apple.developer.hid.virtual.device` entitlement. The code is finished. It presents as a wired Xbox 360 pad, which SDL-based games and emulators (Astris included) recognise automatically. It switches on as soon as macOS allows it. Ways to get there:

1. **Apple Developer Program ($99/yr).** Request the *HID Virtual Device* capability for the app ID, then build with `scripts/build_app.sh --virtual-hid` and a matching provisioning profile. Apple has to approve the request, and some reportedly take weeks.
2. **DriverKit (planned).** A small driver extension can publish the virtual pad using DriverKit's development entitlements. A paid account gets those without approval, but such builds run only on Macs registered to that account.
3. **Lowering Mac security** (turning off SIP and AMFI) also works. It isn't recommended on a work machine.

Until then, the app reports the virtual gamepad as unavailable, and everything else keeps working.

## Controller notes

- Over USB, the Envision Pro (VID `0x2E95`, PID `0x434D`) exposes a standard Game Pad collection, but inside a vendor-page interface. That is why macOS and SDL ignore it. The full layout is in [docs/PROTOCOL.md](docs/PROTOCOL.md).
- The factory onboard profile makes paddles and SAX buttons also press a standard button (P1→A, P2→Y, P3→B, P4→X, SAX→LB/RB). ScufBridge strips that copy so each extra input can be mapped on its own. If you press the paddle and the real button in the same millisecond, the real one is masked until you release the paddle.
- G2, G3 and G4 also send volume down, volume up and mute straight to macOS. ScufBridge blocks that by default (it needs Input Monitoring). Their default mappings reproduce the same behaviour, so nothing changes until you remap them.

## Supported controllers

| Controller | Connection | Status |
|---|---|---|
| SCUF Envision Pro | USB cable | Supported |
| SCUF Envision Pro | Wireless dongle | Not yet: needs a capture |
| SCUF Envision (non-Pro) | USB cable | Untested: needs a capture |

### Help add a controller

With the controller (or its dongle) plugged in, run:

```bash
swift scripts/capture.swift | tee ~/Desktop/scuf_capture.txt
```

It prompts you through every button, about two minutes in all. Then open an issue and attach the file. Before attaching it, check that it doesn't include anything you'd rather not share. The script only records controller data and your macOS version.

## Roadmap

- RGB lighting, trigger modes, and onboard profile sync. These need a capture of iCUE's USB traffic on Windows.
- Rumble passthrough from the virtual pad.
- Wireless dongle support. It needs a capture with the controller in wireless mode.
- A DriverKit virtual-gamepad option.

## Project layout

| Path | Contents |
|---|---|
| `Sources/ScufCore` | Pure Swift: report decoding, profiles, mapping engine, keyboard mode, virtual-pad report. Unit-tested. |
| `Sources/ScufBridge` | The macOS app: HID input thread, actions, macros, scripts, virtual gamepad, SwiftUI settings |
| `Tests/ScufCoreTests` | Tests built from real captured controller reports |
| `Packaging/Artwork` | Controller photos used by the 3D mapping page |
| `scripts/build_app.sh` | Builds, signs and optionally installs the `.app`; `--universal --dmg` makes a release |
| `scripts/capture.swift` | Guided HID capture for adding controllers |

To run the tests: `swift test`. To publish a release, push a tag such as `v0.1.0-beta.1`. GitHub Actions builds a universal DMG and attaches it to a GitHub Release.

Controller photos © SCUF Gaming / Corsair, used to illustrate the controller this app supports.
