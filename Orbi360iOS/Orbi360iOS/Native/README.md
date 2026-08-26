# stitchcore compatibility layer

The Android app loads `libstitchcore.so` through Xamarin `DllImport("stitchcore")`.
That ELF binary cannot be recompiled for iOS without the original C/C++ sources, so
this directory keeps the recovered ABI as an iOS-native replacement point.

`stitchcore_compat.h` mirrors the structs, enums, callbacks, and exported function
names recovered from the Android assemblies. `stitchcore_compat.c` currently
provides a compileable stateful shim: simple player state operations succeed,
network/NFS and media export operations return explicit not-implemented or
filesystem/network errors instead of pretending to work.

Implementation targets:

- Replace NFS placeholders with an iOS-compatible NFS client for
  `nfs://192.168.2.1/run/RTOS/DCIM/...`.
- Replace media information and thumbnail placeholders with AVFoundation image
  extraction for local downloaded files.
- Replace live/raw playback and stitch/export functions with Metal/AVFoundation
  rendering or a recovered vendor SDK if the original source becomes available.
