// Guided capture of a SCUF / Corsair controller's HID reports, used to add support for new
// models and connection modes (for example the wireless dongle).
//
//   swift scripts/capture.swift | tee ~/Desktop/scuf_capture.txt
//
// Press each input when prompted, then attach the file to a GitHub issue.
import Foundation
import IOKit.hid

setvbuf(stdout, nil, _IOLBF, 0)

let steps: [(String, Double)] = [
    ("IDLE start - hands off", 4),
    ("A", 3), ("B", 3), ("X", 3), ("Y", 3),
    ("D-pad UP", 3), ("D-pad DOWN", 3), ("D-pad LEFT", 3), ("D-pad RIGHT", 3),
    ("LB", 3), ("RB", 3),
    ("LT - slow full pull, then release", 4), ("RT - slow full pull, then release", 4),
    ("L3 - click left stick", 3), ("R3 - click right stick", 3),
    ("VIEW - small button left of center", 3), ("MENU - small button right of center", 3),
    ("HOME - round SCUF button", 3), ("PROFILE - small button under HOME", 3),
    ("G1", 3), ("G2", 3), ("G3", 3), ("G4", 3), ("G5", 3),
    ("P1 paddle", 3), ("P2 paddle", 3), ("P3 paddle", 3), ("P4 paddle", 3),
    ("SAX LEFT - side button", 3), ("SAX RIGHT - side button", 3),
    ("LEFT STICK - full up, down, left, right, then 2 slow circles", 7),
    ("RIGHT STICK - full up, down, left, right, then 2 slow circles", 7),
    ("IDLE end - hands off", 3),
]

/// SCUF Gaming and Corsair (Corsair makes the SLIPSTREAM wireless dongle).
let vendorIDs = [0x2E95, 0x1B1C]

final class Session { var label = "SETUP"; var counts: [String: Int] = [:] }

final class Tap {
    let tag: String
    let session: Session
    let buffer: UnsafeMutablePointer<UInt8>
    var last: [UInt8] = []

    init(tag: String, size: Int, session: Session) {
        self.tag = tag
        self.session = session
        buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: size)
    }
}

print("macOS \(ProcessInfo.processInfo.operatingSystemVersionString)")
let session = Session()
let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
let matching = vendorIDs.map { [kIOHIDVendorIDKey as String: $0] as CFDictionary }
IOHIDManagerSetDeviceMatchingMultiple(manager, matching as CFArray)
IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
print(String(format: "open result: 0x%08X", IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))))

let devices = (IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice>) ?? []
print("interfaces found: \(devices.count)")
if devices.isEmpty {
    print("No SCUF or Corsair device found. Plug the controller (or its dongle) in and run again.")
    exit(1)
}

let callback: IOHIDReportCallback = { context, _, _, _, reportID, report, length in
    guard let context = context else { return }
    let tap = Unmanaged<Tap>.fromOpaque(context).takeUnretainedValue()
    let bytes = Array(UnsafeBufferPointer(start: report, count: length))
    if bytes == tap.last { return }
    tap.last = bytes
    let label = tap.session.label
    let count = tap.session.counts[label, default: 0]
    tap.session.counts[label] = count + 1
    if count >= 250 { return }
    print("[\(label)] {\(tap.tag)} id \(reportID) len \(length): " + bytes.map { String(format: "%02X", $0) }.joined(separator: " "))
}

var taps: [Tap] = []
for device in devices {
    let number: (String) -> Int = { (IOHIDDeviceGetProperty(device, $0 as CFString) as? NSNumber)?.intValue ?? -1 }
    let name = IOHIDDeviceGetProperty(device, kIOHIDProductKey as CFString) as? String ?? "?"
    let tag = String(
        format: "vid 0x%04X pid 0x%04X page 0x%04X usage 0x%02X",
        number(kIOHIDVendorIDKey), number(kIOHIDProductIDKey), number(kIOHIDPrimaryUsagePageKey), number(kIOHIDPrimaryUsageKey)
    )
    let inputSize = number(kIOHIDMaxInputReportSizeKey)
    print("== \(name) | \(tag) | in:\(inputSize) out:\(number(kIOHIDMaxOutputReportSizeKey)) feature:\(number(kIOHIDMaxFeatureReportSizeKey))")
    if let descriptor = IOHIDDeviceGetProperty(device, kIOHIDReportDescriptorKey as CFString) as? Data {
        print("   descriptor: " + descriptor.map { String(format: "%02X", $0) }.joined(separator: " "))
    }
    let size = max(inputSize, 64)
    let tap = Tap(tag: tag, size: size, session: session)
    taps.append(tap)
    IOHIDDeviceRegisterInputReportCallback(device, tap.buffer, size, callback, Unmanaged.passUnretained(tap).toOpaque())
}

var stepIndex = -1
func nextStep() {
    stepIndex += 1
    guard stepIndex < steps.count else {
        print("\n=== SUMMARY: changed reports per step ===")
        for (label, _) in steps { print(String(format: "%6d  ", session.counts[label, default: 0]) + label) }
        exit(0)
    }
    let (label, seconds) = steps[stepIndex]
    session.label = label
    print("\n>>> [\(stepIndex + 1)/\(steps.count)] \(label)   (\(Int(seconds))s)")
    DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { nextStep() }
}

print("\nStarting in 3 seconds. Press each input once when prompted.")
DispatchQueue.main.asyncAfter(deadline: .now() + 3) { nextStep() }
CFRunLoopRun()
