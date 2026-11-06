#ifndef YD_CORE_VDP_H
#define YD_CORE_VDP_H

#include <stdint.h>
#include <stdbool.h>
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

/* ==========================================================================
 * SEGA Master System / Game Gear VDP (315-5124 / 315-5246) Constants
 * ========================================================================== */
#define YD_VDP_VRAM_SIZE           0x4000u  /* 16 KB Video RAM */
#define YD_VDP_CRAM_SIZE_SMS       0x20u    /* 32 Bytes Color RAM (SMS: 6-bit RGB) */
#define YD_VDP_CRAM_SIZE_GG        0x40u    /* 64 Bytes Color RAM (GG: 12-bit RGB) */
#define YD_VDP_NUM_REGS            16u      /* 16 Internal Control Registers */

#define YD_VDP_WIDTH               256u     /* Active horizontal resolution */
#define YD_VDP_HEIGHT_STD          192u     /* Standard Mode 4 vertical resolution */
#define YD_VDP_HEIGHT_EXT224       224u     /* Extended 224-line mode */
#define YD_VDP_HEIGHT_EXT240       240u     /* Extended 240-line mode */
#define YD_VDP_MAX_HEIGHT          240u     /* Maximum framebuffer height */
#define YD_VDP_FB_SIZE             (YD_VDP_WIDTH * YD_VDP_MAX_HEIGHT)

/* Game Gear Centered Active LCD Viewport (160x144 inside 256x192) */
#define YD_VDP_GG_VIEW_X           48u
#define YD_VDP_GG_VIEW_Y           24u
#define YD_VDP_GG_VIEW_W           160u
#define YD_VDP_GG_VIEW_H           144u

/* VDP Status Register Flags (Read via Port 0xBF) */
#define YD_VDP_STATUS_VBLANK       (1u << 7) /* Bit 7: Frame / V-Blank Interrupt Pending */
#define YD_VDP_STATUS_OVR          (1u << 6) /* Bit 6: Sprite Overflow (>8 sprites on line) */
#define YD_VDP_STATUS_COL          (1u << 5) /* Bit 5: Sprite Collision */

/* VDP Control Code Values (Bits 15-14 of Command Word) */
#define YD_VDP_CODE_VRAM_READ      0u
#define YD_VDP_CODE_VRAM_WRITE     1u
#define YD_VDP_CODE_REG_WRITE      2u
#define YD_VDP_CODE_CRAM_WRITE     3u

/* ==========================================================================
 * VDP State Structure
 * ========================================================================== */
typedef struct yd_vdp {
    /* Video & Color Memory */
    uint8_t  vram[YD_VDP_VRAM_SIZE];
    uint8_t  cram[YD_VDP_CRAM_SIZE_GG];
    uint32_t palette_lut[32];      /* Pre-converted 32-bit ARGB8888 palette cache */

    /* 16 VDP Control Registers */
    uint8_t  regs[YD_VDP_NUM_REGS];

    /* Command / Data Port State */
    uint16_t addr_reg;             /* 14-bit VRAM/CRAM address pointer (0x0000-0x3FFF) */
    uint8_t  code_reg;             /* 2-bit operation code (0..3) */
    uint8_t  read_buffer;          /* Pre-fetched VRAM read buffer for port 0xBE */
    uint8_t  cmd_low_byte;         /* Latched 1st byte written to control port 0xBF */
    uint8_t  cram_latch;           /* Latched even byte for Game Gear 12-bit CRAM writes */
    bool     first_byte_latched;   /* True if waiting for 2nd control byte on 0xBF */

    /* Status & Interrupt State */
    uint8_t  status;               /* Status flags (VBLANK | OVR | COL) */
    bool     line_irq_pending;     /* True when line counter underflows */
    uint8_t  line_counter;         /* Down-counter reloaded from R10 */
    uint8_t  v_scroll_latch;       /* Vertical scroll latched once per frame */

    /* Timing & Mode Configuration */
    uint16_t current_scanline;     /* Current scanline (0..261 NTSC, 0..312 PAL) */
    uint8_t  v_counter;            /* Hardware V-Counter value read on port 0x7E */
    uint8_t  h_counter;            /* Hardware H-Counter value read on port 0x7F */
    uint16_t active_height;        /* Active display height (192, 224, or 240) */
    bool     is_pal;               /* True for PAL (313 lines), false for NTSC (262 lines) */
    bool     is_game_gear;         /* True for Game Gear 12-bit CRAM mode */

    /* 32-bit ARGB8888 Output Framebuffer (0xFFRRGGBB) */
    uint32_t framebuffer[YD_VDP_FB_SIZE];
} yd_vdp_t;

/* ==========================================================================
 * VDP Public API
 * ========================================================================== */

/**
 * Initialize a VDP instance to power-on state.
 */
void yd_vdp_init(yd_vdp_t *vdp);

/**
 * Reset the VDP registers, latches, VRAM, CRAM, and framebuffer.
 */
void yd_vdp_reset(yd_vdp_t *vdp);

/**
 * Configure VDP console mode (Master System vs Game Gear) and video standard (NTSC vs PAL).
 */
void yd_vdp_set_config(yd_vdp_t *vdp, bool is_game_gear, bool is_pal);

/**
 * Rebuild the 32-entry 32-bit ARGB8888 palette cache from current CRAM contents.
 */
void yd_vdp_refresh_palette(yd_vdp_t *vdp);

/**
 * Read a byte from the VDP Data Port (0xBE).
 */
uint8_t yd_vdp_read_data(yd_vdp_t *vdp);

/**
 * Write a byte to the VDP Data Port (0xBE).
 */
void yd_vdp_write_data(yd_vdp_t *vdp, uint8_t val);

/**
 * Read the VDP Status Register from the Control Port (0xBF).
 * Clears status flags, line interrupt latch, and command byte latch.
 */
uint8_t yd_vdp_read_status(yd_vdp_t *vdp);

/**
 * Write a byte to the VDP Control Port (0xBF).
 */
void yd_vdp_write_control(yd_vdp_t *vdp, uint8_t val);

/**
 * Read the current V-Counter value (Port 0x7E).
 */
uint8_t yd_vdp_read_vcounter(const yd_vdp_t *vdp);

/**
 * Read the current H-Counter value (Port 0x7F).
 */
uint8_t yd_vdp_read_hcounter(const yd_vdp_t *vdp);

/**
 * Render a single active scanline (`scanline < vdp->active_height`) into `framebuffer`.
 */
void yd_vdp_render_scanline(yd_vdp_t *vdp, uint16_t scanline);

/**
 * Advance VDP scanline timing, update V-Counter, decrement Line Counter, and
 * latch V-Blank / Line Interrupt flags for `scanline`.
 */
void yd_vdp_step_scanline(yd_vdp_t *vdp, uint16_t scanline);

/**
 * Return true if the VDP is currently asserting the Z80 /INT line
 * (either V-Blank IRQ enabled & pending, or Line IRQ enabled & pending).
 */
bool yd_vdp_irq_asserted(const yd_vdp_t *vdp);

#ifdef __cplusplus
}
#endif

#endif /* YD_CORE_VDP_H */
