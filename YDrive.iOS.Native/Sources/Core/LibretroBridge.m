// ─────────────────────────────────────────────────────────────────────────────
//  LibretroBridge.m — Objective-C implementation of the libretro bridge
//
//  Two compilation modes:
//
//  1. YDRIVE_CORE_AVAILABLE = 0 (default, no binary linked)
//     All methods are safe stubs. Build succeeds, app runs, emulator shows
//     a "core not available" state. No linker errors.
//
//  2. YDRIVE_CORE_AVAILABLE = 1 (set in project.yml OTHER_CFLAGS when .a is linked)
//     Real libretro symbols are resolved via extern "C". Full pipeline active.
//
// ─────────────────────────────────────────────────────────────────────────────

#import "LibretroBridge.h"
#import <os/log.h>

static os_log_t gLog;

// ── NSError domain ───────────────────────────────────────────────────────────
NSErrorDomain const YDriveBridgeErrorDomain = @"YDriveBridgeError";

// ─────────────────────────────────────────────────────────────────────────────
//  MARK: - libretro C API declarations (only when binary is available)
// ─────────────────────────────────────────────────────────────────────────────

#if YDRIVE_CORE_AVAILABLE

// Libretro pixel format enum (must match libretro.h)
enum retro_pixel_format {
    RETRO_PIXEL_FORMAT_0RGB1555 = 0,
    RETRO_PIXEL_FORMAT_XRGB8888 = 1,
    RETRO_PIXEL_FORMAT_RGB565   = 2,
};

// Libretro key constants
#define RETRO_ENVIRONMENT_SET_PIXEL_FORMAT 10
#define RETRO_DEVICE_JOYPAD                1

typedef struct {
    const char *path;
    const void *data;
    size_t      size;
    const char *meta;
} retro_game_info;

typedef struct { unsigned base_width, base_height, max_width, max_height; float aspect_ratio; } retro_game_geometry;
typedef struct { double fps, sample_rate; } retro_system_timing;
typedef struct { retro_game_geometry geometry; retro_system_timing timing; } retro_system_av_info;
typedef struct { const char *library_name, *library_version, *valid_extensions; bool need_fullpath, block_extract; } retro_system_info;

typedef void (*retro_video_refresh_t)(const void *data, unsigned width, unsigned height, size_t pitch);
typedef void (*retro_audio_sample_t)(int16_t left, int16_t right);
typedef size_t (*retro_audio_sample_batch_t)(const int16_t *data, size_t frames);
typedef void (*retro_input_poll_t)(void);
typedef int16_t (*retro_input_state_t)(unsigned port, unsigned device, unsigned index, unsigned id);
typedef bool (*retro_environment_t)(unsigned cmd, void *data);

extern void retro_init(void);
extern void retro_deinit(void);
extern void retro_get_system_info(retro_system_info *info);
extern void retro_get_system_av_info(retro_system_av_info *info);
extern bool retro_load_game(const retro_game_info *game);
extern void retro_unload_game(void);
extern void retro_run(void);
extern void retro_set_environment(retro_environment_t);
extern void retro_set_video_refresh(retro_video_refresh_t);
extern void retro_set_audio_sample(retro_audio_sample_t);
extern void retro_set_audio_sample_batch(retro_audio_sample_batch_t);
extern void retro_set_input_poll(retro_input_poll_t);
extern void retro_set_input_state(retro_input_state_t);
extern void retro_set_controller_port_device(unsigned port, unsigned device);

// ── Global bridge instance for C callbacks ───────────────────────────────────
static __weak YDriveLibretroBridge *gBridgeInstance = nil;
static YDrivePixelFormat gCurrentPixelFormat = YDrivePixelFormatRGB565;

// ── C-level callbacks ─────────────────────────────────────────────────────────

static bool env_callback(unsigned cmd, void *data) {
    if (cmd == RETRO_ENVIRONMENT_SET_PIXEL_FORMAT) {
        enum retro_pixel_format fmt = *(enum retro_pixel_format *)data;
        switch (fmt) {
            case RETRO_PIXEL_FORMAT_0RGB1555: gCurrentPixelFormat = YDrivePixelFormat0RGB1555; break;
            case RETRO_PIXEL_FORMAT_XRGB8888: gCurrentPixelFormat = YDrivePixelFormatXRGB8888; break;
            case RETRO_PIXEL_FORMAT_RGB565:   gCurrentPixelFormat = YDrivePixelFormatRGB565;   break;
        }
        os_log(gLog, "[CORE] SET_PIXEL_FORMAT: %d", (int)fmt);
        return true;
    }
    return false;
}

static void video_refresh_callback(const void *data, unsigned width, unsigned height, size_t pitch) {
    YDriveLibretroBridge *bridge = gBridgeInstance;
    if (!bridge || !bridge.onVideoFrame) return;

    YDriveVideoFrame frame = {
        .data        = data,
        .width       = width,
        .height      = height,
        .pitch       = pitch,
        .pixelFormat = gCurrentPixelFormat,
    };

    os_log_debug(gLog, "[VIDEO] frame %ux%u pitch=%zu fmt=%d", width, height, pitch, (int)gCurrentPixelFormat);
    bridge.onVideoFrame(frame);
}

static void audio_sample_callback(int16_t left, int16_t right) { /* audio stubbed */ }
static size_t audio_batch_callback(const int16_t *data, size_t frames) { return frames; }
static void input_poll_callback(void) { /* will be extended later */ }
static int16_t input_state_callback(unsigned port, unsigned device, unsigned index, unsigned id) { return 0; }

#endif // YDRIVE_CORE_AVAILABLE

// ─────────────────────────────────────────────────────────────────────────────
//  MARK: - YDriveLibretroBridge
// ─────────────────────────────────────────────────────────────────────────────

@implementation YDriveLibretroBridge {
    BOOL _coreInitialized;
}

+ (void)initialize {
    if (self == [YDriveLibretroBridge class]) {
        gLog = os_log_create("com.yigit.ydrive", "LibretroBridge");
    }
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _isRunning           = NO;
        _videoWidth          = 320;
        _videoHeight         = 224;
        _aspectRatio         = 4.0f / 3.0f;
        _targetFPS           = 60.0;
        _currentPixelFormat  = YDrivePixelFormatRGB565;
        _coreInitialized     = NO;
    }
    return self;
}

- (BOOL)loadGameAtPath:(NSString *)romPath error:(NSError **)error {
    os_log(gLog, "[CORE] loadGameAtPath: %{public}@", romPath.lastPathComponent);

#if YDRIVE_CORE_AVAILABLE
    // ── Register C callbacks ──────────────────────────────────────────────────
    gBridgeInstance = self;
    retro_set_environment(env_callback);
    retro_set_video_refresh(video_refresh_callback);
    retro_set_audio_sample(audio_sample_callback);
    retro_set_audio_sample_batch(audio_batch_callback);
    retro_set_input_poll(input_poll_callback);
    retro_set_input_state(input_state_callback);

    os_log(gLog, "[CORE] Callbacks registered");

    // ── Init ─────────────────────────────────────────────────────────────────
    retro_init();
    _coreInitialized = YES;
    os_log(gLog, "[CORE] retro_init() completed");

    // ── System info ──────────────────────────────────────────────────────────
    retro_system_info sysInfo = {0};
    retro_get_system_info(&sysInfo);
    os_log(gLog, "[CORE] Core: %{public}s v%{public}s needFullPath=%d",
           sysInfo.library_name, sysInfo.library_version, (int)sysInfo.need_fullpath);

    // ── Load game ────────────────────────────────────────────────────────────
    const char *pathC = romPath.fileSystemRepresentation;
    retro_game_info gameInfo = { .path = pathC, .data = NULL, .size = 0, .meta = NULL };

    if (!sysInfo.need_fullpath) {
        // Buffer mode: read ROM into memory
        NSData *romData = [NSData dataWithContentsOfFile:romPath];
        if (!romData) {
            os_log_error(gLog, "[CORE] ROM file not found: %{public}@", romPath);
            if (error) {
                *error = [NSError errorWithDomain:@"YDriveBridgeError"
                                            code:1
                                        userInfo:@{NSLocalizedDescriptionKey: @"ROM file not found"}];
            }
            return NO;
        }
        gameInfo.data = romData.bytes;
        gameInfo.size = romData.length;
        os_log(gLog, "[CORE] Buffer mode: %zu bytes", romData.length);
    } else {
        os_log(gLog, "[CORE] FullPath mode");
    }

    BOOL loaded = retro_load_game(&gameInfo);
    if (!loaded) {
        os_log_error(gLog, "[CORE] retro_load_game returned false");
        if (error) {
            *error = [NSError errorWithDomain:@"YDriveBridgeError"
                                        code:2
                                    userInfo:@{NSLocalizedDescriptionKey: @"retro_load_game failed"}];
        }
        return NO;
    }
    os_log(gLog, "[CORE] retro_load_game SUCCESS");

    // ── AV info ──────────────────────────────────────────────────────────────
    retro_system_av_info avInfo = {0};
    retro_get_system_av_info(&avInfo);
    _videoWidth  = avInfo.geometry.base_width;
    _videoHeight = avInfo.geometry.base_height;
    _aspectRatio = (avInfo.geometry.aspect_ratio > 0.01f)
                    ? avInfo.geometry.aspect_ratio
                    : (float)_videoWidth / (float)_videoHeight;
    _targetFPS   = avInfo.timing.fps > 0 ? avInfo.timing.fps : 60.0;

    os_log(gLog, "[CORE] AV: %ux%u @ %.2f fps aspect=%.3f",
           _videoWidth, _videoHeight, _targetFPS, _aspectRatio);

    retro_set_controller_port_device(0, RETRO_DEVICE_JOYPAD);
    retro_set_controller_port_device(1, RETRO_DEVICE_JOYPAD);

    _currentPixelFormat = gCurrentPixelFormat;
    _isRunning = YES;
    return YES;

#else
    // ── STUB: no core binary linked ──────────────────────────────────────────
    os_log(gLog, "[CORE] STUB MODE — no libretro core binary linked.");
    os_log(gLog, "[CORE] To activate: link libpicodrive_ios.a and set YDRIVE_CORE_AVAILABLE=1");
    if (error) {
        *error = [NSError errorWithDomain:@"YDriveBridgeError"
                                    code:99
                                userInfo:@{NSLocalizedDescriptionKey:
                                    @"No libretro core binary linked. Set YDRIVE_CORE_AVAILABLE=1 and link a core .a file."}];
    }
    return NO;
#endif
}

- (void)runFrame {
#if YDRIVE_CORE_AVAILABLE
    if (!_isRunning) return;
    retro_run();
#endif
}

- (void)unload {
    os_log(gLog, "[CORE] unload called");
#if YDRIVE_CORE_AVAILABLE
    if (_isRunning) {
        retro_unload_game();
        _isRunning = NO;
    }
    if (_coreInitialized) {
        retro_deinit();
        _coreInitialized = NO;
    }
    gBridgeInstance = nil;
#endif
    _isRunning = NO;
}

- (void)dealloc {
    [self unload];
}

@end
