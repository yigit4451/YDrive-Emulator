#ifndef LIBRETRO_H__
#define LIBRETRO_H__

#include <stdint.h>
#include <stddef.h>
#include <stdbool.h>
#include <limits.h>

#ifdef __cplusplus
extern "C" {
#endif

#ifndef RETRO_CALLCONV
#  if defined(__GNUC__) && defined(__i386__) && !defined(__x86_64__)
#    define RETRO_CALLCONV __attribute__((cdecl))
#  elif defined(_MSC_VER) && defined(_M_IX86) && !defined(_M_X64)
#    define RETRO_CALLCONV __cdecl
#  else
#    define RETRO_CALLCONV
#  endif
#endif

#ifndef RETRO_API
#  if defined(_WIN32) || defined(__CYGWIN__)
#    ifdef YD_LIBRETRO_SHARED
#      define RETRO_API __declspec(dllexport)
#    else
#      define RETRO_API
#    endif
#  elif defined(__GNUC__) && __GNUC__ >= 4
#    define RETRO_API __attribute__((visibility("default")))
#  else
#    define RETRO_API
#  endif
#endif

/* ==========================================================================
 * Libretro API Version & Core Constants
 * ========================================================================== */
#define RETRO_API_VERSION         1

/* Device Types */
#define RETRO_DEVICE_TYPE_SHIFT   8
#define RETRO_DEVICE_MASK         ((1 << RETRO_DEVICE_TYPE_SHIFT) - 1)
#define RETRO_DEVICE_NONE         0
#define RETRO_DEVICE_JOYPAD       1
#define RETRO_DEVICE_MOUSE        2
#define RETRO_DEVICE_KEYBOARD     3
#define RETRO_DEVICE_LIGHTGUN     4
#define RETRO_DEVICE_ANALOG       5
#define RETRO_DEVICE_POINTER      6

/* Joypad Button IDs (RetroPad Standard) */
#define RETRO_DEVICE_ID_JOYPAD_B        0
#define RETRO_DEVICE_ID_JOYPAD_Y        1
#define RETRO_DEVICE_ID_JOYPAD_SELECT   2
#define RETRO_DEVICE_ID_JOYPAD_START    3
#define RETRO_DEVICE_ID_JOYPAD_UP       4
#define RETRO_DEVICE_ID_JOYPAD_DOWN     5
#define RETRO_DEVICE_ID_JOYPAD_LEFT     6
#define RETRO_DEVICE_ID_JOYPAD_RIGHT    7
#define RETRO_DEVICE_ID_JOYPAD_A        8
#define RETRO_DEVICE_ID_JOYPAD_X        9
#define RETRO_DEVICE_ID_JOYPAD_L       10
#define RETRO_DEVICE_ID_JOYPAD_R       11
#define RETRO_DEVICE_ID_JOYPAD_L2      12
#define RETRO_DEVICE_ID_JOYPAD_R2      13
#define RETRO_DEVICE_ID_JOYPAD_L3      14
#define RETRO_DEVICE_ID_JOYPAD_R3      15
#define RETRO_DEVICE_ID_JOYPAD_MASK   256

/* Region Constants */
#define RETRO_REGION_NTSC         0
#define RETRO_REGION_PAL          1

/* Memory Type Constants */
#define RETRO_MEMORY_MASK         0xff
#define RETRO_MEMORY_SAVE_RAM     0
#define RETRO_MEMORY_RTC          1
#define RETRO_MEMORY_SYSTEM_RAM   2
#define RETRO_MEMORY_VIDEO_RAM    3

/* Environment Commands */
#define RETRO_ENVIRONMENT_SET_ROTATION            1
#define RETRO_ENVIRONMENT_GET_OVERSCAN            2
#define RETRO_ENVIRONMENT_GET_CAN_DUPE            3
#define RETRO_ENVIRONMENT_SET_MESSAGE             6
#define RETRO_ENVIRONMENT_SHUTDOWN                7
#define RETRO_ENVIRONMENT_SET_PERFORMANCE_LEVEL   8
#define RETRO_ENVIRONMENT_GET_SYSTEM_DIRECTORY    9
#define RETRO_ENVIRONMENT_SET_PIXEL_FORMAT       10
#define RETRO_ENVIRONMENT_SET_INPUT_DESCRIPTORS  11
#define RETRO_ENVIRONMENT_GET_VARIABLE           15
#define RETRO_ENVIRONMENT_SET_VARIABLES          16
#define RETRO_ENVIRONMENT_GET_VARIABLE_UPDATE    17
#define RETRO_ENVIRONMENT_SET_SUPPORT_NO_GAME    18
#define RETRO_ENVIRONMENT_GET_SAVE_DIRECTORY     31

/* Pixel Formats */
enum retro_pixel_format {
    RETRO_PIXEL_FORMAT_0RGB1555 = 0,
    RETRO_PIXEL_FORMAT_XRGB8888 = 1,
    RETRO_PIXEL_FORMAT_RGB565   = 2,
    RETRO_PIXEL_FORMAT_UNKNOWN  = INT_MAX
};

/* Core Variable Structure */
struct retro_variable {
    const char *key;
    const char *value;
};

/* Input Descriptor Structure */
struct retro_input_descriptor {
    unsigned    port;
    unsigned    device;
    unsigned    index;
    unsigned    id;
    const char *description;
};

/* System Information Structure */
struct retro_system_info {
    const char *library_name;
    const char *library_version;
    const char *valid_extensions;
    bool        need_fullpath;
    bool        block_extract;
};

/* Audio / Video Geometry & Timing Structures */
struct retro_game_geometry {
    unsigned base_width;
    unsigned base_height;
    unsigned max_width;
    unsigned max_height;
    float    aspect_ratio;
};

struct retro_system_timing {
    double fps;
    double sample_rate;
};

struct retro_system_av_info {
    struct retro_game_geometry geometry;
    struct retro_system_timing timing;
};

/* Game Information Structure */
struct retro_game_info {
    const char *path;
    const void *data;
    size_t      size;
    const char *meta;
};

/* ==========================================================================
 * Libretro Callback Function Pointer Types
 * ========================================================================== */
typedef bool    (RETRO_CALLCONV *retro_environment_t)(unsigned cmd, void *data);
typedef void    (RETRO_CALLCONV *retro_video_refresh_t)(const void *data, unsigned width, unsigned height, size_t pitch);
typedef void    (RETRO_CALLCONV *retro_audio_sample_t)(int16_t left, int16_t right);
typedef size_t  (RETRO_CALLCONV *retro_audio_sample_batch_t)(const int16_t *data, size_t frames);
typedef void    (RETRO_CALLCONV *retro_input_poll_t)(void);
typedef int16_t (RETRO_CALLCONV *retro_input_state_t)(unsigned port, unsigned device, unsigned index, unsigned id);

/* ==========================================================================
 * Standard Libretro Core Public Entry Points
 * ========================================================================== */
RETRO_API void     RETRO_CALLCONV retro_set_environment(retro_environment_t cb);
RETRO_API void     RETRO_CALLCONV retro_set_video_refresh(retro_video_refresh_t cb);
RETRO_API void     RETRO_CALLCONV retro_set_audio_sample(retro_audio_sample_t cb);
RETRO_API void     RETRO_CALLCONV retro_set_audio_sample_batch(retro_audio_sample_batch_t cb);
RETRO_API void     RETRO_CALLCONV retro_set_input_poll(retro_input_poll_t cb);
RETRO_API void     RETRO_CALLCONV retro_set_input_state(retro_input_state_t cb);
RETRO_API void     RETRO_CALLCONV retro_init(void);
RETRO_API void     RETRO_CALLCONV retro_deinit(void);
RETRO_API unsigned RETRO_CALLCONV retro_api_version(void);
RETRO_API void     RETRO_CALLCONV retro_get_system_info(struct retro_system_info *info);
RETRO_API void     RETRO_CALLCONV retro_get_system_av_info(struct retro_system_av_info *info);
RETRO_API void     RETRO_CALLCONV retro_set_controller_port_device(unsigned port, unsigned device);
RETRO_API void     RETRO_CALLCONV retro_reset(void);
RETRO_API void     RETRO_CALLCONV retro_run(void);
RETRO_API size_t   RETRO_CALLCONV retro_serialize_size(void);
RETRO_API bool     RETRO_CALLCONV retro_serialize(void *data, size_t size);
RETRO_API bool     RETRO_CALLCONV retro_unserialize(const void *data, size_t size);
RETRO_API void     RETRO_CALLCONV retro_cheat_reset(void);
RETRO_API void     RETRO_CALLCONV retro_cheat_set(unsigned index, bool enabled, const char *code);
RETRO_API bool     RETRO_CALLCONV retro_load_game(const struct retro_game_info *game);
RETRO_API bool     RETRO_CALLCONV retro_load_game_special(unsigned game_type, const struct retro_game_info *info, size_t num_info);
RETRO_API void     RETRO_CALLCONV retro_unload_game(void);
RETRO_API unsigned RETRO_CALLCONV retro_get_region(void);
RETRO_API void    *RETRO_CALLCONV retro_get_memory_data(unsigned id);
RETRO_API size_t   RETRO_CALLCONV retro_get_memory_size(unsigned id);

/* ==========================================================================
 * Namespaced YD-Core Libretro Entry Points (for Multi-Core Static Linking)
 *
 * Allows iOS hosts that statically link both PicoDrive (`retro_*`) and
 * YD-Core (`yd_retro_*`) into the same executable to switch between cores
 * dynamically at runtime without linker symbol collisions.
 * ========================================================================== */
RETRO_API void     RETRO_CALLCONV yd_retro_set_environment(retro_environment_t cb);
RETRO_API void     RETRO_CALLCONV yd_retro_set_video_refresh(retro_video_refresh_t cb);
RETRO_API void     RETRO_CALLCONV yd_retro_set_audio_sample(retro_audio_sample_t cb);
RETRO_API void     RETRO_CALLCONV yd_retro_set_audio_sample_batch(retro_audio_sample_batch_t cb);
RETRO_API void     RETRO_CALLCONV yd_retro_set_input_poll(retro_input_poll_t cb);
RETRO_API void     RETRO_CALLCONV yd_retro_set_input_state(retro_input_state_t cb);
RETRO_API void     RETRO_CALLCONV yd_retro_init(void);
RETRO_API void     RETRO_CALLCONV yd_retro_deinit(void);
RETRO_API unsigned RETRO_CALLCONV yd_retro_api_version(void);
RETRO_API void     RETRO_CALLCONV yd_retro_get_system_info(struct retro_system_info *info);
RETRO_API void     RETRO_CALLCONV yd_retro_get_system_av_info(struct retro_system_av_info *info);
RETRO_API void     RETRO_CALLCONV yd_retro_set_controller_port_device(unsigned port, unsigned device);
RETRO_API void     RETRO_CALLCONV yd_retro_reset(void);
RETRO_API void     RETRO_CALLCONV yd_retro_run(void);
RETRO_API size_t   RETRO_CALLCONV yd_retro_serialize_size(void);
RETRO_API bool     RETRO_CALLCONV yd_retro_serialize(void *data, size_t size);
RETRO_API bool     RETRO_CALLCONV yd_retro_unserialize(const void *data, size_t size);
RETRO_API void     RETRO_CALLCONV yd_retro_cheat_reset(void);
RETRO_API void     RETRO_CALLCONV yd_retro_cheat_set(unsigned index, bool enabled, const char *code);
RETRO_API bool     RETRO_CALLCONV yd_retro_load_game(const struct retro_game_info *game);
RETRO_API bool     RETRO_CALLCONV yd_retro_load_game_special(unsigned game_type, const struct retro_game_info *info, size_t num_info);
RETRO_API void     RETRO_CALLCONV yd_retro_unload_game(void);
RETRO_API unsigned RETRO_CALLCONV yd_retro_get_region(void);
RETRO_API void    *RETRO_CALLCONV yd_retro_get_memory_data(unsigned id);
RETRO_API size_t   RETRO_CALLCONV yd_retro_get_memory_size(unsigned id);

#ifdef __cplusplus
}
#endif

#endif /* LIBRETRO_H__ */
