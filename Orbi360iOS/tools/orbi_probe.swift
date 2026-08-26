#!/usr/bin/env swift
import Foundation
import Network

let host = "192.168.2.1"
let port: UInt16 = 8080
let delimiter = "\r\n\r\n"

struct Command: Encodable {
    let id: Int
    let cmd: String
    let mode_short: Bool?

    init(id: Int, cmd: String, modeShort: Bool? = nil) {
        self.id = id
        self.cmd = cmd
        self.mode_short = modeShort
    }
}

func waitReady(_ connection: NWConnection, timeout: TimeInterval = 8) async throws {
    let lock = NSLock()
    var didResume = false

    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
        func resumeOnce(_ result: Result<Void, Error>) {
            lock.lock()
            defer { lock.unlock() }
            guard !didResume else { return }
            didResume = true
            connection.stateUpdateHandler = nil
            switch result {
            case .success:
                continuation.resume()
            case .failure(let error):
                continuation.resume(throwing: error)
            }
        }

        Task {
            try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
            connection.cancel()
            resumeOnce(.failure(NSError(domain: "orbi_probe", code: 2, userInfo: [NSLocalizedDescriptionKey: "Timed out connecting to ORBI"])))
        }

        connection.stateUpdateHandler = { state in
            switch state {
            case .ready:
                resumeOnce(.success(()))
            case .failed(let error):
                resumeOnce(.failure(error))
            case .cancelled:
                resumeOnce(.failure(NSError(domain: "orbi_probe", code: 1, userInfo: [NSLocalizedDescriptionKey: "Connection cancelled"])))
            default:
                break
            }
        }
        connection.start(queue: .global(qos: .userInitiated))
    }
}

func send(_ connection: NWConnection, command: Command) async throws -> Data {
    let payload = try JSONEncoder().encode(command) + Data(delimiter.utf8)
    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
        connection.send(content: payload, completion: .contentProcessed { error in
            if let error {
                continuation.resume(throwing: error)
            } else {
                continuation.resume()
            }
        })
    }

    var buffer = Data()
    let marker = Data(delimiter.utf8)
    while true {
        let chunk = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Data, Error>) in
            connection.receive(minimumIncompleteLength: 1, maximumLength: 16_384) { data, _, isComplete, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let data, !data.isEmpty {
                    continuation.resume(returning: data)
                } else if isComplete {
                    continuation.resume(throwing: NSError(domain: "orbi_probe", code: 3, userInfo: [NSLocalizedDescriptionKey: "Connection closed"]))
                } else {
                    continuation.resume(returning: Data())
                }
            }
        }
        buffer.append(chunk)
        if let range = buffer.range(of: marker) {
            return buffer.subdata(in: buffer.startIndex..<range.lowerBound)
        }
    }
}

print("== ORBI probe ==")
print("Target: \(host):\(port)")

let endpoint = NWEndpoint.Host(host)
let nwPort = NWEndpoint.Port(integerLiteral: port)
let parameters = NWParameters.tcp
parameters.requiredInterfaceType = .wifi
parameters.prohibitedInterfaceTypes = [.cellular, .wiredEthernet]
let connection = NWConnection(host: endpoint, port: nwPort, using: parameters)
defer { connection.cancel() }

do {
    try await waitReady(connection)
    print("TCP: connected")

    let info = try await send(connection, command: Command(id: 1, cmd: "get_info"))
    print("get_info:")
    print(String(data: info, encoding: .utf8) ?? "<non-utf8 response>")

    let status = try await send(connection, command: Command(id: 2, cmd: "get-status", modeShort: true))
    print("get-status:")
    print(String(data: status, encoding: .utf8) ?? "<non-utf8 response>")

    let media = try await send(connection, command: Command(id: 3, cmd: "get_media_list"))
    print("get_media_list:")
    print(String(data: media, encoding: .utf8) ?? "<non-utf8 response>")
} catch {
    print("ERROR: \(error.localizedDescription)")
    exit(1)
}
