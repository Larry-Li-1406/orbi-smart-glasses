# ORBI Raw Media Notes

The Android app delegates raw ORBI media handling to `libstitchcore.so`. The recovered
symbols and strings show that the native library reads a `.CFG` file next to each media
directory, opens multiple MP4/JPG camera sources, applies camera calibration, uses IMU
data, and writes a stitched 360 output.

## Recovered Config Fields

Observed keys in the Android binary include:

- Media identifiers: `glassesUUID`, `mediaUUID`, `videoUUID`, `imageUUID`, `sessionUUID`, `deviceType`
- Sources: `sources`, `chanel`, `fileSize`
- Camera model: `referenceCamera`, `viewAngleX`, `viewAngleY`, `maxTheta`, `ppx`, `ppy`, `k1`, `k2`, `k3`, `k4`
- Orientation: `rotationVector`, `rotationMatrix`, `camera_order`
- IMU/timing: `helmetImu`, `imuPath`, `imuFiles`, `imuCorrection`, `horizontCorrection`, `startPPS`, `shutterTime`, `readout`

Embedded default source names in `libstitchcore.so` include `PRIM0001.MP4` through
`PRIM0004.MP4`, plus sidecar files such as `PRIM0001.BIN` and `PRIM0001.THM`.

## iOS Implementation State

- `OrbiRawBundleParser.swift` reads CFG JSON or loose key/value configs and scans the
  downloaded raw directory for missing camera files.
- `OrbiMP4Inspector.swift` parses MP4 atom metadata without loading full video files
  into memory. It records major brand, compatible brands, video/audio tracks, codec,
  dimensions, duration, timescale, and spherical metadata hints.
- `OrbiProjection.swift` holds the shared equirectangular projection, rotation vector,
  field-of-view, and radial distortion logic used by both photo and video stitching.
- `OrbiSoftwareStitcher.swift` creates stitched JPEG output from multiple raw camera
  photos using recovered camera calibration fields.
- `OrbiMetalVideoStitcher.swift` is the primary video export path. It compiles a
  Metal stitch kernel at runtime, samples up to four BGRA source frame textures with
  linear filtering, blends near-seam candidates when camera scores are close, and
  writes a 1920x960 equirectangular H.264 MP4.
- `OrbiCoreImageVideoStitcher.swift` is the first GPU path. It uses a Core Image
  kernel to map output equirectangular pixels back into up to four source MP4 frames,
  then writes H.264 through `AVAssetWriter`. It remains as a GPU fallback for devices
  or captures where the Metal path cannot run.
- `OrbiVideoStitcher.swift` reads up to four MP4 camera sources with `AVAssetReader`,
  maps each frame through the shared projection model on the CPU, and writes a
  1920x960 equirectangular H.264 MP4 with `AVAssetWriter`.
- `OrbiVideoPreviewExporter.swift` remains as a synchronized 2x2 MP4 fallback when
  full stitch export fails on a raw capture.
- `OrbiStitchService.swift` saves `orbi-ios-raw-manifest.json` beside downloaded raw
  bundles so real-device captures can be inspected and compared against the recovered
  Android format.

## Remaining Video Parity Work

The Android native library contains stitcher classes such as `StitchTask::stitchVideo`,
`RawStreamSource`, `MultiSourceMovie`, `CMP4Demuxer`, `CMP4MuxerRtp`, seam estimation,
and GPU projection shaders. The iOS stitcher now has the same high-level data flow,
a Metal implementation with seam blending, a Core Image fallback, and a CPU fallback.
The remaining production work is empirical: test real ORBI captures, tune seam weights
and calibration assumptions, then replace the runtime Metal source string with a
bundled `.metal` library when full Xcode tooling is available.
