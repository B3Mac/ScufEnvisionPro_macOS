import AppKit
import SwiftUI
import ScufCore

/// The three photos of the controller.
enum ControllerFace: String, CaseIterable, Identifiable {
    case angle, front, back

    var id: String { rawValue }

    var title: String {
        switch self {
        case .angle: return "3/4"
        case .front: return "Front"
        case .back: return "Back"
        }
    }
}

/// The controller photos and where each input sits on them.
enum ControllerArtwork {
    /// Every photo is cropped to this canvas, in pixels. Hotspots are measured on it.
    static let canvas = CGSize(width: 980, height: 740)
    static var aspectRatio: CGFloat { canvas.width / canvas.height }

    private static var cache: [ControllerFace: NSImage] = [:]

    /// Loaded from the app bundle's Resources (copied there by scripts/build_app.sh).
    static func image(for face: ControllerFace) -> NSImage? {
        if let cached = cache[face] { return cached }
        guard let url = Bundle.main.url(forResource: "controller-\(face.rawValue)", withExtension: "png"),
              let image = NSImage(contentsOf: url)
        else { return nil }
        cache[face] = image
        return image
    }

    /// Button centres in canvas pixels. On the back photo the controller's right side is on the left.
    private static let pixelHotspots: [ControllerFace: [ControllerButton: CGPoint]] = [
        .angle: [
            .a: CGPoint(x: 768, y: 225),
            .b: CGPoint(x: 800, y: 172),
            .x: CGPoint(x: 712, y: 172),
            .y: CGPoint(x: 748, y: 118),
            .dpadUp: CGPoint(x: 298, y: 162),
            .dpadDown: CGPoint(x: 302, y: 248),
            .dpadLeft: CGPoint(x: 258, y: 205),
            .dpadRight: CGPoint(x: 342, y: 205),
            .lb: CGPoint(x: 270, y: 62),
            .rb: CGPoint(x: 700, y: 40),
            .l3: CGPoint(x: 440, y: 300),
            .r3: CGPoint(x: 682, y: 288),
            .view: CGPoint(x: 380, y: 130),
            .menu: CGPoint(x: 670, y: 108),
            .home: CGPoint(x: 558, y: 297),
            .profile: CGPoint(x: 565, y: 367),
            .g1: CGPoint(x: 414, y: 440),
            .g2: CGPoint(x: 483, y: 434),
            .g3: CGPoint(x: 552, y: 430),
            .g4: CGPoint(x: 623, y: 424),
            .g5: CGPoint(x: 690, y: 417),
            .saxLeft: CGPoint(x: 172, y: 195),
        ],
        .front: [
            .a: CGPoint(x: 758, y: 263),
            .b: CGPoint(x: 816, y: 206),
            .x: CGPoint(x: 702, y: 203),
            .y: CGPoint(x: 758, y: 145),
            .dpadUp: CGPoint(x: 223, y: 162),
            .dpadDown: CGPoint(x: 223, y: 250),
            .dpadLeft: CGPoint(x: 180, y: 205),
            .dpadRight: CGPoint(x: 267, y: 205),
            .lb: CGPoint(x: 240, y: 62),
            .rb: CGPoint(x: 740, y: 62),
            .l3: CGPoint(x: 347, y: 327),
            .r3: CGPoint(x: 632, y: 327),
            .view: CGPoint(x: 318, y: 141),
            .menu: CGPoint(x: 662, y: 141),
            .home: CGPoint(x: 491, y: 327),
            .profile: CGPoint(x: 491, y: 392),
            .g1: CGPoint(x: 326, y: 460),
            .g2: CGPoint(x: 408, y: 460),
            .g3: CGPoint(x: 491, y: 460),
            .g4: CGPoint(x: 574, y: 460),
            .g5: CGPoint(x: 656, y: 460),
            .saxLeft: CGPoint(x: 128, y: 180),
            .saxRight: CGPoint(x: 870, y: 185),
        ],
        .back: [
            .lb: CGPoint(x: 695, y: 58),
            .rb: CGPoint(x: 285, y: 58),
            .lt: CGPoint(x: 745, y: 105),
            .rt: CGPoint(x: 240, y: 105),
            .p1: CGPoint(x: 262, y: 375),
            .p2: CGPoint(x: 332, y: 388),
            .p3: CGPoint(x: 653, y: 388),
            .p4: CGPoint(x: 720, y: 375),
            .saxLeft: CGPoint(x: 856, y: 180),
            .saxRight: CGPoint(x: 126, y: 180),
        ],
    ]

    struct Spot: Identifiable {
        let input: ControllerButton
        /// 0...1 across and down the canvas.
        let point: CGPoint
        var id: ControllerButton { input }
    }

    static func spots(on face: ControllerFace) -> [Spot] {
        (pixelHotspots[face] ?? [:])
            .map { Spot(input: $0.key, point: CGPoint(x: $0.value.x / canvas.width, y: $0.value.y / canvas.height)) }
            .sorted { $0.input.order < $1.input.order }
    }

    static func shows(_ input: ControllerButton, on face: ControllerFace) -> Bool {
        pixelHotspots[face]?[input] != nil
    }
}

/// Where the stage is turned to. Kept in one object so drags don't redraw the whole tab.
final class StageModel: ObservableObject {
    /// The photo the user is looking at.
    @Published var face: ControllerFace = .angle
    /// Which photo sits on the card's front side (the back side is always the back photo).
    @Published var frontSide: ControllerFace = .angle
    /// Settled turn in degrees, always a multiple of 180.
    @Published var spin: Double = 0
    @Published var drag: CGSize = .zero
    @Published var hoverTilt: CGPoint = .zero
    @Published var hovered: ControllerButton?
}

/// A showroom view of the controller: drag to turn it in 3D, click a button to map it.
struct ControllerStage: View {
    @Binding var selected: ControllerButton?
    let customized: Set<ControllerButton>
    let summary: (ControllerButton) -> String

    @StateObject private var stage = StageModel()

    private let degreesPerPoint = 0.45

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Picker("View", selection: Binding(get: { stage.face }, set: { show($0) })) {
                    ForEach(ControllerFace.allCases) { face in
                        Text(face.title).tag(face)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 210)
                Spacer()
                Label("Drag to turn · click a button to map it", systemImage: "hand.draw")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            GeometryReader { geometry in
                let card = fittedCardSize(in: geometry.size)
                let yaw = stage.spin + Double(stage.drag.width) * degreesPerPoint + Double(stage.hoverTilt.x)
                let pitch = max(-18, min(18, -Double(stage.drag.height) * 0.18)) + Double(stage.hoverTilt.y)
                ZStack {
                    FloorShadow(width: card.width, turn: yaw)
                        .offset(y: card.height * 0.47)
                    ControllerTurntable(
                        yaw: yaw,
                        pitch: pitch,
                        frontSide: stage.frontSide,
                        size: card,
                        selected: selected,
                        hovered: stage.hovered,
                        customized: customized,
                        summary: summary,
                        onSelect: { input in selected = input },
                        onHover: hoverChanged
                    )
                }
                .frame(width: geometry.size.width, height: geometry.size.height)
                .contentShape(Rectangle())
                .gesture(turnGesture)
                .onContinuousHover { phase in
                    switch phase {
                    case .active(let location):
                        let x = location.x / max(1, geometry.size.width) - 0.5
                        let y = location.y / max(1, geometry.size.height) - 0.5
                        withAnimation(.easeOut(duration: 0.25)) {
                            stage.hoverTilt = CGPoint(x: x * 9, y: -y * 7)
                        }
                    case .ended:
                        withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
                            stage.hoverTilt = .zero
                        }
                    }
                }
            }
            .aspectRatio(1.32, contentMode: .fit)
            .background(StageBackdrop())
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.08))
            )
            .environment(\.colorScheme, .dark)
        }
        .onChange(of: selected) { _, input in
            if let input = input { reveal(input) }
        }
    }

    private func fittedCardSize(in space: CGSize) -> CGSize {
        let width = max(1, space.width - 48)
        let height = max(1, space.height - 56)
        let aspect = ControllerArtwork.aspectRatio
        return width / height > aspect
            ? CGSize(width: height * aspect, height: height)
            : CGSize(width: width, height: width / aspect)
    }

    private var turnGesture: some Gesture {
        DragGesture(minimumDistance: 3)
            .onChanged { value in
                stage.drag = value.translation
            }
            .onEnded { value in
                let turned = stage.spin + Double(value.translation.width) * degreesPerPoint
                let flung = Double(value.predictedEndTranslation.width) * degreesPerPoint
                var target = (turned / 180).rounded() * 180
                if target == stage.spin, abs(flung) > 150 {
                    target += flung > 0 ? 180 : -180
                }
                let halfTurns = Int(((target - stage.spin) / 180).rounded())
                withAnimation(.spring(response: 0.6, dampingFraction: 0.78)) {
                    stage.spin = target
                    if halfTurns % 2 != 0 {
                        stage.face = stage.face == .back ? stage.frontSide : .back
                    }
                    stage.drag = .zero
                }
            }
    }

    private func hoverChanged(_ input: ControllerButton, _ inside: Bool) {
        if inside {
            stage.hovered = input
        } else if stage.hovered == input {
            stage.hovered = nil
        }
    }

    /// Turns to a photo. Front and 3/4 cross-fade; anything involving the back flips the card.
    private func show(_ face: ControllerFace) {
        guard face != stage.face else { return }
        withAnimation(.spring(response: 0.7, dampingFraction: 0.82)) {
            if face == .back || stage.face == .back {
                stage.spin += 180
            }
            if face != .back {
                stage.frontSide = face
            }
            stage.face = face
        }
    }

    /// Makes sure the selected input is visible, turning the controller if needed.
    private func reveal(_ input: ControllerButton) {
        guard !ControllerArtwork.shows(input, on: stage.face) else { return }
        if ControllerArtwork.shows(input, on: stage.frontSide) {
            show(stage.frontSide)
        } else if ControllerArtwork.shows(input, on: .front) {
            show(.front)
        } else {
            show(.back)
        }
    }
}

/// The controller as a two-sided card that turns in 3D. Animatable so the side that faces the
/// viewer is chosen on every frame of a flip.
private struct ControllerTurntable: View, Animatable {
    var yaw: Double
    var pitch: Double
    let frontSide: ControllerFace
    let size: CGSize
    let selected: ControllerButton?
    let hovered: ControllerButton?
    let customized: Set<ControllerButton>
    let summary: (ControllerButton) -> String
    let onSelect: (ControllerButton) -> Void
    let onHover: (ControllerButton, Bool) -> Void

    var animatableData: AnimatablePair<Double, Double> {
        get { AnimatablePair(yaw, pitch) }
        set {
            yaw = newValue.first
            pitch = newValue.second
        }
    }

    var body: some View {
        let turn = (yaw.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360)
        let frontVisible = turn < 90 || turn > 270
        // How far the visible side is turned away from the viewer, -90...90.
        let residual = frontVisible ? (turn > 180 ? turn - 360 : turn) : turn - 180

        ZStack {
            face(.angle, visible: frontVisible && frontSide == .angle, residual: residual)
            face(.front, visible: frontVisible && frontSide == .front, residual: residual)
            face(.back, visible: !frontVisible, residual: residual)
                .rotation3DEffect(.degrees(180), axis: (x: 0, y: 1, z: 0))
        }
        .frame(width: size.width, height: size.height)
        .rotation3DEffect(.degrees(pitch), axis: (x: 1, y: 0, z: 0), perspective: 0.45)
        .rotation3DEffect(.degrees(yaw), axis: (x: 0, y: 1, z: 0), perspective: 0.45)
        .shadow(color: .black.opacity(0.5), radius: 24, x: CGFloat(-residual * 0.3), y: 22)
    }

    private func face(_ face: ControllerFace, visible: Bool, residual: Double) -> some View {
        FaceLayer(
            face: face,
            sheen: residual / 90,
            selected: selected,
            hovered: hovered,
            customized: customized,
            summary: summary,
            onSelect: onSelect,
            onHover: onHover
        )
        .opacity(visible ? 1 : 0)
        .allowsHitTesting(visible)
    }
}

/// One photo with its moving highlight and hotspots.
private struct FaceLayer: View {
    let face: ControllerFace
    /// -1...1, how far the card is turned; moves the highlight across the body.
    let sheen: Double
    let selected: ControllerButton?
    let hovered: ControllerButton?
    let customized: Set<ControllerButton>
    let summary: (ControllerButton) -> String
    let onSelect: (ControllerButton) -> Void
    let onHover: (ControllerButton, Bool) -> Void

    var body: some View {
        ZStack {
            if let image = ControllerArtwork.image(for: face) {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                highlight(masked: image)
            } else {
                MissingArtwork(face: face)
            }
            HotspotLayer(
                face: face,
                selected: selected,
                hovered: hovered,
                customized: customized,
                summary: summary,
                onSelect: onSelect,
                onHover: onHover
            )
        }
    }

    /// A soft band of light, clipped to the controller's silhouette, that slides as it turns.
    private func highlight(masked image: NSImage) -> some View {
        let centre = 0.5 - sheen * 0.7
        return LinearGradient(
            stops: [
                .init(color: .white.opacity(0), location: 0),
                .init(color: .white.opacity(0.10 + 0.14 * abs(sheen)), location: 0.5),
                .init(color: .white.opacity(0), location: 1),
            ],
            startPoint: UnitPoint(x: centre - 0.35, y: 0),
            endPoint: UnitPoint(x: centre + 0.35, y: 1)
        )
        .blendMode(.screen)
        .mask(
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
        )
        .allowsHitTesting(false)
    }
}

private struct HotspotLayer: View {
    @EnvironmentObject private var live: LiveModel
    let face: ControllerFace
    let selected: ControllerButton?
    let hovered: ControllerButton?
    let customized: Set<ControllerButton>
    let summary: (ControllerButton) -> String
    let onSelect: (ControllerButton) -> Void
    let onHover: (ControllerButton, Bool) -> Void

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = geometry.size.height
            let diameter = max(16, width * 0.04)
            let spots = ControllerArtwork.spots(on: face)
            let held = live.snapshot.held.union(live.snapshot.state.buttons)

            ZStack(alignment: .topLeading) {
                ForEach(spots) { spot in
                    Hotspot(
                        diameter: diameter,
                        isSelected: spot.input == selected,
                        isHovered: spot.input == hovered,
                        isHeld: held.contains(spot.input),
                        isCustomized: customized.contains(spot.input)
                    )
                    .onTapGesture { onSelect(spot.input) }
                    .onHover { inside in onHover(spot.input, inside) }
                    .help("\(spot.input.displayName): \(summary(spot.input))")
                    .accessibilityLabel(spot.input.displayName)
                    .position(x: spot.point.x * width, y: spot.point.y * height)
                }

                if let focus = hovered ?? selected,
                   let spot = spots.first(where: { $0.input == focus }) {
                    Callout(title: focus.displayName, detail: summary(focus))
                        .position(x: spot.point.x * width, y: max(18, spot.point.y * height - diameter - 12))
                        .allowsHitTesting(false)
                        .transition(.opacity)
                }
            }
            .frame(width: width, height: height)
        }
    }
}

private struct Hotspot: View {
    let diameter: CGFloat
    let isSelected: Bool
    let isHovered: Bool
    let isHeld: Bool
    let isCustomized: Bool

    var body: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color.green.opacity(0.9), Color.green.opacity(0)],
                        center: .center,
                        startRadius: 0,
                        endRadius: diameter
                    )
                )
                .frame(width: diameter * 2, height: diameter * 2)
                .opacity(isHeld ? 1 : 0)

            Circle()
                .fill(fill)
                .overlay(Circle().strokeBorder(ring, lineWidth: isSelected ? 2.5 : 1.5))
                .frame(width: diameter, height: diameter)
                .shadow(color: isSelected ? Color.accentColor.opacity(0.95) : .clear, radius: 10)

            if isCustomized {
                Circle()
                    .fill(Color.accentColor)
                    .frame(width: 6, height: 6)
                    .overlay(Circle().strokeBorder(Color.black.opacity(0.5), lineWidth: 1))
                    .offset(x: diameter * 0.4, y: -diameter * 0.4)
            }
        }
        .frame(width: diameter * 1.4, height: diameter * 1.4)
        .contentShape(Circle())
        .scaleEffect(isHovered || isHeld ? 1.18 : 1)
        .animation(.spring(response: 0.25, dampingFraction: 0.65), value: isHovered)
        .animation(.easeOut(duration: 0.1), value: isHeld)
        .animation(.easeInOut(duration: 0.2), value: isSelected)
    }

    private var ring: Color {
        if isHeld { return .green }
        if isSelected { return .accentColor }
        return .white.opacity(isHovered ? 0.95 : 0.55)
    }

    private var fill: Color {
        if isHeld { return Color.green.opacity(0.35) }
        if isSelected { return Color.accentColor.opacity(0.28) }
        return Color.white.opacity(isHovered ? 0.18 : 0.06)
    }
}

private struct Callout: View {
    let title: String
    let detail: String

    var body: some View {
        VStack(spacing: 1) {
            Text(title)
                .font(.caption.weight(.semibold))
            Text(detail)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(Color.white.opacity(0.15)))
        .fixedSize()
    }
}

/// A soft contact shadow on the floor that leans as the controller turns.
private struct FloorShadow: View {
    let width: CGFloat
    let turn: Double

    var body: some View {
        let lean = CGFloat(sin(turn * .pi / 180))
        Ellipse()
            .fill(Color.black.opacity(0.55))
            .frame(width: width * (0.62 - 0.12 * abs(lean)), height: width * 0.05)
            .offset(x: -lean * width * 0.04)
            .blur(radius: 16)
            .allowsHitTesting(false)
    }
}

private struct StageBackdrop: View {
    var body: some View {
        ZStack {
            Color(white: 0.07)
            RadialGradient(
                colors: [Color(white: 0.26), Color(white: 0.07).opacity(0)],
                center: UnitPoint(x: 0.5, y: 0.38),
                startRadius: 10,
                endRadius: 480
            )
            LinearGradient(
                colors: [Color.clear, Color.black.opacity(0.35)],
                startPoint: UnitPoint(x: 0.5, y: 0.6),
                endPoint: .bottom
            )
        }
    }
}

/// Shown if the photos weren't bundled (for example a build that skipped Packaging/Artwork).
private struct MissingArtwork: View {
    let face: ControllerFace

    var body: some View {
        RoundedRectangle(cornerRadius: 80, style: .continuous)
            .fill(Color(white: 0.2))
            .overlay(
                Text("\(face.title) photo not bundled")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            )
            .padding(.horizontal, 30)
            .padding(.vertical, 50)
    }
}
