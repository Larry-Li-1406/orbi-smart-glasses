import Foundation

struct OrbiVec2 {
    let x: Double
    let y: Double
}

struct OrbiVec3 {
    let x: Double
    let y: Double
    let z: Double

    static func fromEquirectangular(x: Int, y: Int, width: Int, height: Int) -> OrbiVec3 {
        let pitch = (0.5 - Double(y) / Double(max(1, height - 1))) * .pi
        let yaw = (Double(x) / Double(max(1, width - 1)) - 0.5) * 2.0 * .pi
        let cp = cos(pitch)
        return OrbiVec3(x: cp * sin(yaw), y: sin(pitch), z: cp * cos(yaw))
    }
}

struct OrbiMat3 {
    let m: [Double]

    static let identity = OrbiMat3(m: [
        1, 0, 0,
        0, 1, 0,
        0, 0, 1
    ])

    static func rotationVector(_ values: [Double]) -> OrbiMat3 {
        guard values.count == 3 else { return .identity }
        let x = values[0]
        let y = values[1]
        let z = values[2]
        let theta = sqrt(x * x + y * y + z * z)
        guard theta > 0.000001 else { return .identity }
        let kx = x / theta
        let ky = y / theta
        let kz = z / theta
        let c = cos(theta)
        let s = sin(theta)
        let v = 1.0 - c
        return OrbiMat3(m: [
            kx * kx * v + c, kx * ky * v - kz * s, kx * kz * v + ky * s,
            ky * kx * v + kz * s, ky * ky * v + c, ky * kz * v - kx * s,
            kz * kx * v - ky * s, kz * ky * v + kx * s, kz * kz * v + c
        ])
    }

    func transposedMultiply(_ vector: OrbiVec3) -> OrbiVec3 {
        OrbiVec3(
            x: m[0] * vector.x + m[3] * vector.y + m[6] * vector.z,
            y: m[1] * vector.x + m[4] * vector.y + m[7] * vector.z,
            z: m[2] * vector.x + m[5] * vector.y + m[8] * vector.z
        )
    }
}

struct OrbiCameraProjection {
    let source: OrbiRawBundle.CameraSource
    let rotation: OrbiMat3
    let horizontalFOV: Double
    let verticalFOV: Double
    let calibration: OrbiRawBundle.CameraCalibration?

    init(source: OrbiRawBundle.CameraSource) {
        self.source = source
        let calibration = source.referenceCamera
        self.calibration = calibration
        self.rotation = OrbiMat3.rotationVector(calibration?.rotationVector ?? [])
        self.horizontalFOV = calibration?.viewAngleX ?? (2.0 * .pi / 3.0)
        self.verticalFOV = calibration?.viewAngleY ?? (2.0 * .pi / 3.0)
    }

    func uv(for direction: OrbiVec3) -> (uv: OrbiVec2, score: Double)? {
        let local = rotation.transposedMultiply(direction)
        guard local.z > 0 else { return nil }
        let angleX = atan2(local.x, local.z)
        let angleY = atan2(local.y, sqrt(local.x * local.x + local.z * local.z))
        let halfX = horizontalFOV / 2.0
        let halfY = verticalFOV / 2.0
        guard abs(angleX) <= halfX, abs(angleY) <= halfY else { return nil }
        let uv = distortedUV(angleX: angleX, angleY: angleY)
        guard uv.x >= 0, uv.x <= 1, uv.y >= 0, uv.y <= 1 else { return nil }
        return (uv, local.z)
    }

    private func distortedUV(angleX: Double, angleY: Double) -> OrbiVec2 {
        guard let calibration else {
            return OrbiVec2(
                x: 0.5 + angleX / horizontalFOV,
                y: 0.5 - angleY / verticalFOV
            )
        }
        let theta = sqrt(angleX * angleX + angleY * angleY)
        let maxTheta = max(0.0001, calibration.maxTheta ?? max(horizontalFOV, verticalFOV) / 2.0)
        let normalized = theta / maxTheta
        let r2 = normalized * normalized
        let radial = normalized
            * (1.0
                + (calibration.k1 ?? 0) * r2
                + (calibration.k2 ?? 0) * r2 * r2
                + (calibration.k3 ?? 0) * r2 * r2 * r2
                + (calibration.k4 ?? 0) * r2 * r2 * r2 * r2)
        let directionScale = theta > 0.000001 ? radial / theta : 0
        let centerX = calibration.ppx ?? 0.5
        let centerY = calibration.ppy ?? 0.5
        return OrbiVec2(
            x: centerX + angleX * directionScale * 0.5,
            y: centerY - angleY * directionScale * 0.5
        )
    }
}
