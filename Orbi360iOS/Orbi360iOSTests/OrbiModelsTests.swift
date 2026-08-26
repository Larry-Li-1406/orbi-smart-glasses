import XCTest
@testable import Orbi360iOS

final class OrbiModelsTests: XCTestCase {

    // MARK: - DeviceMode

    func testDeviceModeCommandValues() {
        XCTAssertEqual(DeviceMode.photo.commandValue, "shot")
        XCTAssertEqual(DeviceMode.live.commandValue, "live")
        XCTAssertEqual(DeviceMode.video.commandValue, "record")
        XCTAssertEqual(DeviceMode.none.commandValue, "")
    }

    func testDeviceModeInitFromString() {
        XCTAssertEqual(DeviceMode(deviceModeString: "shot"), .photo)
        XCTAssertEqual(DeviceMode(deviceModeString: "live"), .live)
        XCTAssertEqual(DeviceMode(deviceModeString: "record"), .video)
        XCTAssertEqual(DeviceMode(deviceModeString: nil), .none)
        XCTAssertEqual(DeviceMode(deviceModeString: "unknown"), .none)
        XCTAssertEqual(DeviceMode(deviceModeString: ""), .none)
    }

    // MARK: - DeviceBattery

    func testBatteryPercentText() {
        XCTAssertEqual(DeviceBattery.none.percentText, "--")
        XCTAssertEqual(DeviceBattery.chargeZero.percentText, "0%")
        XCTAssertEqual(DeviceBattery.charge25.percentText, "25%")
        XCTAssertEqual(DeviceBattery.charge50.percentText, "50%")
        XCTAssertEqual(DeviceBattery.charge75.percentText, "75%")
        XCTAssertEqual(DeviceBattery.charge100.percentText, "100%")
        XCTAssertEqual(DeviceBattery.charging.percentText, "Charging")
    }

    // MARK: - OrbiDeviceStatus

    func testCardAvailableLogic() {
        var status = OrbiDeviceStatus.sample
        XCTAssertTrue(status.cardAvailable)

        status.sdCardInserted = false
        XCTAssertFalse(status.cardAvailable)

        status.sdCardInserted = true
        status.sdCardMounted = false
        XCTAssertFalse(status.cardAvailable)
    }

    func testRemainingTextNoCard() {
        var status = OrbiDeviceStatus.sample
        status.sdCardInserted = false
        XCTAssertEqual(status.remainingText, "无 SD 卡")
    }

    func testRemainingTextWrongFormat() {
        var status = OrbiDeviceStatus.sample
        status.sdCardInserted = true
        status.sdCardMounted = false
        XCTAssertEqual(status.remainingText, "SD 卡格式错误")
    }

    func testRemainingTextPhotoMode() {
        var status = OrbiDeviceStatus.sample
        status.mode = .photo
        status.sdFreeCapacity = 52_428_800
        XCTAssertEqual(status.remainingText, "可拍: 10 张")
    }

    func testRemainingTextVideoMode() {
        var status = OrbiDeviceStatus.sample
        status.mode = .video
        status.sdFreeCapacity = 9_742 * 3600
        XCTAssertEqual(status.remainingText, "可录: 01:00:00")
    }

    func testRemainingTextNoneMode() {
        var status = OrbiDeviceStatus.sample
        status.mode = .none
        XCTAssertEqual(status.remainingText, "")
    }

    // MARK: - OrbiProtocol Constants

    func testProtocolConstants() {
        XCTAssertEqual(OrbiProtocol.deviceIP, "192.168.2.1")
        XCTAssertEqual(OrbiProtocol.devicePort, 8080)
        XCTAssertEqual(OrbiProtocol.localPort, 5000)
        XCTAssertEqual(OrbiProtocol.messageDelimiter, "\r\n\r\n")
        XCTAssertEqual(OrbiProtocol.dcimPath, "/run/RTOS/DCIM/")
        XCTAssertEqual(OrbiProtocol.livePreviewPorts, [5000, 5002, 5004, 5006])
    }

    // MARK: - DeviceCommandEnvelope Encoding

    func testCommandEnvelopeBasicEncoding() throws {
        let json = try encodedJSONObject(DeviceCommandEnvelope(id: 1, cmd: "get-status"))
        XCTAssertEqual(json["id"] as? Int, 1)
        XCTAssertEqual(json["cmd"] as? String, "get-status")
    }

    func testCommandEnvelopeWithMode() throws {
        let json = try encodedJSONObject(DeviceCommandEnvelope(id: 2, cmd: "mode", mode: "shot", modeShort: true))
        XCTAssertEqual(json["mode"] as? String, "shot")
        XCTAssertEqual(json["mode_short"] as? Bool, true)
    }

    func testCommandEnvelopeWiFiAPEncoding() throws {
        let json = try encodedJSONObject(DeviceCommandEnvelope(
            id: 3,
            cmd: "wifi-ap",
            wifiAp: .init(ssid: "ORBI_360", psk: "password123")
        ))
        let wifiAP = try XCTUnwrap(json["wifi_ap"] as? [String: Any])
        XCTAssertEqual(wifiAP["ssid"] as? String, "ORBI_360")
        XCTAssertEqual(wifiAP["psk"] as? String, "password123")
        XCTAssertEqual(wifiAP["channel"] as? Int, 48)
    }

    func testCommandEnvelopeSetSettingsEncoding() throws {
        let json = try encodedJSONObject(DeviceCommandEnvelope(
            id: 4,
            cmd: "set-settings",
            imageParams: .init(delay: 300),
            videoParams: .init(
                delay: 300,
                audio: true,
                recordTimeout: 12_000,
                recInterval: 5_000,
                idleInterval: 3_000,
                turnOffWiFi: true,
                runner: true
            ),
            calendarData: calendarData()
        ))

        let imageParams = try XCTUnwrap(json["image_params"] as? [String: Any])
        XCTAssertEqual(imageParams["delay"] as? Int, 300)

        let videoParams = try XCTUnwrap(json["video_params"] as? [String: Any])
        XCTAssertEqual(videoParams["delay"] as? Int, 300)
        XCTAssertEqual(videoParams["audio"] as? Bool, true)
        XCTAssertEqual(videoParams["rec_timeout"] as? Int, 12_000)
        XCTAssertEqual(videoParams["time_record"] as? Int, 5_000)
        XCTAssertEqual(videoParams["time_sleep"] as? Int, 3_000)
        XCTAssertEqual(videoParams["turn_off_wifi"] as? Bool, true)
        XCTAssertEqual(videoParams["runner"] as? Bool, true)

        let calendar = try XCTUnwrap(json["calendar_data"] as? [String: Any])
        XCTAssertEqual(calendar["year"] as? Int, 26)
        XCTAssertEqual(calendar["month"] as? Int, 7)
        XCTAssertEqual(calendar["day"] as? Int, 1)
        XCTAssertEqual(calendar["day_of_week"] as? Int, 3)
    }

    func testCommandEnvelopeStreamParamsEncoding() throws {
        let json = try encodedJSONObject(DeviceCommandEnvelope(
            id: 5,
            cmd: "set-stream-params",
            streamParams: .init(
                rtpIP: "192.168.2.100",
                streams: OrbiProtocol.livePreviewPorts.map { .init(rtpPort: $0) }
            )
        ))
        let streamParams = try XCTUnwrap(json["stream_params"] as? [String: Any])
        XCTAssertEqual(streamParams["rtp_ip"] as? String, "192.168.2.100")
        let streams = try XCTUnwrap(streamParams["streams"] as? [[String: Any]])
        XCTAssertEqual(streams.compactMap { $0["rtp_port"] as? Int }, [5000, 5002, 5004, 5006])
    }

    func testCommandEnvelopeNFSTransferAndQuickFormatEncoding() throws {
        let nfs = try encodedJSONObject(DeviceCommandEnvelope(id: 6, cmd: "nfs-transfer", start: true))
        XCTAssertEqual(nfs["start"] as? Bool, true)

        let format = try encodedJSONObject(DeviceCommandEnvelope(id: 7, cmd: "format-sd", quick: true))
        XCTAssertEqual(format["quick"] as? Bool, true)
    }

    // MARK: - DeviceResponseEnvelope Decoding

    func testResponseEnvelopeDecoding() throws {
        let json: [String: Any] = [
            "id": 1,
            "result": true,
            "dev-uuid": "ORBI-TEST-UUID",
            "firmware-version": "1.0115",
            "run": "true",
            "mode": "record",
            "capture-duration": "5000",
            "nfs_transfer": 0,
            "charger": ["threshold": "80", "charging": false],
            "stream_params": [
                "rtp_ip": "192.168.0.123",
                "streams": [
                    ["rtp_port": "5000"],
                    ["rtp_port": "0"]
                ]
            ],
            "sd_card": ["inserted": 1, "mount": true, "free_capacity": "18400000000"],
            "images": [["uuid": "img-uuid-1", "pathname": "ORBI_0001.JPG", "size": 5_242_880, "duration": "0", "date": "2024-01-01T00:00:00Z"]],
            "videos": [["uuid": "vid-uuid-1", "pathname": "ORBI_0002.MP4", "size": 118_000_000, "duration": "42000", "date": "2024-01-01T00:00:00Z"]]
        ]
        let data = try JSONSerialization.data(withJSONObject: json)
        let response = try JSONDecoder().decode(DeviceResponseEnvelope.self, from: data)

        XCTAssertEqual(response.id, 1)
        XCTAssertEqual(response.result, true)
        XCTAssertEqual(response.deviceUUID, "ORBI-TEST-UUID")
        XCTAssertEqual(response.firmwareVersion, "1.0115")
        XCTAssertEqual(response.run, true)
        XCTAssertEqual(response.mode, "record")
        XCTAssertEqual(response.captureDuration, 5000)
        XCTAssertEqual(response.nfsTransfer, false)
        XCTAssertEqual(response.charger?.threshold, 80)
        XCTAssertEqual(response.charger?.charging, false)
        XCTAssertEqual(response.streamParams?.rtpIP, "192.168.0.123")
        XCTAssertEqual(response.streamParams?.streams.map(\.rtpPort), [5000, 0])
        XCTAssertEqual(response.sdCard?.inserted, true)
        XCTAssertEqual(response.sdCard?.mount, true)
        XCTAssertEqual(response.sdCard?.freeCapacity, 18_400_000_000)
        XCTAssertEqual(response.images?.count, 1)
        XCTAssertEqual(response.videos?.count, 1)
    }

    func testResponseEnvelopeWithImageVideoArrays() throws {
        let json: [String: Any] = [
            "id": 2,
            "result": true,
            "image": ["files": [["uuid": "img1", "pathname": "ORBI_0001", "size": 100, "duration": "0", "date": ""]]],
            "video": ["files": [["uuid": "vid1", "pathname": "ORBI_0002", "size": 200, "duration": "1000", "date": ""]]]
        ]
        let data = try JSONSerialization.data(withJSONObject: json)
        let response = try JSONDecoder().decode(DeviceResponseEnvelope.self, from: data)

        XCTAssertEqual(response.image?.files?.count, 1)
        XCTAssertEqual(response.video?.files?.count, 1)
        XCTAssertEqual(response.image?.files?.first?.uuid, "img1")
        XCTAssertEqual(response.video?.files?.first?.uuid, "vid1")
    }

    func testCommandFailureDescription() {
        let response = DeviceResponseEnvelope(responseString: "cant set camera capture mode", descString: nil, result: false)
        XCTAssertEqual(response.commandFailureDescription(for: "start"), "start cant set camera capture mode")
    }

    func testCaptureModeFailureDescription() {
        let response = DeviceResponseEnvelope(responseString: "cant set camera capture mode", descString: nil, result: false)
        let failure = response.commandFailure(for: "start")

        XCTAssertTrue(failure.userDescription.contains("无法切换相机采集模式"))
    }

    func testVideoHardwareSystemErrorDescription() {
        let response = DeviceResponseEnvelope(
            event: "error",
            errorCode: "855638021",
            errorParam: "5",
            descString: "System Error"
        )
        let failure = response.commandFailure(for: "start")

        XCTAssertEqual(failure.rawDescription, "start System Error 855638021 5")
        XCTAssertTrue(failure.userDescription.contains("录像系统错误"))
        XCTAssertTrue(failure.userDescription.contains("855638021"))
        XCTAssertTrue(failure.userDescription.contains("参数 5"))
    }

    func testPhotoHardwareSystemErrorDescription() {
        let response = DeviceResponseEnvelope(
            event: "error",
            errorCode: "838860805",
            errorParam: "5",
            descString: "System Error"
        )
        let failure = response.commandFailure(for: "start")

        XCTAssertTrue(failure.userDescription.contains("拍照系统错误"))
    }

    // MARK: - DeviceEventEnvelope Decoding

    func testEventEnvelopeDecoding() throws {
        let json: [String: Any] = [
            "id": 5,
            "event": "capture_done",
            "mode": "shot",
            "name": "ORBI_0005",
            "uuid": "event-uuid",
            "available_storage": 17_000_000_000
        ]
        let data = try JSONSerialization.data(withJSONObject: json)
        let event = try JSONDecoder().decode(DeviceEventEnvelope.self, from: data)

        XCTAssertEqual(event.id, 5)
        XCTAssertEqual(event.event, "capture_done")
        XCTAssertEqual(event.mode, "shot")
        XCTAssertEqual(event.mediaName, "ORBI_0005")
        XCTAssertEqual(event.mediaUuid, "event-uuid")
        XCTAssertEqual(event.availableStorage, 17_000_000_000)
    }

    // MARK: - NetworkOrbiDeviceService.status(from:)

    func testStatusMappingFromResponse() throws {
        let response = DeviceResponseEnvelope(
            id: 1,
            result: true,
            deviceUUID: "DEVICE-123",
            firmwareVersion: "2.0.0",
            run: true,
            mode: "shot",
            captureDuration: 3000,
            nfsTransfer: true,
            charger: .init(threshold: 50, charging: false),
            sdCard: .init(inserted: true, mount: true, freeCapacity: 1_000_000_000)
        )
        let status = NetworkOrbiDeviceService.status(from: response)

        XCTAssertEqual(status.id, "DEVICE-123")
        XCTAssertEqual(status.firmwareVersion, "2.0.0")
        XCTAssertEqual(status.mode, .photo)
        XCTAssertTrue(status.cameraRunning)
        XCTAssertEqual(status.battery, .charge50)
        XCTAssertEqual(status.sdFreeCapacity, 1_000_000_000)
        XCTAssertTrue(status.sdCardInserted)
        XCTAssertTrue(status.sdCardMounted)
        XCTAssertEqual(status.captureDuration, 3.0)
        XCTAssertTrue(status.nfsUsed)
    }

    func testStatusMappingCharging() throws {
        let response = DeviceResponseEnvelope(charger: .init(threshold: 100, charging: true))
        let status = NetworkOrbiDeviceService.status(from: response)
        XCTAssertEqual(status.battery, .charging)
    }

    func testStatusMappingBatteryThresholds() throws {
        let thresholds: [(Int?, DeviceBattery)] = [
            (0, .chargeZero),
            (25, .charge25),
            (50, .charge50),
            (75, .charge75),
            (100, .charge100)
        ]
        for (threshold, expected) in thresholds {
            let response = DeviceResponseEnvelope(charger: .init(threshold: threshold, charging: false))
            let status = NetworkOrbiDeviceService.status(from: response)
            XCTAssertEqual(status.battery, expected, "Threshold \(String(describing: threshold)) should map to \(expected)")
        }
    }

    func testStatusMappingDefaults() throws {
        let status = NetworkOrbiDeviceService.status(from: DeviceResponseEnvelope())

        XCTAssertEqual(status.id, "ORBI-360")
        XCTAssertEqual(status.firmwareVersion, "")
        XCTAssertEqual(status.mode, .none)
        XCTAssertFalse(status.cameraRunning)
        XCTAssertEqual(status.battery, .charge75)
        XCTAssertEqual(status.sdFreeCapacity, 0)
        XCTAssertFalse(status.sdCardInserted)
        XCTAssertFalse(status.sdCardMounted)
        XCTAssertEqual(status.captureDuration, 0)
        XCTAssertFalse(status.nfsUsed)
    }

    // MARK: - WiFi Credentials Validation

    func testWiFiValidationValid() throws {
        let credentials = WiFiCredentials(ssid: "MyNetwork", password: "password123", passwordVerify: "password123")
        XCTAssertNoThrow(try NetworkOrbiDeviceService.validate(credentials))
    }

    func testWiFiValidationEmptyPassword() throws {
        let credentials = WiFiCredentials(ssid: "MyNetwork", password: "", passwordVerify: "")
        XCTAssertNoThrow(try NetworkOrbiDeviceService.validate(credentials))
    }

    func testWiFiValidationInvalidSSID() throws {
        let credentials = WiFiCredentials(ssid: "", password: "password123", passwordVerify: "password123")
        XCTAssertThrowsError(try NetworkOrbiDeviceService.validate(credentials)) { error in
            guard case OrbiServiceError.invalidSSID = error else {
                XCTFail("Expected invalidSSID error")
                return
            }
        }
    }

    func testWiFiValidationPasswordTooShort() throws {
        let credentials = WiFiCredentials(ssid: "MyNetwork", password: "short", passwordVerify: "short")
        XCTAssertThrowsError(try NetworkOrbiDeviceService.validate(credentials)) { error in
            guard case OrbiServiceError.invalidPassword = error else {
                XCTFail("Expected invalidPassword error")
                return
            }
        }
    }

    func testWiFiValidationPasswordMismatch() throws {
        let credentials = WiFiCredentials(ssid: "MyNetwork", password: "password123", passwordVerify: "password456")
        XCTAssertThrowsError(try NetworkOrbiDeviceService.validate(credentials)) { error in
            guard case OrbiServiceError.invalidPassword = error else {
                XCTFail("Expected invalidPassword error")
                return
            }
        }
    }

    func testWiFiValidationSSIDWithSpecialChars() throws {
        let credentials = WiFiCredentials(ssid: "Network!@#", password: "password123", passwordVerify: "password123")
        XCTAssertThrowsError(try NetworkOrbiDeviceService.validate(credentials))
    }

    func testWiFiValidationSSIDWithHyphenAndUnderscore() throws {
        let credentials = WiFiCredentials(ssid: "My-Network_5G", password: "password123", passwordVerify: "password123")
        XCTAssertNoThrow(try NetworkOrbiDeviceService.validate(credentials))
    }

    // MARK: - OrbiMediaItem

    func testMediaItemURLs() {
        let item = OrbiMediaItem(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            name: "ORBI_0001",
            type: .photo,
            dateUTC: Date(timeIntervalSince1970: 1_700_000_000),
            duration: 0,
            remoteSize: 5_000_000,
            localSize: 5_000_000,
            isRemote: true,
            isLocal: true,
            thumbnailExists: false
        )

        XCTAssertTrue(item.configURLString.contains("192.168.2.1"))
        XCTAssertTrue(item.configURLString.contains("/run/RTOS/DCIM/ORBI_0001/ORBI_0001.CFG"))
        XCTAssertTrue(item.remoteDirectoryURLString.contains("/run/RTOS/DCIM/ORBI_0001"))
    }

    func testMediaItemSizeString() {
        let item = OrbiMediaItem(
            id: UUID(), name: "test", type: .video,
            dateUTC: Date(), duration: 0,
            remoteSize: 1_048_576, localSize: 1_048_576,
            isRemote: true, isLocal: true, thumbnailExists: false
        )
        XCTAssertEqual(item.sizeString, "1.0 MB")
    }

    func testMediaItemDurationString() {
        let video = OrbiMediaItem(
            id: UUID(), name: "test", type: .video,
            dateUTC: Date(), duration: 126,
            remoteSize: 0, localSize: 0,
            isRemote: true, isLocal: false, thumbnailExists: false
        )
        XCTAssertEqual(video.durationString, "2:06")

        let photo = OrbiMediaItem(
            id: UUID(), name: "test", type: .photo,
            dateUTC: Date(), duration: 0,
            remoteSize: 0, localSize: 0,
            isRemote: true, isLocal: false, thumbnailExists: false
        )
        XCTAssertEqual(photo.durationString, "")
    }

    // MARK: - MediaType

    func testMediaTypeFileExtensions() {
        XCTAssertEqual(MediaType.video.fileExtension, ".MP4")
        XCTAssertEqual(MediaType.photo.fileExtension, ".JPG")
        XCTAssertEqual(MediaType.thumbnail.fileExtension, ".THM")
        XCTAssertEqual(MediaType.unknown.fileExtension, "")
    }

    // MARK: - MainTab

    func testMainTabCases() {
        XCTAssertEqual(MainTab.allCases.count, 3)
        XCTAssertEqual(MainTab.shoot.symbol, "camera.viewfinder")
        XCTAssertEqual(MainTab.media.symbol, "photo.on.rectangle")
        XCTAssertEqual(MainTab.settings.symbol, "gearshape")
    }

    private func encodedJSONObject(_ envelope: DeviceCommandEnvelope) throws -> [String: Any] {
        let data = try JSONEncoder().encode(envelope)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func calendarData() -> DeviceCommandEnvelope.CalendarData {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let date = calendar.date(from: DateComponents(
            timeZone: TimeZone(secondsFromGMT: 0),
            year: 2026,
            month: 7,
            day: 1,
            hour: 12,
            minute: 34,
            second: 56
        ))!
        return DeviceCommandEnvelope.CalendarData(date: date, calendar: calendar)
    }
}
