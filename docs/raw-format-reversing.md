# ORBI Raw Format Reversing Notes

Static analysis of `apk_unpacked/lib/arm64-v8a/libstitchcore.so` shows the raw
media path is built around `Serializer::readConfig`, `RawSourceFile`,
`RawPhotoSource`, `RawStreamSource`, `RawFrameSource`, `CamerasInfo`, and
`StitchTask::stitchPhoto/stitchVideo`.

Recovered config keys:

- Identity: `glassesUUID`, `videoUUID`, `imageUUID`, `mediaUUID`,
  `sessionUUID`, `deviceType`
- Sources: `sources`, `path`, `fileSize`, `chanel`
- Camera calibration: `referenceCamera`, `viewAngleX`, `viewAngleY`,
  `maxTheta`, `ppx`, `ppy`, `k1`, `k2`, `k3`, `k4`, `rotationVector`,
  `rotationMatrix`
- IMU: `helmetImu`, `imuPath`, `imuCorrection`, `horizontCorrection`,
  `imuFiles`, `startPPS`, `shutterTime`, `readout`
- Ordering: `camera_order`

The binary contains an embedded sample with four camera files:

- `PRIM0001.MP4`
- `PRIM0002.MP4`
- `PRIM0003.MP4`
- `PRIM0004.MP4`

iOS implementation status:

- `OrbiRawBundleParser.swift` parses JSON/embedded JSON/key-value config and
  falls back to filesystem and file magic scanning.
- `OrbiSoftwareStitcher.swift` can produce a stitched photo output from multiple
  camera JPG sources using equirectangular reverse mapping.
- Camera `rotationVector`, `viewAngleX`, `viewAngleY`, `maxTheta`, optical
  center, and radial distortion `k1-k4` now participate in photo sampling.

Still missing:

- Exact handling of video raw segments and muxed metadata.
- Dynamic seam blending and multiband blending equivalent to the old OpenGL
  implementation.
- IMU stabilization equivalent to `GlassesIMUUtils`, `HelmetImuUtils`, and
  `StitchTask::stabilize`.
