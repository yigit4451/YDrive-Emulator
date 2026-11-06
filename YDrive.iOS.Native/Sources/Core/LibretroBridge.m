// ─────────────────────────────────────────────────────────────────────────────
//  LibretroBridge.m — Objective-C implementation of the libretro bridge
//
//  Supports dynamic runtime switching between:
//    1. PicoDrive (`retro_*` symbols from libpicodrive.a)
//    2. YD-Core v1.2.0 (`yd_retro_*` symbols from YDCore pure C11 engine)
// ─────────────────────────────────────────────────────────────────────────────

#import "LibretroBridge.h"
#import <os/log.h>
#import <stdatomic.h>

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
#define RETRO_DEVICE_MASK                       0xff
#define RETRO_DEVICE_JOYPAD                     1
#define RETRO_DEVICE_ID_JOYPAD_MASK             256
#define RETRO_ENVIRONMENT_GET_SYSTEM_DIRECTORY  9
#define RETRO_ENVIRONMENT_SET_PIXEL_FORMAT      10
#define RETRO_ENVIRONMENT_GET_VARIABLE          15

typedef struct {
    const char *key;
    const char *value;
} retro_variable;

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

// ── 1. PicoDrive Libretro Symbols (`retro_*`) ────────────────────────────────
extern void retro_init(void);
extern void retro_deinit(void);
extern void retro_get_system_info(retro_system_info *info);
extern void retro_get_system_av_info(retro_system_av_info *info);
extern bool retro_load_game(const retro_game_info *game);
extern void retro_unload_game(void);
extern void retro_run(void);
extern void retro_reset(void);
extern void io_ports_reset(void);
extern void  *retro_get_memory_data(unsigned id);
extern size_t retro_get_memory_size(unsigned id);
extern size_t retro_serialize_size(void);
extern bool retro_serialize(void *data, size_t size);
extern bool retro_unserialize(const void *data, size_t size);
extern void retro_set_environment(retro_environment_t);
extern void retro_set_video_refresh(retro_video_refresh_t);
extern void retro_set_audio_sample(retro_audio_sample_t);
extern void retro_set_audio_sample_batch(retro_audio_sample_batch_t);
extern void retro_set_input_poll(retro_input_poll_t);
extern void retro_set_input_state(retro_input_state_t);
extern void retro_set_controller_port_device(unsigned port, unsigned device);

// ── 2. YD-Core v1.2.0 Libretro Symbols (`yd_retro_*`) ────────────────────────
extern void yd_retro_init(void);
extern void yd_retro_deinit(void);
extern void yd_retro_get_system_info(retro_system_info *info);
extern void yd_retro_get_system_av_info(retro_system_av_info *info);
extern bool yd_retro_load_game(const retro_game_info *game);
extern void yd_retro_unload_game(void);
extern void yd_retro_run(void);
extern void yd_retro_reset(void);
extern void  *yd_retro_get_memory_data(unsigned id);
extern size_t yd_retro_get_memory_size(unsigned id);
extern size_t yd_retro_serialize_size(void);
extern bool yd_retro_serialize(void *data, size_t size);
extern bool yd_retro_unserialize(const void *data, size_t size);
extern void yd_retro_set_environment(retro_environment_t);
extern void yd_retro_set_video_refresh(retro_video_refresh_t);
extern void yd_retro_set_audio_sample(retro_audio_sample_t);
extern void yd_retro_set_audio_sample_batch(retro_audio_sample_batch_t);
extern void yd_retro_set_input_poll(retro_input_poll_t);
extern void yd_retro_set_input_state(retro_input_state_t);
extern void yd_retro_set_controller_port_device(unsigned port, unsigned device);

// ── Dynamic Core Dispatch Table ──────────────────────────────────────────────
typedef struct {
    const char *name;
    void   (*init)(void);
    void   (*deinit)(void);
    void   (*get_system_info)(retro_system_info *info);
    void   (*get_system_av_info)(retro_system_av_info *info);
    bool   (*load_game)(const retro_game_info *game);
    void   (*unload_game)(void);
    void   (*run)(void);
    void   (*reset)(void);
    void  *(*get_memory_data)(unsigned id);
    size_t (*get_memory_size)(unsigned id);
    size_t (*serialize_size)(void);
    bool   (*serialize)(void *data, size_t size);
    bool   (*unserialize)(const void *data, size_t size);
    void   (*set_environment)(retro_environment_t);
    void   (*set_video_refresh)(retro_video_refresh_t);
    void   (*set_audio_sample)(retro_audio_sample_t);
    void   (*set_audio_sample_batch)(retro_audio_sample_batch_t);
    void   (*set_input_poll)(retro_input_poll_t);
    void   (*set_input_state)(retro_input_state_t);
    void   (*set_controller_port_device)(unsigned port, unsigned device);
    bool   has_io_ports_reset;
} YDriveCoreDispatchTable;

static const YDriveCoreDispatchTable kPicoDriveTable = {
    .name                       = "PicoDrive",
    .init                       = retro_init,
    .deinit                     = retro_deinit,
    .get_system_info            = retro_get_system_info,
    .get_system_av_info         = retro_get_system_av_info,
    .load_game                  = retro_load_game,
    .unload_game                = retro_unload_game,
    .run                        = retro_run,
    .reset                      = retro_reset,
    .get_memory_data            = retro_get_memory_data,
    .get_memory_size            = retro_get_memory_size,
    .serialize_size             = retro_serialize_size,
    .serialize                  = retro_serialize,
    .unserialize                = retro_unserialize,
    .set_environment            = retro_set_environment,
    .set_video_refresh          = retro_set_video_refresh,
    .set_audio_sample           = retro_set_audio_sample,
    .set_audio_sample_batch     = retro_set_audio_sample_batch,
    .set_input_poll             = retro_set_input_poll,
    .set_input_state            = retro_set_input_state,
    .set_controller_port_device = retro_set_controller_port_device,
    .has_io_ports_reset         = true,
};

// ── Global bridge instance for C callbacks ───────────────────────────────────
static __weak YDriveLibretroBridge *gBridgeInstance = nil;
static const YDriveCoreDispatchTable *gActiveCore = &kPicoDriveTable;
static YDrivePixelFormat gCurrentPixelFormat = YDrivePixelFormatRGB565;
static BOOL gCoreGlobalInitialized = NO;
static BOOL gCoreGameLoaded = NO;

// ── C-level callbacks ─────────────────────────────────────────────────────────

static bool env_callback(unsigned cmd, void *data) {
    if (cmd == RETRO_ENVIRONMENT_SET_PIXEL_FORMAT) {
        enum retro_pixel_format fmt = *(enum retro_pixel_format *)data;
        switch (fmt) {
            case RETRO_PIXEL_FORMAT_0RGB1555: gCurrentPixelFormat = YDrivePixelFormatTRGB1555; break;
            case RETRO_PIXEL_FORMAT_XRGB8888: gCurrentPixelFormat = YDrivePixelFormatXRGB8888; break;
            case RETRO_PIXEL_FORMAT_RGB565:   gCurrentPixelFormat = YDrivePixelFormatRGB565;   break;
        }
        os_log(gLog, "[CORE] SET_PIXEL_FORMAT: %d", (int)fmt);
        return true;
    } else if (cmd == RETRO_ENVIRONMENT_GET_SYSTEM_DIRECTORY) {
        const char **dir = (const char **)data;
        static char systemDir[1024] = {0};
        if (systemDir[0] == '\0') {
            NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
            NSString *docsDir = [paths firstObject];
            NSString *sysPath = [docsDir stringByAppendingPathComponent:@"BIOS"];
            [[NSFileManager defaultManager] createDirectoryAtPath:sysPath withIntermediateDirectories:YES attributes:nil error:nil];
            strncpy(systemDir, [sysPath UTF8String], sizeof(systemDir) - 1);
        }
        *dir = systemDir;
        os_log(gLog, "[CORE] GET_SYSTEM_DIRECTORY: %{public}s", systemDir);
        return true;
    } else if (cmd == RETRO_ENVIRONMENT_GET_VARIABLE) {
        retro_variable *var = (retro_variable *)data;
        YDriveLibretroBridge *bridge = gBridgeInstance;
        if (var && var->key) {
            if (strcmp(var->key, "picodrive_input1") == 0 || strcmp(var->key, "picodrive_input2") == 0) {
                var->value = "6 button pad";
                os_log(gLog, "[CORE] GET_VARIABLE: %{public}s -> 6 button pad", var->key);
                return true;
            }
            if (strcmp(var->key, "yd_fast_memory") == 0) {
                var->value = (!bridge || bridge.fastMemoryEnabled) ? "enabled" : "disabled";
                return true;
            }
            if (strcmp(var->key, "yd_audio_interpolation") == 0) {
                var->value = (!bridge || bridge.audioInterpolationEnabled) ? "enabled" : "disabled";
                return true;
            }
            if (strcmp(var->key, "yd_force_6button_pad") == 0) {
                var->value = (bridge && bridge.forceSixButtonPad) ? "enabled" : "disabled";
                return true;
            }
        }
        return false;
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

static void audio_sample_callback(int16_t left, int16_t right) {
    if (!gBridgeInstance) return;
    int16_t frame[2] = {left, right};
    if (gBridgeInstance.onAudioPCM) {
        gBridgeInstance.onAudioPCM(frame, 1);
    }
}
static size_t audio_batch_callback(const int16_t *data, size_t frames) {
    if (gBridgeInstance && gBridgeInstance.onAudioPCM) {
        gBridgeInstance.onAudioPCM(data, frames);
    }
    return frames;
}

// ── Input State ───────────────────────────────────────────────────────────────
static atomic_uint_fast16_t gInputBitmask = 0;

// TEMP diagnostics: uptime (ns) at which each button's press was recorded, 0 = already reported.
static _Atomic uint64_t gPressStampNs[16];

static void input_poll_callback(void) {
    // Live atomic state is read directly in input_state_callback.
    // TEMP diagnostics: report press->poll latency once per press.
    void (^cb)(unsigned, double) = gBridgeInstance.onInputPolled;
    if (!cb) return;
    uint16_t mask = (uint16_t)atomic_load(&gInputBitmask);
    for (unsigned i = 0; i < 16; i++) {
        if (!(mask & (1u << i))) continue;
        uint64_t stamp = atomic_exchange(&gPressStampNs[i], 0);
        if (stamp != 0) {
            uint64_t now = clock_gettime_nsec_np(CLOCK_UPTIME_RAW);
            cb(i, (double)(now - stamp) / 1.0e6);
        }
    }
}

// TEMP diagnostics: per-press lifecycle (all indexed by RetroPad id).
static _Atomic uint64_t gFrameIndex;            // incremented right before every retro_run()
static _Atomic uint64_t gRunStartNs;            // uptime at start of the current/last retro_run()
static _Atomic uint64_t gPressStartNs[16];      // uptime of setButton(pressed) ; 0 = not held
static _Atomic uint64_t gPressFrame[16];        // gFrameIndex at press
static _Atomic uint64_t gFirstReadNs[16];       // first time the core's input_state read returned 1
static _Atomic uint64_t gFirstReadFrame[16];    // gFrameIndex when that happened
static _Atomic uint64_t gFirstReadRunStartNs[16];
static _Atomic uint64_t gFramesSeen[16];        // distinct frames in which the core read the bit as 1
static _Atomic uint64_t gFirstPresentedNs[16];  // first GPU completion of a frame run after the press
static _Atomic uint64_t gFramesPresented[16];   // distinct produced frames drawn by Metal while held
static _Atomic uint64_t gLastPresentedFrame[16];
static _Atomic uint64_t gLastSeenFrame[16];
static _Atomic uint32_t gSlowRunLogged;

static inline void note_core_read(unsigned i) {
    if (atomic_load(&gPressStartNs[i]) == 0) return;
    uint64_t frame = atomic_load(&gFrameIndex);
    if (atomic_exchange(&gLastSeenFrame[i], frame) != frame) {
        atomic_fetch_add(&gFramesSeen[i], 1);
    }
    if (atomic_load(&gFirstReadNs[i]) == 0) {
        atomic_store(&gFirstReadFrame[i], frame);
        atomic_store(&gFirstReadRunStartNs[i], atomic_load(&gRunStartNs));
        atomic_store(&gFirstReadNs[i], clock_gettime_nsec_np(CLOCK_UPTIME_RAW));
    }
}

static int16_t input_state_callback(unsigned port, unsigned device, unsigned index, unsigned id) {
    if (port != 0) return 0; // Only player 1 for now
    unsigned baseDevice = device & RETRO_DEVICE_MASK;
    if (baseDevice == RETRO_DEVICE_JOYPAD || baseDevice == 1) {
        // Read live atomic bitmask directly so touchDown is active on the exact
        // microsecond of finger contact and never fires after touchUp.
        uint16_t mask = (uint16_t)atomic_load(&gInputBitmask);
        if (id == RETRO_DEVICE_ID_JOYPAD_MASK) {
            for (unsigned i = 0; i < 16; i++) {
                if (mask & (1u << i)) note_core_read(i);
            }
            return (int16_t)mask;
        }
        if (id < 16) {
            if (mask & (1u << id)) {
                note_core_read(id);
                return 1;
            }
            return 0;
        }
    }
    return 0;
}

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
        _selectedCore              = YDriveEmulationCorePicoDrive;
        _fastMemoryEnabled         = YES;
        _audioInterpolationEnabled = YES;
        _forceSixButtonPad         = NO;
        _isRunning                 = NO;
        _videoWidth                = 320;
        _videoHeight               = 224;
        _aspectRatio               = 4.0f / 3.0f;
        _targetFPS                 = 60.0;
        _audioSampleRate           = 44100.0;
        _currentPixelFormat        = YDrivePixelFormatRGB565;
        _coreInitialized           = NO;
    }
    return self;
}

- (BOOL)loadGameAtPath:(NSString *)romPath error:(NSError **)error {
    os_log(gLog, "[CORE] loadGameAtPath: %{public}@ (selectedCore=%ld)",
           romPath.lastPathComponent, (long)self.selectedCore);

#if YDRIVE_CORE_AVAILABLE
    // Ensure any previously loaded game in the active global static core is cleanly unloaded first
    if (gCoreGameLoaded && gActiveCore) {
        os_log(gLog, "[CORE] Unloading previous global game on %{public}s before loading new ROM", gActiveCore->name);
        gActiveCore->unload_game();
        gCoreGameLoaded = NO;
    }
    // Standard libretro lifecycle: every session is init -> load -> run -> unload -> deinit.
    if (gCoreGlobalInitialized && gActiveCore) {
        gActiveCore->deinit();
        gCoreGlobalInitialized = NO;
        os_log(gLog, "[CORE] %{public}s deinit() — stale core state cleared before new session", gActiveCore->name);
    }

    // ── Select dynamic core dispatch table (YD-Core v1.2.0 vs PicoDrive) ──────
    static const YDriveCoreDispatchTable kYDCoreResolvedTable = {
        .name                       = "YD-Core v1.2.0",
        .init                       = yd_retro_init,
        .deinit                     = yd_retro_deinit,
        .get_system_info            = yd_retro_get_system_info,
        .get_system_av_info         = yd_retro_get_system_av_info,
        .load_game                  = yd_retro_load_game,
        .unload_game                = yd_retro_unload_game,
        .run                        = yd_retro_run,
        .reset                      = yd_retro_reset,
        .get_memory_data            = yd_retro_get_memory_data,
        .get_memory_size            = yd_retro_get_memory_size,
        .serialize_size             = yd_retro_serialize_size,
        .serialize                  = yd_retro_serialize,
        .unserialize                = yd_retro_unserialize,
        .set_environment            = yd_retro_set_environment,
        .set_video_refresh          = yd_retro_set_video_refresh,
        .set_audio_sample           = yd_retro_set_audio_sample,
        .set_audio_sample_batch     = yd_retro_set_audio_sample_batch,
        .set_input_poll             = yd_retro_set_input_poll,
        .set_input_state            = yd_retro_set_input_state,
        .set_controller_port_device = yd_retro_set_controller_port_device,
        .has_io_ports_reset         = false,
    };

    // Note: SEGA CD (.chd / .cue / .iso) or 32X (.32x) automatically fall back to PicoDrive
    NSString *ext = romPath.pathExtension.lowercaseString;
    BOOL isCDOr32X = ([ext isEqualToString:@"chd"] ||
                      [ext isEqualToString:@"cue"] ||
                      [ext isEqualToString:@"iso"] ||
                      [ext isEqualToString:@"32x"]);

    if (self.selectedCore == YDriveEmulationCoreYDCore && !isCDOr32X) {
        gActiveCore = &kYDCoreResolvedTable;
    } else {
        gActiveCore = &kPicoDriveTable;
    }

    // ── Register C callbacks (always re-bind to ensure function pointers stay valid) ──
    gBridgeInstance = self;
    gCurrentPixelFormat = YDrivePixelFormatRGB565;
    atomic_store(&gInputBitmask, 0);

    gActiveCore->set_environment(env_callback);
    gActiveCore->set_video_refresh(video_refresh_callback);
    gActiveCore->set_audio_sample(audio_sample_callback);
    gActiveCore->set_audio_sample_batch(audio_batch_callback);
    gActiveCore->set_input_poll(input_poll_callback);
    gActiveCore->set_input_state(input_state_callback);

    // ── Init ─────────────────────────────────────────────────────────────────
    if (!gCoreGlobalInitialized) {
        gActiveCore->init();
        gCoreGlobalInitialized = YES;
        os_log(gLog, "[CORE] %{public}s init() completed globally", gActiveCore->name);
    }
    _coreInitialized = YES;

    // ── System info ──────────────────────────────────────────────────────────
    retro_system_info sysInfo = {0};
    gActiveCore->get_system_info(&sysInfo);
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

    BOOL loaded = gActiveCore->load_game(&gameInfo);
    if (!loaded) {
        os_log_error(gLog, "[CORE] %{public}s load_game returned false", gActiveCore->name);
        if (error) {
            *error = [NSError errorWithDomain:@"YDriveBridgeError"
                                        code:2
                                    userInfo:@{NSLocalizedDescriptionKey: @"retro_load_game failed"}];
        }
        return NO;
    }
    gCoreGameLoaded = YES;
    os_log(gLog, "[CORE] %{public}s load_game SUCCESS", gActiveCore->name);

    // ── AV info ──────────────────────────────────────────────────────────────
    retro_system_av_info avInfo = {0};
    gActiveCore->get_system_av_info(&avInfo);
    _videoWidth  = avInfo.geometry.base_width;
    _videoHeight = avInfo.geometry.base_height;
    _aspectRatio = (avInfo.geometry.aspect_ratio > 0.01f)
                    ? avInfo.geometry.aspect_ratio
                    : (float)_videoWidth / (float)_videoHeight;
    _targetFPS   = avInfo.timing.fps > 0 ? avInfo.timing.fps : 60.0;
    _audioSampleRate = avInfo.timing.sample_rate > 0 ? avInfo.timing.sample_rate : 44100.0;

    os_log(gLog, "[CORE] AV: %ux%u @ %.2f fps aspect=%.3f audio=%.0fHz",
           _videoWidth, _videoHeight, _targetFPS, _aspectRatio, _audioSampleRate);

    if (gActiveCore->has_io_ports_reset) {
        io_ports_reset();
    }
    gActiveCore->set_controller_port_device(0, RETRO_DEVICE_JOYPAD);
    gActiveCore->set_controller_port_device(1, RETRO_DEVICE_JOYPAD);

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
    if (!_isRunning || !gCoreGameLoaded || !gActiveCore) return;
    if (gBridgeInstance != self) return;
    // TEMP diagnostics: bracket retro_run() with uptime stamps.
    uint64_t runStart = clock_gettime_nsec_np(CLOCK_UPTIME_RAW);
    atomic_store(&gRunStartNs, runStart);
    uint64_t frame = atomic_fetch_add(&gFrameIndex, 1) + 1;
    gActiveCore->run();
    double runMs = (double)(clock_gettime_nsec_np(CLOCK_UPTIME_RAW) - runStart) / 1.0e6;
    if (runMs > 14.0 && atomic_load(&gSlowRunLogged) < 40) {
        atomic_fetch_add(&gSlowRunLogged, 1);
        void (^trace)(NSString *) = self.onInputTrace;
        if (trace) trace([NSString stringWithFormat:@"slowrun frame=%llu dur=%.2fms", frame, runMs]);
    }

    // TEMP diagnostics (read-only): watch the GAME's own reaction in 68k work RAM while A/B/C
    // (RetroPad ids 1/0/8) are held, plus 20 frames after release.
    {
        static BOOL     active = NO, released = NO;
        static uint64_t startFrame = 0;
        static int      tail = 0, events = 0;
        static uint8_t  last[8];
        static NSMutableString *buf = nil;
        uint16_t m = (uint16_t)atomic_load(&gInputBitmask);
        BOOL held = (m & 0x103) != 0;
        void (^trace)(NSString *) = self.onInputTrace;
        if (trace && (held || active)) {
            if (!active) {
                active = YES; released = NO; startFrame = frame; tail = 20; events = 0;
                memset(last, 0xEE, sizeof(last));
                buf = [NSMutableString string];
            }
            if (!held && !released) {
                released = YES;
                [buf appendFormat:@" |RELEASE@+%llu|", frame - startFrame];
            } else if (held && released) {
                released = NO; tail = 20;
                [buf appendFormat:@" |REPRESS@+%llu|", frame - startFrame];
            }
            uint8_t *ram = (uint8_t *)gActiveCore->get_memory_data(2);
            size_t   sz  = gActiveCore->get_memory_size(2);
            if (ram && sz >= 0x10000) {
                uint8_t cur[8] = {
                    ram[0xF604], ram[0xF605],
                    ram[0xD012], ram[0xD013], ram[0xD00C], ram[0xD00D],
                    ram[0xB012], ram[0xB013]
                };
                if (memcmp(cur, last, sizeof(cur)) != 0 && events < 60) {
                    events++;
                    memcpy(last, cur, sizeof(cur));
                    [buf appendFormat:@" +%llu[pad %02x%02x|s1YSpd %02x%02x yPos %02x%02x|s2YSpd %02x%02x]",
                        frame - startFrame, cur[0], cur[1], cur[2], cur[3], cur[4], cur[5], cur[6], cur[7]];
                }
            } else if (events == 0) {
                events = 1;
                [buf appendString:@" (system RAM unavailable)"];
            }
            if (released && --tail <= 0) {
                trace([NSString stringWithFormat:@"ramtrace pressFrame=%llu changes:%@", startFrame, buf]);
                active = NO; buf = nil;
            }
        }
    }
#endif
}

- (void)setButton:(unsigned)buttonID pressed:(BOOL)pressed {
#if YDRIVE_CORE_AVAILABLE
    if (buttonID >= 16) return;
    uint16_t bit = (uint16_t)(1u << buttonID);
    if (pressed) {
        uint16_t prev = (uint16_t)atomic_fetch_or(&gInputBitmask, bit);
        if (!(prev & bit)) {
            uint64_t now = clock_gettime_nsec_np(CLOCK_UPTIME_RAW);
            atomic_store(&gPressStampNs[buttonID], now);
            // TEMP diagnostics: reset lifecycle counters, then publish the press start last.
            atomic_store(&gFirstReadNs[buttonID], 0);
            atomic_store(&gFirstPresentedNs[buttonID], 0);
            atomic_store(&gFramesPresented[buttonID], 0);
            atomic_store(&gLastPresentedFrame[buttonID], 0);
            atomic_store(&gFramesSeen[buttonID], 0);
            atomic_store(&gLastSeenFrame[buttonID], 0);
            atomic_store(&gPressFrame[buttonID], atomic_load(&gFrameIndex));
            atomic_store(&gPressStartNs[buttonID], now);
        }
    } else {
        uint16_t prev = (uint16_t)atomic_fetch_and(&gInputBitmask, ~bit);
        uint64_t start = atomic_exchange(&gPressStartNs[buttonID], 0);
        void (^trace)(NSString *) = self.onInputTrace;
        if ((prev & bit) && start != 0 && trace) {
            uint64_t now        = clock_gettime_nsec_np(CLOCK_UPTIME_RAW);
            double   heldMs     = (double)(now - start) / 1.0e6;
            uint64_t framesRun  = atomic_load(&gFrameIndex) - atomic_load(&gPressFrame[buttonID]);
            uint64_t seen       = atomic_load(&gFramesSeen[buttonID]);
            uint64_t firstRead  = atomic_load(&gFirstReadNs[buttonID]);
            if (firstRead == 0) {
                trace([NSString stringWithFormat:
                    @"life   id=%u held=%.1fms CORE NEVER READ BIT WHILE HELD framesRun=%llu",
                    buttonID, heldMs, framesRun]);
            } else {
                double readMs   = (double)(firstRead - start) / 1.0e6;
                double intoRun  = (double)(firstRead - atomic_load(&gFirstReadRunStartNs[buttonID])) / 1.0e6;
                uint64_t rdFrm  = atomic_load(&gFirstReadFrame[buttonID]) - atomic_load(&gPressFrame[buttonID]);
                uint64_t shown  = atomic_load(&gFirstPresentedNs[buttonID]);
                uint64_t drawn  = atomic_load(&gFramesPresented[buttonID]);
                NSString *shownStr = shown ? [NSString stringWithFormat:@"+%.1fms", (double)(shown - start) / 1.0e6]
                                           : @"not-yet-presented";
                trace([NSString stringWithFormat:
                    @"life   id=%u held=%.1fms firstCoreRead=+%.2fms (frame +%llu, %.2fms into retro_run) firstFramePresented=%@ framesPresented=%llu framesCoreSawBit=%llu framesRun=%llu expected~%.0f",
                    buttonID, heldMs, readMs, rdFrm, intoRun, shownStr, drawn, seen, framesRun, heldMs / 16.67]);
            }
        }
    }
#endif
}

- (void)reset {
    os_log(gLog, "[CORE] reset called");
#if YDRIVE_CORE_AVAILABLE
    atomic_store(&gInputBitmask, 0);
    if (_isRunning && gCoreGameLoaded && gBridgeInstance == self && gActiveCore) {
        gActiveCore->reset();
        if (gActiveCore->has_io_ports_reset) {
            io_ports_reset();
        }
    }
#endif
}

- (NSData * _Nullable)saveState {
    os_log(gLog, "[CORE] saveState called");
#if YDRIVE_CORE_AVAILABLE
    if (!_isRunning || !gCoreGameLoaded || gBridgeInstance != self || !gActiveCore) return nil;
    
    size_t size = gActiveCore->serialize_size();
    if (size == 0) {
        os_log_error(gLog, "[CORE] Core does not support save states (size=0)");
        return nil;
    }
    
    NSMutableData *data = [NSMutableData dataWithLength:size];
    if (gActiveCore->serialize(data.mutableBytes, size)) {
        return data;
    } else {
        os_log_error(gLog, "[CORE] serialize failed");
        return nil;
    }
#else
    return nil;
#endif
}

- (BOOL)loadState:(NSData *)data {
    os_log(gLog, "[CORE] loadState called");
#if YDRIVE_CORE_AVAILABLE
    if (!_isRunning || !gCoreGameLoaded || gBridgeInstance != self || !gActiveCore || !data || data.length == 0) return NO;
    
    size_t expectedSize = gActiveCore->serialize_size();
    if (expectedSize == 0 || data.length != expectedSize) {
        os_log_error(gLog, "[CORE] State size mismatch: got %zu, expected %zu", data.length, expectedSize);
        return NO;
    }
    
    if (gActiveCore->unserialize(data.bytes, data.length)) {
        return YES;
    } else {
        os_log_error(gLog, "[CORE] unserialize failed");
        return NO;
    }
#else
    return NO;
#endif
}

- (void)unload {
    os_log(gLog, "[CORE] unload called");
#if YDRIVE_CORE_AVAILABLE
    // Guard with gBridgeInstance == self so a deallocating old YDriveLibretroBridge
    // never unloads or clobbers a newly started session's global core!
    if (gBridgeInstance == self && gActiveCore) {
        if (_isRunning && gCoreGameLoaded) {
            gActiveCore->unload_game();
            gCoreGameLoaded = NO;
        }
        if (gCoreGlobalInitialized) {
            gActiveCore->deinit();
            gCoreGlobalInitialized = NO;
        }
        atomic_store(&gInputBitmask, 0);
        gBridgeInstance = nil;
    }
    _isRunning = NO;
    _coreInitialized = NO;
#else
    _isRunning = NO;
#endif
}

- (void)dealloc {
    [self unload];
}

@end

// ── TEMP diagnostics: video presentation correlation ─────────────────────────
uint64_t YDriveCurrentFrameIndex(void) {
#if YDRIVE_CORE_AVAILABLE
    return atomic_load(&gFrameIndex);
#else
    return 0;
#endif
}

/// Called (from Metal's presented handler) when the frame produced by retro_run #producedFrame
/// reached the display. Records, for every currently held button, the first presentation of a
/// frame that was run at/after the press.
void YDriveNotePresented(uint64_t producedFrame, uint64_t presentedUptimeNs) {
#if YDRIVE_CORE_AVAILABLE
    for (unsigned i = 0; i < 16; i++) {
        if (atomic_load(&gPressStartNs[i]) == 0) continue;
        if (producedFrame > atomic_load(&gPressFrame[i])) {
            if (atomic_exchange(&gLastPresentedFrame[i], producedFrame) != producedFrame) {
                atomic_fetch_add(&gFramesPresented[i], 1);
            }
            if (atomic_load(&gFirstPresentedNs[i]) == 0) {
                atomic_store(&gFirstPresentedNs[i], presentedUptimeNs);
            }
        }
    }
#endif
}
