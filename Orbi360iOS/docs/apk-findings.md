# APK Findings

Source artifact:

- `Orbi 360_1.5.1_APKPure.apk`
- Version timestamp inside APK: June 2020
- Package indicated by assembly activity names: `com.orbi.orbi360`
- Framework: Xamarin.Android / Mono

Useful files found after unpacking:

- `assemblies/OrbiApp.dll`: shared app logic, about 38 MB
- `assemblies/OrbiApp.Droid.dll`: Android platform layer
- `res/layout/*`: Android binary XML layouts
- `res/drawable/*`: UI icons for capture, media, editor, battery, running modes
- `lib/arm64-v8a/*`: native Android media and stitching libraries

View and view-model names visible from strings:

- `MainViewModel`
- `ConnectionLobbyViewModel`
- `HowToConnectViewModel`
- `DeviceControlViewModel`
- `MediaCollectionViewModel`
- `MediaViewModel`
- `PhotoItemViewModel`
- `SettingsWiFiSettingsViewModel`
- `FirmwareUpdateViewModel`
- `FirmwareUpdateProcessViewModel`
- `EditorProjectViewModel`
- `EditorExportViewModel`
- `RawPlayerViewModel`

Main layouts:

- `connection_lobby.xml`
- `glasses_fragment.xml`
- `live_preview_fragment.xml`
- `media_fragment.xml`
- `photo_fragment.xml`
- `video_fragment.xml`
- `wifi_settings_fragment.xml`
- `video_editor_activity.xml`
- `photo_viewer_activity.xml`
- `settings_activity.xml`
- `firmware_update_activity.xml`
- `request_support_fragment.xml`

Feature strings visible from resources:

- `Connect to Device`
- `On the smartphone's WiFi setting screen select the glasses SSID and enter the password.`
- `Video recording`
- `1, 2...`
- `SNAP!`
- `RECORD!`
- `Done!`
- `Running mode`
- `Name`, `Password`, `Verify`

Native media stack:

- FFmpeg libraries
- Qt libraries
- `libstitchcore.so`
- OpenH264, FAAC/FAAD, libyuv, turbojpeg

Recovered protocol:

- TCP endpoint: `192.168.2.1:8080`
- Local/live base port: `5000`
- Command delimiter: `\r\n\r\n`
- Command envelope: `{"id":N,"cmd":"..."}`
- Response envelope includes `id`, `result`, `dev-uuid`, `firmware-version`, `mode`, `run`, `charger`, `SD_card`, `images`, and `videos`.
- Remote media path: `nfs://192.168.2.1/run/RTOS/DCIM/{media}/{media}.CFG`

Important commands:

- `get_info`
- `get-status`
- `get_media_list`
- `mode` with `shot`, `live`, or `record`
- `start`
- `stop`
- `save`
- `set-wifi`
- `format-sd`
- `nfs-transfer`
- `start-firmware-update`

Remaining blocker:

- Native Android media libraries cannot be reused on iOS. File transfer, stitching, and rendering need iOS-native implementations or original native source rebuilt for iOS.
