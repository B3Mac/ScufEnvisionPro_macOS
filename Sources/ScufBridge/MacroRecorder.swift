import AppKit
import CoreGraphics
import ScufCore

/// Records keystrokes system-wide (with timing) into macro steps. Needs Input Monitoring.
final class MacroRecorder: ObservableObject {
    @Published private(set) var isRecording = false
    @Published private(set) var steps: [MacroStep] = []
    @Published var recordTiming = true

    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var lastTimestamp: UInt64 = 0

    /// Returns false if macOS refused (Input Monitoring not granted).
    @discardableResult
    func start() -> Bool {
        guard !isRecording else { return true }
        steps = []
        lastTimestamp = 0
        let mask: CGEventMask = (1 << CGEventMask(CGEventType.keyDown.rawValue))
            | (1 << CGEventMask(CGEventType.keyUp.rawValue))
            | (1 << CGEventMask(CGEventType.flagsChanged.rawValue))
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: mask,
            callback: { _, type, event, refcon in
                if let refcon = refcon {
                    Unmanaged<MacroRecorder>.fromOpaque(refcon).takeUnretainedValue().handle(type, event)
                }
                return Unmanaged.passUnretained(event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            return false
        }
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, CFRunLoopMode.commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        self.tap = tap
        self.source = source
        isRecording = true
        return true
    }

    /// Stops and returns what was recorded.
    @discardableResult
    func stop() -> [MacroStep] {
        if let tap = tap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let source = source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, CFRunLoopMode.commonModes) }
        tap = nil
        source = nil
        isRecording = false
        return steps
    }

    private func handle(_ type: CGEventType, _ event: CGEvent) {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return
        }
        let code = UInt16(truncatingIfNeeded: event.getIntegerValueField(.keyboardEventKeycode))
        switch type {
        case .keyDown:
            if event.getIntegerValueField(.keyboardEventAutorepeat) != 0 { return }
            append(.keyDown(keyCode: code), at: event.timestamp)
        case .keyUp:
            append(.keyUp(keyCode: code), at: event.timestamp)
        case .flagsChanged:
            guard let modifier = KeyCodes.modifierKeys[code] else { return }
            let isDown = event.flags.contains(Self.flag(for: modifier))
            append(isDown ? .keyDown(keyCode: code) : .keyUp(keyCode: code), at: event.timestamp)
        default:
            break
        }
    }

    private func append(_ step: MacroStep, at timestamp: UInt64) {
        if recordTiming, lastTimestamp != 0, timestamp > lastTimestamp {
            let ms = Int((timestamp - lastTimestamp) / 1_000_000)
            if ms > 0 { steps.append(.delay(ms: ms)) }
        }
        lastTimestamp = timestamp
        steps.append(step)
    }

    private static func flag(for modifier: Modifier) -> CGEventFlags {
        switch modifier {
        case .command: return .maskCommand
        case .shift: return .maskShift
        case .option: return .maskAlternate
        case .control: return .maskControl
        case .function: return .maskSecondaryFn
        }
    }
}
