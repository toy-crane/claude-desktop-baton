import Foundation
import Testing
@testable import BatonCore

@Suite("Control socket", .serialized)
struct ControlChannelTests {
    /// Socket paths are limited to 104 bytes, so tests use short ones in /tmp.
    private func socketPath() -> URL {
        URL(fileURLWithPath: "/tmp/baton-\(UUID().uuidString.prefix(8)).sock")
    }

    private func waitUntil(_ condition: () -> Bool, seconds: Double = 3) async {
        let deadline = Date().addingTimeInterval(seconds)
        while !condition(), Date() < deadline { try? await Task.sleep(for: .milliseconds(20)) }
    }

    @Test func aRefusalComesBackToTheCaller() throws {
        let socket = socketPath()
        let server = try ControlServer(socket: socket) { _, reply in reply.send(.refused(.sessionsWorking)) }
        defer { server.stop() }

        let response = try ControlClient.send(ControlRequest(accountId: "b"), socket: socket, wait: true, timeout: 5)

        #expect(response == .refused(.sessionsWorking))
        #expect(ControlClient.isListening(socket))
    }

    @Test func aWaitingCallerGetsTheOutcome() throws {
        let socket = socketPath()
        let server = try ControlServer(socket: socket) { request, reply in
            reply.send(.accepted)
            DispatchQueue.global().asyncAfter(deadline: .now() + 0.1) { reply.send(.done(error: "no \(request.accountId)")) }
        }
        defer { server.stop() }

        let response = try ControlClient.send(ControlRequest(accountId: "b"), socket: socket, wait: true, timeout: 5)

        #expect(response == .done(error: "no b"))
    }

    // AC6: the app finishes a switch whose caller went away, and keeps answering.
    @Test func aSwitchFinishesWhenTheCallerGoesAway() async throws {
        let socket = socketPath()
        let finished = Locked(false)
        let server = try ControlServer(socket: socket) { _, reply in
            reply.send(.accepted)
            DispatchQueue.global().asyncAfter(deadline: .now() + 0.2) {
                reply.send(.done(error: nil))
                finished.set(true)
            }
        }
        defer { server.stop() }

        let first = try ControlClient.send(ControlRequest(accountId: "b"), socket: socket, wait: false, timeout: 5)
        await waitUntil { finished.get() }
        let second = try ControlClient.send(ControlRequest(accountId: "c"), socket: socket, wait: false, timeout: 5)

        #expect(first == .accepted)
        #expect(finished.get())
        #expect(second == .accepted)
    }

    // Bug: a second menu bar app took over the socket, leaving the first one unreachable.
    @Test func aSecondServerDoesNotTakeOverASocketInUse() throws {
        let socket = socketPath()
        let first = try ControlServer(socket: socket) { _, reply in reply.send(.refused(.switching)) }
        defer { first.stop() }

        let second = try? ControlServer(socket: socket) { _, reply in reply.send(.refused(.unknownAccount)) }
        second?.stop()
        let response = try ControlClient.send(ControlRequest(accountId: "b"), socket: socket, wait: true, timeout: 5)

        #expect(second == nil)
        #expect(response == .refused(.switching))
    }

    @Test func nobodyListeningIsUnreachable() {
        let socket = socketPath()

        #expect(!ControlClient.isListening(socket))
        #expect(throws: ControlError.unreachable) {
            try ControlClient.send(ControlRequest(accountId: "b"), socket: socket, wait: true, timeout: 1)
        }
    }

    @Test func requestsArriveIntact() async throws {
        let socket = socketPath()
        let received = Locked<ControlRequest?>(nil)
        let server = try ControlServer(socket: socket) { request, reply in
            received.set(request)
            reply.send(.refused(.switching))
        }
        defer { server.stop() }
        let request = ControlRequest(accountId: "bbbbbbbb-0000-4000-8000-000000000002", force: true, insideDesktop: true)

        _ = try ControlClient.send(request, socket: socket, wait: true, timeout: 5)

        #expect(received.get() == request)
    }
}

final class Locked<Value>: @unchecked Sendable {
    private var value: Value
    private let lock = NSLock()
    init(_ value: Value) { self.value = value }
    func get() -> Value { lock.lock(); defer { lock.unlock() }; return value }
    func set(_ new: Value) { lock.lock(); value = new; lock.unlock() }
}
