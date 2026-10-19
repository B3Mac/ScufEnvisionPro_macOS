import SwiftUI
import ScufCore

/// Live view of the controller: every input, sticks, triggers, what the game receives, and raw bytes.
struct MonitorView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var live: LiveModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header

                GroupBox("Inputs") {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(ButtonGroup.allCases, id: \.self) { group in
                            HStack(alignment: .firstTextBaseline) {
                                Text(group.rawValue)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .frame(width: 130, alignment: .leading)
                                FlowRow(items: group.buttons) { input in
                                    InputPill(title: input.shortName, pressed: isPressed(input))
                                }
                            }
                        }
                    }
                    .padding(6)
                }

                HStack(alignment: .top, spacing: 18) {
                    GroupBox("Sticks (raw)") {
                        HStack(spacing: 24) {
                            RawStick(x: live.snapshot.state.leftX, y: live.snapshot.state.leftY, label: "Left")
                            RawStick(x: live.snapshot.state.rightX, y: live.snapshot.state.rightY, label: "Right")
                        }
                        .padding(6)
                    }
                    GroupBox("Triggers (raw)") {
                        VStack(alignment: .leading, spacing: 12) {
                            MeterRow(label: "LT", value: live.snapshot.state.leftTrigger)
                            MeterRow(label: "RT", value: live.snapshot.state.rightTrigger)
                        }
                        .padding(6)
                        .frame(width: 240)
                    }
                }

                GroupBox("What the game receives (\(model.config.activeProfile.output.displayName))") {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(padSummary)
                            .font(.system(.body, design: .monospaced))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(6)
                }

                GroupBox("Raw report") {
                    Text(live.snapshot.lastReport.isEmpty ? "—" : live.snapshot.lastReport.map { String(format: "%02X", $0) }.joined(separator: " "))
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(6)
                }

                GroupBox("Controller options") {
                    VStack(alignment: .leading, spacing: 8) {
                        Toggle("Stop G2–G4 from changing the Mac's volume on their own", isOn: $model.config.blockOnboardMediaKeys)
                        if model.config.blockOnboardMediaKeys && !live.snapshot.mediaKeysBlocked {
                            Text("Couldn't take over the controller's media keys. Allow ScufBridge under Input Monitoring (Setup & Permissions), then reconnect the controller.")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                        Toggle("Paddles and SAX buttons act alone (remove the button the controller copies onto them)", isOn: $model.config.stripMirroredButtons)
                    }
                    .toggleStyle(.checkbox)
                    .padding(6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding()
        }
        .navigationTitle("Controller")
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: live.snapshot.connected ? "gamecontroller.fill" : "gamecontroller")
                .font(.system(size: 28))
                .foregroundStyle(live.snapshot.connected ? Color.green : Color.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(live.snapshot.connected ? "SCUF Envision Pro connected" : "Controller not connected")
                    .font(.title3.weight(.semibold))
                Text("Profile: \(model.config.activeProfile.name) · \(model.outputStatus.text)")
                    .foregroundStyle(model.outputStatus.ok ? Color.secondary : Color.orange)
            }
        }
    }

    private func isPressed(_ input: ControllerButton) -> Bool {
        live.snapshot.state.buttons.contains(input) || live.snapshot.held.contains(input)
    }

    private var padSummary: String {
        let pad = live.snapshot.pad
        let buttons = PadButton.allCases.filter { pad.buttons.contains($0) }.map(\.displayName)
        func f(_ v: Double) -> String { String(format: "%+.2f", v) }
        return """
        Buttons: \(buttons.isEmpty ? "none" : buttons.joined(separator: ", "))
        Left stick:  x \(f(pad.leftX))  y \(f(pad.leftY))      LT \(String(format: "%.2f", pad.leftTrigger))
        Right stick: x \(f(pad.rightX))  y \(f(pad.rightY))      RT \(String(format: "%.2f", pad.rightTrigger))
        """
    }
}

private struct InputPill: View {
    let title: String
    let pressed: Bool

    var body: some View {
        Text(title)
            .font(.callout.weight(pressed ? .semibold : .regular))
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Capsule().fill(pressed ? Color.green.opacity(0.85) : Color.secondary.opacity(0.15)))
            .foregroundStyle(pressed ? Color.white : Color.primary)
    }
}

/// Lays items out left to right, wrapping onto new lines.
private struct FlowRow<Item: Hashable, Content: View>: View {
    let items: [Item]
    let content: (Item) -> Content

    var body: some View {
        FlowLayout(spacing: 6) {
            ForEach(items, id: \.self) { content($0) }
        }
    }
}

private struct RawStick: View {
    let x: Double
    let y: Double
    let label: String

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                Circle().stroke(Color.secondary.opacity(0.5), lineWidth: 1)
                Circle()
                    .fill(Color.accentColor)
                    .frame(width: 10, height: 10)
                    .offset(x: x * 55, y: y * 55)
            }
            .frame(width: 120, height: 120)
            Text("\(label)  \(String(format: "%+.2f, %+.2f", x, y))")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
    }
}

private struct MeterRow: View {
    let label: String
    let value: Double

    var body: some View {
        HStack {
            Text(label).frame(width: 26, alignment: .leading)
            ProgressView(value: max(0, min(1, value)))
            Text(String(format: "%3.0f%%", value * 100))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 44, alignment: .trailing)
        }
    }
}
