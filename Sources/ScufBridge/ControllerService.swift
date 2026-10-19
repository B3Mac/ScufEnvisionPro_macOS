import Foundation
import IOKit.hid
import ScufCore

/// What the UI shows about the controller right now.
struct LiveSnapshot: Equatable {
    var connected = false
    var state = ControllerState()
    var held: Set<ControllerButton> = []
    var pad = PadState()
    var lastReport: [UInt8] = []
    var lastPressed: ControllerButton?
    var pressSerial = 0
    var mediaKeysBlocked = false
    var openResult: Int32 = 0
}

/// Reads the controller on a dedicated high-priority thread, runs the mapping engine and drives
/// the outputs. All engine state is confined to that thread; other threads talk to it via `perform`.
final class ControllerService: @unchecked Sendable {
    let runner = ActionRunner()
    let virtualPad = VirtualGamepad()

    /// Called on the HID thread when an input asks to switch profiles.
    var onProfileRequest: (ProfileTarget) -> Void = { _ in }

    private var runLoop: CFRunLoop?
    private let started = DispatchSemaphore(value: 0)

    private var gamepadManager: IOHIDManager?
    private var mediaManager: IOHIDManager?
    private var taps: [IOHIDDevice: ReportTap] = [:]
    private var retiredTaps: [ReportTap] = []

    private var config: AppConfig
    private var decoder: EnvisionDecoder
    private var engine: MappingEngine
    private var keyboard = KeyboardModeMapper()
    private var lastPad = PadState()
    private var tickTimer: CFRunLoopTimer?

    private let snapshotLock = NSLock()
    private var snapshot = LiveSnapshot()

    init(config: AppConfig) {
        self.config = config
        self.decoder = EnvisionDecoder(stripMirroredButtons: config.stripMirroredButtons)
        self.engine = MappingEngine(profile: config.activeProfile)
    }

    // MARK: Public API (any thread)

    func start() {
        runner.requestProfile = { [weak self] target in self?.onProfileRequest(target) }
        runner.macros.onPadChange = { [weak self] in
            self?.perform { self?.refreshOutputs() }
        }
        let thread = Thread { [weak self] in
            guard let self = self else { return }
            let runLoop = CFRunLoopGetCurrent()!
            self.runLoop = runLoop
            // Keeps the run loop alive even before any device shows up.
            let keepAlive = CFRunLoopTimerCreateWithHandler(kCFAllocatorDefault, CFAbsoluteTimeGetCurrent() + 1e9, 1e9, 0, 0) { _ in }
            CFRunLoopAddTimer(runLoop, keepAlive, CFRunLoopMode.defaultMode)
            self.setUpManagers()
            self.started.signal()
            while true {
                CFRunLoopRunInMode(CFRunLoopMode.defaultMode, 60, false)
            }
        }
        thread.name = "ScufBridge HID"
        thread.qualityOfService = .userInteractive
        thread.start()
        started.wait()
    }

    func currentSnapshot() -> LiveSnapshot {
        snapshotLock.withLock { snapshot }
    }

    func update(config newConfig: AppConfig) {
        perform { [weak self] in self?.apply(config: newConfig) }
    }

    // MARK: HID thread

    private func perform(_ block: @escaping () -> Void) {
        guard let runLoop = runLoop else { return }
        CFRunLoopPerformBlock(runLoop, CFRunLoopMode.defaultMode.rawValue, block)
        CFRunLoopWakeUp(runLoop)
    }

    private func updateSnapshot(_ change: (inout LiveSnapshot) -> Void) {
        snapshotLock.withLock { change(&snapshot) }
    }

    private func setUpManagers() {
        guard let runLoop = runLoop else { return }
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        // Only the interface that carries the Game Pad collection (report ID 6).
        let matching: [String: Any] = [
            kIOHIDVendorIDKey: EnvisionDecoder.vendorID,
            kIOHIDDeviceUsagePageKey: 0x01,
            kIOHIDDeviceUsageKey: 0x05,
        ]
        IOHIDManagerSetDeviceMatching(manager, matching as CFDictionary)
        let context = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterDeviceMatchingCallback(manager, { context, _, _, device in
            guard let context = context else { return }
            Unmanaged<ControllerService>.fromOpaque(context).takeUnretainedValue().deviceMatched(device)
        }, context)
        IOHIDManagerRegisterDeviceRemovalCallback(manager, { context, _, _, device in
            guard let context = context else { return }
            Unmanaged<ControllerService>.fromOpaque(context).takeUnretainedValue().deviceRemoved(device)
        }, context)
        IOHIDManagerScheduleWithRunLoop(manager, runLoop, CFRunLoopMode.defaultMode.rawValue)
        let result = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        updateSnapshot { $0.openResult = result }
        gamepadManager = manager
        applyMediaKeyBlocking()
    }

    /// Seizes the controller's consumer-control interface so its built-in volume keys (G2-G4)
    /// stop reaching macOS directly; those buttons then only do what their mapping says.
    private func applyMediaKeyBlocking() {
        guard let runLoop = runLoop else { return }
        if let manager = mediaManager {
            IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
            IOHIDManagerUnscheduleFromRunLoop(manager, runLoop, CFRunLoopMode.defaultMode.rawValue)
            mediaManager = nil
        }
        guard config.blockOnboardMediaKeys else {
            updateSnapshot { $0.mediaKeysBlocked = false }
            return
        }
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        let matching: [String: Any] = [
            kIOHIDVendorIDKey: EnvisionDecoder.vendorID,
            kIOHIDPrimaryUsagePageKey: 0x0C,
        ]
        IOHIDManagerSetDeviceMatching(manager, matching as CFDictionary)
        IOHIDManagerScheduleWithRunLoop(manager, runLoop, CFRunLoopMode.defaultMode.rawValue)
        let result = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeSeizeDevice))
        mediaManager = manager
        updateSnapshot { $0.mediaKeysBlocked = result == kIOReturnSuccess }
    }

    private func deviceMatched(_ device: IOHIDDevice) {
        guard taps[device] == nil else { return }
        let reported = (IOHIDDeviceGetProperty(device, kIOHIDMaxInputReportSizeKey as CFString) as? NSNumber)?.intValue ?? 0
        let size = max(reported, 64)
        let tap = ReportTap(service: self, size: size)
        taps[device] = tap
        IOHIDDeviceRegisterInputReportCallback(device, tap.buffer, size, { context, _, _, _, _, report, length in
            guard let context = context else { return }
            let tap = Unmanaged<ReportTap>.fromOpaque(context).takeUnretainedValue()
            tap.service?.handleReport(Array(UnsafeBufferPointer(start: report, count: length)))
        }, Unmanaged.passUnretained(tap).toOpaque())
        updateSnapshot { $0.connected = true }
    }

    private func deviceRemoved(_ device: IOHIDDevice) {
        if let tap = taps.removeValue(forKey: device) {
            // Kept alive in case a late callback still references it.
            retiredTaps.append(tap)
        }
        guard taps.isEmpty else { return }
        let profileName = engine.profile.name
        for event in engine.releaseAll() { runner.handle(event, profileName: profileName) }
        runner.macros.stopAll()
        resetOutputs()
        setTicking(false)
        updateSnapshot { snap in
            snap.connected = false
            snap.state = ControllerState()
            snap.held = []
            snap.pad = PadState()
        }
    }

    private func handleReport(_ bytes: [UInt8]) {
        guard let state = decoder.decode(bytes) else { return }
        let before = engine.heldInputs
        let output = engine.process(state, now: ProcessInfo.processInfo.systemUptime)
        let newlyPressed = engine.heldInputs.subtracting(before).sorted { $0.order < $1.order }
        updateSnapshot { snap in
            snap.state = state
            snap.lastReport = bytes
            if let first = newlyPressed.first {
                snap.lastPressed = first
                snap.pressSerial += 1
            }
        }
        apply(output)
    }

    private func apply(_ output: EngineOutput) {
        let profileName = engine.profile.name
        for event in output.events { runner.handle(event, profileName: profileName) }
        let pad = output.pad.merging(runner.macros.padButtons)
        send(pad)
        setTicking(output.needsTicks)
        let held = engine.heldInputs
        updateSnapshot { snap in
            snap.pad = pad
            snap.held = held
        }
    }

    private func send(_ pad: PadState) {
        switch engine.profile.output {
        case .virtualGamepad:
            if pad != lastPad { virtualPad.send(VirtualPadReport.encode(pad)) }
        case .keyboard:
            let change = keyboard.update(pad: pad, map: engine.profile.keyboardMap)
            for key in change.release { runner.keys.keyUp(key) }
            for key in change.press { runner.keys.keyDown(key) }
        case .actionsOnly:
            break
        }
        lastPad = pad
    }

    private func resetOutputs() {
        for key in keyboard.releaseAll() { runner.keys.keyUp(key) }
        virtualPad.send(VirtualPadReport.encode(PadState()))
        lastPad = PadState()
    }

    private func refreshOutputs() {
        apply(engine.tick(now: ProcessInfo.processInfo.systemUptime))
    }

    private func setTicking(_ on: Bool) {
        guard let runLoop = runLoop else { return }
        if on, tickTimer == nil {
            let timer = CFRunLoopTimerCreateWithHandler(kCFAllocatorDefault, CFAbsoluteTimeGetCurrent() + 0.008, 0.008, 0, 0) { [weak self] _ in
                self?.refreshOutputs()
            }
            CFRunLoopAddTimer(runLoop, timer, CFRunLoopMode.defaultMode)
            tickTimer = timer
        } else if !on, let timer = tickTimer {
            CFRunLoopTimerInvalidate(timer)
            tickTimer = nil
        }
    }

    private func apply(config newConfig: AppConfig) {
        let oldConfig = config
        config = newConfig
        decoder.stripMirroredButtons = newConfig.stripMirroredButtons

        let newProfile = newConfig.activeProfile
        let oldProfile = engine.profile
        if newProfile != oldProfile {
            for event in engine.setProfile(newProfile) { runner.handle(event, profileName: oldProfile.name) }
            if newProfile.id != oldProfile.id || newProfile.output != oldProfile.output {
                runner.macros.stopAll()
                resetOutputs()
            }
            refreshOutputs()
        }
        if oldConfig.blockOnboardMediaKeys != newConfig.blockOnboardMediaKeys {
            applyMediaKeyBlocking()
        }
    }
}

/// Owns the report buffer for one HID interface.
private final class ReportTap {
    weak var service: ControllerService?
    let buffer: UnsafeMutablePointer<UInt8>

    init(service: ControllerService, size: Int) {
        self.service = service
        self.buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: size)
        self.buffer.initialize(repeating: 0, count: size)
    }

    deinit {
        buffer.deallocate()
    }
}
