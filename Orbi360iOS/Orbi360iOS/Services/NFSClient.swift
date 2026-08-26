import Darwin
import Foundation

enum NFSClientError: LocalizedError {
    case invalidURL(String)
    case rpcDenied(String)
    case mountFailed(path: String, status: UInt32)
    case nfsFailed(operation: String, status: UInt32)
    case connectionFailed(String)
    case shortRead

    var errorDescription: String? {
        switch self {
        case .invalidURL(let value):
            return "Invalid NFS URL: \(value)"
        case .rpcDenied(let reason):
            return "RPC denied: \(reason)"
        case .mountFailed(let path, let status):
            return "NFS mount failed for \(path), status \(status)."
        case .nfsFailed(let operation, let status):
            return "NFS \(operation) failed, status \(status)."
        case .connectionFailed(let reason):
            return "NFS connection failed: \(reason)"
        case .shortRead:
            return "NFS connection closed before the reply completed."
        }
    }
}

final class NFSClient {
    private let host: String
    private var xid: UInt32 = UInt32.random(in: 1...UInt32.max)

    init(host: String = OrbiProtocol.deviceIP) {
        self.host = host
    }

    func download(urlString: String, to localURL: URL) throws -> Int64 {
        let remote = try NFSRemotePath(urlString: urlString, fallbackHost: host)
        let session = NFSSession(host: remote.host)
        defer { session.close() }

        let mountPort = try getPort(session: session, program: 100005, version: 3)
        let nfsPort = try getPort(session: session, program: 100003, version: 3)
        let mounted = try mount(session: session, port: mountPort, remotePath: remote.path)
        let fileHandle = try lookupPath(session: session, port: nfsPort, root: mounted.handle, components: mounted.remainingComponents)

        try FileManager.default.createDirectory(at: localURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: localURL.path, contents: nil)
        let output = try FileHandle(forWritingTo: localURL)
        defer { try? output.close() }

        var offset: UInt64 = 0
        var bytesWritten: Int64 = 0
        while true {
            let chunk = try read(session: session, port: nfsPort, handle: fileHandle, offset: offset, count: 32_768)
            if !chunk.data.isEmpty {
                try output.write(contentsOf: chunk.data)
                offset += UInt64(chunk.data.count)
                bytesWritten += Int64(chunk.data.count)
            }
            if chunk.eof || chunk.data.isEmpty {
                break
            }
        }
        return bytesWritten
    }

    func downloadDirectory(urlString: String, to localDirectoryURL: URL) throws -> Int64 {
        let remote = try NFSRemotePath(urlString: urlString, fallbackHost: host)
        let session = NFSSession(host: remote.host)
        defer { session.close() }

        let mountPort = try getPort(session: session, program: 100005, version: 3)
        let nfsPort = try getPort(session: session, program: 100003, version: 3)
        let mounted = try mount(session: session, port: mountPort, remotePath: remote.path)
        let directoryHandle = try lookupPath(session: session, port: nfsPort, root: mounted.handle, components: mounted.remainingComponents)
        try FileManager.default.createDirectory(at: localDirectoryURL, withIntermediateDirectories: true)

        let entries = try readdirplus(session: session, port: nfsPort, directory: directoryHandle)
        var total: Int64 = 0
        for entry in entries where entry.name != "." && entry.name != ".." {
            let destination = localDirectoryURL.appendingPathComponent(entry.name)
            if entry.type == 2 {
                total += try downloadFile(session: session, port: nfsPort, handle: entry.handle, to: destination)
            }
        }
        return total
    }

    func fileSize(urlString: String) throws -> UInt64 {
        let remote = try NFSRemotePath(urlString: urlString, fallbackHost: host)
        let session = NFSSession(host: remote.host)
        defer { session.close() }

        let mountPort = try getPort(session: session, program: 100005, version: 3)
        let nfsPort = try getPort(session: session, program: 100003, version: 3)
        let mounted = try mount(session: session, port: mountPort, remotePath: remote.path)
        let fileHandle = try lookupPath(session: session, port: nfsPort, root: mounted.handle, components: mounted.remainingComponents)
        return try getattr(session: session, port: nfsPort, handle: fileHandle).size
    }

    func remove(urlString: String) throws {
        let remote = try NFSRemotePath(urlString: urlString, fallbackHost: host)
        let session = NFSSession(host: remote.host)
        defer { session.close() }

        let mountPort = try getPort(session: session, program: 100005, version: 3)
        let nfsPort = try getPort(session: session, program: 100003, version: 3)
        let mounted = try mount(session: session, port: mountPort, remotePath: remote.path)
        guard let fileName = mounted.remainingComponents.last else {
            throw NFSClientError.invalidURL(urlString)
        }
        let parentComponents = Array(mounted.remainingComponents.dropLast())
        let parentHandle = try lookupPath(session: session, port: nfsPort, root: mounted.handle, components: parentComponents)
        try remove(session: session, port: nfsPort, directory: parentHandle, name: fileName)
    }

    func removeDirectory(urlString: String) throws {
        let remote = try NFSRemotePath(urlString: urlString, fallbackHost: host)
        let session = NFSSession(host: remote.host)
        defer { session.close() }

        let mountPort = try getPort(session: session, program: 100005, version: 3)
        let nfsPort = try getPort(session: session, program: 100003, version: 3)
        let mounted = try mount(session: session, port: mountPort, remotePath: remote.path)
        guard let directoryName = mounted.remainingComponents.last else {
            throw NFSClientError.invalidURL(urlString)
        }
        let parentComponents = Array(mounted.remainingComponents.dropLast())
        let parentHandle = try lookupPath(session: session, port: nfsPort, root: mounted.handle, components: parentComponents)
        let directoryHandle = try lookup(session: session, port: nfsPort, directory: parentHandle, name: directoryName)
        try removeDirectoryContents(session: session, port: nfsPort, directory: directoryHandle)
        try rmdir(session: session, port: nfsPort, directory: parentHandle, name: directoryName)
    }

    private func getPort(session: NFSSession, program: UInt32, version: UInt32) throws -> UInt32 {
        var body = XDRWriter()
        body.write(program)
        body.write(version)
        body.write(UInt32(IPPROTO_TCP))
        body.write(UInt32(0))
        let reply = try rpc(session: session, port: 111, program: 100000, version: 2, procedure: 3, body: body.data, authUnix: false)
        let port = try reply.readUInt32()
        guard port != 0 else {
            throw NFSClientError.connectionFailed("RPC program \(program) version \(version) is not available.")
        }
        return port
    }

    private func mount(session: NFSSession, port: UInt32, remotePath: String) throws -> (handle: Data, remainingComponents: [String]) {
        var lastError: Error?
        for candidate in NFSRemotePath.mountCandidates(for: remotePath) {
            do {
                var body = XDRWriter()
                body.writeString(candidate.mountPoint)
                let reply = try rpc(session: session, port: port, program: 100005, version: 3, procedure: 1, body: body.data, authUnix: true)
                let status = try reply.readUInt32()
                guard status == 0 else {
                    throw NFSClientError.mountFailed(path: candidate.mountPoint, status: status)
                }
                let handle = try reply.readOpaque()
                return (handle, candidate.remainingComponents)
            } catch {
                lastError = error
            }
        }
        throw lastError ?? NFSClientError.mountFailed(path: remotePath, status: UInt32.max)
    }

    private func lookupPath(session: NFSSession, port: UInt32, root: Data, components: [String]) throws -> Data {
        var handle = root
        for component in components where !component.isEmpty {
            handle = try lookup(session: session, port: port, directory: handle, name: component)
        }
        return handle
    }

    private func lookup(session: NFSSession, port: UInt32, directory: Data, name: String) throws -> Data {
        var body = XDRWriter()
        body.writeOpaque(directory)
        body.writeString(name)
        let reply = try rpc(session: session, port: port, program: 100003, version: 3, procedure: 3, body: body.data, authUnix: true)
        let status = try reply.readUInt32()
        guard status == 0 else {
            throw NFSClientError.nfsFailed(operation: "LOOKUP \(name)", status: status)
        }
        let handle = try reply.readOpaque()
        try reply.skipPostOpAttr()
        try reply.skipPostOpAttr()
        return handle
    }

    private func getattr(session: NFSSession, port: UInt32, handle: Data) throws -> NFSAttributes {
        var body = XDRWriter()
        body.writeOpaque(handle)
        let reply = try rpc(session: session, port: port, program: 100003, version: 3, procedure: 1, body: body.data, authUnix: true)
        let status = try reply.readUInt32()
        guard status == 0 else {
            throw NFSClientError.nfsFailed(operation: "GETATTR", status: status)
        }
        return try reply.readFattr3()
    }

    private func read(session: NFSSession, port: UInt32, handle: Data, offset: UInt64, count: UInt32) throws -> (data: Data, eof: Bool) {
        var body = XDRWriter()
        body.writeOpaque(handle)
        body.write(offset)
        body.write(count)
        let reply = try rpc(session: session, port: port, program: 100003, version: 3, procedure: 6, body: body.data, authUnix: true)
        let status = try reply.readUInt32()
        guard status == 0 else {
            throw NFSClientError.nfsFailed(operation: "READ", status: status)
        }
        try reply.skipPostOpAttr()
        _ = try reply.readUInt32()
        let eof = try reply.readBool()
        let data = try reply.readOpaque()
        return (data, eof)
    }

    private func readdirplus(session: NFSSession, port: UInt32, directory: Data) throws -> [NFSEntry] {
        var cookie: UInt64 = 0
        var cookieVerifier: UInt64 = 0
        var entries: [NFSEntry] = []
        var eof = false
        while !eof {
            var body = XDRWriter()
            body.writeOpaque(directory)
            body.write(cookie)
            body.write(cookieVerifier)
            body.write(UInt32(8_192))
            body.write(UInt32(32_768))
            let reply = try rpc(session: session, port: port, program: 100003, version: 3, procedure: 17, body: body.data, authUnix: true)
            let status = try reply.readUInt32()
            guard status == 0 else {
                throw NFSClientError.nfsFailed(operation: "READDIRPLUS", status: status)
            }
            try reply.skipPostOpAttr()
            cookieVerifier = try reply.readUInt64()
            while try reply.readBool() {
                _ = try reply.readUInt64()
                let name = try reply.readString()
                cookie = try reply.readUInt64()
                let attributes = try reply.readOptionalFattr3()
                let handle = try reply.readOptionalOpaque()
                if let attributes, let handle {
                    entries.append(NFSEntry(name: name, type: attributes.type, handle: handle))
                }
            }
            eof = try reply.readBool()
        }
        return entries
    }

    private func downloadFile(session: NFSSession, port: UInt32, handle: Data, to localURL: URL) throws -> Int64 {
        try FileManager.default.createDirectory(at: localURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: localURL.path, contents: nil)
        let output = try FileHandle(forWritingTo: localURL)
        defer { try? output.close() }

        var offset: UInt64 = 0
        var bytesWritten: Int64 = 0
        while true {
            let chunk = try read(session: session, port: port, handle: handle, offset: offset, count: 32_768)
            if !chunk.data.isEmpty {
                try output.write(contentsOf: chunk.data)
                offset += UInt64(chunk.data.count)
                bytesWritten += Int64(chunk.data.count)
            }
            if chunk.eof || chunk.data.isEmpty {
                break
            }
        }
        return bytesWritten
    }

    private func remove(session: NFSSession, port: UInt32, directory: Data, name: String) throws {
        var body = XDRWriter()
        body.writeOpaque(directory)
        body.writeString(name)
        let reply = try rpc(session: session, port: port, program: 100003, version: 3, procedure: 12, body: body.data, authUnix: true)
        let status = try reply.readUInt32()
        guard status == 0 else {
            throw NFSClientError.nfsFailed(operation: "REMOVE \(name)", status: status)
        }
    }

    private func removeDirectoryContents(session: NFSSession, port: UInt32, directory: Data) throws {
        let entries = try readdirplus(session: session, port: port, directory: directory)
        for entry in entries where entry.name != "." && entry.name != ".." {
            if entry.type == 2 {
                try remove(session: session, port: port, directory: directory, name: entry.name)
            } else if entry.type == 1 {
                try removeDirectoryContents(session: session, port: port, directory: entry.handle)
                try rmdir(session: session, port: port, directory: directory, name: entry.name)
            }
        }
    }

    private func rmdir(session: NFSSession, port: UInt32, directory: Data, name: String) throws {
        var body = XDRWriter()
        body.writeOpaque(directory)
        body.writeString(name)
        let reply = try rpc(session: session, port: port, program: 100003, version: 3, procedure: 13, body: body.data, authUnix: true)
        let status = try reply.readUInt32()
        guard status == 0 else {
            throw NFSClientError.nfsFailed(operation: "RMDIR \(name)", status: status)
        }
    }

    private func rpc(session: NFSSession, port: UInt32, program: UInt32, version: UInt32, procedure: UInt32, body: Data, authUnix: Bool) throws -> XDRReader {
        xid &+= 1
        try session.connect(port: UInt16(port))

        var call = XDRWriter()
        call.write(xid)
        call.write(UInt32(0))
        call.write(UInt32(2))
        call.write(program)
        call.write(version)
        call.write(procedure)
        if authUnix {
            call.writeAuthUnix()
        } else {
            call.writeAuthNull()
        }
        call.writeAuthNull()
        call.append(body)

        var framed = XDRWriter()
        framed.write(UInt32(0x8000_0000 | UInt32(call.data.count)))
        framed.append(call.data)
        try session.writeAll(framed.data)

        let replyData = try session.readRecord()
        let reply = XDRReader(data: replyData)
        let replyXid = try reply.readUInt32()
        guard replyXid == xid else {
            throw NFSClientError.rpcDenied("Unexpected XID \(replyXid), expected \(xid).")
        }
        guard try reply.readUInt32() == 1 else {
            throw NFSClientError.rpcDenied("Not an RPC reply.")
        }
        guard try reply.readUInt32() == 0 else {
            throw NFSClientError.rpcDenied("RPC message was denied.")
        }
        try reply.skipAuth()
        guard try reply.readUInt32() == 0 else {
            throw NFSClientError.rpcDenied("RPC call was not accepted.")
        }
        return reply
    }
}

struct NFSRemotePath {
    let host: String
    let path: String

    init(urlString: String, fallbackHost: String) throws {
        guard let url = URL(string: urlString), url.scheme == "nfs" else {
            throw NFSClientError.invalidURL(urlString)
        }
        host = url.host ?? fallbackHost
        path = url.path
        guard !path.isEmpty else {
            throw NFSClientError.invalidURL(urlString)
        }
    }

    static func mountCandidates(for path: String) -> [(mountPoint: String, remainingComponents: [String])] {
        let components = path.split(separator: "/").map(String.init)
        guard !components.isEmpty else { return [("/", [])] }
        var result: [(String, [String])] = []
        let preferredDepths = [min(3, components.count - 1), min(2, components.count - 1), 0]
        for depth in preferredDepths where depth >= 0 {
            let mountPoint = depth == 0 ? "/" : "/" + components.prefix(depth).joined(separator: "/")
            let remaining = Array(components.dropFirst(depth))
            if !result.contains(where: { $0.0 == mountPoint }) {
                result.append((mountPoint, remaining))
            }
        }
        return result
    }
}

private final class NFSSession {
    private let host: String
    private let interfaceName: String?
    private var fd: Int32 = -1
    private var connectedPort: UInt16?

    init(host: String, interfaceName: String? = OrbiProtocol.wifiInterfaceName) {
        self.host = host
        self.interfaceName = interfaceName
    }

    func connect(port: UInt16) throws {
        if connectedPort == port, fd >= 0 { return }
        close()
        fd = socket(AF_INET, SOCK_STREAM, IPPROTO_TCP)
        guard fd >= 0 else {
            throw NFSClientError.connectionFailed(String(cString: strerror(errno)))
        }
        try bindToPreferredInterfaceIfNeeded()

        var timeout = timeval(tv_sec: 15, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))

        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = port.bigEndian
        guard inet_pton(AF_INET, host, &address.sin_addr) == 1 else {
            throw NFSClientError.connectionFailed("Invalid host \(host).")
        }

        let connected = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard connected == 0 else {
            let reason = String(cString: strerror(errno))
            close()
            throw NFSClientError.connectionFailed("\(host):\(port) \(reason)")
        }
        connectedPort = port
    }

    private func bindToPreferredInterfaceIfNeeded() throws {
        guard let interfaceName, !interfaceName.isEmpty else { return }
        let index = if_nametoindex(interfaceName)
        guard index != 0 else { return }
        var boundInterface = UInt32(index)
        let status = setsockopt(
            fd,
            IPPROTO_IP,
            IP_BOUND_IF,
            &boundInterface,
            socklen_t(MemoryLayout<UInt32>.size)
        )
        guard status == 0 else {
            throw NFSClientError.connectionFailed("Could not bind socket to \(interfaceName): \(String(cString: strerror(errno)))")
        }
    }

    func close() {
        if fd >= 0 {
            Darwin.close(fd)
            fd = -1
        }
        connectedPort = nil
    }

    func writeAll(_ data: Data) throws {
        var offset = 0
        while offset < data.count {
            let written = data.withUnsafeBytes { bytes -> Int in
                guard let base = bytes.baseAddress else { return -1 }
                return Darwin.write(fd, base.advanced(by: offset), data.count - offset)
            }
            guard written > 0 else {
                throw NFSClientError.connectionFailed(String(cString: strerror(errno)))
            }
            offset += written
        }
    }

    func readRecord() throws -> Data {
        var payload = Data()
        var isLast = false
        while !isLast {
            let header = XDRReader.uint32(from: try readExact(count: 4))
            isLast = (header & 0x8000_0000) != 0
            let length = Int(header & 0x7fff_ffff)
            payload.append(try readExact(count: length))
        }
        return payload
    }

    private func readExact(count: Int) throws -> Data {
        var data = Data(count: count)
        var offset = 0
        while offset < count {
            let readCount = data.withUnsafeMutableBytes { bytes -> Int in
                guard let base = bytes.baseAddress else { return -1 }
                return Darwin.read(fd, base.advanced(by: offset), count - offset)
            }
            guard readCount > 0 else {
                if readCount == 0 { throw NFSClientError.shortRead }
                throw NFSClientError.connectionFailed(String(cString: strerror(errno)))
            }
            offset += readCount
        }
        return data
    }
}

private struct NFSEntry {
    let name: String
    let type: UInt32
    let handle: Data
}

private struct NFSAttributes {
    let type: UInt32
    let size: UInt64
}

struct XDRWriter {
    private(set) var data = Data()

    mutating func append(_ value: Data) {
        data.append(value)
    }

    mutating func write(_ value: UInt32) {
        var big = value.bigEndian
        data.append(Data(bytes: &big, count: MemoryLayout<UInt32>.size))
    }

    mutating func write(_ value: UInt64) {
        var big = value.bigEndian
        data.append(Data(bytes: &big, count: MemoryLayout<UInt64>.size))
    }

    mutating func writeString(_ value: String) {
        writeOpaque(Data(value.utf8))
    }

    mutating func writeOpaque(_ value: Data) {
        write(UInt32(value.count))
        data.append(value)
        pad(to: 4)
    }

    mutating func writeAuthNull() {
        write(UInt32(0))
        write(UInt32(0))
    }

    mutating func writeAuthUnix() {
        var auth = XDRWriter()
        auth.write(UInt32(0))
        auth.writeString("ios")
        auth.write(UInt32(0))
        auth.write(UInt32(0))
        auth.write(UInt32(0))
        write(UInt32(1))
        write(UInt32(auth.data.count))
        append(auth.data)
    }

    private mutating func pad(to boundary: Int) {
        let remainder = data.count % boundary
        guard remainder != 0 else { return }
        data.append(contentsOf: repeatElement(0, count: boundary - remainder))
    }
}

final class XDRReader {
    private let data: Data
    private var offset = 0

    init(data: Data) {
        self.data = data
    }

    func readUInt32() throws -> UInt32 {
        guard offset + 4 <= data.count else { throw NFSClientError.shortRead }
        let value = Self.uint32(from: data[offset..<offset + 4])
        offset += 4
        return value
    }

    func readUInt64() throws -> UInt64 {
        guard offset + 8 <= data.count else { throw NFSClientError.shortRead }
        let value = Self.uint64(from: data[offset..<offset + 8])
        offset += 8
        return value
    }

    func readBool() throws -> Bool {
        try readUInt32() != 0
    }

    func readOpaque() throws -> Data {
        let count = Int(try readUInt32())
        guard offset + count <= data.count else { throw NFSClientError.shortRead }
        let value = data[offset..<offset + count]
        offset += count
        skipPadding(for: count)
        return Data(value)
    }

    func readString() throws -> String {
        let data = try readOpaque()
        return String(data: data, encoding: .utf8) ?? ""
    }

    func skipAuth() throws {
        _ = try readUInt32()
        _ = try readOpaque()
    }

    func skipPostOpAttr() throws {
        _ = try readOptionalFattr3()
    }

    fileprivate func readOptionalFattr3() throws -> NFSAttributes? {
        guard try readBool() else { return nil }
        return try readFattr3()
    }

    func readOptionalOpaque() throws -> Data? {
        guard try readBool() else { return nil }
        return try readOpaque()
    }

    fileprivate func readFattr3() throws -> NFSAttributes {
        let type = try readUInt32()
        _ = try readUInt32()
        _ = try readUInt32()
        _ = try readUInt32()
        _ = try readUInt32()
        let size = try readUInt64()
        _ = try readUInt64()
        _ = try readUInt32()
        _ = try readUInt32()
        _ = try readUInt64()
        _ = try readUInt64()
        _ = try readUInt32()
        _ = try readUInt32()
        _ = try readUInt32()
        _ = try readUInt32()
        _ = try readUInt32()
        _ = try readUInt32()
        return NFSAttributes(type: type, size: size)
    }

    private func skipPadding(for count: Int) {
        let remainder = count % 4
        if remainder != 0 {
            offset += 4 - remainder
        }
    }

    static func uint32<D: DataProtocol>(from bytes: D) -> UInt32 {
        var value: UInt32 = 0
        for byte in bytes.prefix(4) {
            value = (value << 8) | UInt32(byte)
        }
        return value
    }

    static func uint64<D: DataProtocol>(from bytes: D) -> UInt64 {
        var value: UInt64 = 0
        for byte in bytes.prefix(8) {
            value = (value << 8) | UInt64(byte)
        }
        return value
    }
}
