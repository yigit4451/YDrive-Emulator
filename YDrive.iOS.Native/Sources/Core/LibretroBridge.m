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
extern void retro_reset(void);
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

// ── Global bridge instance for C callbacks ───────────────────────────────────
static __weak YDriveLibretroBridge *gBridgeInstance = nil;
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
        _isRunning           = NO;
        _videoWidth          = 320;
        _videoHeight         = 224;
        _aspectRatio         = 4.0f / 3.0f;
        _targetFPS           = 60.0;
        _audioSampleRate     = 44100.0;
        _currentPixelFormat  = YDrivePixelFormatRGB565;
        _coreInitialized     = NO;
    }
    return self;
}

- (BOOL)loadGameAtPath:(NSString *)romPath error:(NSError **)error {
    os_log(gLog, "[CORE] loadGameAtPath: %{public}@", romPath.lastPathComponent);

#if YDRIVE_CORE_AVAILABLE
    // Ensure any previously loaded game in the global static core is cleanly unloaded first
    if (gCoreGameLoaded) {
        os_log(gLog, "[CORE] Unloading previous global game before loading new ROM");
        retro_unload_game();
        gCoreGameLoaded = NO;
    }
    // Standard libretro lifecycle: every session is init -> load -> run -> unload -> deinit.
    // Never carry core-internal state (input, timing, audio, video) over to the next ROM.
    if (gCoreGlobalInitialized) {
        retro_deinit();
        gCoreGlobalInitialized = NO;
        os_log(gLog, "[CORE] retro_deinit() — stale core state cleared before new session");
    }

    // ── Register C callbacks (always re-bind to ensure function pointers stay valid) ──
    gBridgeInstance = self;
    atomic_store(&gInputBitmask, 0);

    retro_set_environment(env_callback);
    retro_set_video_refresh(video_refresh_callback);
    retro_set_audio_sample(audio_sample_callback);
    retro_set_audio_sample_batch(audio_batch_callback);
    retro_set_input_poll(input_poll_callback);
    retro_set_input_state(input_state_callback);

    // ── Init ─────────────────────────────────────────────────────────────────
    if (!gCoreGlobalInitialized) {
        retro_init();
        gCoreGlobalInitialized = YES;
        os_log(gLog, "[CORE] retro_init() completed globally");
    }
    _coreInitialized = YES;

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
    gCoreGameLoaded = YES;
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
    _audioSampleRate = avInfo.timing.sample_rate > 0 ? avInfo.timing.sample_rate : 44100.0;

    os_log(gLog, "[CORE] AV: %ux%u @ %.2f fps aspect=%.3f audio=%.0fHz",
           _videoWidth, _videoHeight, _targetFPS, _aspectRatio, _audioSampleRate);

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
    if (!_isRunning || !gCoreGameLoaded) return;
    if (gBridgeInstance != self) return;
    // TEMP diagnostics: bracket retro_run() with uptime stamps.
    uint64_t runStart = clock_gettime_nsec_np(CLOCK_UPTIME_RAW);
    atomic_store(&gRunStartNs, runStart);
    uint64_t frame = atomic_fetch_add(&gFrameIndex, 1) + 1;
    retro_run();
    double runMs = (double)(clock_gettime_nsec_np(CLOCK_UPTIME_RAW) - runStart) / 1.0e6;
    if (runMs > 14.0 && atomic_load(&gSlowRunLogged) < 40) {
        atomic_fetch_add(&gSlowRunLogged, 1);
        void (^trace)(NSString *) = self.onInputTrace;
        if (trace) trace([NSString stringWithFormat:@"slowrun frame=%llu dur=%.2fms", frame, runMs]);
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
                trace([NSString stringWithFormat:
                    @"life   id=%u held=%.1fms firstCoreRead=+%.2fms (frame +%llu, %.2fms into retro_run) framesCoreSawBit=%llu framesRun=%llu expected~%.0f",
                    buttonID, heldMs, readMs, rdFrm, intoRun, seen, framesRun, heldMs / 16.67]);
            }
        }
    }
#endif
}

- (void)reset {
    os_log(gLog, "[CORE] reset called");
#if YDRIVE_CORE_AVAILABLE
    atomic_store(&gInputBitmask, 0);
    if (_isRunning && gCoreGameLoaded && gBridgeInstance == self) {
        retro_reset();
    }
#endif
}

- (NSData * _Nullable)saveState {
    os_log(gLog, "[CORE] saveState called");
#if YDRIVE_CORE_AVAILABLE
    if (!_isRunning || !gCoreGameLoaded || gBridgeInstance != self) return nil;
    
    size_t size = retro_serialize_size();
    if (size == 0) {
        os_log_error(gLog, "[CORE] Core does not support save states (size=0)");
        return nil;
    }
    
    NSMutableData *data = [NSMutableData dataWithLength:size];
    if (retro_serialize(data.mutableBytes, size)) {
        return data;
    } else {
        os_log_error(gLog, "[CORE] retro_serialize failed");
        return nil;
    }
#else
    return nil;
#endif
}

- (BOOL)loadState:(NSData *)data {
    os_log(gLog, "[CORE] loadState called");
#if YDRIVE_CORE_AVAILABLE
    if (!_isRunning || !gCoreGameLoaded || gBridgeInstance != self || !data || data.length == 0) return NO;
    
    size_t expectedSize = retro_serialize_size();
    if (expectedSize == 0 || data.length != expectedSize) {
        os_log_error(gLog, "[CORE] State size mismatch: got %zu, expected %zu", data.length, expectedSize);
        return NO;
    }
    
    if (retro_unserialize(data.bytes, data.length)) {
        return YES;
    } else {
        os_log_error(gLog, "[CORE] retro_unserialize failed");
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
    if (gBridgeInstance == self) {
        if (_isRunning && gCoreGameLoaded) {
            retro_unload_game();
            gCoreGameLoaded = NO;
        }
        if (gCoreGlobalInitialized) {
            retro_deinit();
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
