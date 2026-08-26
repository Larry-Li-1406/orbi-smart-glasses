#ifndef STITCHCORE_COMPAT_H
#define STITCHCORE_COMPAT_H

#include <stdbool.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef enum {
    MediaFileTypeEmpty = 0,
    MediaFileTypeVideo = 1,
    MediaFileTypePhoto = 2,
    MediaFileTypeAudioFile = 4,
    MediaFileTypeStream = 8,
    MediaFileTypePanorama = 16,
    MediaFileTypeRaw = 32,
    MediaFileTypeVideoStream = 9,
    MediaFileTypeRawStream = 57,
    MediaFileTypeVideo360 = 17,
    MediaFileTypePhoto360 = 18,
    MediaFileTypeRawVideo = 49,
    MediaFileTypeRawPhoto = 50,
    MediaFileTypeUnknown = 512
} MediaFileType;

typedef enum {
    OutProjectionTypeEquirect = 0,
    OutProjectionTypePlain = 1,
    OutProjectionTypeLittlePlanet = 2,
    OutProjectionTypeMixed = 3
} OutProjectionType;

typedef enum {
    PovTypePovFree = 0,
    PovTypeRotationTrackObject = 1,
    PovTypeRotationTrackCompass = 2,
    PovTypeRotationLookHere = 4,
    PovTypeRotation = 7,
    PovTypeProjectionProjection = 8,
    PovTypeProjectionZoom = 16,
    PovTypeProjection = 24,
    PovTypePovAny = 31
} PovType;

typedef enum {
    MediaCompletionSuccess = 0,
    MediaCompletionNotReady = 1,
    MediaCompletionInvalidParam = 2,
    MediaCompletionGeneralError = 3,
    MediaCompletionNotFound = 4,
    MediaCompletionNotImplemented = 5,
    MediaCompletionHwNotFound = 6,
    MediaCompletionEOS = 7,
    MediaCompletionInvalidStreams = 8,
    MediaCompletionInvalidState = 9,
    MediaCompletionGetFrameTimeout = 10,
    MediaCompletionMuxerError = 11,
    MediaCompletionDeMuxerError = 12,
    MediaCompletionFrameDropped = 13,
    MediaCompletionEncoderError = 14,
    MediaCompletionInitNotCompleted = 15,
    MediaCompletionOutOfLimits = 16,
    MediaCompletionGLError = 17,
    MediaCompletionChannelsOutOfSync = 18,
    MediaCompletionSuspended = 19
} MediaCompletion;

typedef enum {
    SeekModeTargetFrame = 0,
    SeekModeSyncBefore = 1,
    SeekModeSyncAfter = 2,
    SeekModeFast = 3,
    SeekModeForceFrame = 4,
    SeekModeNoSeek = 5
} SeekMode;

typedef enum {
    PlayerErrorsSuccess = 0,
    PlayerErrorsOpenSourceError = 1,
    PlayerErrorsFunctionOrderError = 2,
    PlayerErrorsPlayerExceptionError = 3,
    PlayerErrorsUnknowExceptionError = 4,
    PlayerErrorsParametersError = 5,
    PlayerErrorsTrackError = 6,
    PlayerErrorsThreadError = 7
} PlayerErrors;

typedef enum {
    PlaybackStatePause = 0,
    PlaybackStatePlay = 1
} PlaybackState;

typedef enum {
    PlayerFollowModeFollowUserValue = 0,
    PlayerFollowModeFollowPovCalculation = 1,
    PlayerFollowModeFollowPovPanoram = 2
} PlayerFollowMode;

typedef enum {
    PlayerGlassCameraLeftBack = 0,
    PlayerGlassCameraLeftFront = 1,
    PlayerGlassCameraRightFront = 2,
    PlayerGlassCameraRightBack = 3
} PlayerGlassCamera;

typedef enum {
    StabilizationModeNone = 0,
    StabilizationModeHorizon = 1,
    StabilizationModeFull = 2
} StabilizationMode;

typedef enum {
    StitchCompletionSuccess = 0,
    StitchCompletionOpenGLError = 1,
    StitchCompletionUnknownExceptionError = 2,
    StitchCompletionFileSystemError = 3,
    StitchCompletionImageFormatError = 4,
    StitchCompletionReadThumbnailsError = 5,
    StitchCompletionAborted = 6,
    StitchCompletionBadParameterError = 7,
    StitchCompletionLibPlayerError = 8,
    StitchCompletionImuDataReadingError = 9,
    StitchCompletionConfigError = 10,
    StitchCompletionOrbiError = 11,
    StitchCompletionStabilizationError = 12
} StitchCompletion;

typedef enum {
    ConfigOperationStatusSuccess = 0,
    ConfigOperationStatusAborted = 1,
    ConfigOperationStatusFoldersParseError = 2,
    ConfigOperationStatusConfigParseError = 3,
    ConfigOperationStatusNoDirrectoryError = 4,
    ConfigOperationStatusRemoteFileSystemError = 5,
    ConfigOperationStatusLocalFIleSystemError = 6,
    ConfigOperationStatusException = 7
} ConfigOperationStatus;

typedef enum {
    NFSStatusSuccess = 0,
    NFSStatusAborted = 1,
    NFSStatusFoldersParseError = 2,
    NFSStatusConfigParseError = 3,
    NFSStatusNoDirectoryError = 4,
    NFSStatusRemoteFileSystemError = 5,
    NFSStatusLocalFileSystemError = 6,
    NFSStatusException = 7
} NFSStatus;

typedef struct {
    int32_t width;
    int32_t height;
    uint32_t streamId;
    uint32_t duration;
    uint32_t totalFrames;
    uint32_t nFPSnum;
    uint32_t nFPSden;
    MediaFileType mediaFileType;
} MediaInfo;

typedef struct {
    float yaw;
    float pitch;
    float roll;
    float zoom;
    OutProjectionType outProjection;
} DynamicPlayerParams;

typedef struct {
    PovType keyType;
    uint32_t keyFrame;
    uint32_t endFrame;
} EditorKeyInfo;

typedef struct {
    MediaCompletion mediaReaderError;
    PlayerErrors playerError;
} PlayerErrorStatus;

typedef struct {
    MediaCompletion readerError;
    MediaCompletion writerError;
    StitchCompletion stitchError;
} StitchStatus;

typedef void (*ManagedLoggerCallback)(int32_t level, const char *category, const char *filename, int32_t line, const char *message);
typedef uint64_t (*GLContextIdCallback)(void);

void Logging_initWithManagedLogCallback(ManagedLoggerCallback callback);

ConfigOperationStatus ConfigLibrary_savePixmap(const char *savePath, const char *configFilePath, MediaFileType fileType, int32_t width, int32_t height);
ConfigOperationStatus ConfigLibrary_removeConfigDir(const char *configFilePath);
NFSStatus ConfigLibrary_uploadFileToNfsRun(const char *nfsPath, const char *sourcePath);
NFSStatus ConfigLibrary_downloadFileFromNfsRun(const char *nfsPath, const char *targetPath);
NFSStatus ConfigLibrary_downloadFolderFromNfsRun(const char *nfsPath, const char *targetPath);
void ConfigLibrary_uploadFileToNfsAbort(void);
float ConfigLibrary_uploadFileToNfsProgress(void);
NFSStatus ConfigLibrary_fileSize(const char *nfsPath, uint64_t *size);
NFSStatus ConfigLibrary_deleteFileFromNfs(const char *path);

MediaCompletion MI_syncSetSuspend(bool pause);
MediaCompletion MO_syncSetSuspend(bool pause);

MediaInfo MediaEditor_static_mediaInfo(const char *path);
PlayerErrorStatus MediaEditor_static_saveThumbnails(const char *mediaPath, const char *thumbnailsPath, int32_t width, int32_t height, int64_t frameNumber);
PlayerErrorStatus MediaEditor_createInstance(void);
PlayerErrorStatus MediaEditor_deleteInstance(void);

void StitchLib_createInstance(void);
void StitchLib_deleteInstance(void);
void StitchLib_openThread(void);
void StitchLib_closeThread(void);
StitchStatus StitchLib_getStatus(void);
void StitchLib_stitch(const char *jsonSettings, const char *configPath, const char *outputFile, int32_t startFrame, int32_t endFrame);
float StitchLib_progress(void);
void StitchLib_pause(bool pause);
void StitchLib_abort(void);
void StitchLib_export(void *sample, const char *outputFile, int32_t frameWidth, int32_t frameHeight, bool isPanoram);
void StitchLib_setGlContextCallback(GLContextIdCallback callback);

PlayerErrorStatus MediaPlayer_mediaInfo(MediaInfo *mediaInfo);
PlayerErrorStatus MediaPlayer_openVideoFile(const char *fileName);
PlayerErrorStatus MediaPlayer_openRawVideoFile(const char *fileName);
PlayerErrorStatus MediaPlayer_openPhoto(const char *fileName);
PlayerErrorStatus MediaPlayer_openStream(const char *ip, int32_t port1, int32_t port2, int32_t port3, int32_t port4, const char *configJson);
PlayerErrorStatus MediaPlayer_close(void);
PlayerErrorStatus MediaPlayer_closeAndSaveState(void);
PlayerErrorStatus MediaPlayer_restoreStateAndOpen(void);
PlayerErrorStatus MediaPlayer_resetRenderer(void);
PlayerErrorStatus MediaPlayer_resize(int32_t width, int32_t height);
PlayerErrorStatus MediaPlayer_setViewPointAbs(float yaw, float pitch, float roll);
PlayerErrorStatus MediaPlayer_changeViewPoint(float horizontal, float vertical);
PlayerErrorStatus MediaPlayer_setScale(float scale);
PlayerErrorStatus MediaPlayer_setDynamicParams(DynamicPlayerParams playerParams);
PlayerErrorStatus MediaPlayer_render(void);
PlayerErrorStatus MediaPlayer_update(void);
PlayerErrorStatus MediaPlayer_setFrame(uint32_t frame, SeekMode seekMode);
PlayerErrorStatus MediaPlayer_currentFrame(uint32_t *frame);
PlayerErrorStatus MediaPlayer_checkKeyFrame(uint32_t frame, bool *result);
PlayerErrorStatus MediaPlayer_getNearestKeyFrame(uint32_t frame, bool beforeThis, uint32_t *result);
PlayerErrorStatus MediaPlayer_setSuspend(bool flag);
PlayerErrorStatus MediaPlayer_setPlaybackState(PlaybackState state);
PlayerErrorStatus MediaPlayer_playbackState(PlaybackState *state);
PlayerErrorStatus MediaPlayer_initTimeline(void);
PlayerErrorStatus MediaPlayer_resizeTimeline(int32_t width, int32_t height);
PlayerErrorStatus MediaPlayer_prepareTimeline(float startFrame);
PlayerErrorStatus MediaPlayer_renderTimeline(void);
PlayerErrorStatus MediaPlayer_resetTimeline(void);
PlayerErrorStatus MediaPlayer_setTimelineFrameWidth(float width);
PlayerErrorStatus MediaPlayer_setCurrentCamera(PlayerGlassCamera camera);
PlayerErrorStatus MediaPlayer_getSample(void **sample);
PlayerErrorStatus MediaPlayer_loadProject(const char *path);
PlayerErrorStatus MediaPlayer_saveProject(const char *path);
PlayerErrorStatus MediaPlayer_setTrim(uint32_t startFrame, uint32_t finishFrame);
PlayerErrorStatus MediaPlayer_getTrim(uint32_t *startFrame, uint32_t *finishFrame);
PlayerErrorStatus MediaPlayer_followMode(PlayerFollowMode *followMode);
PlayerErrorStatus MediaPlayer_setFollowMode(PlayerFollowMode followMode);
PlayerErrorStatus MediaPlayer_calcPoint(uint32_t frame, DynamicPlayerParams *result);
PlayerErrorStatus MediaPlayer_calcScreenRotation(float x, float y, DynamicPlayerParams *result);
PlayerErrorStatus MediaPlayer_pointStatus(uint32_t frame, EditorKeyInfo *keyInfo);
PlayerErrorStatus MediaPlayer_getProjectKeysCount(PovType type, int32_t *count);
PlayerErrorStatus MediaPlayer_getProjectKeys(PovType type, int32_t count, void *keysArray);
PlayerErrorStatus MediaPlayer_clearPoints(PovType type);
PlayerErrorStatus MediaPlayer_deleteKeys(uint32_t frame, PovType type);
PlayerErrorStatus MediaPlayer_addProjectionPoint(uint32_t frame, OutProjectionType projection);
PlayerErrorStatus MediaPlayer_addZoomPoint(uint32_t frame, float zoom);
PlayerErrorStatus MediaPlayer_addLookHere(uint32_t frame, float x, float y);
PlayerErrorStatus MediaPlayer_fixPov(void);
bool MediaPlayer_isTracking(void);
PlayerErrorStatus MediaPlayer_startObjectTracking(float x, float y);
void MediaPlayer_stopObjectTracking(void);
PlayerErrorStatus MediaPlayer_stabilizationMode(StabilizationMode *stabMode);
PlayerErrorStatus MediaPlayer_setStabilizationMode(StabilizationMode stabMode);
PlayerErrorStatus MediaPlayer_saveScreen(const char *fileName, int32_t frameWidth, int32_t frameHeight, OutProjectionType projection);
PlayerErrorStatus MediaPlayer_currentPov(DynamicPlayerParams *result);

#ifdef __cplusplus
}
#endif

#endif
