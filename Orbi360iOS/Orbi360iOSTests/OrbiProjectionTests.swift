import XCTest
@testable import Orbi360iOS

final class OrbiProjectionTests: XCTestCase {

    // MARK: - OrbiVec3

    func testEquirectangularToDirectionCenter() {
        // Center pixel should map to forward direction (z=1)
        let dir = OrbiVec3.fromEquirectangular(x: 960, y: 480, width: 1920, height: 960)
        XCTAssertEqual(dir.z, 1.0, accuracy: 0.01)
        XCTAssertEqual(dir.x, 0.0, accuracy: 0.01)
        XCTAssertEqual(dir.y, 0.0, accuracy: 0.01)
    }

    func testEquirectangularToDirectionRightEdge() {
        // Right edge should face right (x positive)
        let dir = OrbiVec3.fromEquirectangular(x: 1440, y: 480, width: 1920, height: 960)
        XCTAssertGreaterThan(dir.x, 0)
        XCTAssertEqual(dir.z, 0.0, accuracy: 0.01) // 90 degrees
    }

    func testEquirectangularToDirectionLeftEdge() {
        // Left edge should face left (x negative)
        let dir = OrbiVec3.fromEquirectangular(x: 480, y: 480, width: 1920, height: 960)
        XCTAssertLessThan(dir.x, 0)
    }

    func testEquirectangularToDirectionTop() {
        // Top center should face up (y positive)
        let dir = OrbiVec3.fromEquirectangular(x: 960, y: 0, width: 1920, height: 960)
        XCTAssertEqual(dir.y, 1.0, accuracy: 0.01)
    }

    func testEquirectangularToDirectionBottom() {
        // Bottom center should face down (y negative)
        let dir = OrbiVec3.fromEquirectangular(x: 960, y: 959, width: 1920, height: 960)
        XCTAssertEqual(dir.y, -1.0, accuracy: 0.01)
    }

    func testEquirectangularUnitVectors() {
        // All directions should be unit vectors
        for y in stride(from: 0, to: 960, by: 120) {
            for x in stride(from: 0, to: 1920, by: 120) {
                let dir = OrbiVec3.fromEquirectangular(x: x, y: y, width: 1920, height: 960)
                let length = sqrt(dir.x * dir.x + dir.y * dir.y + dir.z * dir.z)
                XCTAssertEqual(length, 1.0, accuracy: 0.001)
            }
        }
    }

    // MARK: - OrbiMat3

    func testIdentityMatrix() {
        let identity = OrbiMat3.identity
        XCTAssertEqual(identity.m, [1, 0, 0, 0, 1, 0, 0, 0, 1])
    }

    func testRotationVectorZeroIsIdentity() {
        let rotation = OrbiMat3.rotationVector([0, 0, 0])
        XCTAssertEqual(rotation.m, OrbiMat3.identity.m)
    }

    func testRotationVectorWrongCountIsIdentity() {
        let rotation = OrbiMat3.rotationVector([1, 2]) // only 2 elements
        XCTAssertEqual(rotation.m, OrbiMat3.identity.m)
    }

    func testRotationVector90DegreesAroundZ() {
        // 90 degrees around Z axis
        let angle = Double.pi / 2
        let rotation = OrbiMat3.rotationVector([0, 0, angle])
        let v = OrbiVec3(x: 1, y: 0, z: 0)
        let result = rotation.transposedMultiply(v)
        // transposedMultiply applies the camera-to-world matrix as world-to-camera.
        XCTAssertEqual(result.x, 0.0, accuracy: 0.001)
        XCTAssertEqual(result.y, -1.0, accuracy: 0.001)
        XCTAssertEqual(result.z, 0.0, accuracy: 0.001)
    }

    func testRotationVector180DegreesAroundX() {
        let angle = Double.pi
        let rotation = OrbiMat3.rotationVector([angle, 0, 0])
        let v = OrbiVec3(x: 0, y: 1, z: 0)
        let result = rotation.transposedMultiply(v)
        // 180° around X: (0,1,0) -> (0,-1,0)
        XCTAssertEqual(result.x, 0.0, accuracy: 0.001)
        XCTAssertEqual(result.y, -1.0, accuracy: 0.001)
        XCTAssertEqual(result.z, 0.0, accuracy: 0.001)
    }

    func testTransposedMultiplyIdentity() {
        let v = OrbiVec3(x: 1, y: 2, z: 3)
        let result = OrbiMat3.identity.transposedMultiply(v)
        XCTAssertEqual(result.x, 1.0, accuracy: 0.001)
        XCTAssertEqual(result.y, 2.0, accuracy: 0.001)
        XCTAssertEqual(result.z, 3.0, accuracy: 0.001)
    }

    // MARK: - OrbiCameraProjection

    func testProjectionForwardDirectionReturnsCenter() {
        let source = OrbiRawBundle.CameraSource(
            channel: 0,
            path: "PRIM0001.MP4",
            fileSize: nil,
            kind: .video,
            referenceCamera: nil,
            mp4Info: nil
        )
        let projection = OrbiCameraProjection(source: source)
        // Forward direction (z=1) should map to center of image
        let forward = OrbiVec3(x: 0, y: 0, z: 1)
        let result = projection.uv(for: forward)
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.uv.x ?? -1, 0.5, accuracy: 0.01)
        XCTAssertEqual(result?.uv.y ?? -1, 0.5, accuracy: 0.01)
    }

    func testProjectionBackwardDirectionReturnsNil() {
        let source = OrbiRawBundle.CameraSource(
            channel: 0, path: "PRIM0001.MP4", fileSize: nil, kind: .video,
            referenceCamera: nil, mp4Info: nil
        )
        let projection = OrbiCameraProjection(source: source)
        // Backward direction (z=-1) should return nil
        let backward = OrbiVec3(x: 0, y: 0, z: -1)
        let result = projection.uv(for: backward)
        XCTAssertNil(result)
    }

    func testProjectionDefaultFOV() {
        let source = OrbiRawBundle.CameraSource(
            channel: 0, path: "PRIM0001.MP4", fileSize: nil, kind: .video,
            referenceCamera: nil, mp4Info: nil
        )
        let projection = OrbiCameraProjection(source: source)
        // Default FOV should be 2*pi/3 (120 degrees)
        XCTAssertEqual(projection.horizontalFOV, 2.0 * .pi / 3.0, accuracy: 0.001)
        XCTAssertEqual(projection.verticalFOV, 2.0 * .pi / 3.0, accuracy: 0.001)
    }

    func testProjectionWithCalibration() {
        let calibration = OrbiRawBundle.CameraCalibration(
            viewAngleX: 1.5, viewAngleY: 1.2,
            maxTheta: 0.8, ppx: 0.5, ppy: 0.5,
            k1: 0.1, k2: 0.0, k3: 0.0, k4: 0.0,
            rotationVector: [0, 0, 0],
            rotationMatrix: []
        )
        let source = OrbiRawBundle.CameraSource(
            channel: 0, path: "PRIM0001.MP4", fileSize: nil, kind: .video,
            referenceCamera: calibration, mp4Info: nil
        )
        let projection = OrbiCameraProjection(source: source)
        XCTAssertEqual(projection.horizontalFOV, 1.5, accuracy: 0.001)
        XCTAssertEqual(projection.verticalFOV, 1.2, accuracy: 0.001)
        XCTAssertNotNil(projection.calibration)
    }

    func testProjectionScoreIsPositiveForForward() {
        let source = OrbiRawBundle.CameraSource(
            channel: 0, path: "PRIM0001.MP4", fileSize: nil, kind: .video,
            referenceCamera: nil, mp4Info: nil
        )
        let projection = OrbiCameraProjection(source: source)
        let forward = OrbiVec3(x: 0, y: 0, z: 1)
        let result = projection.uv(for: forward)
        XCTAssertNotNil(result)
        XCTAssertGreaterThan(result?.score ?? -1, 0)
    }

    func testProjectionUVBounds() {
        let source = OrbiRawBundle.CameraSource(
            channel: 0, path: "PRIM0001.MP4", fileSize: nil, kind: .video,
            referenceCamera: nil, mp4Info: nil
        )
        let projection = OrbiCameraProjection(source: source)
        // Sample many directions and check UV bounds
        for pitch in stride(from: -0.5, through: 0.5, by: 0.1) {
            for yaw in stride(from: -0.5, through: 0.5, by: 0.1) {
                let dir = OrbiVec3(x: sin(yaw), y: sin(pitch), z: cos(yaw) * cos(pitch))
                if let result = projection.uv(for: dir) {
                    XCTAssertGreaterThanOrEqual(result.uv.x, 0.0)
                    XCTAssertLessThanOrEqual(result.uv.x, 1.0)
                    XCTAssertGreaterThanOrEqual(result.uv.y, 0.0)
                    XCTAssertLessThanOrEqual(result.uv.y, 1.0)
                }
            }
        }
    }

    func testProjectionWithRotation() {
        let calibration = OrbiRawBundle.CameraCalibration(
            viewAngleX: 2.0 * .pi / 3.0, viewAngleY: 2.0 * .pi / 3.0,
            maxTheta: nil, ppx: 0.5, ppy: 0.5,
            k1: 0, k2: 0, k3: 0, k4: 0,
            rotationVector: [0, 0, Double.pi / 2], // 90° around Z
            rotationMatrix: []
        )
        let source = OrbiRawBundle.CameraSource(
            channel: 0, path: "PRIM0001.MP4", fileSize: nil, kind: .video,
            referenceCamera: calibration, mp4Info: nil
        )
        let projection = OrbiCameraProjection(source: source)
        // After 90° rotation, forward should still map to center
        let forward = OrbiVec3(x: 0, y: 0, z: 1)
        let result = projection.uv(for: forward)
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.uv.x ?? -1, 0.5, accuracy: 0.01)
        XCTAssertEqual(result?.uv.y ?? -1, 0.5, accuracy: 0.01)
    }

    // MARK: - Distortion

    func testDistortionWithZeroCoefficients() {
        let calibration = OrbiRawBundle.CameraCalibration(
            viewAngleX: 2.0 * .pi / 3.0, viewAngleY: 2.0 * .pi / 3.0,
            maxTheta: 1.0, ppx: 0.5, ppy: 0.5,
            k1: 0, k2: 0, k3: 0, k4: 0,
            rotationVector: [0, 0, 0],
            rotationMatrix: []
        )
        let source = OrbiRawBundle.CameraSource(
            channel: 0, path: "PRIM0001.MP4", fileSize: nil, kind: .video,
            referenceCamera: calibration, mp4Info: nil
        )
        let projection = OrbiCameraProjection(source: source)
        // With zero distortion, forward should map exactly to center
        let forward = OrbiVec3(x: 0, y: 0, z: 1)
        let result = projection.uv(for: forward)
        XCTAssertEqual(result?.uv.x ?? -1, 0.5, accuracy: 0.001)
        XCTAssertEqual(result?.uv.y ?? -1, 0.5, accuracy: 0.001)
    }

    func testDistortionShiftsUV() {
        let noDistortion = OrbiRawBundle.CameraCalibration(
            viewAngleX: 2.0 * .pi / 3.0, viewAngleY: 2.0 * .pi / 3.0,
            maxTheta: 1.0, ppx: 0.5, ppy: 0.5,
            k1: 0, k2: 0, k3: 0, k4: 0,
            rotationVector: [0, 0, 0],
            rotationMatrix: []
        )
        let withDistortion = OrbiRawBundle.CameraCalibration(
            viewAngleX: 2.0 * .pi / 3.0, viewAngleY: 2.0 * .pi / 3.0,
            maxTheta: 1.0, ppx: 0.5, ppy: 0.5,
            k1: 0.5, k2: 0.1, k3: 0, k4: 0,
            rotationVector: [0, 0, 0],
            rotationMatrix: []
        )

        let source1 = OrbiRawBundle.CameraSource(
            channel: 0, path: "test.MP4", fileSize: nil, kind: .video,
            referenceCamera: noDistortion, mp4Info: nil
        )
        let source2 = OrbiRawBundle.CameraSource(
            channel: 0, path: "test.MP4", fileSize: nil, kind: .video,
            referenceCamera: withDistortion, mp4Info: nil
        )

        let proj1 = OrbiCameraProjection(source: source1)
        let proj2 = OrbiCameraProjection(source: source2)

        // Use a direction slightly off-center to see distortion effect
        let dir = OrbiVec3(x: 0.3, y: 0, z: 0.95)
        let result1 = proj1.uv(for: dir)
        let result2 = proj2.uv(for: dir)

        XCTAssertNotNil(result1)
        XCTAssertNotNil(result2)
        // Distortion should shift the UV coordinates
        XCTAssertNotEqual(result1?.uv.x ?? 0, result2?.uv.x ?? 1, accuracy: 0.001)
    }
}
