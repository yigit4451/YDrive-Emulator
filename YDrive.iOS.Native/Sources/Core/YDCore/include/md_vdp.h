#ifndef YD_CORE_MD_VDP_H
#define YD_CORE_MD_VDP_H

#include <stdint.h>
#include <stdbool.h>
#include <stddef.h>
#include "m68k.h"
#include "md_mmu.h"

#ifdef __cplusplus
extern "C" {
#endif

/* ==========================================================================
 * SEGA Genesis / Mega Drive VDP (Yamaha YM7101 / 315-5313, Mode 5) Constants
 * ========================================================================== */
#define YD_MD_VDP_VRAM_SIZE        0x10000u /* 64 KB Video RAM                   */
#define YD_MD_VDP_CRAM_WORDS       64u      /* 64 x 16-bit Color RAM (128 bytes) */
#define YD_MD_VDP_VSRAM_WORDS      40u      /* 40 x 16-bit Vertical Scroll RAM   */
#define YD_MD_VDP_NUM_REGS         24u      /* 24 Mode 5 Control Registers       */

#define YD_MD_VDP_WIDTH_H40        320u     /* H40 mode horizontal width (40 cells) */
#define YD_MD_VDP_WIDTH_H32        256u     /* H32 mode horizontal width (32 cells) */
#define YD_MD_VDP_HEIGHT_V28       224u     /* V28 NTSC/PAL standard height         */
#define YD_MD_VDP_HEIGHT_V30       240u     /* V30 PAL extended height              */
#define YD_MD_VDP_MAX_WIDTH        320u
#define YD_MD_VDP_MAX_HEIGHT       240u
#define YD_MD_VDP_FB_SIZE          (YD_MD_VDP_MAX_WIDTH * YD_MD_VDP_MAX_HEIGHT)

#define YD_MD_SCANLINES_NTSC       262u     /* Total scanlines per NTSC frame    */
#define YD_MD_SCANLINES_PAL        313u     /* Total scanlines per PAL frame     */
#define YD_MD_CYCLES_PER_LINE      488      /* M68K cycles per scanline (~7.67MHz)*/

/* Genesis VDP Status Register Bitmasks (Port 0xC00004 Read) */
#define YD_MD_VDP_STATUS_EMPTY     (1u << 9) /* FIFO Empty                      */
#define YD_MD_VDP_STATUS_FULL      (1u << 8) /* FIFO Full                       */
#define YD_MD_VDP_STATUS_VIP       (1u << 7) /* V-Blank Interrupt Pending       */
#define YD_MD_VDP_STATUS_SOVR      (1u << 6) /* Sprite Limit Overflow           */
#define YD_MD_VDP_STATUS_SCOL      (1u << 5) /* Sprite Non-Zero Pixel Collision */
#define YD_MD_VDP_STATUS_ODD       (1u << 4) /* Odd Frame in Interlace Mode     */
#define YD_MD_VDP_STATUS_VBLK      (1u << 3) /* Inside V-Blank Interval         */
#define YD_MD_VDP_STATUS_HBLK      (1u << 2) /* Inside H-Blank Interval         */
#define YD_MD_VDP_STATUS_DMA       (1u << 1) /* DMA Transfer Busy               */
#define YD_MD_VDP_STATUS_PAL       (1u << 0) /* PAL Hardware Mode               */

/* VDP Target Access Codes (CD3..CD0 in code_reg) */
#define YD_MD_VDP_CODE_VRAM_READ   0x00u
#define YD_MD_VDP_CODE_VRAM_WRITE  0x01u
#define YD_MD_VDP_CODE_CRAM_WRITE  0x03u
#define YD_MD_VDP_CODE_VSRAM_READ  0x04u
#define YD_MD_VDP_CODE_VSRAM_WRITE 0x05u
#define YD_MD_VDP_CODE_CRAM_READ   0x08u

/* ==========================================================================
 * SEGA Genesis VDP State Structure
 * ========================================================================== */
typedef struct yd_md_vdp {
    /* Video, Color & Vertical Scroll Memory */
    uint8_t  vram[YD_MD_VDP_VRAM_SIZE];
    uint16_t cram[YD_MD_VDP_CRAM_WORDS];
    uint16_t vsram[YD_MD_VDP_VSRAM_WORDS];

    /* Pre-calculated 32-bit ARGB8888 Palette Caches (Normal, Shadow, Highlight) */
    uint32_t palette_lut[YD_MD_VDP_CRAM_WORDS];
    uint32_t palette_shadow[YD_MD_VDP_CRAM_WORDS];
    uint32_t palette_hilite[YD_MD_VDP_CRAM_WORDS];

    /* 24 VDP Control Registers (R00 - R23) */
    uint8_t  regs[YD_MD_VDP_NUM_REGS];

    /* Command Latch & Address Pointer State */
    uint16_t addr_reg;             /* 16-bit VRAM/CRAM/VSRAM address register */
    uint8_t  code_reg;             /* 6-bit command code (CD5..CD0)           */
    bool     pending_second_word;  /* Waiting for 2nd control word on 0xC00004*/
    bool     dma_fill_pending;     /* Waiting for Data Port write to start Fill*/
    uint16_t read_buffer;          /* Prefetched word for Data Port reads     */

    /* Status & Interrupt Latches */
    uint16_t status;               /* Status Register (bits 9..0)             */
    uint8_t  h_int_counter;        /* Down-counter reloaded from R10          */
    bool     h_int_pending;        /* Level 4 H-Blank IRQ latch               */
    bool     v_int_pending;        /* Level 6 V-Blank IRQ latch               */

    /* Scanline Timing & Display Dimensions */
    uint16_t current_scanline;
    uint8_t  v_counter;
    uint8_t  h_counter;
    uint16_t active_width;         /* 320 (H40) or 256 (H32)                  */
    uint16_t active_height;        /* 224 (V28) or 240 (V30)                  */
    bool     is_pal;

    /* Attached M68K Bus & CPU for 68K->VDP DMA and Level 4/6 Interrupts */
    m68k_bus_t *m68k_bus;
    m68k_cpu_t *m68k_cpu;

    /* 32-bit ARGB8888 Output Framebuffer (Up to 320 x 240) */
    uint32_t framebuffer[YD_MD_VDP_FB_SIZE];
} yd_md_vdp_t;

/* ==========================================================================
 * Genesis VDP Public API
 * ========================================================================== */

/**
 * Initialize a Genesis VDP instance to power-on defaults (H40 320x224 NTSC).
 */
void yd_md_vdp_init(yd_md_vdp_t *vdp);

/**
 * Reset VRAM, CRAM, VSRAM, registers, command latches, and framebuffer.
 */
void yd_md_vdp_reset(yd_md_vdp_t *vdp);

/**
 * Attach the M68K memory bus (for 68K->VDP DMA reads) and M68K CPU (for Level 4/6 IRQs).
 */
void yd_md_vdp_attach_m68k(yd_md_vdp_t *vdp, m68k_bus_t *bus, m68k_cpu_t *cpu);

/**
 * Configure PAL (50Hz) or NTSC (60Hz) video timing.
 */
void yd_md_vdp_set_pal(yd_md_vdp_t *vdp, bool is_pal);

/**
 * Rebuild the 64-entry 32-bit ARGB8888 palette lookup tables from CRAM.
 */
void yd_md_vdp_refresh_palette(yd_md_vdp_t *vdp);

/**
 * 16-bit and 8-bit Port Read/Write Entry Points (0xC00000 - 0xC0001F).
 */
uint16_t yd_md_vdp_read16(void *ctx, uint32_t addr);
uint8_t  yd_md_vdp_read8(void *ctx, uint32_t addr);
void     yd_md_vdp_write16(void *ctx, uint32_t addr, uint16_t val);
void     yd_md_vdp_write8(void *ctx, uint32_t addr, uint8_t val);

/**
 * Read/Write specific VDP ports directly (Data Port 0xC00000, Control/Status 0xC00004, HV 0xC00008).
 */
uint16_t yd_md_vdp_read_data(yd_md_vdp_t *vdp);
void     yd_md_vdp_write_data(yd_md_vdp_t *vdp, uint16_t val);
uint16_t yd_md_vdp_read_status(yd_md_vdp_t *vdp);
void     yd_md_vdp_write_control(yd_md_vdp_t *vdp, uint16_t val);
uint16_t yd_md_vdp_read_hv_counter(const yd_md_vdp_t *vdp);

/**
 * Render a single active scanline (`scanline < vdp->active_height`) into `framebuffer`.
 */
void yd_md_vdp_render_scanline(yd_md_vdp_t *vdp, uint16_t scanline);

/**
 * Advance VDP scanline timing, update V-Counter, decrement H-Int counter (R10),
 * and assert Level 4 (H-Blank) or Level 6 (V-Blank) interrupts on the M68K CPU.
 */
void yd_md_vdp_step_scanline(yd_md_vdp_t *vdp, uint16_t scanline);

/**
 * Populate a `yd_md_vdp_handlers_t` descriptor so `yd_md_mmu_t` routes
 * `0xC00000 - 0xC0001F` reads and writes directly to this VDP.
 */
void yd_md_vdp_bind_mmu_handlers(yd_md_vdp_t *vdp, yd_md_vdp_handlers_t *handlers);

#ifdef __cplusplus
}
#endif

#endif /* YD_CORE_MD_VDP_H */
