#ifndef YD_CORE_H
#define YD_CORE_H

#include <stdint.h>
#include <stdbool.h>
#include <stddef.h>
#include "z80.h"
#include "mmu.h"
#include "vdp.h"
#include "psg.h"
#include "io.h"
#include "m68k.h"
#include "md_mmu.h"
#include "md_vdp.h"
#include "ym2612.h"

#ifdef __cplusplus
extern "C" {
#endif

/* ==========================================================================
 * YD-Core Version & Hardware Timing Constants
 * ========================================================================== */
#define YD_CORE_VERSION_MAJOR            1
#define YD_CORE_VERSION_MINOR            2
#define YD_CORE_VERSION_PATCH            0
#define YD_CORE_VERSION_STRING           "1.2.0"

/* Save State Binary Header Constants ("YDSS") */
#define YD_STATE_MAGIC                   0x53534459u
#define YD_STATE_VERSION                 2u

/* SEGA Master System / Game Gear Clock & Frame Timing */
#define YD_SMS_CPU_CLOCK_NTSC            3579545u
#define YD_SMS_CPU_CLOCK_PAL             3546895u
#define YD_SMS_CYCLES_PER_SCANLINE       228
#define YD_SMS_SCANLINES_NTSC            262
#define YD_SMS_SCANLINES_PAL             313
#define YD_SMS_CYCLES_PER_FRAME_NTSC     (YD_SMS_CYCLES_PER_SCANLINE * YD_SMS_SCANLINES_NTSC) /* 59736 */
#define YD_SMS_CYCLES_PER_FRAME_PAL      (YD_SMS_CYCLES_PER_SCANLINE * YD_SMS_SCANLINES_PAL)  /* 71364 */

/* SEGA Genesis / Mega Drive Clock & Frame Timing */
#define YD_MD_CPU_CLOCK_NTSC             7670454u
#define YD_MD_CPU_CLOCK_PAL              7600489u
#define YD_MD_CYCLES_PER_SCANLINE        488
#define YD_MD_SCANLINES_NTSC_TOTAL       262
#define YD_MD_SCANLINES_PAL_TOTAL        313
#define YD_MD_CYCLES_PER_FRAME_NTSC      (YD_MD_CYCLES_PER_SCANLINE * YD_MD_SCANLINES_NTSC_TOTAL) /* 127856 */
#define YD_MD_CYCLES_PER_FRAME_PAL       (YD_MD_CYCLES_PER_SCANLINE * YD_MD_SCANLINES_PAL_TOTAL)  /* 152744 */

/* ==========================================================================
 * Target Console & Region Enumerations
 * ========================================================================== */
typedef enum yd_system_type {
    YD_SYSTEM_SMS = 0,      /* SEGA Master System / Mark III */
    YD_SYSTEM_GG  = 1,      /* SEGA Game Gear                */
    YD_SYSTEM_MD  = 2       /* SEGA Genesis / Mega Drive     */
} yd_system_type_t;

typedef enum yd_region {
    YD_REGION_NTSC = 0,     /* 60 Hz (262 scanlines) */
    YD_REGION_PAL  = 1      /* 50 Hz (313 scanlines) */
} yd_region_t;

/* ==========================================================================
 * Master Emulator Core Instance (`yd_core_t`)
 * ========================================================================== */
typedef struct yd_core {
    /* 8-bit SEGA Master System / Game Gear Subsystem */
    z80_cpu_t        cpu;
    yd_mmu_t         mmu;
    yd_vdp_t         vdp;
    yd_psg_t         psg;
    yd_io_t          io;

    /* 16/32-bit SEGA Genesis / Mega Drive Subsystem */
    m68k_cpu_t       md_cpu;
    yd_md_mmu_t      md_mmu;
    yd_md_vdp_t      md_vdp;
    yd_ym2612_t      ym2612;

    yd_system_type_t system;
    yd_region_t      region;

    uint64_t         frame_count;
    int32_t          cycle_deficit; /* Overshoot cycles carried across scanlines/frames */
    bool             rom_loaded;
} yd_core_t;

/* ==========================================================================
 * Public YD-Core Lifecycle & Execution API
 * ========================================================================== */

/**
 * Dynamically allocate and initialize a new `yd_core_t` instance.
 * Returns NULL if memory allocation fails.
 */
yd_core_t *yd_core_create(void);

/**
 * Free all resources owned by `core` and deallocate the instance.
 */
void yd_core_destroy(yd_core_t *core);

/**
 * Initialize an already-allocated `yd_core_t` structure in place and wire
 * both the SMS/GG (Z80) and Genesis/Mega Drive (M68K) subsystems together.
 */
void yd_core_init(yd_core_t *core);

/**
 * Configure target console type (SMS, Game Gear, or Genesis) and video region (NTSC vs PAL).
 */
void yd_core_set_system(yd_core_t *core, yd_system_type_t system, yd_region_t region);

/**
 * Auto-detect the target console (`YD_SYSTEM_MD`, `YD_SYSTEM_GG`, or `YD_SYSTEM_SMS`)
 * by inspecting the ROM header (`"SEGA MEGA DRIVE"`, `"SEGA GENESIS"`, `.smd` magic, or `"TMR SEGA"`).
 */
yd_system_type_t yd_core_detect_system(const uint8_t *rom_data, size_t rom_size);

/**
 * Configure the output PCM audio sample rate in Hz (e.g. 44100 or 48000).
 */
void yd_core_set_audio_sample_rate(yd_core_t *core, uint32_t sample_rate);

/**
 * Load a ROM buffer into the core, automatically detecting whether it is a
 * SEGA Genesis / Mega Drive or Master System / Game Gear cartridge.
 */
bool yd_core_load_rom(yd_core_t *core, const uint8_t *rom_data, size_t rom_size);

/**
 * Reset the active console subsystem to its initial hardware state.
 */
void yd_core_reset(yd_core_t *core);

/**
 * Execute a single CPU instruction on the active console and return clock cycles elapsed.
 */
int yd_core_step(yd_core_t *core);

/**
 * Run the emulation for one full video frame scanline-by-scanline,
 * rendering each active line into the VDP framebuffer, synthesizing PCM audio,
 * and servicing H-Blank and V-Blank interrupts.
 * Returns the total number of CPU clock cycles executed in this frame.
 */
int yd_core_run_frame(yd_core_t *core);

/* ==========================================================================
 * Save State Serialization API
 * ========================================================================== */

size_t yd_core_get_state_size(const yd_core_t *core);
bool   yd_core_save_state(const yd_core_t *core, uint8_t *buffer, size_t size);
bool   yd_core_load_state(yd_core_t *core, const uint8_t *buffer, size_t size);

/* ==========================================================================
 * Video, Audio & Input Accessors
 * ========================================================================== */

/**
 * Return a pointer to the active 32-bit ARGB8888 (`0xFFRRGGBB`) framebuffer
 * (256x192/224/240 for SMS/GG, or 320x224/256x224/320x240 for Genesis).
 */
const uint32_t *yd_core_get_framebuffer(const yd_core_t *core);

/**
 * Return a pointer to the interleaved 16-bit signed stereo PCM buffer (`L, R, L, R...`)
 * generated during the most recent frame, and write the number of stereo sample
 * pairs into `*out_stereo_samples` (if non-NULL).
 */
const int16_t *yd_core_get_audio_buffer(const yd_core_t *core, uint32_t *out_stereo_samples);

/**
 * Return the active framebuffer width in pixels (256 for SMS/GG, 320 or 256 for Genesis).
 */
uint16_t yd_core_get_screen_width(const yd_core_t *core);

/**
 * Return the active framebuffer height in pixels (192, 224, or 240).
 */
uint16_t yd_core_get_screen_height(const yd_core_t *core);

/**
 * Update controller button state for `player` (0 = Player 1, 1 = Player 2).
 * Accepts 8-bit `yd_button_t` for SMS/GG or 12-bit `yd_md_button_t` (including X/Y/Z/Mode) for Genesis.
 */
void yd_core_set_joypad(yd_core_t *core, int player, uint16_t buttons);

/**
 * Return the version string of YD-Core.
 */
const char *yd_core_version(void);

#ifdef __cplusplus
}
#endif

#endif /* YD_CORE_H */
