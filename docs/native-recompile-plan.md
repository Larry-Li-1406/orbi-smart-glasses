# Native Recompile Plan

The APK contains an Android ARM64 ELF library at
`apk_unpacked/lib/arm64-v8a/libstitchcore.so`. It cannot be linked into an iOS app
because iOS requires Mach-O binaries built for Apple platforms and App Store rules
do not allow loading that Android ELF binary.

What was recovered:

- Xamarin imports every native symbol from `DllImport("stitchcore")`.
- The public ABI is now captured in
  `Orbi360iOS/Orbi360iOS/Native/stitchcore_compat.h`.
- A compileable replacement implementation is in
  `Orbi360iOS/Orbi360iOS/Native/stitchcore_compat.c`.

Current replacement status:

- Player state, viewpoint, timeline state, trim, follow mode, and stabilization
  APIs keep internal iOS-side state and return the same status shapes as the old
  app expected.
- TCP device control is implemented in Swift against the recovered ORBI protocol:
  `192.168.2.1:8080`, JSON commands, delimiter `\r\n\r\n`.
- A minimal Swift NFSv3 client now implements portmapper lookup, mount, lookup,
  getattr, read, readdirplus, remove, and rmdir against the glasses. Media
  transfer downloads the full remote media directory into an iOS raw bundle.
- AVFoundation thumbnail generation is wired for local playable media files.
- Raw live preview, stitch/export, and object tracking are preserved as function
  entry points but still need real iOS implementations.

Next native work:

1. Validate the Swift NFSv3 client against real ORBI hardware and adjust mount
   export paths if a firmware variant exports a different root.
2. Implement the ORBI raw bundle parser used by `.CFG` and the camera segment
   files.
3. Recreate the four-camera live preview and stitch path using Metal, or use the
   original vendor source/SDK if it is found.
