import Foundation
import ScufCore

/// Plays macros on background threads. Each input can have one running macro.
final class MacroPlayer: @unchecked Sendable {
    private final class Run: @unchecked Sendable {
        private let lock = NSLock()
        private var cancelled = false
        var heldKeys: Set<UInt16> = []
        var heldPad: Set<PadButton> = []

        var isCancelled: Bool { lock.withLock { cancelled } }
        func cancel() { lock.withLock { cancelled = true } }
    }

    private let keys: KeySender
    private let lock = NSLock()
    private var running: [ControllerButton: Run] = [:]
    private var padCounts: [PadButton: Int] = [:]

    /// Called (from any thread) when the set of pad buttons held by macros changes.
    var onPadChange: () -> Void = {}

    init(keys: KeySender) {
        self.keys = keys
    }

    /// Pad buttons currently held by running macros.
    var padButtons: Set<PadButton> {
        lock.withLock { Set(padCounts.filter { $0.value > 0 }.keys) }
    }

    func pressed(_ input: ControllerButton, _ macro: Macro) {
        // A run that has been cancelled but hasn't finished unwinding doesn't count as running.
        let existing = lock.withLock { running[input] }.flatMap { $0.isCancelled ? nil : $0 }
        switch macro.mode {
        case .once:
            if existing != nil { return }
            start(input, macro, loop: false)
        case .whileHeld:
            existing?.cancel()
            start(input, macro, loop: true)
        case .toggle:
            if let existing = existing {
                existing.cancel()
            } else {
                start(input, macro, loop: true)
            }
        }
    }

    func released(_ input: ControllerButton, _ macro: Macro) {
        guard macro.mode == .whileHeld else { return }
        lock.withLock { running[input] }?.cancel()
    }

    func stopAll() {
        let runs = lock.withLock { Array(running.values) }
        runs.forEach { $0.cancel() }
    }

    private func start(_ input: ControllerButton, _ macro: Macro, loop: Bool) {
        guard !macro.steps.isEmpty else { return }
        let run = Run()
        lock.withLock { running[input] = run }
        let thread = Thread { [weak self] in
            guard let self = self else { return }
            repeat {
                for step in macro.steps {
                    if run.isCancelled { break }
                    self.perform(step, run)
                }
                if !loop || run.isCancelled { break }
                self.sleep(ms: max(1, macro.repeatGapMs), run)
            } while !run.isCancelled
            for key in run.heldKeys { self.keys.keyUp(key) }
            for button in run.heldPad { self.changePad(button, by: -1) }
            self.lock.withLock {
                if self.running[input] === run { self.running[input] = nil }
            }
        }
        thread.qualityOfService = .userInteractive
        thread.start()
    }

    private func perform(_ step: MacroStep, _ run: Run) {
        switch step {
        case .tap(let combo):
            keys.tap(combo)
        case .keyDown(let code):
            keys.keyDown(code)
            run.heldKeys.insert(code)
        case .keyUp(let code):
            keys.keyUp(code)
            run.heldKeys.remove(code)
        case .text(let string):
            keys.type(string)
        case .delay(let ms):
            sleep(ms: ms, run)
        case .click(let button):
            keys.click(button)
        case .padTap(let button):
            changePad(button, by: 1)
            sleep(ms: 60, run)
            changePad(button, by: -1)
        case .padDown(let button):
            if run.heldPad.insert(button).inserted { changePad(button, by: 1) }
        case .padUp(let button):
            if run.heldPad.remove(button) != nil { changePad(button, by: -1) }
        }
    }

    private func changePad(_ button: PadButton, by delta: Int) {
        lock.withLock { padCounts[button, default: 0] = max(0, padCounts[button, default: 0] + delta) }
        onPadChange()
    }

    /// Sleeps in small slices so cancellation is quick.
    private func sleep(ms: Int, _ run: Run) {
        var remaining = max(0, ms)
        while remaining > 0, !run.isCancelled {
            let slice = min(remaining, 5)
            usleep(useconds_t(slice * 1000))
            remaining -= slice
        }
    }
}
