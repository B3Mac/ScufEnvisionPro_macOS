import Foundation

/// The virtual gamepad's identity and report format.
///
/// It presents as a wired Xbox 360 controller using the report layout of the macOS
/// 360Controller driver. SDL (used by Astris/Ryujinx and most emulators) recognises that
/// VID/PID through its HIDAPI Xbox 360 driver, so the pad gets a correct mapping with no setup.
public enum VirtualPadReport {
    public static let vendorID: UInt32 = 0x045E
    public static let productID: UInt32 = 0x028E
    /// SDL treats version 1 as Steam's virtual pad and ignores it, so use a real controller's bcdDevice.
    public static let versionNumber: UInt32 = 0x0114
    public static let productName = "ScufBridge Virtual Pad"
    public static let reportLength = 20

    public static let descriptor: [UInt8] = [
        0x05, 0x01,                   // Usage Page (Generic Desktop)
        0x09, 0x05,                   // Usage (Game Pad)
        0xA1, 0x01,                   // Collection (Application)
        0x75, 0x08, 0x95, 0x02,       //   2 bytes: message type, length
        0x81, 0x01,                   //   Input (Constant)
        0x05, 0x09,                   //   Usage Page (Button)
        0x19, 0x01, 0x29, 0x10,       //   Buttons 1-16
        0x15, 0x00, 0x25, 0x01,       //   Logical 0...1
        0x75, 0x01, 0x95, 0x10,       //   16 x 1 bit
        0x81, 0x02,                   //   Input (Data, Var, Abs)
        0x05, 0x01,                   //   Usage Page (Generic Desktop)
        0x09, 0x32, 0x09, 0x35,       //   Z, Rz (triggers)
        0x15, 0x00, 0x26, 0xFF, 0x00, //   Logical 0...255
        0x75, 0x08, 0x95, 0x02,       //   2 x 8 bit
        0x81, 0x02,                   //   Input (Data, Var, Abs)
        0x09, 0x30, 0x09, 0x31,       //   X, Y
        0x09, 0x33, 0x09, 0x34,       //   Rx, Ry
        0x16, 0x00, 0x80,             //   Logical Min -32768
        0x26, 0xFF, 0x7F,             //   Logical Max 32767
        0x75, 0x10, 0x95, 0x04,       //   4 x 16 bit
        0x81, 0x02,                   //   Input (Data, Var, Abs)
        0x75, 0x08, 0x95, 0x06,       //   6 bytes padding
        0x81, 0x01,                   //   Input (Constant)
        0x06, 0x00, 0xFF, 0x09, 0x01, //   Usage Page (Vendor 0xFF00), Usage 1
        0x15, 0x00, 0x26, 0xFF, 0x00, //   Logical 0...255
        0x75, 0x08, 0x95, 0x08,       //   8 bytes
        0x91, 0x02,                   //   Output (rumble / LED requests)
        0xC0,                         // End Collection
    ]

    public static func encode(_ pad: PadState) -> [UInt8] {
        var r = [UInt8](repeating: 0, count: reportLength)
        r[0] = 0x00
        r[1] = 0x14
        let b = pad.buttons
        func bit(_ button: PadButton, _ mask: UInt8) -> UInt8 { b.contains(button) ? mask : 0 }
        r[2] = bit(.dpadUp, 0x01) | bit(.dpadDown, 0x02) | bit(.dpadLeft, 0x04) | bit(.dpadRight, 0x08)
            | bit(.menu, 0x10) | bit(.view, 0x20) | bit(.l3, 0x40) | bit(.r3, 0x80)
        r[3] = bit(.lb, 0x01) | bit(.rb, 0x02) | bit(.home, 0x04)
            | bit(.a, 0x10) | bit(.b, 0x20) | bit(.x, 0x40) | bit(.y, 0x80)

        func trigger(_ value: Double) -> UInt8 {
            UInt8(clamping: Int((max(0, min(1, value)) * 255).rounded()))
        }
        r[4] = trigger(b.contains(.lt) ? 1 : pad.leftTrigger)
        r[5] = trigger(b.contains(.rt) ? 1 : pad.rightTrigger)

        func put(_ value: Double, at offset: Int) {
            let v = Int16(clamping: Int((max(-1, min(1, value)) * 32767).rounded()))
            let u = UInt16(bitPattern: v)
            r[offset] = UInt8(u & 0xFF)
            r[offset + 1] = UInt8(u >> 8)
        }
        // The 360Controller driver reports Y with down = positive, and SDL reads it that way on macOS.
        put(pad.leftX, at: 6)
        put(pad.leftY, at: 8)
        put(pad.rightX, at: 10)
        put(pad.rightY, at: 12)
        return r
    }
}
