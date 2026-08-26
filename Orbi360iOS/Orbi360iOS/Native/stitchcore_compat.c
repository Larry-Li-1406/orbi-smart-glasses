#include "stitchcore_compat.h"

#include <stddef.h>
#include <string.h>

typedef struct {
    bool hasInstance;
    bool isOpen;
    bool isPlaying;
    bool isSuspended;
    bool isTracking;
    bool stitchAborted;
    float progress;
    uint32_t currentFrame;
    uint32_t trimStart;
    uint32_t trimEnd;
    PlaybackState playbackState;
    PlayerFollowMode followMode;
    StabilizationMode stabilizationMode;
    DynamicPlayerParams currentPov;
    ManagedLoggerCallback logger;
    GLContextIdCallback glContextCallback;
    MediaInfo mediaInfo;
} OrbiStitchCoreState;

static OrbiStitchCoreState gState = {
    .playbackState = PlaybackStatePause,
    .followMode = PlayerFollowModeFollowUserValue,
    .stabilizationMode = StabilizationModeNone,
    .currentPov = {0.0f, 0.0f, 0.0f, 1.0f, OutProjectionTypeEquirect},
    .mediaInfo = {3840, 1920, 0, 0, 0, 30, 1, MediaFileTypeUnknown}
};

static PlayerErrorStatus playerStatus(PlayerErrors playerError)
{
    PlayerErrorStatus status = {MediaCompletionSuccess, playerError};
    return status;
}

static PlayerErrorStatus playerNotImplemented(void)
{
    PlayerErrorStatus status = {MediaCompletionNotImplemented, PlayerErrorsFunctionOrderError};
    return status;
}

static StitchStatus stitchStatus(StitchCompletion completion)
{
    StitchStatus status = {MediaCompletionSuccess, MediaCompletionSuccess, completion};
    return status;
}

static bool hasText(const char *value)
{
    return value != NULL && value[0] != '\0';
}

void Logging_initWithManagedLogCallback(ManagedLoggerCallback callback)
{
    gState.logger = callback;
}

ConfigOperationStatus ConfigLibrary_savePixmap(const char *savePath, const char *configFilePath, MediaFileType fileType, int32_t width, int32_t height)
{
    (void)fileType;
    if (!hasText(savePath) || !hasText(configFilePath) || width <= 0 || height <= 0) {
        return ConfigOperationStatusConfigParseError;
    }
    return ConfigOperationStatusLocalFIleSystemError;
}

ConfigOperationStatus ConfigLibrary_removeConfigDir(const char *configFilePath)
{
    return hasText(configFilePath) ? ConfigOperationStatusSuccess : ConfigOperationStatusNoDirrectoryError;
}

NFSStatus ConfigLibrary_uploadFileToNfsRun(const char *nfsPath, const char *sourcePath)
{
    if (!hasText(nfsPath) || !hasText(sourcePath)) {
        return NFSStatusConfigParseError;
    }
    return NFSStatusRemoteFileSystemError;
}

NFSStatus ConfigLibrary_downloadFileFromNfsRun(const char *nfsPath, const char *targetPath)
{
    if (!hasText(nfsPath) || !hasText(targetPath)) {
        return NFSStatusConfigParseError;
    }
    return NFSStatusRemoteFileSystemError;
}

NFSStatus ConfigLibrary_downloadFolderFromNfsRun(const char *nfsPath, const char *targetPath)
{
    if (!hasText(nfsPath) || !hasText(targetPath)) {
        return NFSStatusConfigParseError;
    }
    return NFSStatusRemoteFileSystemError;
}

void ConfigLibrary_uploadFileToNfsAbort(void)
{
}

float ConfigLibrary_uploadFileToNfsProgress(void)
{
    return 0.0f;
}

NFSStatus ConfigLibrary_fileSize(const char *nfsPath, uint64_t *size)
{
    if (size != NULL) {
        *size = 0;
    }
    return hasText(nfsPath) ? NFSStatusRemoteFileSystemError : NFSStatusConfigParseError;
}

NFSStatus ConfigLibrary_deleteFileFromNfs(const char *path)
{
    return hasText(path) ? NFSStatusRemoteFileSystemError : NFSStatusConfigParseError;
}

MediaCompletion MI_syncSetSuspend(bool pause)
{
    gState.isSuspended = pause;
    return MediaCompletionSuccess;
}

MediaCompletion MO_syncSetSuspend(bool pause)
{
    gState.isSuspended = pause;
    return MediaCompletionSuccess;
}

MediaInfo MediaEditor_static_mediaInfo(const char *path)
{
    MediaInfo info = gState.mediaInfo;
    if (!hasText(path)) {
        info.mediaFileType = MediaFileTypeUnknown;
    } else if (strstr(path, ".JPG") || strstr(path, ".jpg")) {
        info.mediaFileType = MediaFileTypePhoto360;
    } else {
        info.mediaFileType = MediaFileTypeVideo360;
    }
    return info;
}

PlayerErrorStatus MediaEditor_static_saveThumbnails(const char *mediaPath, const char *thumbnailsPath, int32_t width, int32_t height, int64_t frameNumber)
{
    (void)frameNumber;
    if (!hasText(mediaPath) || !hasText(thumbnailsPath) || width <= 0 || height <= 0) {
        return playerStatus(PlayerErrorsParametersError);
    }
    return playerNotImplemented();
}

PlayerErrorStatus MediaEditor_createInstance(void)
{
    gState.hasInstance = true;
    return playerStatus(PlayerErrorsSuccess);
}

PlayerErrorStatus MediaEditor_deleteInstance(void)
{
    gState.hasInstance = false;
    gState.isOpen = false;
    return playerStatus(PlayerErrorsSuccess);
}

void StitchLib_createInstance(void)
{
    gState.hasInstance = true;
}

void StitchLib_deleteInstance(void)
{
    gState.hasInstance = false;
}

void StitchLib_openThread(void)
{
}

void StitchLib_closeThread(void)
{
}

StitchStatus StitchLib_getStatus(void)
{
    if (gState.stitchAborted) {
        return stitchStatus(StitchCompletionAborted);
    }
    if (gState.progress >= 1.0f) {
        return stitchStatus(StitchCompletionSuccess);
    }
    return stitchStatus(StitchCompletionSuccess);
}

void StitchLib_stitch(const char *jsonSettings, const char *configPath, const char *outputFile, int32_t startFrame, int32_t endFrame)
{
    (void)jsonSettings;
    (void)configPath;
    (void)outputFile;
    gState.stitchAborted = false;
    gState.progress = (endFrame >= startFrame) ? 0.01f : 0.0f;
}

float StitchLib_progress(void)
{
    return gState.progress;
}

void StitchLib_pause(bool pause)
{
    gState.isSuspended = pause;
}

void StitchLib_abort(void)
{
    gState.stitchAborted = true;
}

void StitchLib_export(void *sample, const char *outputFile, int32_t frameWidth, int32_t frameHeight, bool isPanoram)
{
    (void)sample;
    (void)outputFile;
    (void)frameWidth;
    (void)frameHeight;
    (void)isPanoram;
}

void StitchLib_setGlContextCallback(GLContextIdCallback callback)
{
    gState.glContextCallback = callback;
}

PlayerErrorStatus MediaPlayer_mediaInfo(MediaInfo *mediaInfo)
{
    if (mediaInfo == NULL) {
        return playerStatus(PlayerErrorsParametersError);
    }
    *mediaInfo = gState.mediaInfo;
    return playerStatus(PlayerErrorsSuccess);
}

PlayerErrorStatus MediaPlayer_openVideoFile(const char *fileName)
{
    if (!hasText(fileName)) {
        return playerStatus(PlayerErrorsOpenSourceError);
    }
    gState.isOpen = true;
    gState.mediaInfo.mediaFileType = MediaFileTypeVideo360;
    return playerStatus(PlayerErrorsSuccess);
}

PlayerErrorStatus MediaPlayer_openRawVideoFile(const char *fileName)
{
    if (!hasText(fileName)) {
        return playerStatus(PlayerErrorsOpenSourceError);
    }
    gState.isOpen = true;
    gState.mediaInfo.mediaFileType = MediaFileTypeRawVideo;
    return playerStatus(PlayerErrorsSuccess);
}

PlayerErrorStatus MediaPlayer_openPhoto(const char *fileName)
{
    if (!hasText(fileName)) {
        return playerStatus(PlayerErrorsOpenSourceError);
    }
    gState.isOpen = true;
    gState.mediaInfo.mediaFileType = MediaFileTypePhoto360;
    return playerStatus(PlayerErrorsSuccess);
}

PlayerErrorStatus MediaPlayer_openStream(const char *ip, int32_t port1, int32_t port2, int32_t port3, int32_t port4, const char *configJson)
{
    (void)configJson;
    if (!hasText(ip) || port1 <= 0 || port2 <= 0 || port3 <= 0 || port4 <= 0) {
        return playerStatus(PlayerErrorsOpenSourceError);
    }
    gState.isOpen = true;
    gState.mediaInfo.mediaFileType = MediaFileTypeVideoStream;
    return playerStatus(PlayerErrorsSuccess);
}

PlayerErrorStatus MediaPlayer_close(void)
{
    gState.isOpen = false;
    gState.isPlaying = false;
    return playerStatus(PlayerErrorsSuccess);
}

PlayerErrorStatus MediaPlayer_closeAndSaveState(void)
{
    return MediaPlayer_close();
}

PlayerErrorStatus MediaPlayer_restoreStateAndOpen(void)
{
    gState.isOpen = true;
    return playerStatus(PlayerErrorsSuccess);
}

PlayerErrorStatus MediaPlayer_resetRenderer(void)
{
    return playerStatus(PlayerErrorsSuccess);
}

PlayerErrorStatus MediaPlayer_resize(int32_t width, int32_t height)
{
    if (width <= 0 || height <= 0) {
        return playerStatus(PlayerErrorsParametersError);
    }
    gState.mediaInfo.width = width;
    gState.mediaInfo.height = height;
    return playerStatus(PlayerErrorsSuccess);
}

PlayerErrorStatus MediaPlayer_setViewPointAbs(float yaw, float pitch, float roll)
{
    gState.currentPov.yaw = yaw;
    gState.currentPov.pitch = pitch;
    gState.currentPov.roll = roll;
    return playerStatus(PlayerErrorsSuccess);
}

PlayerErrorStatus MediaPlayer_changeViewPoint(float horizontal, float vertical)
{
    gState.currentPov.yaw += horizontal;
    gState.currentPov.pitch += vertical;
    return playerStatus(PlayerErrorsSuccess);
}

PlayerErrorStatus MediaPlayer_setScale(float scale)
{
    if (scale <= 0.0f) {
        return playerStatus(PlayerErrorsParametersError);
    }
    gState.currentPov.zoom = scale;
    return playerStatus(PlayerErrorsSuccess);
}

PlayerErrorStatus MediaPlayer_setDynamicParams(DynamicPlayerParams playerParams)
{
    gState.currentPov = playerParams;
    return playerStatus(PlayerErrorsSuccess);
}

PlayerErrorStatus MediaPlayer_render(void)
{
    return gState.isOpen ? playerStatus(PlayerErrorsSuccess) : playerStatus(PlayerErrorsFunctionOrderError);
}

PlayerErrorStatus MediaPlayer_update(void)
{
    return playerStatus(PlayerErrorsSuccess);
}

PlayerErrorStatus MediaPlayer_setFrame(uint32_t frame, SeekMode seekMode)
{
    (void)seekMode;
    gState.currentFrame = frame;
    return playerStatus(PlayerErrorsSuccess);
}

PlayerErrorStatus MediaPlayer_currentFrame(uint32_t *frame)
{
    if (frame == NULL) {
        return playerStatus(PlayerErrorsParametersError);
    }
    *frame = gState.currentFrame;
    return playerStatus(PlayerErrorsSuccess);
}

PlayerErrorStatus MediaPlayer_checkKeyFrame(uint32_t frame, bool *result)
{
    (void)frame;
    if (result == NULL) {
        return playerStatus(PlayerErrorsParametersError);
    }
    *result = false;
    return playerStatus(PlayerErrorsSuccess);
}

PlayerErrorStatus MediaPlayer_getNearestKeyFrame(uint32_t frame, bool beforeThis, uint32_t *result)
{
    if (result == NULL) {
        return playerStatus(PlayerErrorsParametersError);
    }
    *result = beforeThis && frame > 0 ? frame - 1 : frame;
    return playerStatus(PlayerErrorsSuccess);
}

PlayerErrorStatus MediaPlayer_setSuspend(bool flag)
{
    gState.isSuspended = flag;
    return playerStatus(PlayerErrorsSuccess);
}

PlayerErrorStatus MediaPlayer_setPlaybackState(PlaybackState state)
{
    gState.playbackState = state;
    gState.isPlaying = state == PlaybackStatePlay;
    return playerStatus(PlayerErrorsSuccess);
}

PlayerErrorStatus MediaPlayer_playbackState(PlaybackState *state)
{
    if (state == NULL) {
        return playerStatus(PlayerErrorsParametersError);
    }
    *state = gState.playbackState;
    return playerStatus(PlayerErrorsSuccess);
}

PlayerErrorStatus MediaPlayer_initTimeline(void)
{
    return playerStatus(PlayerErrorsSuccess);
}

PlayerErrorStatus MediaPlayer_resizeTimeline(int32_t width, int32_t height)
{
    return (width > 0 && height > 0) ? playerStatus(PlayerErrorsSuccess) : playerStatus(PlayerErrorsParametersError);
}

PlayerErrorStatus MediaPlayer_prepareTimeline(float startFrame)
{
    return startFrame >= 0.0f ? playerStatus(PlayerErrorsSuccess) : playerStatus(PlayerErrorsParametersError);
}

PlayerErrorStatus MediaPlayer_renderTimeline(void)
{
    return playerStatus(PlayerErrorsSuccess);
}

PlayerErrorStatus MediaPlayer_resetTimeline(void)
{
    return playerStatus(PlayerErrorsSuccess);
}

PlayerErrorStatus MediaPlayer_setTimelineFrameWidth(float width)
{
    return width > 0.0f ? playerStatus(PlayerErrorsSuccess) : playerStatus(PlayerErrorsParametersError);
}

PlayerErrorStatus MediaPlayer_setCurrentCamera(PlayerGlassCamera camera)
{
    return camera >= PlayerGlassCameraLeftBack && camera <= PlayerGlassCameraRightBack ? playerStatus(PlayerErrorsSuccess) : playerStatus(PlayerErrorsParametersError);
}

PlayerErrorStatus MediaPlayer_getSample(void **sample)
{
    if (sample == NULL) {
        return playerStatus(PlayerErrorsParametersError);
    }
    *sample = NULL;
    return playerNotImplemented();
}

PlayerErrorStatus MediaPlayer_loadProject(const char *path)
{
    return hasText(path) ? playerStatus(PlayerErrorsSuccess) : playerStatus(PlayerErrorsParametersError);
}

PlayerErrorStatus MediaPlayer_saveProject(const char *path)
{
    return hasText(path) ? playerStatus(PlayerErrorsSuccess) : playerStatus(PlayerErrorsParametersError);
}

PlayerErrorStatus MediaPlayer_setTrim(uint32_t startFrame, uint32_t finishFrame)
{
    if (finishFrame < startFrame) {
        return playerStatus(PlayerErrorsParametersError);
    }
    gState.trimStart = startFrame;
    gState.trimEnd = finishFrame;
    return playerStatus(PlayerErrorsSuccess);
}

PlayerErrorStatus MediaPlayer_getTrim(uint32_t *startFrame, uint32_t *finishFrame)
{
    if (startFrame == NULL || finishFrame == NULL) {
        return playerStatus(PlayerErrorsParametersError);
    }
    *startFrame = gState.trimStart;
    *finishFrame = gState.trimEnd;
    return playerStatus(PlayerErrorsSuccess);
}

PlayerErrorStatus MediaPlayer_followMode(PlayerFollowMode *followMode)
{
    if (followMode == NULL) {
        return playerStatus(PlayerErrorsParametersError);
    }
    *followMode = gState.followMode;
    return playerStatus(PlayerErrorsSuccess);
}

PlayerErrorStatus MediaPlayer_setFollowMode(PlayerFollowMode followMode)
{
    gState.followMode = followMode;
    return playerStatus(PlayerErrorsSuccess);
}

PlayerErrorStatus MediaPlayer_calcPoint(uint32_t frame, DynamicPlayerParams *result)
{
    (void)frame;
    if (result == NULL) {
        return playerStatus(PlayerErrorsParametersError);
    }
    *result = gState.currentPov;
    return playerStatus(PlayerErrorsSuccess);
}

PlayerErrorStatus MediaPlayer_calcScreenRotation(float x, float y, DynamicPlayerParams *result)
{
    if (result == NULL) {
        return playerStatus(PlayerErrorsParametersError);
    }
    *result = gState.currentPov;
    result->yaw += x;
    result->pitch += y;
    return playerStatus(PlayerErrorsSuccess);
}

PlayerErrorStatus MediaPlayer_pointStatus(uint32_t frame, EditorKeyInfo *keyInfo)
{
    if (keyInfo == NULL) {
        return playerStatus(PlayerErrorsParametersError);
    }
    keyInfo->keyType = PovTypePovFree;
    keyInfo->keyFrame = frame;
    keyInfo->endFrame = frame;
    return playerStatus(PlayerErrorsSuccess);
}

PlayerErrorStatus MediaPlayer_getProjectKeysCount(PovType type, int32_t *count)
{
    (void)type;
    if (count == NULL) {
        return playerStatus(PlayerErrorsParametersError);
    }
    *count = 0;
    return playerStatus(PlayerErrorsSuccess);
}

PlayerErrorStatus MediaPlayer_getProjectKeys(PovType type, int32_t count, void *keysArray)
{
    (void)type;
    (void)count;
    (void)keysArray;
    return playerStatus(PlayerErrorsSuccess);
}

PlayerErrorStatus MediaPlayer_clearPoints(PovType type)
{
    (void)type;
    return playerStatus(PlayerErrorsSuccess);
}

PlayerErrorStatus MediaPlayer_deleteKeys(uint32_t frame, PovType type)
{
    (void)frame;
    (void)type;
    return playerStatus(PlayerErrorsSuccess);
}

PlayerErrorStatus MediaPlayer_addProjectionPoint(uint32_t frame, OutProjectionType projection)
{
    (void)frame;
    gState.currentPov.outProjection = projection;
    return playerStatus(PlayerErrorsSuccess);
}

PlayerErrorStatus MediaPlayer_addZoomPoint(uint32_t frame, float zoom)
{
    (void)frame;
    return MediaPlayer_setScale(zoom);
}

PlayerErrorStatus MediaPlayer_addLookHere(uint32_t frame, float x, float y)
{
    (void)frame;
    gState.currentPov.yaw = x;
    gState.currentPov.pitch = y;
    return playerStatus(PlayerErrorsSuccess);
}

PlayerErrorStatus MediaPlayer_fixPov(void)
{
    return playerStatus(PlayerErrorsSuccess);
}

bool MediaPlayer_isTracking(void)
{
    return gState.isTracking;
}

PlayerErrorStatus MediaPlayer_startObjectTracking(float x, float y)
{
    (void)x;
    (void)y;
    gState.isTracking = true;
    return playerStatus(PlayerErrorsSuccess);
}

void MediaPlayer_stopObjectTracking(void)
{
    gState.isTracking = false;
}

PlayerErrorStatus MediaPlayer_stabilizationMode(StabilizationMode *stabMode)
{
    if (stabMode == NULL) {
        return playerStatus(PlayerErrorsParametersError);
    }
    *stabMode = gState.stabilizationMode;
    return playerStatus(PlayerErrorsSuccess);
}

PlayerErrorStatus MediaPlayer_setStabilizationMode(StabilizationMode stabMode)
{
    gState.stabilizationMode = stabMode;
    return playerStatus(PlayerErrorsSuccess);
}

PlayerErrorStatus MediaPlayer_saveScreen(const char *fileName, int32_t frameWidth, int32_t frameHeight, OutProjectionType projection)
{
    (void)projection;
    if (!hasText(fileName) || frameWidth <= 0 || frameHeight <= 0) {
        return playerStatus(PlayerErrorsParametersError);
    }
    return playerNotImplemented();
}

PlayerErrorStatus MediaPlayer_currentPov(DynamicPlayerParams *result)
{
    if (result == NULL) {
        return playerStatus(PlayerErrorsParametersError);
    }
    *result = gState.currentPov;
    return playerStatus(PlayerErrorsSuccess);
}
