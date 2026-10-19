# SCUF Envision Pro: USB HID notes (macOS, wired)

Captured on a Mac Studio over USB with the factory onboard profile. Every input was pressed one at a time and labelled. The raw capture is in [`capture-2026-10-19.txt`](capture-2026-10-19.txt).

## Device

| | |
|---|---|
| Vendor ID | `0x2E95` (SCUF Gaming) |
| Product ID | `0x434D` (wired) |
| Interfaces 0–2 | USB Audio (headset jack) |
| Interface 3 | HID, primary usage page `0x000C` (consumer control, telephony, LEDs, vendor `0xFF42` config channel) |
| Interface 4 | HID, primary usage page `0xFF58`, **which also contains a Generic Desktop / Game Pad collection** |

macOS reports a device's *primary* usage from its first top-level collection. Interface 4's first collection is vendor page `0xFF58`, so SDL's IOKit backend (which filters on primary usage page = Generic Desktop) and Apple's GameController framework both skip the controller, even though a standard gamepad report is right there.

## Interface 4 report descriptor

```
06 58 FF 09 01 A1 01 85 58 09 01 15 00 26 FF 00 95 3F 75 08 81 02 85 58 09 01 15 00 26 FF 00
95 3F 75 08 91 02 C0 05 01 09 05 A1 01 A1 00 85 06 09 30 09 31 09 32 09 35 16 00 80 26 FF 7F
36 00 80 46 FF 7F 75 10 95 04 81 02 05 01 09 33 09 34 15 00 26 FF 03 75 0A 95 02 81 02 09 39
15 00 25 07 35 00 46 3B 01 65 14 75 04 95 01 81 42 65 00 05 09 19 01 29 13 15 00 25 01 75 01
95 13 81 02 06 00 FF 09 20 75 0D 95 01 81 02 C0 85 09 15 00 26 FF 00 75 08 95 0C 09 01 91 02
C0
```

- Report `0x58`: 63-byte vendor input and output (iCUE channel, not yet decoded).
- Report `0x06`: the gamepad input report, below.
- Report `0x09`: 12-byte output inside the gamepad collection. Probably rumble; not yet decoded.

## Gamepad input report (ID `0x06`, 16 bytes including the ID)

| Byte(s) | Contents |
|---|---|
| 0 | `0x06` (report ID) |
| 1–2 | Left stick X, int16 LE |
| 3–4 | Left stick Y, int16 LE, **up = negative** |
| 5–6 | Right stick X, int16 LE |
| 7–8 | Right stick Y, int16 LE, up = negative |
| 9–11 | LT 10 bits (bits 0–9), RT 10 bits (bits 10–19), hat 4 bits (bits 20–23) |
| 12 | bit0 A, bit1 B, bit2 X, bit3 Y, bit4 LB, bit5 RB, bit6 View, bit7 Menu |
| 13 | bit0 L3, bit1 R3, bit2 Home, bit3 G1, bit4 G2, bit5 G3, bit6 G4, bit7 G5 |
| 14 | bit0 Profile, bit1–2 unused, bit3 P1, bit4 P2, bit5 **P4**, bit6 **P3**, bit7 SAX left |
| 15 | bit0 SAX right, rest unused |

Decoding the packed trigger and hat bytes:

```
LT  = b[9] | (b[10] & 0x03) << 8          // 0...~1010
RT  = (b[10] >> 2) | (b[11] & 0x0F) << 6  // 0...~1010
hat = b[11] >> 4                          // 0 up, 2 right, 4 down, 6 left (odd = diagonals), 8 = centred
```

Sticks rest at exactly 0 (the firmware applies its own small dead zone). Triggers top out a little short of 1023, so the default trigger profile treats 96% as a full pull.

## Onboard-profile side effects (factory profile)

- **Paddles and SAX buttons echo a standard button** in the same report: P1 → A, P2 → Y, P3 → B, P4 → X, SAX left → LB, SAX right → RB. Their own bits in bytes 14–15 are set as well, so the paddle can be told apart. ScufBridge attributes any standard button that rises in the same report as a paddle to that paddle, and hides it until the paddle is released.
- **G2, G3 and G4 also send consumer-control report `0x11`** on interface 3: bit0 volume up (G3), bit1 volume down (G2), bit2 mute (G4). macOS acts on these directly. ScufBridge seizes interface 3 (this needs Input Monitoring) to stop it, and maps G2–G4 to the same media keys by default.
- G1, G5, Home, Profile and the stick clicks only appear in the gamepad report.

## Still unknown

- The iCUE configuration protocol (vendor report `0x58` on interface 4, `0xFF42` reports on interface 3): RGB, trigger stops, onboard profiles.
- Rumble (output report `0x09`).
- The wireless dongle's product ID and report format.
