import AppKit
import SwiftUI
import ScufCore

/// Local view state held in a `@StateObject`.
///
/// Used instead of `@State`: in newer macOS SDKs `@State` is a macro whose plugin ships only with
/// full Xcode, so `@State` code fails to build with just the Command Line Tools.
final class ViewState<Value>: ObservableObject {
    @Published var value: Value

    init(_ value: Value) {
        self.value = value
    }
}

/// Shows a key combination with a Record button, a key menu and modifier checkboxes.
struct KeyComboField: View {
    @Binding var combo: KeyCombo
    @StateObject private var recordingState = ViewState(false)
    @StateObject private var monitorState = ViewState<Any?>(nil)

    private var recording: Bool {
        get { recordingState.value }
        nonmutating set { recordingState.value = newValue }
    }

    private var monitor: Any? {
        get { monitorState.value }
        nonmutating set { monitorState.value = newValue }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(combo.summary)
                    .font(.system(.body, design: .monospaced))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Color.secondary.opacity(0.15)))
                Button(recording ? "Press a key…" : "Record") {
                    recording ? stopRecording() : startRecording()
                }
                KeyMenu(code: $combo.keyCode)
                    .frame(width: 150)
            }
            HStack(spacing: 12) {
                ForEach(Modifier.allCases, id: \.self) { modifier in
                    Toggle(modifierName(modifier), isOn: Binding(
                        get: { combo.modifiers.contains(modifier) },
                        set: { on in
                            if on { combo.modifiers.insert(modifier) } else { combo.modifiers.remove(modifier) }
                        }
                    ))
                    .toggleStyle(.checkbox)
                }
            }
        }
        .onDisappear { stopRecording() }
    }

    private func modifierName(_ modifier: Modifier) -> String {
        switch modifier {
        case .control: return "⌃ Control"
        case .option: return "⌥ Option"
        case .shift: return "⇧ Shift"
        case .command: return "⌘ Command"
        case .function: return "fn"
        }
    }

    private func startRecording() {
        recording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { event in
            var modifiers = Set<Modifier>()
            let flags = event.modifierFlags
            if flags.contains(.command) { modifiers.insert(.command) }
            if flags.contains(.option) { modifiers.insert(.option) }
            if flags.contains(.control) { modifiers.insert(.control) }
            if flags.contains(.shift) { modifiers.insert(.shift) }
            combo = KeyCombo(event.keyCode, modifiers)
            stopRecording()
            return nil
        }
    }

    private func stopRecording() {
        if let monitor = monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        recording = false
    }
}

/// A menu of every key, for keys that are awkward to record.
struct KeyMenu: View {
    @Binding var code: UInt16

    var body: some View {
        Picker("Key", selection: $code) {
            ForEach(KeyCodes.all, id: \.code) { key in
                Text(key.name).tag(key.code)
            }
        }
        .labelsHidden()
    }
}

/// A key menu that can also be empty.
struct OptionalKeyPicker: View {
    let title: String
    @Binding var code: UInt16?

    var body: some View {
        Picker(title, selection: $code) {
            Text("None").tag(UInt16?.none)
            ForEach(KeyCodes.all, id: \.code) { key in
                Text(key.name).tag(UInt16?.some(key.code))
            }
        }
    }
}

struct LabeledSlider: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    var format: (Double) -> String = { "\(Int(($0 * 100).rounded()))%" }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(title)
                Spacer()
                Text(format(value))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            Slider(value: $value, in: range)
        }
    }
}

struct MacroEditor: View {
    @Binding var macro: Macro
    @StateObject private var recorder = MacroRecorder()
    @StateObject private var recordFailedState = ViewState(false)

    private var recordFailed: Bool {
        get { recordFailedState.value }
        nonmutating set { recordFailedState.value = newValue }
    }

    var body: some View {
        Section("Playback") {
            Picker("Mode", selection: $macro.mode) {
                ForEach(MacroMode.allCases, id: \.self) { Text($0.displayName).tag($0) }
            }
            if macro.mode != .once {
                Stepper("Pause between repeats: \(macro.repeatGapMs) ms", value: $macro.repeatGapMs, in: 0...10_000, step: 10)
            }
        }

        Section {
            if macro.steps.isEmpty {
                Text("No steps yet. Add steps below or record keystrokes.")
                    .foregroundStyle(.secondary)
            }
            ForEach(Array(macro.steps.indices), id: \.self) { index in
                MacroStepRow(
                    step: stepBinding(index),
                    index: index,
                    count: macro.steps.count,
                    move: { offset in move(index, by: offset) },
                    delete: { if index < macro.steps.count { macro.steps.remove(at: index) } }
                )
            }
            HStack {
                Menu("Add Step") {
                    Button("Tap key") { macro.steps.append(.tap(combo: KeyCombo(KeyCodes.a))) }
                    Button("Hold key down") { macro.steps.append(.keyDown(keyCode: KeyCodes.a)) }
                    Button("Release key") { macro.steps.append(.keyUp(keyCode: KeyCodes.a)) }
                    Button("Type text") { macro.steps.append(.text(string: "")) }
                    Button("Wait") { macro.steps.append(.delay(ms: 100)) }
                    Button("Mouse click") { macro.steps.append(.click(button: .left)) }
                    Divider()
                    Button("Tap pad button") { macro.steps.append(.padTap(button: .a)) }
                    Button("Hold pad button") { macro.steps.append(.padDown(button: .a)) }
                    Button("Release pad button") { macro.steps.append(.padUp(button: .a)) }
                }
                .fixedSize()
                Button(recorder.isRecording ? "Stop Recording" : "Record Keystrokes") {
                    if recorder.isRecording {
                        macro.steps.append(contentsOf: recorder.stop())
                    } else {
                        recordFailed = !recorder.start()
                    }
                }
                Toggle("Keep timing", isOn: $recorder.recordTiming)
                    .toggleStyle(.checkbox)
                    .disabled(recorder.isRecording)
                Spacer()
                if !macro.steps.isEmpty {
                    Button("Clear", role: .destructive) { macro.steps.removeAll() }
                }
            }
            if recorder.isRecording {
                Text("Recording… type in any app, then click Stop Recording. \(recorder.steps.count) events so far.")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            if recordFailed {
                Text("macOS blocked recording. Allow ScufBridge under Privacy & Security → Input Monitoring, then try again.")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        } header: {
            Text("Steps")
        }
        .onDisappear {
            if recorder.isRecording { recorder.stop() }
        }
    }

    private func stepBinding(_ index: Int) -> Binding<MacroStep> {
        Binding(
            get: { index < macro.steps.count ? macro.steps[index] : .delay(ms: 0) },
            set: { if index < macro.steps.count { macro.steps[index] = $0 } }
        )
    }

    private func move(_ index: Int, by offset: Int) {
        let target = index + offset
        guard macro.steps.indices.contains(index), macro.steps.indices.contains(target) else { return }
        macro.steps.swapAt(index, target)
    }
}

private struct MacroStepRow: View {
    @Binding var step: MacroStep
    let index: Int
    let count: Int
    let move: (Int) -> Void
    let delete: () -> Void
    @StateObject private var editingComboState = ViewState(false)

    private var editingCombo: Bool {
        get { editingComboState.value }
        nonmutating set { editingComboState.value = newValue }
    }

    var body: some View {
        HStack(spacing: 8) {
            Text("\(index + 1).")
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 28, alignment: .trailing)
            editor
            Spacer(minLength: 4)
            Button { move(-1) } label: { Image(systemName: "chevron.up") }
                .disabled(index == 0)
            Button { move(1) } label: { Image(systemName: "chevron.down") }
                .disabled(index >= count - 1)
            Button(role: .destructive, action: delete) { Image(systemName: "trash") }
        }
        .buttonStyle(.borderless)
    }

    @ViewBuilder
    private var editor: some View {
        switch step {
        case .tap(let combo):
            Text("Tap")
            Button(combo.summary) { editingCombo = true }
                .popover(isPresented: $editingComboState.value) {
                    KeyComboField(combo: Binding(get: { combo }, set: { step = .tap(combo: $0) }))
                        .padding()
                }
        case .keyDown(let code):
            Text("Hold")
            KeyMenu(code: Binding(get: { code }, set: { step = .keyDown(keyCode: $0) })).frame(width: 140)
        case .keyUp(let code):
            Text("Release")
            KeyMenu(code: Binding(get: { code }, set: { step = .keyUp(keyCode: $0) })).frame(width: 140)
        case .text(let string):
            Text("Type")
            TextField("text", text: Binding(get: { string }, set: { step = .text(string: $0) }))
        case .delay(let ms):
            Text("Wait")
            TextField("ms", value: Binding(get: { ms }, set: { step = .delay(ms: max(0, $0)) }), format: .number)
                .frame(width: 70)
            Text("ms")
        case .click(let button):
            Picker("Click", selection: Binding(get: { button }, set: { step = .click(button: $0) })) {
                ForEach(MouseButton.allCases, id: \.self) { Text($0.displayName).tag($0) }
            }
            .frame(width: 180)
        case .padTap(let button):
            Text("Tap pad")
            PadPicker(button: Binding(get: { button }, set: { step = .padTap(button: $0) }))
        case .padDown(let button):
            Text("Hold pad")
            PadPicker(button: Binding(get: { button }, set: { step = .padDown(button: $0) }))
        case .padUp(let button):
            Text("Release pad")
            PadPicker(button: Binding(get: { button }, set: { step = .padUp(button: $0) }))
        }
    }
}

private struct PadPicker: View {
    @Binding var button: PadButton

    var body: some View {
        Picker("Pad button", selection: $button) {
            ForEach(PadButton.allCases, id: \.self) { Text($0.displayName).tag($0) }
        }
        .labelsHidden()
        .frame(width: 130)
    }
}

/// Lays items out left to right, wrapping onto new lines.
struct FlowLayout: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var widest: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > maxWidth {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
            widest = max(widest, x - spacing)
        }
        return CGSize(width: widest, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
