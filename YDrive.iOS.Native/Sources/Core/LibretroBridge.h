// ─────────────────────────────────────────────────────────────────────────────
//  LibretroBridge.h — Objective-C bridge between libretro C API and Swift
//
//  This header exposes a clean ObjC interface for the libretro core lifecycle.
//  The actual core symbol resolution is done in LibretroBridge.m.
//
//  When a libretro static library (.a) is linked into the project, define
//  YDRIVE_CORE_AVAILABLE=1 in Other C Flags (project.yml / Xcode build settings)
//  to activate the real implementation. Until then all calls are safe stubs.
// ─────────────────────────────────────────────────────────────────────────────

#ifndef LibretroBridge_h
#define LibretroBridge_h

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// ── Pixel format mirroring libretro RETRO_PIXEL_FORMAT_* constants ────────────
typedef NS_ENUM(NSInteger, YDrivePixelFormat) {
    YDrivePixelFormat0RGB1555 = 0,   // 15-bit, bit 15 always 0
    YDrivePixelFormatXRGB8888 = 1,   // 32-bit, X (alpha) ignored
    YDrivePixelFormatRGB565   = 2,   // 16-bit packed
};

// ── Frame data delivered per retro_run() cycle ────────────────────────────────
typedef struct {
    const void * _Nullable data;     // raw pixel pointer (may be NULL on dupe frame)
    unsigned int           width;
    unsigned int           height;
    size_t                 pitch;    // bytes per row
    YDrivePixelFormat      pixelFormat;
} YDriveVideoFrame;

// ── Callback block types ─────────────────────────────────────────────────────
typedef void (^YDriveVideoFrameCallback)(YDriveVideoFrame frame);

// ─────────────────────────────────────────────────────────────────────────────
/// Manages the full libretro core lifecycle on behalf of LibretroEmulatorEngine.
///
/// Thread safety: `loadGame:` and `unload` must be called from any single thread;
/// `runFrame` is called from the emulation background thread.
// ─────────────────────────────────────────────────────────────────────────────
@interface YDriveLibretroBridge : NSObject

/// YES when a core is loaded and a game has been successfully started.
@property (nonatomic, readonly) BOOL isRunning;

/// Geometry reported by the core after retro_load_game.
@property (nonatomic, readonly) unsigned int videoWidth;
@property (nonatomic, readonly) unsigned int videoHeight;
@property (nonatomic, readonly) float        aspectRatio;
@property (nonatomic, readonly) double       targetFPS;
@property (nonatomic, readonly) YDrivePixelFormat currentPixelFormat;

/// Called on the emulation thread each frame with the latest video data.
@property (nonatomic, copy, nullable) YDriveVideoFrameCallback onVideoFrame;

/// Initialize the core. Returns YES on success.
/// `romPath` must be the full filesystem path to the ROM file.
- (BOOL)loadGameAtPath:(NSString *)romPath error:(NSError **)error;

/// Run exactly one emulation frame. Call from a background thread at targetFPS cadence.
- (void)runFrame;

/// Stop emulation, unload game, and release core resources.
- (void)unload;

@end

NS_ASSUME_NONNULL_END

#endif /* LibretroBridge_h */
