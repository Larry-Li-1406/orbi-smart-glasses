import XCTest
@testable import Orbi360iOS

final class OrbiRawBundleParserTests: XCTestCase {

    var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("OrbiRawBundleTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let tempDir {
            try? FileManager.default.removeItem(at: tempDir)
        }
    }

    // MARK: - Empty Directory

    func testParseEmptyDirectory() throws {
        let bundle = try OrbiRawBundleParser.parse(directory: tempDir, mediaName: "ORBI_0001")
        XCTAssertNil(bundle.configURL)
        XCTAssertNil(bundle.mediaUUID)
        XCTAssertTrue(bundle.sources.isEmpty)
        XCTAssertTrue(bundle.imuFiles.isEmpty)
    }

    // MARK: - JSON Config Parsing

    func testParseJSONConfig() throws {
        let configJSON = """
        {
            "glassesUUID": "GLASS-UUID",
            "mediaUUID": "MEDIA-UUID",
            "sessionUUID": "SESSION-UUID",
            "deviceType": "ORBI-360",
            "duration": 30000,
            "camera_order": [0, 1, 2, 3],
            "imuFiles": ["imu1.dat", "imu2.dat"],
            "helmetImu": {
                "imuPath": "helmet_imu.bin",
                "imuFiles": ["helmet1.dat"]
            },
            "sources": [
                {"path": "PRIM0001.MP4", "chanel": 0, "fileSize": 1000000, "referenceCamera": {"viewAngleX": 1.5, "viewAngleY": 1.2, "rotationVector": [0, 0, 0], "rotationMatrix": []}},
                {"path": "PRIM0002.MP4", "chanel": 1, "fileSize": 2000000},
                {"path": "PRIM0001.JPG", "chanel": 0, "fileSize": 5000000},
                {"path": "PRIM0002.JPG", "chanel": 1, "fileSize": 6000000}
            ]
        }
        """
        let configURL = tempDir.appendingPathComponent("ORBI_0001.CFG")
        try configJSON.write(to: configURL, atomically: true, encoding: .utf8)

        let bundle = try OrbiRawBundleParser.parse(directory: tempDir, mediaName: "ORBI_0001")

        XCTAssertEqual(bundle.glassesUUID, "GLASS-UUID")
        XCTAssertEqual(bundle.mediaUUID, "MEDIA-UUID")
        XCTAssertEqual(bundle.sessionUUID, "SESSION-UUID")
        XCTAssertEqual(bundle.deviceType, "ORBI-360")
        XCTAssertEqual(bundle.durationMilliseconds, 30000)
        XCTAssertEqual(bundle.cameraOrder, [0, 1, 2, 3])
        XCTAssertTrue(bundle.imuFiles.contains("imu1.dat"))
        XCTAssertTrue(bundle.imuFiles.contains("imu2.dat"))
        XCTAssertTrue(bundle.imuFiles.contains("helmet_imu.bin"))
        XCTAssertTrue(bundle.imuFiles.contains("helmet1.dat"))
    }

    func testParseJSONConfigSourceCount() throws {
        let configJSON = """
        {
            "sources": [
                {"path": "PRIM0001.MP4", "chanel": 0},
                {"path": "PRIM0002.MP4", "chanel": 1},
                {"path": "PRIM0003.MP4", "chanel": 2},
                {"path": "PRIM0004.MP4", "chanel": 3}
            ]
        }
        """
        let configURL = tempDir.appendingPathComponent("test.CFG")
        try configJSON.write(to: configURL, atomically: true, encoding: .utf8)

        let bundle = try OrbiRawBundleParser.parse(directory: tempDir, mediaName: "test")
        XCTAssertEqual(bundle.videoSources.count, 4)
    }

    func testParseJSONConfigCalibration() throws {
        let configJSON = """
        {
            "sources": [
                {
                    "path": "PRIM0001.MP4",
                    "chanel": 0,
                    "referenceCamera": {
                        "viewAngleX": 1.5,
                        "viewAngleY": 1.2,
                        "maxTheta": 0.8,
                        "ppx": 0.52,
                        "ppy": 0.48,
                        "k1": 0.1,
                        "k2": 0.01,
                        "k3": 0.001,
                        "k4": 0.0001,
                        "rotationVector": [0.1, 0.2, 0.3],
                        "rotationMatrix": [1, 0, 0, 0, 1, 0, 0, 0, 1]
                    }
                }
            ]
        }
        """
        let configURL = tempDir.appendingPathComponent("ORBI_0001.CFG")
        try configJSON.write(to: configURL, atomically: true, encoding: .utf8)

        let bundle = try OrbiRawBundleParser.parse(directory: tempDir, mediaName: "ORBI_0001")
        let source = bundle.sources.first
        XCTAssertNotNil(source?.referenceCamera)
        XCTAssertEqual(source?.referenceCamera?.viewAngleX, 1.5)
        XCTAssertEqual(source?.referenceCamera?.viewAngleY, 1.2)
        XCTAssertEqual(source?.referenceCamera?.maxTheta, 0.8)
        XCTAssertEqual(source?.referenceCamera?.ppx, 0.52)
        XCTAssertEqual(source?.referenceCamera?.ppy, 0.48)
        XCTAssertEqual(source?.referenceCamera?.k1, 0.1)
        XCTAssertEqual(source?.referenceCamera?.k2, 0.01)
        XCTAssertEqual(source?.referenceCamera?.rotationVector, [0.1, 0.2, 0.3])
    }

    // MARK: - Loose Key-Value Config

    func testParseLooseKeyValueConfig() throws {
        let configText = """
        glassesUUID=GLASS-001
        mediaUUID=MEDIA-001
        duration=15000
        imuPath=imu_data.bin
        path1=PRIM0001.MP4
        path2=PRIM0002.MP4
        """
        let configURL = tempDir.appendingPathComponent("ORBI_0001.CFG")
        try configText.write(to: configURL, atomically: true, encoding: .utf8)

        let bundle = try OrbiRawBundleParser.parse(directory: tempDir, mediaName: "ORBI_0001")
        XCTAssertEqual(bundle.glassesUUID, "GLASS-001")
        XCTAssertEqual(bundle.mediaUUID, "MEDIA-001")
        XCTAssertEqual(bundle.durationMilliseconds, 15000)
        XCTAssertTrue(bundle.imuFiles.contains("imu_data.bin"))
    }

    // MARK: - Filesystem Sources

    func testFilesystemSourcesAdded() throws {
        // Create dummy MP4 files with ftyp header
        let mp4Header = Data([0x00, 0x00, 0x00, 0x20] + "ftyp".data(using: .ascii)! + [0x00, 0x00, 0x00, 0x00])
        let mp4URL1 = tempDir.appendingPathComponent("PRIM0001.MP4")
        let mp4URL2 = tempDir.appendingPathComponent("PRIM0002.MP4")
        try mp4Header.write(to: mp4URL1)
        try mp4Header.write(to: mp4URL2)

        // Create dummy JPG files
        let jpgHeader = Data([0xff, 0xd8, 0xff, 0xe0])
        let jpgURL1 = tempDir.appendingPathComponent("PRIM0001.JPG")
        let jpgURL2 = tempDir.appendingPathComponent("PRIM0002.JPG")
        try jpgHeader.write(to: jpgURL1)
        try jpgHeader.write(to: jpgURL2)

        let bundle = try OrbiRawBundleParser.parse(directory: tempDir, mediaName: "ORBI_0001")
        XCTAssertEqual(bundle.videoSources.count, 2)
        XCTAssertEqual(bundle.photoSources.count, 2)
    }

    func testFilesystemSourceChannelFromName() throws {
        let mp4Header = Data([0x00, 0x00, 0x00, 0x20] + "ftyp".data(using: .ascii)! + [0x00, 0x00, 0x00, 0x00])
        let mp4URL1 = tempDir.appendingPathComponent("PRIM0001.MP4")
        let mp4URL2 = tempDir.appendingPathComponent("PRIM0002.MP4")
        try mp4Header.write(to: mp4URL1)
        try mp4Header.write(to: mp4URL2)

        let bundle = try OrbiRawBundleParser.parse(directory: tempDir, mediaName: "ORBI_0001")
        // Channel from name: PRIM0001 -> channel 0 (1-1), PRIM0002 -> channel 1 (2-1)
        XCTAssertEqual(bundle.videoSources[0].channel, 0)
        XCTAssertEqual(bundle.videoSources[1].channel, 1)
    }

    // MARK: - Source Sorting

    func testSourcesSortedByChannel() throws {
        let configJSON = """
        {
            "sources": [
                {"path": "PRIM0003.MP4", "chanel": 3},
                {"path": "PRIM0001.MP4", "chanel": 1},
                {"path": "PRIM0002.MP4", "chanel": 2},
                {"path": "PRIM0000.MP4", "chanel": 0}
            ]
        }
        """
        let configURL = tempDir.appendingPathComponent("ORBI_0001.CFG")
        try configJSON.write(to: configURL, atomically: true, encoding: .utf8)

        let bundle = try OrbiRawBundleParser.parse(directory: tempDir, mediaName: "ORBI_0001")
        XCTAssertEqual(bundle.videoSources[0].channel, 0)
        XCTAssertEqual(bundle.videoSources[1].channel, 1)
        XCTAssertEqual(bundle.videoSources[2].channel, 2)
        XCTAssertEqual(bundle.videoSources[3].channel, 3)
    }

    // MARK: - Config File Selection

    func testPreferredConfigExactMatch() throws {
        let exactConfig = tempDir.appendingPathComponent("ORBI_0001.CFG")
        try "{}".write(to: exactConfig, atomically: true, encoding: .utf8)
        let otherConfig = tempDir.appendingPathComponent("other.CFG")
        try "{}".write(to: otherConfig, atomically: true, encoding: .utf8)

        let bundle = try OrbiRawBundleParser.parse(directory: tempDir, mediaName: "ORBI_0001")
        XCTAssertEqual(bundle.configURL?.lastPathComponent, "ORBI_0001.CFG")
    }

    func testPreferredConfigFallback() throws {
        let otherConfig = tempDir.appendingPathComponent("config.CFG")
        try "{}".write(to: otherConfig, atomically: true, encoding: .utf8)

        let bundle = try OrbiRawBundleParser.parse(directory: tempDir, mediaName: "ORBI_0001")
        XCTAssertEqual(bundle.configURL?.lastPathComponent, "config.CFG")
    }

    // MARK: - Kind Detection

    func testKindForPathExtensions() {
        let bundle = OrbiRawBundle(
            directory: tempDir, configURL: nil, mediaUUID: nil, glassesUUID: nil,
            sessionUUID: nil, deviceType: nil, durationMilliseconds: nil,
            cameraOrder: [], sources: [], imuFiles: [], rawConfig: nil
        )
        // Test through filesystem detection
        XCTAssertEqual(bundle.videoSources.count, 0)
        XCTAssertEqual(bundle.photoSources.count, 0)
    }

    // MARK: - Raw Config Preservation

    func testRawConfigPreserved() throws {
        let configText = "{\"test\": \"value\"}"
        let configURL = tempDir.appendingPathComponent("ORBI_0001.CFG")
        try configText.write(to: configURL, atomically: true, encoding: .utf8)

        let bundle = try OrbiRawBundleParser.parse(directory: tempDir, mediaName: "ORBI_0001")
        XCTAssertNotNil(bundle.rawConfig)
        XCTAssertTrue(bundle.rawConfig?.contains("test") ?? false)
    }

    // MARK: - Config URL Property

    func testConfigURLSet() throws {
        let configURL = tempDir.appendingPathComponent("ORBI_0001.CFG")
        try "{}".write(to: configURL, atomically: true, encoding: .utf8)

        let bundle = try OrbiRawBundleParser.parse(directory: tempDir, mediaName: "ORBI_0001")
        XCTAssertNotNil(bundle.configURL)
        XCTAssertEqual(bundle.configURL, configURL)
    }

    // MARK: - Video/Photo Source Filtering

    func testVideoAndPhotoSourceFiltering() throws {
        let configJSON = """
        {
            "sources": [
                {"path": "PRIM0001.MP4", "chanel": 0},
                {"path": "PRIM0001.JPG", "chanel": 0},
                {"path": "PRIM0002.MP4", "chanel": 1},
                {"path": "PRIM0002.JPG", "chanel": 1},
                {"path": "audio.aac", "chanel": 2}
            ]
        }
        """
        let configURL = tempDir.appendingPathComponent("ORBI_0001.CFG")
        try configJSON.write(to: configURL, atomically: true, encoding: .utf8)

        let bundle = try OrbiRawBundleParser.parse(directory: tempDir, mediaName: "ORBI_0001")
        XCTAssertEqual(bundle.videoSources.count, 2)
        XCTAssertEqual(bundle.photoSources.count, 2)
        XCTAssertEqual(bundle.sources.count, 5) // including audio
    }
}
