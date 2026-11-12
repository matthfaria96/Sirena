// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Darwin
import Foundation

private final class BoundedProcessOutput: @unchecked Sendable {
    private let lock = NSLock()
    private let limit: Int
    private var data = Data()

    init(limit: Int) {
        self.limit = max(0, limit)
    }

    func append(_ chunk: Data) {
        lock.lock()
        defer { lock.unlock() }
        let available = max(0, limit - data.count)
        if available > 0 { data.append(chunk.prefix(available)) }
    }

    func value() -> Data {
        lock.lock()
        defer { lock.unlock() }
        return data
    }
}

/// Cancellation owns one process launch; the lock closes the gap between
/// cancelling a queued request and that request launching its child.
final class IslandBoundedProcessCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false
    private var process: Process?

    var isCancelled: Bool { lock.lock(); defer { lock.unlock() }; return cancelled }

    func cancel() {
        lock.lock()
        guard !cancelled else { lock.unlock(); return }
        cancelled = true
        let child = process
        lock.unlock()
        guard let child, child.isRunning else { return }
        child.terminate()
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 0.5) {
            if child.isRunning { kill(child.processIdentifier, SIGKILL) }
        }
    }

    func launch(_ child: Process) throws {
        lock.lock()
        defer { lock.unlock() }
        guard !cancelled, process == nil else { throw CancellationError() }
        try child.run()
        process = child
    }

    func release(_ child: Process) {
        lock.lock()
        defer { lock.unlock() }
        if process === child { process = nil }
    }
}

/// What the bounded wait needs from a child, however it was started.
private struct BoundedChild {
    let pid: pid_t
    let terminate: () -> Void
    let status: () -> Int32
}

enum IslandBoundedProcessRunner {
    struct Result {
        let status: Int32
        let output: Data
        let timedOut: Bool
    }

    static func run(_ path: String,
                    _ arguments: [String],
                    timeout: TimeInterval,
                    maxOutputBytes: Int,
                    environment: [String: String]? = nil,
                    cancellation: IslandBoundedProcessCancellation? = nil) -> Result {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        process.environment = environment
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        defer { cancellation?.release(process) }
        return collect(from: pipe, timeout: timeout, maxOutputBytes: maxOutputBytes) { finished in
            // The child is watched through its termination handler. A blocking
            // `waitUntilExit()` has to be parked on a thread of its own, and the
            // timeout below makes `run` walk away from it while it still holds one
            // worker of the shared 64-thread pool. Those abandoned waits pile up
            // faster than they drain, and a full pool starves every later user of
            // it, the main thread's window walk included (issue #971). It also
            // starves this runner, which then reports timeouts for commands that
            // exited at once and abandons another wait doing it. A termination
            // handler occupies no thread, so none of that accumulates.
            process.terminationHandler = { _ in finished.signal() }
            if let cancellation { try cancellation.launch(process) }
            else { try process.run() }
            return BoundedChild(pid: process.processIdentifier,
                                terminate: { process.terminate() },
                                status: { process.terminationStatus })
        }
    }

    private static func collect(from pipe: Pipe,
                                timeout: TimeInterval,
                                maxOutputBytes: Int,
                                launch: (DispatchSemaphore) throws -> BoundedChild) -> Result {
        let output = BoundedProcessOutput(limit: maxOutputBytes)
        let drained = DispatchSemaphore(value: 0)
        let reader = pipe.fileHandleForReading
        reader.readabilityHandler = { handle in
            let chunk = handle.availableData
            if chunk.isEmpty {
                drained.signal()
            } else {
                // Keep draining after the retained prefix is full so the child
                // can never block on a full pipe or turn output into memory use.
                output.append(chunk)
            }
        }

        let finished = DispatchSemaphore(value: 0)
        let child: BoundedChild
        do {
            child = try launch(finished)
        } catch {
            reader.readabilityHandler = nil
            try? reader.close()
            return Result(status: -1, output: Data(), timedOut: false)
        }

        var didFinish = finished.wait(timeout: .now() + max(0, timeout)) == .success
        let timedOut = !didFinish
        if timedOut {
            child.terminate()
            didFinish = finished.wait(timeout: .now() + 0.5) == .success
            if !didFinish {
                kill(child.pid, SIGKILL)
                _ = finished.wait(timeout: .now() + 0.5)
            }
        }

        // A child may inherit stdout after the command itself exits. Give an
        // ordinary EOF a moment to deliver the tail, then close our descriptor
        // so that inherited handle cannot leave a reader alive indefinitely.
        _ = drained.wait(timeout: .now() + 0.2)
        reader.readabilityHandler = nil
        try? reader.close()

        return Result(status: timedOut ? -1 : child.status(),
                      output: output.value(),
                      timedOut: timedOut)
    }

}
