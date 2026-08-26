import XCTest
@testable import Orbi360iOS

final class NFSClientTests: XCTestCase {

    // MARK: - NFSClientError

    func testErrorDescriptions() {
        XCTAssertNotNil(NFSClientError.invalidURL("test").errorDescription)
        XCTAssertNotNil(NFSClientError.rpcDenied("test").errorDescription)
        XCTAssertNotNil(NFSClientError.mountFailed(path: "/test", status: 1).errorDescription)
        XCTAssertNotNil(NFSClientError.nfsFailed(operation: "READ", status: 1).errorDescription)
        XCTAssertNotNil(NFSClientError.connectionFailed("test").errorDescription)
        XCTAssertNotNil(NFSClientError.shortRead.errorDescription)

        XCTAssertTrue(NFSClientError.invalidURL("bad-url").errorDescription?.contains("bad-url") ?? false)
        XCTAssertTrue(NFSClientError.mountFailed(path: "/mount", status: 13).errorDescription?.contains("/mount") ?? false)
        XCTAssertTrue(NFSClientError.nfsFailed(operation: "LOOKUP", status: 2).errorDescription?.contains("LOOKUP") ?? false)
    }

    // MARK: - NFSRemotePath

    func testRemotePathParsing() throws {
        let path = try NFSRemotePath(urlString: "nfs://192.168.2.1/run/RTOS/DCIM/ORBI_0001", fallbackHost: "10.0.0.1")
        XCTAssertEqual(path.host, "192.168.2.1")
        XCTAssertEqual(path.path, "/run/RTOS/DCIM/ORBI_0001")
    }

    func testRemotePathFallbackHost() throws {
        let path = try NFSRemotePath(urlString: "nfs:///run/RTOS/DCIM/ORBI_0001", fallbackHost: "192.168.2.1")
        XCTAssertEqual(path.host, "192.168.2.1")
        XCTAssertEqual(path.path, "/run/RTOS/DCIM/ORBI_0001")
    }

    func testRemotePathInvalidScheme() {
        XCTAssertThrowsError(try NFSRemotePath(urlString: "http://192.168.2.1/path", fallbackHost: "")) { error in
            guard case NFSClientError.invalidURL = error else {
                XCTFail("Expected invalidURL error")
                return
            }
        }
    }

    func testRemotePathEmptyPath() {
        XCTAssertThrowsError(try NFSRemotePath(urlString: "nfs://192.168.2.1", fallbackHost: "")) { error in
            guard case NFSClientError.invalidURL = error else {
                XCTFail("Expected invalidURL error for empty path")
                return
            }
        }
    }

    // MARK: - Mount Candidates

    func testMountCandidatesDeepPath() {
        let candidates = NFSRemotePath.mountCandidates(for: "/run/RTOS/DCIM/ORBI_0001")
        XCTAssertFalse(candidates.isEmpty)
        // Should try different mount depths
        let mountPoints = candidates.map { $0.mountPoint }
        XCTAssertTrue(mountPoints.contains("/"))
    }

    func testMountCandidatesRootPath() {
        let candidates = NFSRemotePath.mountCandidates(for: "/")
        XCTAssertEqual(candidates.count, 1)
        XCTAssertEqual(candidates.first?.mountPoint, "/")
        XCTAssertTrue(candidates.first?.remainingComponents.isEmpty ?? false)
    }

    func testMountCandidatesShortPath() {
        let candidates = NFSRemotePath.mountCandidates(for: "/DCIM")
        XCTAssertFalse(candidates.isEmpty)
        // Should include root mount with DCIM as remaining
        let rootCandidate = candidates.first { $0.mountPoint == "/" }
        XCTAssertNotNil(rootCandidate)
        XCTAssertEqual(rootCandidate?.remainingComponents, ["DCIM"])
    }

    func testMountCandidatesNoDuplicates() {
        let candidates = NFSRemotePath.mountCandidates(for: "/run/RTOS/DCIM")
        let mountPoints = candidates.map { $0.mountPoint }
        XCTAssertEqual(Set(mountPoints).count, mountPoints.count, "Mount candidates should not have duplicates")
    }

    // MARK: - XDRWriter

    func testXDRWriterUInt32() {
        var writer = XDRWriter()
        writer.write(UInt32(0x12345678))
        let bytes = [UInt8](writer.data)
        XCTAssertEqual(bytes, [0x12, 0x34, 0x56, 0x78])
    }

    func testXDRWriterUInt64() {
        var writer = XDRWriter()
        writer.write(UInt64(0x123456789ABCDEF0))
        let bytes = [UInt8](writer.data)
        XCTAssertEqual(bytes, [0x12, 0x34, 0x56, 0x78, 0x9A, 0xBC, 0xDE, 0xF0])
    }

    func testXDRWriterString() {
        var writer = XDRWriter()
        writer.writeString("test")
        // Length (4) + "test" (4 bytes) = 8 bytes, no padding needed
        XCTAssertEqual(writer.data.count, 8)
        // First 4 bytes: length = 4
        let reader = XDRReader(data: writer.data)
        let result = try? reader.readString()
        XCTAssertEqual(result, "test")
    }

    func testXDRWriterStringPadding() {
        var writer = XDRWriter()
        writer.writeString("abc") // 3 bytes -> padded to 4
        // Length (4) + "abc" (3) + padding (1) = 8
        XCTAssertEqual(writer.data.count, 8)
    }

    func testXDRWriterOpaque() {
        var writer = XDRWriter()
        let data = Data([0x01, 0x02, 0x03, 0x04, 0x05])
        writer.writeOpaque(data)
        // Length (4) + data (5) + padding (3) = 12
        XCTAssertEqual(writer.data.count, 12)
    }

    func testXDRWriterAuthNull() {
        var writer = XDRWriter()
        writer.writeAuthNull()
        // Two zero uint32s = 8 bytes
        XCTAssertEqual(writer.data.count, 8)
    }

    func testXDRWriterAuthUnix() {
        var writer = XDRWriter()
        writer.writeAuthUnix()
        // flavor(4) + length(4) + body (stamp(4) + hostname "ios"(4+3+1pad) + uid(4) + gid(4) + gids_count(4))
        // = 4 + 4 + (4 + 8 + 4 + 4 + 4) = 32
        XCTAssertGreaterThan(writer.data.count, 20)
    }

    func testXDRWriterAppend() {
        var writer = XDRWriter()
        let extra = Data([0xAA, 0xBB])
        writer.append(extra)
        XCTAssertEqual(writer.data, extra)
    }

    // MARK: - XDRReader

    func testXDRReaderUInt32() throws {
        var writer = XDRWriter()
        writer.write(UInt32(0xDEADBEEF))
        let reader = XDRReader(data: writer.data)
        XCTAssertEqual(try reader.readUInt32(), 0xDEADBEEF)
    }

    func testXDRReaderUInt64() throws {
        var writer = XDRWriter()
        writer.write(UInt64(0x1234567890ABCDEF))
        let reader = XDRReader(data: writer.data)
        XCTAssertEqual(try reader.readUInt64(), 0x1234567890ABCDEF)
    }

    func testXDRReaderBool() throws {
        var writer = XDRWriter()
        writer.write(UInt32(1))
        let reader = XDRReader(data: writer.data)
        XCTAssertTrue(try reader.readBool())

        var writer2 = XDRWriter()
        writer2.write(UInt32(0))
        let reader2 = XDRReader(data: writer2.data)
        XCTAssertFalse(try reader2.readBool())
    }

    func testXDRReaderString() throws {
        var writer = XDRWriter()
        writer.writeString("Hello")
        let reader = XDRReader(data: writer.data)
        XCTAssertEqual(try reader.readString(), "Hello")
    }

    func testXDRReaderOpaque() throws {
        var writer = XDRWriter()
        let original = Data([0x01, 0x02, 0x03, 0x04])
        writer.writeOpaque(original)
        let reader = XDRReader(data: writer.data)
        let result = try reader.readOpaque()
        XCTAssertEqual(result, original)
    }

    func testXDRReaderMultipleValues() throws {
        var writer = XDRWriter()
        writer.write(UInt32(42))
        writer.writeString("test")
        writer.write(UInt64(999))
        writer.writeOpaque(Data([0xAA, 0xBB, 0xCC]))

        let reader = XDRReader(data: writer.data)
        XCTAssertEqual(try reader.readUInt32(), 42)
        XCTAssertEqual(try reader.readString(), "test")
        XCTAssertEqual(try reader.readUInt64(), 999)
        XCTAssertEqual(try reader.readOpaque(), Data([0xAA, 0xBB, 0xCC]))
    }

    func testXDRReaderShortRead() {
        let reader = XDRReader(data: Data([0x01, 0x02])) // Too short for UInt32
        XCTAssertThrowsError(try reader.readUInt32()) { error in
            guard case NFSClientError.shortRead = error else {
                XCTFail("Expected shortRead error")
                return
            }
        }
    }

    func testXDRReaderOptionalOpaque() throws {
        var writer = XDRWriter()
        writer.write(UInt32(1)) // present = true
        writer.writeOpaque(Data([0x01, 0x02]))

        let reader = XDRReader(data: writer.data)
        let result = try reader.readOptionalOpaque()
        XCTAssertNotNil(result)
        XCTAssertEqual(result, Data([0x01, 0x02]))
    }

    func testXDRReaderOptionalOpaqueNil() throws {
        var writer = XDRWriter()
        writer.write(UInt32(0)) // present = false

        let reader = XDRReader(data: writer.data)
        let result = try reader.readOptionalOpaque()
        XCTAssertNil(result)
    }

    // MARK: - Round Trip Tests

    func testRoundTripMultipleStrings() throws {
        var writer = XDRWriter()
        let strings = ["short", "medium_length", "x"]
        for s in strings {
            writer.writeString(s)
        }

        let reader = XDRReader(data: writer.data)
        for s in strings {
            XCTAssertEqual(try reader.readString(), s)
        }
    }

    func testRoundTripAuthUnix() throws {
        var writer = XDRWriter()
        writer.writeAuthUnix()

        // AuthUnix: flavor(4) + body_length(4) + body
        let reader = XDRReader(data: writer.data)
        let flavor = try reader.readUInt32() // should be 1 (AUTH_UNIX)
        XCTAssertEqual(flavor, 1)
        let body = try reader.readOpaque()
        XCTAssertFalse(body.isEmpty)
    }

    // MARK: - Static uint32/uint64 helpers

    func testStaticUInt32FromBytes() {
        let data = Data([0x12, 0x34, 0x56, 0x78])
        XCTAssertEqual(XDRReader.uint32(from: data), 0x12345678)
    }

    func testStaticUInt64FromBytes() {
        let data = Data([0x01, 0x23, 0x45, 0x67, 0x89, 0xAB, 0xCD, 0xEF])
        XCTAssertEqual(XDRReader.uint64(from: data), 0x0123456789ABCDEF)
    }

    // MARK: - NFSClient Init

    func testNFSClientInit() {
        let client = NFSClient(host: "192.168.1.100")
        XCTAssertNotNil(client)
    }

    func testNFSClientDefaultInit() {
        let client = NFSClient()
        XCTAssertNotNil(client)
    }
}
