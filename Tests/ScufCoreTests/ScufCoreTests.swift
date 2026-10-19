import XCTest
@testable import ScufCore

/// Reports below are copied from a real wired SCUF Envision Pro capture.
private func hex(_ s: String) -> [UInt8] {
    s.split(separator: " ").map { UInt8($0, radix: 16)! }
}

private let idle = hex("06 00 00 00 00 00 00 00 00 00 00 80 00 00 00 00")

final class DecoderTests: XCTestCase {
    func testFaceButtonsAndMenu() {
        var d = EnvisionDecoder()
        XCTAssertEqual(d.decode(hex("06 00 00 00 00 00 00 00 00 00 00 80 01 00 00 00"))?.buttons, [.a])
        XCTAssertEqual(d.decode(hex("06 00 00 00 00 00 00 00 00 00 00 80 08 00 00 00"))?.buttons, [.y])
        XCTAssertEqual(d.decode(hex("06 00 00 00 00 00 00 00 00 00 00 80 80 00 00 00"))?.buttons, [.menu])
        XCTAssertEqual(d.decode(idle)?.buttons, [])
    }

    func testSystemAndGKeys() {
        var d = EnvisionDecoder()
        XCTAssertEqual(d.decode(hex("06 00 00 00 00 00 00 00 00 00 00 80 00 04 00 00"))?.buttons, [.home])
        XCTAssertEqual(d.decode(hex("06 00 00 00 00 00 00 00 00 00 00 80 00 00 01 00"))?.buttons, [.profile])
        XCTAssertEqual(d.decode(hex("06 00 00 00 00 00 00 00 00 00 00 80 00 08 00 00"))?.buttons, [.g1])
        XCTAssertEqual(d.decode(hex("06 00 00 00 00 00 00 00 00 00 00 80 00 80 00 00"))?.buttons, [.g5])
    }

    func testHat() {
        var d = EnvisionDecoder()
        XCTAssertEqual(d.decode(hex("06 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00"))?.buttons, [.dpadUp])
        XCTAssertEqual(d.decode(hex("06 00 00 00 00 00 00 00 00 00 00 20 00 00 00 00"))?.buttons, [.dpadRight])
        XCTAssertEqual(d.decode(hex("06 00 00 00 00 00 00 00 00 00 00 40 00 00 00 00"))?.buttons, [.dpadDown])
        XCTAssertEqual(d.decode(hex("06 00 00 00 00 00 00 00 00 00 00 60 00 00 00 00"))?.buttons, [.dpadLeft])
        XCTAssertEqual(d.decode(hex("06 00 00 00 00 00 00 00 00 00 00 70 00 00 00 00"))?.buttons, [.dpadUp, .dpadLeft])
    }

    func testPaddleMirrorIsStripped() {
        var d = EnvisionDecoder()
        _ = d.decode(idle)
        // P1 press: onboard profile also sets A.
        XCTAssertEqual(d.decode(hex("06 00 00 00 00 00 00 00 00 00 00 80 01 00 08 00"))?.buttons, [.p1])
        XCTAssertEqual(d.decode(idle)?.buttons, [])
        // SAX right echoes RB.
        XCTAssertEqual(d.decode(hex("06 00 00 00 00 00 00 00 00 00 00 80 20 00 00 01"))?.buttons, [.saxRight])
        XCTAssertEqual(d.decode(idle)?.buttons, [])
    }

    func testPaddleMirrorKeptWhenDisabled() {
        var d = EnvisionDecoder(stripMirroredButtons: false)
        XCTAssertEqual(d.decode(hex("06 00 00 00 00 00 00 00 00 00 00 80 02 00 40 00"))?.buttons, [.b, .p3])
    }

    func testRealButtonHeldBeforePaddleSurvives() {
        var d = EnvisionDecoder()
        _ = d.decode(hex("06 00 00 00 00 00 00 00 00 00 00 80 01 00 00 00")) // A held
        XCTAssertEqual(d.decode(hex("06 00 00 00 00 00 00 00 00 00 00 80 01 00 08 00"))?.buttons, [.a, .p1])
    }

    func testAllPaddlesAndSax() {
        let cases: [(String, ControllerButton)] = [
            ("06 00 00 00 00 00 00 00 00 00 00 80 08 00 10 00", .p2),
            ("06 00 00 00 00 00 00 00 00 00 00 80 02 00 40 00", .p3),
            ("06 00 00 00 00 00 00 00 00 00 00 80 04 00 20 00", .p4),
            ("06 00 00 00 00 00 00 00 00 00 00 80 10 00 80 00", .saxLeft),
        ]
        for (report, expected) in cases {
            var d = EnvisionDecoder()
            _ = d.decode(idle)
            XCTAssertEqual(d.decode(hex(report))?.buttons, [expected], "\(expected)")
        }
    }

    func testTriggers() {
        var d = EnvisionDecoder()
        let lt = d.decode(hex("06 00 00 00 00 00 00 00 00 F0 03 80 00 00 00 00"))!
        XCTAssertEqual(lt.leftTrigger, 1008.0 / 1023, accuracy: 0.0001)
        XCTAssertEqual(lt.rightTrigger, 0)
        let rt = d.decode(hex("06 00 00 00 00 00 00 00 00 00 60 8F 00 00 00 00"))!
        XCTAssertEqual(rt.rightTrigger, 984.0 / 1023, accuracy: 0.0001)
        XCTAssertEqual(rt.leftTrigger, 0)
        XCTAssertEqual(rt.buttons, [], "trigger nibble must not leak into the hat")
    }

    func testSticks() {
        var d = EnvisionDecoder()
        let up = d.decode(hex("06 41 07 00 80 00 00 00 00 00 00 80 00 00 00 00"))!
        XCTAssertEqual(up.leftY, -1, accuracy: 0.0001)
        XCTAssertEqual(up.leftX, 1857.0 / 32767, accuracy: 0.0001)
        let right = d.decode(hex("06 00 00 00 00 B4 F2 00 80 00 00 80 00 00 00 00"))!
        XCTAssertEqual(right.rightX, -3404.0 / 32767, accuracy: 0.0001)
        XCTAssertEqual(right.rightY, -1, accuracy: 0.0001)
    }

    func testIgnoresOtherReports() {
        var d = EnvisionDecoder()
        XCTAssertNil(d.decode([0x11, 0x02]))
        let media = EnvisionDecoder.decodeMedia([0x11, 0x02])
        XCTAssertEqual(media?.volumeDown, true)
        XCTAssertEqual(media?.volumeUp, false)
    }
}

final class EngineTests: XCTestCase {
    func state(_ buttons: Set<ControllerButton>, lt: Double = 0, lx: Double = 0) -> ControllerState {
        var s = ControllerState()
        s.buttons = buttons
        s.leftTrigger = lt
        s.leftX = lx
        return s
    }

    func testDefaultsPassThroughToPad() {
        var engine = MappingEngine(profile: Profile(name: "t"))
        let out = engine.process(state([.a, .p1]), now: 0)
        XCTAssertEqual(out.pad.buttons, [.a])           // P1 defaults to A
        XCTAssertTrue(out.events.isEmpty)              // gamepad actions are not events
    }

    func testCustomActionEvents() {
        var profile = Profile(name: "t")
        profile.bindings[.g1] = .key(combo: KeyCombo(KeyCodes.a, [.command]))
        var engine = MappingEngine(profile: profile)
        let down = engine.process(state([.g1]), now: 0)
        XCTAssertEqual(down.events, [.pressed(.g1, .key(combo: KeyCombo(KeyCodes.a, [.command])))])
        let up = engine.process(state([]), now: 0.1)
        XCTAssertEqual(up.events, [.released(.g1, .key(combo: KeyCombo(KeyCodes.a, [.command])))])
    }

    func testAnalogTriggerPassThroughAndThreshold() {
        var engine = MappingEngine(profile: Profile(name: "t"))
        let out = engine.process(state([], lt: 0.5), now: 0)
        XCTAssertGreaterThan(out.pad.leftTrigger, 0.4)
        XCTAssertLessThan(out.pad.leftTrigger, 0.6)
        XCTAssertTrue(engine.heldInputs.contains(.lt))
    }

    func testTriggerRemappedToKeyIsDigital() {
        var profile = Profile(name: "t")
        profile.bindings[.lt] = .key(combo: KeyCombo(KeyCodes.w))
        var engine = MappingEngine(profile: profile)
        let light = engine.process(state([], lt: 0.1), now: 0)
        XCTAssertTrue(light.events.isEmpty)
        let full = engine.process(state([], lt: 0.9), now: 0.1)
        XCTAssertEqual(full.events, [.pressed(.lt, .key(combo: KeyCombo(KeyCodes.w)))])
        XCTAssertEqual(full.pad.leftTrigger, 0)
    }

    func testTurbo() {
        var profile = Profile(name: "t")
        profile.turboHz = 10
        profile.bindings[.a] = .gamepad(button: .a, turbo: true)
        var engine = MappingEngine(profile: profile)
        XCTAssertTrue(engine.process(state([.a]), now: 0).pad.buttons.contains(.a))
        let off = engine.tick(now: 0.06)
        XCTAssertFalse(off.pad.buttons.contains(.a))
        XCTAssertTrue(off.needsTicks)
        XCTAssertTrue(engine.tick(now: 0.11).pad.buttons.contains(.a))
    }

    func testProfileSwitchDoesNotRefire() {
        var config = AppConfig.makeDefault()
        var engine = MappingEngine(profile: config.activeProfile)
        let press = engine.process(state([.profile]), now: 0)
        XCTAssertEqual(press.events, [.pressed(.profile, .profile(target: .next))])
        config.activeProfileID = config.resolve(.next)
        _ = engine.setProfile(config.activeProfile)
        XCTAssertTrue(engine.process(state([.profile]), now: 0.05).events.isEmpty, "held button must stay inert")
        XCTAssertTrue(engine.process(state([]), now: 0.1).events.isEmpty)
        XCTAssertEqual(engine.process(state([.profile]), now: 0.2).events.count, 1)
    }

    func testStickDeadzoneAndSwap() {
        var profile = Profile(name: "t")
        profile.leftStick.output = .rightStick
        var engine = MappingEngine(profile: profile)
        XCTAssertEqual(engine.process(state([], lx: 0.03), now: 0).pad.rightX, 0)
        let out = engine.process(state([], lx: 1), now: 0)
        XCTAssertEqual(out.pad.rightX, 1, accuracy: 0.0001)
        XCTAssertEqual(out.pad.leftX, 0)
    }
}

final class KeyboardModeTests: XCTestCase {
    func testButtonsAndSticks() {
        var mapper = KeyboardModeMapper()
        var pad = PadState()
        pad.buttons = [.b]
        pad.leftY = -0.8
        let first = mapper.update(pad: pad, map: .ryujinxDefault)
        XCTAssertEqual(Set(first.press), [0x06, KeyCodes.w])   // Z (Switch A) and W
        XCTAssertTrue(first.release.isEmpty)
        // Hysteresis: 0.45 stays on, 0.35 releases.
        pad.leftY = -0.45
        XCTAssertTrue(mapper.update(pad: pad, map: .ryujinxDefault).release.isEmpty)
        pad.leftY = -0.35
        pad.buttons = []
        let second = mapper.update(pad: pad, map: .ryujinxDefault)
        XCTAssertEqual(Set(second.release), [0x06, KeyCodes.w])
    }
}

final class ReportTests: XCTestCase {
    func testEncode() {
        var pad = PadState()
        pad.buttons = [.a, .menu, .dpadUp]
        pad.leftX = 1
        pad.leftY = -1
        pad.rightTrigger = 1
        let r = VirtualPadReport.encode(pad)
        XCTAssertEqual(r.count, 20)
        XCTAssertEqual(r[0], 0x00)
        XCTAssertEqual(r[1], 0x14)
        XCTAssertEqual(r[2], 0x11)
        XCTAssertEqual(r[3], 0x10)
        XCTAssertEqual(r[5], 0xFF)
        XCTAssertEqual(Array(r[6...9]), [0xFF, 0x7F, 0x01, 0x80])
    }

    func testDescriptorDeclaresTwentyByteInput() {
        // 2 const + 2 buttons + 2 triggers + 8 sticks + 6 padding.
        XCTAssertEqual(2 + 2 + 2 + 8 + 6, VirtualPadReport.reportLength)
        XCTAssertEqual(VirtualPadReport.descriptor.first, 0x05)
        XCTAssertEqual(VirtualPadReport.descriptor.last, 0xC0)
    }
}

final class ConfigTests: XCTestCase {
    func testRoundTrip() throws {
        var config = AppConfig.makeDefault()
        var profile = config.profiles[0]
        profile.bindings[.g1] = .macro(macro: Macro(steps: [.tap(combo: KeyCombo(KeyCodes.a, [.shift])), .delay(ms: 30), .text(string: "gg")], mode: .whileHeld))
        profile.bindings[.g5] = .script(script: ScriptAction(command: "say hi"))
        profile.bindings[.p2] = .profile(target: .specific(id: config.profiles[1].id))
        config.profiles[0] = profile
        let data = try JSONEncoder().encode(config)
        let json = String(decoding: data, as: UTF8.self)
        XCTAssertTrue(json.contains("\"g1\""), "bindings should encode as an object keyed by input name")
        let back = try JSONDecoder().decode(AppConfig.self, from: data)
        XCTAssertEqual(back, config)
    }

    func testMissingFieldsFallBackToDefaults() throws {
        let back = try JSONDecoder().decode(AppConfig.self, from: Data("{}".utf8))
        XCTAssertEqual(back.profiles.count, 2)
        XCTAssertTrue(back.autoSwitch)
    }

    func testResolveCycles() {
        let config = AppConfig.makeDefault()
        XCTAssertEqual(config.resolve(.next), config.profiles[1].id)
        XCTAssertEqual(config.resolve(.previous), config.profiles[1].id)
    }
}
