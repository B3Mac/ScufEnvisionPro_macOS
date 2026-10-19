import CoreHID
import Foundation
import ScufCore

/// A virtual Xbox-layout gamepad that games and emulators can see.
///
/// macOS only allows this with the `com.apple.developer.hid.virtual.device` entitlement.
/// Without it, `HIDVirtualDevice(properties:)` returns nil and the status explains why.
final class VirtualGamepad: @unchecked Sendable {
    enum Status: Equatable {
        case starting
        case active
        case unavailable(String)
    }

    private let lock = NSLock()
    private var continuation: AsyncStream<[UInt8]>.Continuation?
    private var task: Task<Void, Never>?

    /// Output reports sent to the pad by games (rumble / LED requests).
    var onOutputReport: (([UInt8]) -> Void)?

    func start(statusHandler: @escaping (Status) -> Void) {
        let (stream, continuation) = AsyncStream<[UInt8]>.makeStream(bufferingPolicy: .bufferingNewest(32))
        lock.withLock { self.continuation = continuation }
        let delegate = PadDelegate { [weak self] data in self?.onOutputReport?(data) }

        task = Task.detached(priority: .userInitiated) {
            let properties = HIDVirtualDevice.Properties(
                descriptor: Data(VirtualPadReport.descriptor),
                vendorID: VirtualPadReport.vendorID,
                productID: VirtualPadReport.productID,
                product: VirtualPadReport.productName,
                manufacturer: "ScufBridge",
                versionNumber: UInt64(VirtualPadReport.versionNumber)
            )
            guard let device = HIDVirtualDevice(properties: properties) else {
                statusHandler(.unavailable(
                    "macOS didn't allow the virtual gamepad. It needs the HID virtual-device entitlement "
                        + "(see README: Virtual gamepad). Keyboard mode and all other actions still work."
                ))
                return
            }
            await device.activate(delegate: delegate)
            statusHandler(.active)
            for await report in stream {
                do {
                    try await device.dispatchInputReport(data: Data(report), timestamp: SuspendingClock.now)
                } catch {
                    // A dropped frame is harmless; the next report carries the full state.
                }
            }
        }
    }

    func send(_ report: [UInt8]) {
        let continuation = lock.withLock { self.continuation }
        continuation?.yield(report)
    }
}

private final class PadDelegate: HIDVirtualDeviceDelegate, @unchecked Sendable {
    private let onOutput: ([UInt8]) -> Void

    init(onOutput: @escaping ([UInt8]) -> Void) {
        self.onOutput = onOutput
    }

    func hidVirtualDevice(
        _ device: HIDVirtualDevice,
        receivedSetReportRequestOfType type: HIDReportType,
        id: HIDReportID?,
        data: Data
    ) throws {
        onOutput([UInt8](data))
    }

    func hidVirtualDevice(
        _ device: HIDVirtualDevice,
        receivedGetReportRequestOfType type: HIDReportType,
        id: HIDReportID?,
        maxSize: Int
    ) throws -> Data {
        Data(repeating: 0, count: min(maxSize, VirtualPadReport.reportLength))
    }
}
