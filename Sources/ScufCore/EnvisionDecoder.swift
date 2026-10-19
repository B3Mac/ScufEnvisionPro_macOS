import Foundation

/// Decodes the SCUF Envision Pro's wired USB input reports.
///
/// The controller's second HID interface (primary usage page 0xFF58) carries a standard
/// Generic Desktop / Game Pad collection with report ID 6, 16 bytes including the ID:
///
/// | bytes | field |
/// |-------|-------|
/// | 1-2, 3-4 | left stick X, Y (int16 LE, up = negative) |
/// | 5-6, 7-8 | right stick X, Y (int16 LE) |
/// | 9-11 | LT (10 bit), RT (10 bit), hat (4 bit, 0 = up, clockwise, 8 = centred) |
/// | 12 | A B X Y LB RB View Menu |
/// | 13 | L3 R3 Home G1 G2 G3 G4 G5 |
/// | 14 | Profile, -, -, P1, P2, P4, P3, SAX-L |
/// | 15 | SAX-R |
///
/// The onboard profile makes paddles and SAX buttons also press a standard button
/// (P1 -> A, P2 -> Y, P3 -> B, P4 -> X, SAX -> LB/RB). `stripMirroredButtons` removes that
/// echo so the extra inputs can be remapped on their own.
public struct EnvisionDecoder: Sendable {
    public static let vendorID = 0x2E95
    public static let wiredProductID = 0x434D
    public static let gamepadReportID: UInt8 = 0x06
    /// Consumer-control report on the other interface (onboard media keys: bit0 vol+, bit1 vol-, bit2 mute).
    public static let mediaReportID: UInt8 = 0x11

    public static let extraInputs: [ControllerButton] = [.p1, .p2, .p3, .p4, .saxLeft, .saxRight]

    static let bitMap: [(byte: Int, mask: UInt8, button: ControllerButton)] = [
        (12, 0x01, .a), (12, 0x02, .b), (12, 0x04, .x), (12, 0x08, .y),
        (12, 0x10, .lb), (12, 0x20, .rb), (12, 0x40, .view), (12, 0x80, .menu),
        (13, 0x01, .l3), (13, 0x02, .r3), (13, 0x04, .home), (13, 0x08, .g1),
        (13, 0x10, .g2), (13, 0x20, .g3), (13, 0x40, .g4), (13, 0x80, .g5),
        (14, 0x01, .profile), (14, 0x08, .p1), (14, 0x10, .p2), (14, 0x20, .p4),
        (14, 0x40, .p3), (14, 0x80, .saxLeft), (15, 0x01, .saxRight),
    ]

    public var stripMirroredButtons: Bool

    private var previousRaw: Set<ControllerButton> = []
    private var mirrored: [ControllerButton: Set<ControllerButton>] = [:]

    public init(stripMirroredButtons: Bool = true) {
        self.stripMirroredButtons = stripMirroredButtons
    }

    /// Buttons exactly as the report states them, including hat directions and mirrored buttons.
    public static func rawButtons(_ report: [UInt8]) -> Set<ControllerButton> {
        var result = Set<ControllerButton>()
        guard report.count >= 16 else { return result }
        for entry in bitMap where report[entry.byte] & entry.mask != 0 {
            result.insert(entry.button)
        }
        switch report[11] >> 4 {
        case 0: result.insert(.dpadUp)
        case 1: result.formUnion([.dpadUp, .dpadRight])
        case 2: result.insert(.dpadRight)
        case 3: result.formUnion([.dpadDown, .dpadRight])
        case 4: result.insert(.dpadDown)
        case 5: result.formUnion([.dpadDown, .dpadLeft])
        case 6: result.insert(.dpadLeft)
        case 7: result.formUnion([.dpadUp, .dpadLeft])
        default: break
        }
        return result
    }

    /// Decodes a report delivered with its report ID as the first byte. Returns nil for other reports.
    public mutating func decode(_ report: [UInt8]) -> ControllerState? {
        guard report.count >= 16, report[0] == Self.gamepadReportID else { return nil }
        var state = ControllerState()

        func axis(_ offset: Int) -> Double {
            let value = Int16(bitPattern: UInt16(report[offset]) | UInt16(report[offset + 1]) << 8)
            return max(-1, min(1, Double(value) / 32767))
        }
        state.leftX = axis(1)
        state.leftY = axis(3)
        state.rightX = axis(5)
        state.rightY = axis(7)

        let lt = Int(report[9]) | Int(report[10] & 0x03) << 8
        let rt = Int(report[10] >> 2) | Int(report[11] & 0x0F) << 6
        state.leftTrigger = Double(lt) / 1023
        state.rightTrigger = Double(rt) / 1023

        let raw = Self.rawButtons(report)
        state.buttons = stripMirroredButtons ? attribute(raw) : raw
        previousRaw = raw
        return state
    }

    /// Whatever standard buttons rise in the same report as a paddle belong to that paddle
    /// until it is released.
    private mutating func attribute(_ raw: Set<ControllerButton>) -> Set<ControllerButton> {
        let rose = raw.subtracting(previousRaw)
        for extra in Self.extraInputs {
            if raw.contains(extra) {
                if !previousRaw.contains(extra) {
                    mirrored[extra] = rose.subtracting(Self.extraInputs)
                }
            } else {
                mirrored[extra] = nil
            }
        }
        var result = raw
        for buttons in mirrored.values { result.subtract(buttons) }
        return result
    }

    /// Decodes the onboard media-key report (report ID 0x11). Returns nil for other reports.
    public static func decodeMedia(_ report: [UInt8]) -> (volumeUp: Bool, volumeDown: Bool, mute: Bool)? {
        guard report.count >= 2, report[0] == mediaReportID else { return nil }
        let bits = report[1]
        return (bits & 0x01 != 0, bits & 0x02 != 0, bits & 0x04 != 0)
    }
}
