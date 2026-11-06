#include "libretro.h"
#include "yd_core.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/* ==========================================================================
 * Global Libretro Core State & Registered Host Callbacks
 * ========================================================================== */
static yd_core_t                 *g_core                = NULL;
static retro_environment_t        g_environ_cb          = NULL;
static retro_video_refresh_t      g_video_cb            = NULL;
static retro_audio_sample_t       g_audio_cb            = NULL;
static retro_audio_sample_batch_t g_audio_batch_cb      = NULL;
static retro_input_poll_t         g_input_poll_cb       = NULL;
static retro_input_state_t        g_input_state_cb      = NULL;

/* Experimental Core Options */
static bool    g_opt_fast_memory         = true;
static bool    g_opt_audio_interpolation = true;
static bool    g_opt_force_6button       = false;
static int16_t g_prev_audio_l            = 0;
static int16_t g_prev_audio_r            = 0;
static int16_t g_interp_pcm[YD_PSG_MAX_SAMPLES_PER_FRAME * 2u];

/* ==========================================================================
 * Internal Helpers: Core Options & Input Polling
 * ========================================================================== */

static bool yd_str_ends_with_ci(const char *str, const char *suffix) {
    if (!str || !suffix) {
        return false;
    }
    size_t slen = strlen(str);
    size_t xlen = strlen(suffix);
    if (xlen > slen) {
        return false;
    }
    const char *p = str + (slen - xlen);
    for (size_t i = 0; i < xlen; i++) {
        char c1 = p[i];
        char c2 = suffix[i];
        if (c1 >= 'A' && c1 <= 'Z') c1 = (char)(c1 + ('a' - 'A'));
        if (c2 >= 'A' && c2 <= 'Z') c2 = (char)(c2 + ('a' - 'A'));
        if (c1 != c2) {
            return false;
        }
    }
    return true;
}

static void yd_retro_update_variables(void) {
    if (!g_environ_cb) {
        return;
    }

    struct retro_variable var;

    var.key   = "yd_fast_memory";
    var.value = NULL;
    if (g_environ_cb(RETRO_ENVIRONMENT_GET_VARIABLE, &var) && var.value) {
        g_opt_fast_memory = (strcmp(var.value, "disabled") != 0 &&
                             strcmp(var.value, "false") != 0 &&
                             strcmp(var.value, "0") != 0);
    }

    var.key   = "yd_audio_interpolation";
    var.value = NULL;
    if (g_environ_cb(RETRO_ENVIRONMENT_GET_VARIABLE, &var) && var.value) {
        g_opt_audio_interpolation = (strcmp(var.value, "disabled") != 0 &&
                                     strcmp(var.value, "false") != 0 &&
                                     strcmp(var.value, "0") != 0);
    }

    var.key   = "yd_force_6button_pad";
    var.value = NULL;
    if (g_environ_cb(RETRO_ENVIRONMENT_GET_VARIABLE, &var) && var.value) {
        g_opt_force_6button = (strcmp(var.value, "enabled") == 0 ||
                               strcmp(var.value, "true") == 0 ||
                               strcmp(var.value, "1") == 0);
    }

    if (g_core) {
        g_core->md_mmu.check_address_error = !g_opt_fast_memory;
        g_core->md_mmu.six_button_enabled  = true;
    }
}

static uint16_t yd_retro_query_joypad_bits(unsigned port) {
    if (!g_input_state_cb) {
        return 0u;
    }

    uint16_t mask = 0u;
    for (unsigned id = 0; id <= RETRO_DEVICE_ID_JOYPAD_R; id++) {
        if (g_input_state_cb(port, RETRO_DEVICE_JOYPAD, 0, id) != 0) {
            mask |= (uint16_t)(1u << id);
        }
    }
    return mask;
}

static void yd_retro_poll_inputs(void) {
    if (!g_core || !g_input_poll_cb || !g_input_state_cb) {
        return;
    }

    g_input_poll_cb();

    for (unsigned port = 0; port < 2; port++) {
        uint16_t raw = yd_retro_query_joypad_bits(port);

        if (g_core->system == YD_SYSTEM_MD) {
            /* SEGA Genesis 3-Button / 6-Button Controller Mapping */
            uint16_t md_btns = 0u;
            if (raw & (1u << RETRO_DEVICE_ID_JOYPAD_UP))     md_btns |= YD_MD_BTN_UP;
            if (raw & (1u << RETRO_DEVICE_ID_JOYPAD_DOWN))   md_btns |= YD_MD_BTN_DOWN;
            if (raw & (1u << RETRO_DEVICE_ID_JOYPAD_LEFT))   md_btns |= YD_MD_BTN_LEFT;
            if (raw & (1u << RETRO_DEVICE_ID_JOYPAD_RIGHT))  md_btns |= YD_MD_BTN_RIGHT;
            if (raw & (1u << RETRO_DEVICE_ID_JOYPAD_Y))      md_btns |= YD_MD_BTN_A;
            if (raw & (1u << RETRO_DEVICE_ID_JOYPAD_B))      md_btns |= YD_MD_BTN_B;
            if (raw & (1u << RETRO_DEVICE_ID_JOYPAD_A))      md_btns |= YD_MD_BTN_C;
            if (raw & (1u << RETRO_DEVICE_ID_JOYPAD_START))  md_btns |= YD_MD_BTN_START;
            if (raw & (1u << RETRO_DEVICE_ID_JOYPAD_X))      md_btns |= YD_MD_BTN_X;
            if (raw & (1u << RETRO_DEVICE_ID_JOYPAD_L))      md_btns |= YD_MD_BTN_Y;
            if (raw & (1u << RETRO_DEVICE_ID_JOYPAD_R))      md_btns |= YD_MD_BTN_Z;
            if (raw & (1u << RETRO_DEVICE_ID_JOYPAD_SELECT)) md_btns |= YD_MD_BTN_MODE;

            yd_core_set_joypad(g_core, (int)port, md_btns);
        } else {
            /* SEGA Master System / Game Gear 2-Button Controller Mapping */
            uint16_t sms_btns = 0u;
            if (raw & (1u << RETRO_DEVICE_ID_JOYPAD_UP))    sms_btns |= YD_PAD_UP;
            if (raw & (1u << RETRO_DEVICE_ID_JOYPAD_DOWN))  sms_btns |= YD_PAD_DOWN;
            if (raw & (1u << RETRO_DEVICE_ID_JOYPAD_LEFT))  sms_btns |= YD_PAD_LEFT;
            if (raw & (1u << RETRO_DEVICE_ID_JOYPAD_RIGHT)) sms_btns |= YD_PAD_RIGHT;
            if (raw & ((1u << RETRO_DEVICE_ID_JOYPAD_B) | (1u << RETRO_DEVICE_ID_JOYPAD_Y))) {
                sms_btns |= YD_PAD_BTN1;
            }
            if (raw & (1u << RETRO_DEVICE_ID_JOYPAD_A))     sms_btns |= YD_PAD_BTN2;
            if (raw & (1u << RETRO_DEVICE_ID_JOYPAD_START)) sms_btns |= YD_PAD_START;

            /* Note: yd_io_set_joypad automatically triggers Z80 NMI on P1 Start rising edge in SMS mode */
            yd_core_set_joypad(g_core, (int)port, sms_btns);
        }
    }
}

/* ==========================================================================
 * Namespaced YD-Core Libretro Implementation (`yd_retro_*`)
 * ========================================================================== */

RETRO_API unsigned RETRO_CALLCONV yd_retro_api_version(void) {
    return RETRO_API_VERSION;
}

RETRO_API void RETRO_CALLCONV yd_retro_set_environment(retro_environment_t cb) {
    g_environ_cb = cb;
}

RETRO_API void RETRO_CALLCONV yd_retro_set_video_refresh(retro_video_refresh_t cb) {
    g_video_cb = cb;
}

RETRO_API void RETRO_CALLCONV yd_retro_set_audio_sample(retro_audio_sample_t cb) {
    g_audio_cb = cb;
}

RETRO_API void RETRO_CALLCONV yd_retro_set_audio_sample_batch(retro_audio_sample_batch_t cb) {
    g_audio_batch_cb = cb;
}

RETRO_API void RETRO_CALLCONV yd_retro_set_input_poll(retro_input_poll_t cb) {
    g_input_poll_cb = cb;
}

RETRO_API void RETRO_CALLCONV yd_retro_set_input_state(retro_input_state_t cb) {
    g_input_state_cb = cb;
}

RETRO_API void RETRO_CALLCONV yd_retro_init(void) {
    if (!g_core) {
        g_core = yd_core_create();
    } else {
        yd_core_init(g_core);
    }
    g_prev_audio_l = 0;
    g_prev_audio_r = 0;
}

RETRO_API void RETRO_CALLCONV yd_retro_deinit(void) {
    if (g_core) {
        yd_core_destroy(g_core);
        g_core = NULL;
    }
}

RETRO_API void RETRO_CALLCONV yd_retro_get_system_info(struct retro_system_info *info) {
    if (!info) {
        return;
    }
    memset(info, 0, sizeof(*info));
    info->library_name     = "YD-Core";
    info->library_version  = YD_CORE_VERSION_STRING;
    info->valid_extensions = "sms|gg|md|gen|bin|smd";
    info->need_fullpath    = false;
    info->block_extract    = false;
}

RETRO_API void RETRO_CALLCONV yd_retro_get_system_av_info(struct retro_system_av_info *info) {
    if (!info) {
        return;
    }
    memset(info, 0, sizeof(*info));

    uint16_t width  = 320u;
    uint16_t height = 224u;
    double   fps    = 60.0;
    double   srate  = (double)YD_PSG_DEFAULT_SAMPLE_RATE;
    float    aspect = 4.0f / 3.0f;

    if (g_core) {
        if (g_core->system == YD_SYSTEM_GG) {
            width  = YD_VDP_GG_VIEW_W;
            height = YD_VDP_GG_VIEW_H;
            aspect = (float)YD_VDP_GG_VIEW_W / (float)YD_VDP_GG_VIEW_H;
        } else {
            width  = yd_core_get_screen_width(g_core);
            height = yd_core_get_screen_height(g_core);
            aspect = 4.0f / 3.0f;
        }
        fps   = (g_core->region == YD_REGION_PAL) ? 50.0 : 60.0;
        srate = (double)g_core->psg.sample_rate;
    }

    info->geometry.base_width   = width;
    info->geometry.base_height  = height;
    info->geometry.max_width    = YD_MD_VDP_MAX_WIDTH;
    info->geometry.max_height   = YD_MD_VDP_HEIGHT_V30;
    info->geometry.aspect_ratio = aspect;

    info->timing.fps         = fps;
    info->timing.sample_rate = srate;
}

RETRO_API void RETRO_CALLCONV yd_retro_set_controller_port_device(unsigned port, unsigned device) {
    (void)port;
    (void)device;
}

RETRO_API void RETRO_CALLCONV yd_retro_reset(void) {
    if (g_core) {
        yd_core_reset(g_core);
    }
}

RETRO_API bool RETRO_CALLCONV yd_retro_load_game(const struct retro_game_info *game) {
    if (!game) {
        return false;
    }
    if (!g_core) {
        yd_retro_init();
        if (!g_core) {
            return false;
        }
    }

    enum retro_pixel_format fmt = RETRO_PIXEL_FORMAT_XRGB8888;
    if (g_environ_cb) {
        g_environ_cb(RETRO_ENVIRONMENT_SET_PIXEL_FORMAT, &fmt);
    }

    const uint8_t *rom_buf  = (const uint8_t *)game->data;
    size_t         rom_size = game->size;
    uint8_t       *temp_buf = NULL;

    /* Fallback: if host passed only a file path without reading into memory */
    if ((!rom_buf || rom_size == 0u) && game->path) {
        FILE *fp = fopen(game->path, "rb");
        if (!fp) {
            return false;
        }
        if (fseek(fp, 0, SEEK_END) != 0) {
            fclose(fp);
            return false;
        }
        long flen = ftell(fp);
        if (flen <= 0 || fseek(fp, 0, SEEK_SET) != 0) {
            fclose(fp);
            return false;
        }
        temp_buf = (uint8_t *)malloc((size_t)flen);
        if (!temp_buf) {
            fclose(fp);
            return false;
        }
        if (fread(temp_buf, 1u, (size_t)flen, fp) != (size_t)flen) {
            free(temp_buf);
            fclose(fp);
            return false;
        }
        fclose(fp);
        rom_buf  = temp_buf;
        rom_size = (size_t)flen;
    }

    if (!rom_buf || rom_size == 0u) {
        if (temp_buf) free(temp_buf);
        return false;
    }

    /* Hint Game Gear console type if file extension is .gg */
    if (game->path && yd_str_ends_with_ci(game->path, ".gg")) {
        yd_core_set_system(g_core, YD_SYSTEM_GG, g_core->region);
    } else {
        yd_core_set_system(g_core, YD_SYSTEM_SMS, g_core->region);
    }

    bool ok = yd_core_load_rom(g_core, rom_buf, rom_size);
    if (temp_buf) {
        free(temp_buf);
    }

    if (ok) {
        yd_retro_update_variables();
    }
    return ok;
}

RETRO_API bool RETRO_CALLCONV yd_retro_load_game_special(unsigned game_type, const struct retro_game_info *info, size_t num_info) {
    (void)game_type;
    if (num_info > 0 && info) {
        return yd_retro_load_game(&info[0]);
    }
    return false;
}

RETRO_API void RETRO_CALLCONV yd_retro_unload_game(void) {
    if (g_core) {
        yd_mmu_destroy(&g_core->mmu);
        yd_md_mmu_destroy(&g_core->md_mmu);
        yd_core_init(g_core);
    }
}

RETRO_API unsigned RETRO_CALLCONV yd_retro_get_region(void) {
    if (g_core && g_core->region == YD_REGION_PAL) {
        return RETRO_REGION_PAL;
    }
    return RETRO_REGION_NTSC;
}

RETRO_API void RETRO_CALLCONV yd_retro_run(void) {
    if (!g_core) {
        return;
    }

    /* 1. Poll host controller state and map to SMS/GG/Genesis buttons */
    yd_retro_poll_inputs();

    /* 2. Execute one full emulation frame */
    yd_core_run_frame(g_core);

    /* 3. Output 32-bit XRGB8888 Video Frame */
    if (g_video_cb) {
        const uint32_t *fb = yd_core_get_framebuffer(g_core);
        if (g_core->system == YD_SYSTEM_GG) {
            /* Crop Game Gear 160x144 active viewport from 256x192 VDP buffer */
            const uint32_t *gg_fb = fb + (YD_VDP_GG_VIEW_Y * YD_VDP_WIDTH) + YD_VDP_GG_VIEW_X;
            g_video_cb(gg_fb,
                       YD_VDP_GG_VIEW_W,
                       YD_VDP_GG_VIEW_H,
                       YD_VDP_WIDTH * sizeof(uint32_t));
        } else {
            uint16_t w = yd_core_get_screen_width(g_core);
            uint16_t h = yd_core_get_screen_height(g_core);
            g_video_cb(fb, w, h, (size_t)w * sizeof(uint32_t));
        }
    }

    /* 4. Output 44.1 kHz Stereo PCM Audio Batch */
    uint32_t       num_samples = 0u;
    const int16_t *pcm         = yd_core_get_audio_buffer(g_core, &num_samples);
    if (pcm && num_samples > 0u) {
        const int16_t *out_pcm = pcm;

        if (g_opt_audio_interpolation && num_samples <= YD_PSG_MAX_SAMPLES_PER_FRAME) {
            int16_t prev_l = g_prev_audio_l;
            int16_t prev_r = g_prev_audio_r;
            for (uint32_t i = 0; i < num_samples; i++) {
                int16_t cur_l = pcm[i * 2u + 0u];
                int16_t cur_r = pcm[i * 2u + 1u];
                g_interp_pcm[i * 2u + 0u] = (int16_t)(((int32_t)cur_l * 3 + (int32_t)prev_l) >> 2);
                g_interp_pcm[i * 2u + 1u] = (int16_t)(((int32_t)cur_r * 3 + (int32_t)prev_r) >> 2);
                prev_l = cur_l;
                prev_r = cur_r;
            }
            g_prev_audio_l = prev_l;
            g_prev_audio_r = prev_r;
            out_pcm        = g_interp_pcm;
        }

        if (g_audio_batch_cb) {
            g_audio_batch_cb(out_pcm, num_samples);
        } else if (g_audio_cb) {
            for (uint32_t i = 0; i < num_samples; i++) {
                g_audio_cb(out_pcm[i * 2u + 0u], out_pcm[i * 2u + 1u]);
            }
        }
    }
}

RETRO_API size_t RETRO_CALLCONV yd_retro_serialize_size(void) {
    return yd_core_get_state_size(g_core);
}

RETRO_API bool RETRO_CALLCONV yd_retro_serialize(void *data, size_t size) {
    if (!g_core || !data) {
        return false;
    }
    return yd_core_save_state(g_core, (uint8_t *)data, size);
}

RETRO_API bool RETRO_CALLCONV yd_retro_unserialize(const void *data, size_t size) {
    if (!g_core || !data) {
        return false;
    }
    return yd_core_load_state(g_core, (const uint8_t *)data, size);
}

RETRO_API void RETRO_CALLCONV yd_retro_cheat_reset(void) {
}

RETRO_API void RETRO_CALLCONV yd_retro_cheat_set(unsigned index, bool enabled, const char *code) {
    (void)index;
    (void)enabled;
    (void)code;
}

RETRO_API void *RETRO_CALLCONV yd_retro_get_memory_data(unsigned id) {
    if (!g_core) {
        return NULL;
    }
    switch (id & RETRO_MEMORY_MASK) {
        case RETRO_MEMORY_SAVE_RAM:
            return (g_core->system == YD_SYSTEM_MD)
                   ? (void *)g_core->md_mmu.sram
                   : (void *)g_core->mmu.cart_ram;
        case RETRO_MEMORY_SYSTEM_RAM:
            return (g_core->system == YD_SYSTEM_MD)
                   ? (void *)g_core->md_mmu.work_ram
                   : (void *)g_core->mmu.sys_ram;
        case RETRO_MEMORY_VIDEO_RAM:
            return (g_core->system == YD_SYSTEM_MD)
                   ? (void *)g_core->md_vdp.vram
                   : (void *)g_core->vdp.vram;
        default:
            return NULL;
    }
}

RETRO_API size_t RETRO_CALLCONV yd_retro_get_memory_size(unsigned id) {
    if (!g_core) {
        return 0u;
    }
    switch (id & RETRO_MEMORY_MASK) {
        case RETRO_MEMORY_SAVE_RAM:
            return (g_core->system == YD_SYSTEM_MD)
                   ? YD_MD_SRAM_SIZE
                   : YD_MMU_CART_RAM_SIZE;
        case RETRO_MEMORY_SYSTEM_RAM:
            return (g_core->system == YD_SYSTEM_MD)
                   ? YD_MD_WORK_RAM_SIZE
                   : YD_MMU_SYS_RAM_SIZE;
        case RETRO_MEMORY_VIDEO_RAM:
            return (g_core->system == YD_SYSTEM_MD)
                   ? YD_MD_VDP_VRAM_SIZE
                   : YD_VDP_VRAM_SIZE;
        default:
            return 0u;
    }
}

/* ==========================================================================
 * Standard Unprefixed Libretro Exports (`retro_*`)
 *
 * Included by default when building `libydcore_libretro.a` standalone.
 * Define `YD_LIBRETRO_PREFIX_ONLY` when statically linking alongside another
 * Libretro core (e.g. `libpicodrive.a`) in a single iOS binary.
 * ========================================================================== */
#ifndef YD_LIBRETRO_PREFIX_ONLY

RETRO_API unsigned RETRO_CALLCONV retro_api_version(void) {
    return yd_retro_api_version();
}

RETRO_API void RETRO_CALLCONV retro_set_environment(retro_environment_t cb) {
    yd_retro_set_environment(cb);
}

RETRO_API void RETRO_CALLCONV retro_set_video_refresh(retro_video_refresh_t cb) {
    yd_retro_set_video_refresh(cb);
}

RETRO_API void RETRO_CALLCONV retro_set_audio_sample(retro_audio_sample_t cb) {
    yd_retro_set_audio_sample(cb);
}

RETRO_API void RETRO_CALLCONV retro_set_audio_sample_batch(retro_audio_sample_batch_t cb) {
    yd_retro_set_audio_sample_batch(cb);
}

RETRO_API void RETRO_CALLCONV retro_set_input_poll(retro_input_poll_t cb) {
    yd_retro_set_input_poll(cb);
}

RETRO_API void RETRO_CALLCONV retro_set_input_state(retro_input_state_t cb) {
    yd_retro_set_input_state(cb);
}

RETRO_API void RETRO_CALLCONV retro_init(void) {
    yd_retro_init();
}

RETRO_API void RETRO_CALLCONV retro_deinit(void) {
    yd_retro_deinit();
}

RETRO_API void RETRO_CALLCONV retro_get_system_info(struct retro_system_info *info) {
    yd_retro_get_system_info(info);
}

RETRO_API void RETRO_CALLCONV retro_get_system_av_info(struct retro_system_av_info *info) {
    yd_retro_get_system_av_info(info);
}

RETRO_API void RETRO_CALLCONV retro_set_controller_port_device(unsigned port, unsigned device) {
    yd_retro_set_controller_port_device(port, device);
}

RETRO_API void RETRO_CALLCONV retro_reset(void) {
    yd_retro_reset();
}

RETRO_API void RETRO_CALLCONV retro_run(void) {
    yd_retro_run();
}

RETRO_API size_t RETRO_CALLCONV retro_serialize_size(void) {
    return yd_retro_serialize_size();
}

RETRO_API bool RETRO_CALLCONV retro_serialize(void *data, size_t size) {
    return yd_retro_serialize(data, size);
}

RETRO_API bool RETRO_CALLCONV retro_unserialize(const void *data, size_t size) {
    return yd_retro_unserialize(data, size);
}

RETRO_API void RETRO_CALLCONV retro_cheat_reset(void) {
    yd_retro_cheat_reset();
}

RETRO_API void RETRO_CALLCONV retro_cheat_set(unsigned index, bool enabled, const char *code) {
    yd_retro_cheat_set(index, enabled, code);
}

RETRO_API bool RETRO_CALLCONV retro_load_game(const struct retro_game_info *game) {
    return yd_retro_load_game(game);
}

RETRO_API bool RETRO_CALLCONV retro_load_game_special(unsigned game_type, const struct retro_game_info *info, size_t num_info) {
    return yd_retro_load_game_special(game_type, info, num_info);
}

RETRO_API void RETRO_CALLCONV retro_unload_game(void) {
    yd_retro_unload_game();
}

RETRO_API unsigned RETRO_CALLCONV retro_get_region(void) {
    return yd_retro_get_region();
}

RETRO_API void *RETRO_CALLCONV retro_get_memory_data(unsigned id) {
    return yd_retro_get_memory_data(id);
}

RETRO_API size_t RETRO_CALLCONV retro_get_memory_size(unsigned id) {
    return yd_retro_get_memory_size(id);
}

#endif /* YD_LIBRETRO_PREFIX_ONLY */
