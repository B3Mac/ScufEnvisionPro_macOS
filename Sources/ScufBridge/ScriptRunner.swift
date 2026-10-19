import Foundation
import ScufCore

/// Runs shell commands bound to inputs. Output goes to ~/Library/Logs/ScufBridge/scripts.log.
enum ScriptRunner {
    static let logURL: URL = {
        let logs = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Logs/ScufBridge", isDirectory: true)
        try? FileManager.default.createDirectory(at: logs, withIntermediateDirectories: true)
        return logs.appendingPathComponent("scripts.log")
    }()

    static func run(_ command: String, input: ControllerButton, event: String, profile: String) {
        guard !command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let fd = open(logURL.path, O_WRONLY | O_APPEND | O_CREAT, 0o644)
        guard fd >= 0 else { return }
        let log = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        let header = "\n[\(Date())] \(input.rawValue) \(event) (profile: \(profile))\n$ \(command)\n"
        log.write(Data(header.utf8))

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-lc", command]
        var environment = ProcessInfo.processInfo.environment
        environment["SCUF_INPUT"] = input.rawValue
        environment["SCUF_EVENT"] = event
        environment["SCUF_PROFILE"] = profile
        process.environment = environment
        process.standardOutput = log
        process.standardError = log
        process.standardInput = FileHandle.nullDevice
        process.terminationHandler = { finished in
            log.write(Data("[exit \(finished.terminationStatus)]\n".utf8))
        }
        do {
            try process.run()
        } catch {
            log.write(Data("[failed to start: \(error.localizedDescription)]\n".utf8))
        }
    }

    /// Runs a command and returns its combined output (for the Test button). Times out after 10 s.
    static func capture(_ command: String, completion: @escaping (String) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/zsh")
            process.arguments = ["-lc", command]
            var environment = ProcessInfo.processInfo.environment
            environment["SCUF_INPUT"] = "test"
            environment["SCUF_EVENT"] = "press"
            environment["SCUF_PROFILE"] = "test"
            process.environment = environment
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe
            process.standardInput = FileHandle.nullDevice
            do {
                try process.run()
            } catch {
                completion("Failed to start: \(error.localizedDescription)")
                return
            }
            let timeout = DispatchWorkItem { if process.isRunning { process.terminate() } }
            DispatchQueue.global().asyncAfter(deadline: .now() + 10, execute: timeout)
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            timeout.cancel()
            let text = String(decoding: data, as: UTF8.self)
            completion((text.isEmpty ? "(no output)" : text) + "\n[exit \(process.terminationStatus)]")
        }
    }
}
