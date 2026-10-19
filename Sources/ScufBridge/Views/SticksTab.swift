import SwiftUI
import ScufCore

struct SticksTab: View {
    @EnvironmentObject private var live: LiveModel
    @Binding var profile: Profile

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(alignment: .top, spacing: 20) {
                    StickPanel(
                        title: "Left stick",
                        settings: $profile.leftStick,
                        rawX: live.snapshot.state.leftX,
                        rawY: live.snapshot.state.leftY
                    )
                    StickPanel(
                        title: "Right stick",
                        settings: $profile.rightStick,
                        rawX: live.snapshot.state.rightX,
                        rawY: live.snapshot.state.rightY
                    )
                }
                HStack(alignment: .top, spacing: 20) {
                    TriggerPanel(title: "Left trigger (LT)", settings: $profile.leftTrigger, raw: live.snapshot.state.leftTrigger)
                    TriggerPanel(title: "Right trigger (RT)", settings: $profile.rightTrigger, raw: live.snapshot.state.rightTrigger)
                }
                GroupBox("Turbo") {
                    LabeledSlider(
                        title: "Turbo speed",
                        value: $profile.turboHz,
                        range: 2...30,
                        format: { "\(Int($0.rounded())) presses/sec" }
                    )
                    .padding(6)
                }
            }
            .padding(4)
        }
    }
}

private struct StickPanel: View {
    let title: String
    @Binding var settings: StickSettings
    let rawX: Double
    let rawY: Double

    var body: some View {
        GroupBox(title) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Spacer()
                    StickPreview(rawX: rawX, rawY: rawY, settings: settings)
                        .frame(width: 150, height: 150)
                    Spacer()
                }
                Picker("Sends to", selection: $settings.output) {
                    ForEach(StickOutput.allCases, id: \.self) { Text($0.displayName).tag($0) }
                }
                LabeledSlider(title: "Inner dead zone", value: $settings.innerDeadzone, range: 0...0.5)
                LabeledSlider(title: "Outer dead zone", value: $settings.outerDeadzone, range: 0...0.3)
                LabeledSlider(
                    title: "Response curve",
                    value: $settings.curve,
                    range: 0.4...3,
                    format: { String(format: "%.2f", $0) + ($0 > 1.05 ? " (finer aim)" : $0 < 0.95 ? " (faster)" : " (linear)") }
                )
                HStack {
                    Toggle("Invert X", isOn: $settings.invertX)
                    Toggle("Invert Y", isOn: $settings.invertY)
                }
                .toggleStyle(.checkbox)
            }
            .padding(6)
        }
        .frame(maxWidth: .infinity)
    }
}

/// Grey dot: raw stick position. Coloured dot: what the game receives.
private struct StickPreview: View {
    let rawX: Double
    let rawY: Double
    let settings: StickSettings

    var body: some View {
        let output = settings.apply(x: rawX, y: rawY)
        Canvas { context, size in
            let radius = min(size.width, size.height) / 2 - 6
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            func point(_ x: Double, _ y: Double) -> CGPoint {
                CGPoint(x: center.x + x * radius, y: center.y + y * radius)
            }
            let outer = Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
            context.stroke(outer, with: .color(.secondary.opacity(0.5)), lineWidth: 1)
            let deadRadius = radius * settings.innerDeadzone
            let dead = Path(ellipseIn: CGRect(x: center.x - deadRadius, y: center.y - deadRadius, width: deadRadius * 2, height: deadRadius * 2))
            context.fill(dead, with: .color(.secondary.opacity(0.15)))
            var cross = Path()
            cross.move(to: CGPoint(x: center.x - radius, y: center.y))
            cross.addLine(to: CGPoint(x: center.x + radius, y: center.y))
            cross.move(to: CGPoint(x: center.x, y: center.y - radius))
            cross.addLine(to: CGPoint(x: center.x, y: center.y + radius))
            context.stroke(cross, with: .color(.secondary.opacity(0.2)), lineWidth: 0.5)
            let raw = point(rawX, rawY)
            context.fill(Path(ellipseIn: CGRect(x: raw.x - 4, y: raw.y - 4, width: 8, height: 8)), with: .color(.gray))
            let out = point(output.x, output.y)
            context.fill(Path(ellipseIn: CGRect(x: out.x - 5, y: out.y - 5, width: 10, height: 10)), with: .color(.accentColor))
        }
    }
}

private struct TriggerPanel: View {
    let title: String
    @Binding var settings: TriggerSettings
    let raw: Double

    var body: some View {
        GroupBox(title) {
            VStack(alignment: .leading, spacing: 10) {
                TriggerBar(raw: raw, output: settings.apply(raw), threshold: settings.pressThreshold)
                    .frame(height: 22)
                LabeledSlider(title: "Dead zone", value: $settings.deadzone, range: 0...0.5)
                LabeledSlider(title: "Full pull at", value: $settings.maxPoint, range: 0.5...1)
                LabeledSlider(title: "Response curve", value: $settings.curve, range: 0.4...3, format: { String(format: "%.2f", $0) })
                LabeledSlider(title: "Counts as pressed at (when mapped to an action)", value: $settings.pressThreshold, range: 0.05...0.95)
                Toggle("Hair trigger (any pull = full pull)", isOn: $settings.hairTrigger)
                    .toggleStyle(.checkbox)
            }
            .padding(6)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct TriggerBar: View {
    let raw: Double
    let output: Double
    let threshold: Double

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 4).fill(Color.secondary.opacity(0.15))
                RoundedRectangle(cornerRadius: 4).fill(Color.gray.opacity(0.5))
                    .frame(width: max(0, width * raw), height: 8)
                    .offset(y: -5)
                RoundedRectangle(cornerRadius: 4).fill(Color.accentColor)
                    .frame(width: max(0, width * output), height: 8)
                    .offset(y: 5)
                Rectangle().fill(Color.orange)
                    .frame(width: 2)
                    .offset(x: width * threshold)
            }
        }
    }
}
