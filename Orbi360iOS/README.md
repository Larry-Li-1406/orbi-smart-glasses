# ORBI 360 iOS Port

This is a SwiftUI iOS port rebuilt from the legacy `Orbi 360_1.5.1_APKPure.apk`.

The Android app was decoded with `apktool` and decompiled with ILSpy. It is a Xamarin.Android app. The original source was not present, but the C# assemblies were recoverable enough to map the UI, navigation, device protocol, model names, and service behavior.

## What Was Recreated

- Main structure matches the Android app:
  - Bottom navigation: `Shoot`, `Media`, `Settings`
  - Shoot section tabs: `Photo`, `Live`, `Video`
  - Connection lobby shown when no device is connected
  - Media toolbar, photo/video tabs, grid/list media views
  - Settings for firmware info, running mode, Wi-Fi, SD format, support, and legal links
- Styling follows decoded Android resources:
  - Primary color `#01A4D3`
  - 56dp bottom navigation and top bars
  - 70dp media thumbnails
  - Blue photo/video capture screens
  - Black live preview/editor surfaces with floating 50dp controls
- Device command protocol has been ported:
  - TCP endpoint: `192.168.2.1:8080`
  - Message delimiter: `\r\n\r\n`
  - JSON commands use `id` and `cmd`
  - Commands implemented in Swift: `get-status`, `get_media_list`, `mode`, `start`, `stop`, `set-wifi`, `format-sd`, `nfs-transfer`
- Media transfer now has an iOS-native NFSv3 path:
  - RPC portmapper lookup
  - NFS mount, lookup, getattr, read, readdirplus, remove, and rmdir
  - Full remote media directories are downloaded into `Documents/ORBI 360 Raw`
  - ORBI `.CFG` raw bundles are parsed for UUIDs, camera sources, camera calibration,
    IMU paths, and camera order
  - Raw photo bundles with multiple camera images are stitched into a 360 JPEG with
    an iOS-native CoreGraphics stitcher
  - Raw video bundles with multiple MP4 camera sources are stitched into a 1920x960
    equirectangular H.264 MP4. Export tries a runtime-compiled Metal stitch kernel
    with seam blending first, falls back to a Core Image GPU kernel, then the CPU
    AVAssetReader/Writer stitcher, then a synchronized 2x2 preview MP4 if full stitch
    export fails
  - Single ready-to-play MP4/JPG downloads are copied into `Documents/ORBI 360` and
    thumbnailed with AVFoundation
- Live preview constants were mapped:
  - Device IP `192.168.2.1`
  - Stream ports `5000`, `5002`, `5004`, `5006`
- Remote media paths match the Android code:
  - `nfs://192.168.2.1/run/RTOS/DCIM/...`

## Remaining Native Work

The Android app depends on native `.so` libraries for NFS transfer, stitching, playback, and rendering:

- `libstitchcore.so`
- FFmpeg libraries
- Qt libraries
- OpenH264, FAAC/FAAD, libyuv, turbojpeg

Those Android binaries cannot run on iOS. The Swift project now has the original protocol, UI structure, an iOS NFS transfer implementation, raw bundle parsing, software photo stitching, Metal/Core Image/CPU video stitching, seam blending, and raw video preview fallback. Production parity still needs real-device tuning against ORBI captures:

- Replace the runtime Metal kernel string with a bundled `.metal` library when full
  Xcode tooling is available
- Tune stitch calibration and seam weights with real ORBI captures
- AVFoundation/Metal renderer for 360 playback and live preview
- Firmware upload transport matching the original native transfer behavior

## Open In Xcode

```sh
open /Users/bendizhanghu/Desktop/代码/orbi智能眼镜\ /Orbi360iOS/Orbi360iOS.xcodeproj
```

Run the `Orbi360iOS` target on an iPhone or simulator. If the glasses hotspot is not reachable, the app falls back to a demo status so the recreated UI can still be inspected.
