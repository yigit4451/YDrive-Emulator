#include "md_vdp.h"
#include <string.h>

/* ==========================================================================
 * Internal Palette Conversion & Helper Functions
 * ========================================================================== */

/* Convert 9-bit Genesis CRAM word (0000 BBB0 GGG0 RRR0) to 32-bit 0xFFRRGGBB */
static void yd_md_vdp_update_cram_entry(yd_md_vdp_t *vdp, uint8_t index) {
    index &= 0x3Fu;
    uint16_t raw = vdp->cram[index];

    uint32_t r3 = (raw >> 1) & 0x07u;
    uint32_t g3 = (raw >> 5) & 0x07u;
    uint32_t b3 = (raw >> 9) & 0x07u;

    /* Normal intensity (0..7 -> 0..255) */
    uint32_t r = (r3 * 255u + 3u) / 7u;
    uint32_t g = (g3 * 255u + 3u) / 7u;
    uint32_t b = (b3 * 255u + 3u) / 7u;
    vdp->palette_lut[index] = 0xFF000000u | (r << 16) | (g << 8) | b;

    /* Shadow intensity (~half brightness: 0..7 -> 0..127) */
    uint32_t rs = r >> 1;
    uint32_t gs = g >> 1;
    uint32_t bs = b >> 1;
    vdp->palette_shadow[index] = 0xFF000000u | (rs << 16) | (gs << 8) | bs;

    /* Highlight intensity (shifted toward white: 128 + half) */
    uint32_t rh = 128u + rs;
    uint32_t gh = 128u + gs;
    uint32_t bh = 128u + bs;
    vdp->palette_hilite[index] = 0xFF000000u | (rh << 16) | (gh << 8) | bh;
}

static void yd_md_vdp_update_geometry(yd_md_vdp_t *vdp) {
    /* R12 bit 0 or bit 7 selects H40 (320px) vs H32 (256px) */
    bool h40 = (vdp->regs[12] & 0x81u) != 0u;
    vdp->active_width = h40 ? YD_MD_VDP_WIDTH_H40 : YD_MD_VDP_WIDTH_H32;

    /* R1 bit 3 selects V30 (240 lines) vs V28 (224 lines) */
    bool v30 = (vdp->regs[1] & 0x08u) != 0u;
    vdp->active_height = v30 ? YD_MD_VDP_HEIGHT_V30 : YD_MD_VDP_HEIGHT_V28;
}

static void yd_md_vdp_sync_irq(yd_md_vdp_t *vdp) {
    if (!vdp->m68k_cpu) {
        return;
    }
    bool ie0_vblank = (vdp->regs[1] & 0x20u) != 0u;
    bool ie1_hblank = (vdp->regs[0] & 0x10u) != 0u;

    if (!ie0_vblank && vdp->m68k_cpu->int_level == 6u) {
        vdp->m68k_cpu->int_level = 0u;
    }
    if (!ie1_hblank && vdp->m68k_cpu->int_level == 4u) {
        vdp->m68k_cpu->int_level = 0u;
    }

    if (vdp->v_int_pending && ie0_vblank) {
        if (vdp->m68k_cpu->int_level < 6u) {
            m68k_set_irq(vdp->m68k_cpu, 6u);
        }
        vdp->v_int_pending = false;
    } else if (vdp->h_int_pending && ie1_hblank) {
        if (vdp->m68k_cpu->int_level < 4u) {
            m68k_set_irq(vdp->m68k_cpu, 4u);
        }
        vdp->h_int_pending = false;
    }
}

static inline uint16_t vram_read16(const yd_md_vdp_t *vdp, uint32_t addr) {
    addr &= 0xFFFEu;
    return (uint16_t)(((uint16_t)vdp->vram[addr] << 8) | (uint16_t)vdp->vram[addr + 1u]);
}

static inline void vram_write16_raw(yd_md_vdp_t *vdp, uint16_t addr, uint16_t val) {
    if ((addr & 1u) == 0u) {
        vdp->vram[addr]                  = (uint8_t)(val >> 8);
        vdp->vram[(uint16_t)(addr + 1u)] = (uint8_t)(val & 0xFFu);
    } else {
        /* Odd VRAM address swaps high and low bytes on real YM7101 hardware */
        uint16_t base = (uint16_t)(addr & 0xFFFEu);
        vdp->vram[base]                  = (uint8_t)(val & 0xFFu);
        vdp->vram[(uint16_t)(base + 1u)] = (uint8_t)(val >> 8);
    }
}

static void yd_md_vdp_write_target_word(yd_md_vdp_t *vdp, uint16_t val) {
    switch (vdp->code_reg & 0x0Fu) {
        case YD_MD_VDP_CODE_VRAM_WRITE:
            vram_write16_raw(vdp, vdp->addr_reg, val);
            break;

        case YD_MD_VDP_CODE_CRAM_WRITE: {
            uint8_t idx     = (uint8_t)((vdp->addr_reg >> 1) & 0x3Fu);
            vdp->cram[idx]  = (uint16_t)(val & 0x0EEEu);
            yd_md_vdp_update_cram_entry(vdp, idx);
            break;
        }

        case YD_MD_VDP_CODE_VSRAM_WRITE: {
            uint8_t idx = (uint8_t)((vdp->addr_reg >> 1) & 0x3Fu);
            if (idx < YD_MD_VDP_VSRAM_WORDS) {
                vdp->vsram[idx] = (uint16_t)(val & 0x07FFu);
            }
            break;
        }

        default:
            break;
    }
    vdp->addr_reg = (uint16_t)(vdp->addr_reg + vdp->regs[15]);
}

/* ==========================================================================
 * DMA Engine (68K -> VDP Memory, VRAM Fill, VRAM Copy)
 * ========================================================================== */

static uint32_t yd_md_vdp_get_dma_length(const yd_md_vdp_t *vdp) {
    uint32_t len = ((uint32_t)vdp->regs[20] << 8) | (uint32_t)vdp->regs[19];
    return (len == 0u) ? 0x10000u : len;
}

static void yd_md_vdp_set_dma_length_zero(yd_md_vdp_t *vdp) {
    vdp->regs[19] = 0u;
    vdp->regs[20] = 0u;
}

static void yd_md_vdp_exec_dma_68k(yd_md_vdp_t *vdp) {
    if (!vdp->m68k_bus || !vdp->m68k_bus->read16) {
        return;
    }

    uint32_t len      = yd_md_vdp_get_dma_length(vdp);
    uint32_t src_bank = ((uint32_t)(vdp->regs[23] & 0x7Fu)) << 17;
    uint32_t src_lo   = (((uint32_t)vdp->regs[22] << 8) | (uint32_t)vdp->regs[21]) << 1;

    for (uint32_t i = 0; i < len; i++) {
        uint32_t addr = (src_bank | (src_lo & 0x1FFFFu)) & M68K_ADDR_MASK;
        uint16_t word = vdp->m68k_bus->read16(vdp->m68k_bus->ctx, addr);
        yd_md_vdp_write_target_word(vdp, word);
        src_lo = (src_lo + 2u) & 0x1FFFFu;
    }

    vdp->regs[21] = (uint8_t)((src_lo >> 1) & 0xFFu);
    vdp->regs[22] = (uint8_t)((src_lo >> 9) & 0xFFu);
    yd_md_vdp_set_dma_length_zero(vdp);
}

static void yd_md_vdp_exec_dma_fill(yd_md_vdp_t *vdp, uint16_t fill_word) {
    vdp->dma_fill_pending = false;

    /* First write the 16-bit word normally to VRAM (and increment addr_reg once) */
    vram_write16_raw(vdp, vdp->addr_reg, fill_word);
    vdp->addr_reg = (uint16_t)(vdp->addr_reg + vdp->regs[15]);

    uint32_t len       = yd_md_vdp_get_dma_length(vdp);
    uint8_t  fill_byte = (uint8_t)(fill_word >> 8);
    uint16_t step      = vdp->regs[15];

    for (uint32_t i = 0; i < len; i++) {
        vdp->vram[(uint16_t)(vdp->addr_reg ^ 1u)] = fill_byte;
        vdp->addr_reg = (uint16_t)(vdp->addr_reg + step);
    }

    yd_md_vdp_set_dma_length_zero(vdp);
}

static void yd_md_vdp_exec_dma_copy(yd_md_vdp_t *vdp) {
    uint32_t len  = yd_md_vdp_get_dma_length(vdp);
    uint16_t src  = (uint16_t)(((uint16_t)vdp->regs[22] << 8) | (uint16_t)vdp->regs[21]);
    uint16_t step = vdp->regs[15];

    for (uint32_t i = 0; i < len; i++) {
        uint8_t b = vdp->vram[src];
        vdp->vram[vdp->addr_reg] = b;
        src           = (uint16_t)(src + 1u);
        vdp->addr_reg = (uint16_t)(vdp->addr_reg + step);
    }

    vdp->regs[21] = (uint8_t)(src & 0xFFu);
    vdp->regs[22] = (uint8_t)(src >> 8);
    yd_md_vdp_set_dma_length_zero(vdp);
}

/* ==========================================================================
 * Lifecycle & Configuration
 * ========================================================================== */

void yd_md_vdp_init(yd_md_vdp_t *vdp) {
    if (!vdp) {
        return;
    }
    memset(vdp, 0, sizeof(*vdp));
    yd_md_vdp_reset(vdp);
}

void yd_md_vdp_reset(yd_md_vdp_t *vdp) {
    if (!vdp) {
        return;
    }
    memset(vdp->vram, 0, sizeof(vdp->vram));
    memset(vdp->cram, 0, sizeof(vdp->cram));
    memset(vdp->vsram, 0, sizeof(vdp->vsram));
    memset(vdp->regs, 0, sizeof(vdp->regs));

    /* Power-on Mode 5 defaults: H40 (320x224), auto-inc = 2 */
    vdp->regs[1]  = 0x04u; /* Mode 5 enabled */
    vdp->regs[12] = 0x81u; /* H40 320px width */
    vdp->regs[15] = 0x02u; /* Auto-increment 2 bytes */

    vdp->addr_reg            = 0u;
    vdp->code_reg            = 0u;
    vdp->pending_second_word = false;
    vdp->dma_fill_pending    = false;
    vdp->read_buffer         = 0u;

    vdp->status           = (uint16_t)(0x3400u | YD_MD_VDP_STATUS_EMPTY |
                                       (vdp->is_pal ? YD_MD_VDP_STATUS_PAL : 0u));
    vdp->h_int_counter    = 0xFFu;
    vdp->h_int_pending    = false;
    vdp->v_int_pending    = false;
    vdp->current_scanline = 0u;
    vdp->v_counter        = 0u;
    vdp->h_counter        = 0u;

    yd_md_vdp_update_geometry(vdp);
    yd_md_vdp_refresh_palette(vdp);

    for (size_t i = 0; i < YD_MD_VDP_FB_SIZE; i++) {
        vdp->framebuffer[i] = 0xFF000000u;
    }
}

void yd_md_vdp_attach_m68k(yd_md_vdp_t *vdp, m68k_bus_t *bus, m68k_cpu_t *cpu) {
    if (!vdp) {
        return;
    }
    vdp->m68k_bus = bus;
    vdp->m68k_cpu = cpu;
}

void yd_md_vdp_set_pal(yd_md_vdp_t *vdp, bool is_pal) {
    if (!vdp) {
        return;
    }
    vdp->is_pal = is_pal;
    if (is_pal) {
        vdp->status |= YD_MD_VDP_STATUS_PAL;
    } else {
        vdp->status &= (uint16_t)(0xFFFFu ^ YD_MD_VDP_STATUS_PAL);
    }
}

void yd_md_vdp_refresh_palette(yd_md_vdp_t *vdp) {
    if (!vdp) {
        return;
    }
    for (uint8_t i = 0; i < YD_MD_VDP_CRAM_WORDS; i++) {
        yd_md_vdp_update_cram_entry(vdp, i);
    }
}

/* ==========================================================================
 * Data, Control & HV Counter Port I/O
 * ========================================================================== */

uint16_t yd_md_vdp_read_data(yd_md_vdp_t *vdp) {
    vdp->pending_second_word = false;
    uint16_t result = 0u;

    switch (vdp->code_reg & 0x0Fu) {
        case YD_MD_VDP_CODE_VRAM_READ:
            result = vram_read16(vdp, vdp->addr_reg);
            break;
        case YD_MD_VDP_CODE_VSRAM_READ: {
            uint8_t idx = (uint8_t)((vdp->addr_reg >> 1) & 0x3Fu);
            result = (idx < YD_MD_VDP_VSRAM_WORDS) ? vdp->vsram[idx] : 0u;
            break;
        }
        case YD_MD_VDP_CODE_CRAM_READ: {
            uint8_t idx = (uint8_t)((vdp->addr_reg >> 1) & 0x3Fu);
            result = vdp->cram[idx];
            break;
        }
        default:
            result = vdp->read_buffer;
            break;
    }

    vdp->read_buffer = result;
    vdp->addr_reg    = (uint16_t)(vdp->addr_reg + vdp->regs[15]);
    return result;
}

void yd_md_vdp_write_data(yd_md_vdp_t *vdp, uint16_t val) {
    vdp->pending_second_word = false;

    if (vdp->dma_fill_pending) {
        yd_md_vdp_exec_dma_fill(vdp, val);
        return;
    }

    yd_md_vdp_write_target_word(vdp, val);
}

uint16_t yd_md_vdp_read_status(yd_md_vdp_t *vdp) {
    vdp->pending_second_word = false;
    uint16_t ret = vdp->status;

    /* Reading the status register clears VIP, SOVR, SCOL, and pending V-Int latch */
    vdp->status &= (uint16_t)(0xFFFFu ^ (YD_MD_VDP_STATUS_VIP |
                                         YD_MD_VDP_STATUS_SOVR |
                                         YD_MD_VDP_STATUS_SCOL));
    vdp->v_int_pending = false;
    return ret;
}

void yd_md_vdp_write_control(yd_md_vdp_t *vdp, uint16_t val) {
    /* If not waiting for 2nd word and top bits are 10 (0x8000..0x9FFF), it is a Register Write */
    if (!vdp->pending_second_word && (val & 0xC000u) == 0x8000u) {
        uint8_t reg_idx = (uint8_t)((val >> 8) & 0x1Fu);
        if (reg_idx < YD_MD_VDP_NUM_REGS) {
            vdp->regs[reg_idx] = (uint8_t)(val & 0xFFu);
            if (reg_idx == 1u || reg_idx == 12u) {
                yd_md_vdp_update_geometry(vdp);
            }
            if (reg_idx == 10u &&
                (vdp->current_scanline == 0u || vdp->current_scanline >= vdp->active_height ||
                 (vdp->status & YD_MD_VDP_STATUS_VBLK) != 0u)) {
                vdp->h_int_counter = vdp->regs[10];
            }
            if (reg_idx == 0u || reg_idx == 1u) {
                yd_md_vdp_sync_irq(vdp);
            }
        }
        vdp->addr_reg = (uint16_t)((vdp->addr_reg & 0xC000u) | (val & 0x3FFFu));
        vdp->code_reg = (uint8_t)((vdp->code_reg & 0x3Cu) | ((val >> 14) & 0x03u));
        return;
    }

    if (!vdp->pending_second_word) {
        /* First word of 32-bit VDP command */
        vdp->addr_reg            = (uint16_t)((vdp->addr_reg & 0xC000u) | (val & 0x3FFFu));
        vdp->code_reg            = (uint8_t)((vdp->code_reg & 0x3Cu) | ((val >> 14) & 0x03u));
        vdp->pending_second_word = true;
    } else {
        /* Second word of 32-bit VDP command */
        vdp->addr_reg            = (uint16_t)((vdp->addr_reg & 0x3FFFu) | ((val & 0x0003u) << 14));
        vdp->code_reg            = (uint8_t)((vdp->code_reg & 0x03u) | (((val >> 4) & 0x0Fu) << 2));
        vdp->pending_second_word = false;

        /* Check if CD5 (bit 5 of code_reg) and M1 (bit 4 of R1: DMA Enable) are both set */
        if ((vdp->code_reg & 0x20u) != 0u && (vdp->regs[1] & 0x10u) != 0u) {
            uint8_t dma_mode = (uint8_t)((vdp->regs[23] >> 6) & 0x03u);
            if (dma_mode == 0u || dma_mode == 1u) {
                yd_md_vdp_exec_dma_68k(vdp);
            } else if (dma_mode == 2u) {
                vdp->dma_fill_pending = true;
            } else if (dma_mode == 3u) {
                yd_md_vdp_exec_dma_copy(vdp);
            }
        }
    }
}

uint16_t yd_md_vdp_read_hv_counter(const yd_md_vdp_t *vdp) {
    return (uint16_t)(((uint16_t)vdp->v_counter << 8) | (uint16_t)vdp->h_counter);
}

/* ==========================================================================
 * Memory-Mapped Bus Handlers (0xC00000 - 0xC0001F)
 * ========================================================================== */

uint16_t yd_md_vdp_read16(void *ctx, uint32_t addr) {
    yd_md_vdp_t *vdp = (yd_md_vdp_t *)ctx;
    uint32_t     port = addr & 0x1Eu;

    if (port <= 0x02u) {
        return yd_md_vdp_read_data(vdp);
    }
    if (port == 0x04u || port == 0x06u) {
        return yd_md_vdp_read_status(vdp);
    }
    if (port >= 0x08u && port <= 0x0Eu) {
        return yd_md_vdp_read_hv_counter(vdp);
    }
    return 0xFFFFu;
}

uint8_t yd_md_vdp_read8(void *ctx, uint32_t addr) {
    uint16_t w = yd_md_vdp_read16(ctx, addr & ~1u);
    return (addr & 1u) ? (uint8_t)(w & 0xFFu) : (uint8_t)(w >> 8);
}

void yd_md_vdp_write16(void *ctx, uint32_t addr, uint16_t val) {
    yd_md_vdp_t *vdp = (yd_md_vdp_t *)ctx;
    uint32_t     port = addr & 0x1Eu;

    if (port <= 0x02u) {
        yd_md_vdp_write_data(vdp, val);
    } else if (port == 0x04u || port == 0x06u) {
        yd_md_vdp_write_control(vdp, val);
    }
}

void yd_md_vdp_write8(void *ctx, uint32_t addr, uint8_t val) {
    uint32_t port = addr & 0x1Fu;
    if (port <= 0x07u) {
        /* 8-bit writes to VDP Data/Control duplicate the byte across both halves */
        uint16_t dup = (uint16_t)(((uint16_t)val << 8) | (uint16_t)val);
        yd_md_vdp_write16(ctx, addr & ~1u, dup);
    }
}

void yd_md_vdp_bind_mmu_handlers(yd_md_vdp_t *vdp, yd_md_vdp_handlers_t *handlers) {
    if (!vdp || !handlers) {
        return;
    }
    handlers->ctx     = vdp;
    handlers->read8   = yd_md_vdp_read8;
    handlers->read16  = yd_md_vdp_read16;
    handlers->write8  = yd_md_vdp_write8;
    handlers->write16 = yd_md_vdp_write16;
}

/* ==========================================================================
 * Mode 5 Scanline Rasterizer (Plane B, Plane A, Window, Sprites)
 * ========================================================================== */

static void yd_md_vdp_get_plane_dims(const yd_md_vdp_t *vdp, uint16_t *w_cells, uint16_t *h_cells) {
    switch (vdp->regs[16] & 0x03u) {
        case 0:  *w_cells = 32u;  break;
        case 1:  *w_cells = 64u;  break;
        case 3:  *w_cells = 128u; break;
        default: *w_cells = 32u;  break;
    }
    switch ((vdp->regs[16] >> 4) & 0x03u) {
        case 0:  *h_cells = 32u;  break;
        case 1:  *h_cells = 64u;  break;
        case 3:  *h_cells = 128u; break;
        default: *h_cells = 32u;  break;
    }
}

static uint16_t yd_md_vdp_get_hscroll(const yd_md_vdp_t *vdp, uint16_t scanline, bool is_plane_b) {
    uint32_t base   = ((uint32_t)(vdp->regs[13] & 0x3Fu)) << 10;
    uint32_t offset = is_plane_b ? 2u : 0u;

    switch (vdp->regs[11] & 0x03u) {
        case 0: /* Full-screen H-Scroll */
            break;
        case 1: /* First 8 lines */
            offset += (uint32_t)(scanline & 7u) * 4u;
            break;
        case 2: /* Line Scroll (R11 low 2 bits == 10: Plane A +0, Plane B +2 at scanline * 4) */
        case 3: /* 1-Pixel Line Scroll (R11 low 2 bits == 11: Plane A +0, Plane B +2 at scanline * 4) */
            offset += (uint32_t)scanline * 4u;
            break;
    }
    return vram_read16(vdp, base + offset) & 0x03FFu;
}

static uint16_t yd_md_vdp_get_vscroll(const yd_md_vdp_t *vdp, uint16_t x, bool is_plane_b) {
    bool two_cell_mode = (vdp->regs[11] & 0x04u) != 0u;
    uint32_t idx = is_plane_b ? 1u : 0u;
    if (two_cell_mode) {
        uint32_t col_pair = (x >> 4) & 0x1Fu;
        idx = (col_pair * 2u + (is_plane_b ? 1u : 0u));
        if (idx >= YD_MD_VDP_VSRAM_WORDS) {
            idx &= 1u;
        }
    }
    return vdp->vsram[idx] & 0x03FFu;
}

static inline uint8_t sample_tile_4bpp(const yd_md_vdp_t *vdp, uint16_t tile_idx,
                                       uint8_t px, uint8_t py, bool hf, bool vf) {
    uint8_t  rx       = hf ? (uint8_t)(7u - px) : px;
    uint8_t  ry       = vf ? (uint8_t)(7u - py) : py;
    uint32_t byte_off = ((uint32_t)(tile_idx & 0x07FFu) * 32u) + ((uint32_t)ry * 4u) + ((uint32_t)rx >> 1);
    uint8_t  packed   = vdp->vram[byte_off & 0xFFFFu];
    return ((rx & 1u) == 0u) ? (uint8_t)(packed >> 4) : (uint8_t)(packed & 0x0Fu);
}

static bool is_pixel_in_window(const yd_md_vdp_t *vdp, uint16_t x, uint16_t y) {
    uint8_t  r17     = vdp->regs[17];
    uint8_t  r18     = vdp->regs[18];
    uint16_t win_x   = (uint16_t)((r17 & 0x1Fu) * 16u);
    uint16_t win_y   = (uint16_t)((r18 & 0x1Fu) * 8u);
    bool     right   = (r17 & 0x80u) != 0u;
    bool     down    = (r18 & 0x80u) != 0u;

    bool in_v = down ? (y >= win_y) : (y < win_y);
    if (in_v) {
        return true;
    }
    bool in_h = right ? (x >= win_x) : (x < win_x);
    return in_h;
}

static void render_scroll_plane_line(const yd_md_vdp_t *vdp, uint16_t scanline,
                                     bool is_plane_b, bool high_prio, uint32_t *line_out) {
    uint16_t w_cells = 32u, h_cells = 32u;
    yd_md_vdp_get_plane_dims(vdp, &w_cells, &h_cells);

    uint16_t w_px_mask = (uint16_t)(w_cells * 8u - 1u);
    uint16_t h_px_mask = (uint16_t)(h_cells * 8u - 1u);

    uint32_t nt_base = is_plane_b
                           ? (((uint32_t)(vdp->regs[4] & 0x07u)) << 13)
                           : (((uint32_t)(vdp->regs[2] & 0x38u)) << 10);

    bool     h40      = (vdp->active_width == YD_MD_VDP_WIDTH_H40);
    uint32_t win_base = h40 ? (((uint32_t)(vdp->regs[3] & 0x3Cu)) << 10)
                            : (((uint32_t)(vdp->regs[3] & 0x3Eu)) << 10);
    uint16_t win_cols = h40 ? 64u : 32u;

    uint16_t hscroll = yd_md_vdp_get_hscroll(vdp, scanline, is_plane_b);

    for (uint16_t x = 0; x < vdp->active_width; x++) {
        if (!is_plane_b && is_pixel_in_window(vdp, x, scanline)) {
            /* Render from Window Name Table (no scrolling) */
            uint16_t cell_x  = x >> 3;
            uint16_t cell_y  = scanline >> 3;
            uint32_t nt_addr = win_base + (((uint32_t)cell_y * win_cols + cell_x) * 2u);
            uint16_t attr    = vram_read16(vdp, nt_addr);
            bool     prio    = (attr & 0x8000u) != 0u;
            if (prio != high_prio) {
                continue;
            }
            uint8_t col_idx = sample_tile_4bpp(vdp, attr & 0x07FFu,
                                               (uint8_t)(x & 7u), (uint8_t)(scanline & 7u),
                                               (attr & 0x0800u) != 0u, (attr & 0x1000u) != 0u);
            if (col_idx != 0u) {
                uint8_t pal = (uint8_t)((attr >> 13) & 0x03u);
                line_out[x] = vdp->palette_lut[(pal * 16u) + col_idx];
            }
            continue;
        }

        uint16_t vscroll = yd_md_vdp_get_vscroll(vdp, x, is_plane_b);
        uint16_t sx      = (uint16_t)((x - hscroll) & w_px_mask);
        uint16_t sy      = (uint16_t)((scanline + vscroll) & h_px_mask);
        uint16_t cell_x  = sx >> 3;
        uint16_t cell_y  = sy >> 3;

        uint32_t nt_addr = nt_base + (((uint32_t)cell_y * w_cells + cell_x) * 2u);
        uint16_t attr    = vram_read16(vdp, nt_addr);
        bool     prio    = (attr & 0x8000u) != 0u;
        if (prio != high_prio) {
            continue;
        }

        uint8_t col_idx = sample_tile_4bpp(vdp, attr & 0x07FFu,
                                           (uint8_t)(sx & 7u), (uint8_t)(sy & 7u),
                                           (attr & 0x0800u) != 0u, (attr & 0x1000u) != 0u);
        if (col_idx != 0u) {
            uint8_t pal = (uint8_t)((attr >> 13) & 0x03u);
            line_out[x] = vdp->palette_lut[(pal * 16u) + col_idx];
        }
    }
}

static void render_sprites_line(yd_md_vdp_t *vdp, uint16_t scanline,
                                uint8_t *spr_color_line, uint8_t *spr_prio_line) {
    bool     h40        = (vdp->active_width == YD_MD_VDP_WIDTH_H40);
    uint32_t sat_base   = h40 ? (((uint32_t)(vdp->regs[5] & 0x7Eu)) << 9)
                              : (((uint32_t)(vdp->regs[5] & 0x7Fu)) << 9);
    uint8_t  max_total  = h40 ? 80u : 64u;
    uint8_t  max_line   = h40 ? 20u : 16u;

    uint8_t  cur_idx    = 0u;
    uint8_t  visited    = 0u;
    uint8_t  on_line    = 0u;
    bool     seen_nzero = false;
    bool     masked     = false;

    while (visited < max_total) {
        visited++;
        uint32_t entry_addr = sat_base + ((uint32_t)cur_idx * 8u);
        uint16_t w0         = vram_read16(vdp, entry_addr + 0u);
        uint16_t w1         = vram_read16(vdp, entry_addr + 2u);
        uint16_t w2         = vram_read16(vdp, entry_addr + 4u);
        uint16_t w3         = vram_read16(vdp, entry_addr + 6u);

        int16_t  y_pos      = (int16_t)(w0 & 0x03FFu) - 128;
        uint8_t  h_cells    = (uint8_t)(((w1 >> 10) & 0x03u) + 1u);
        uint8_t  v_cells    = (uint8_t)(((w1 >> 8) & 0x03u) + 1u);
        uint8_t  link       = (uint8_t)(w1 & 0x7Fu);
        uint16_t height_px  = (uint16_t)(v_cells * 8u);
        uint16_t width_px   = (uint16_t)(h_cells * 8u);

        if ((int16_t)scanline >= y_pos && (int16_t)scanline < (y_pos + (int16_t)height_px)) {
            if (on_line >= max_line) {
                vdp->status |= YD_MD_VDP_STATUS_SOVR;
                break;
            }
            on_line++;

            uint16_t raw_x = w3 & 0x03FFu;
            if (raw_x == 0u && seen_nzero) {
                masked = true;
            } else if (raw_x != 0u) {
                seen_nzero = true;
            }

            if (!masked) {
                int16_t  x_pos     = (int16_t)raw_x - 128;
                uint16_t rel_y     = (uint16_t)((int16_t)scanline - y_pos);
                bool     vf        = (w2 & 0x1000u) != 0u;
                bool     hf        = (w2 & 0x0800u) != 0u;
                bool     prio      = (w2 & 0x8000u) != 0u;
                uint8_t  pal       = (uint8_t)((w2 >> 13) & 0x03u);
                uint16_t base_tile = w2 & 0x07FFu;

                uint16_t eff_y     = vf ? (uint16_t)(height_px - 1u - rel_y) : rel_y;
                uint8_t  cell_row  = (uint8_t)(eff_y >> 3);
                uint8_t  py        = (uint8_t)(eff_y & 7u);

                for (uint16_t dx = 0; dx < width_px; dx++) {
                    int16_t sx = x_pos + (int16_t)dx;
                    if (sx < 0 || sx >= (int16_t)vdp->active_width) {
                        continue;
                    }
                    uint16_t eff_x    = hf ? (uint16_t)(width_px - 1u - dx) : dx;
                    uint8_t  cell_col = (uint8_t)(eff_x >> 3);
                    uint8_t  px       = (uint8_t)(eff_x & 7u);

                    /* Genesis sprites store tiles in column-major order */
                    uint16_t tile_idx = (uint16_t)(base_tile + (uint16_t)cell_col * v_cells + cell_row);
                    uint8_t  col_idx  = sample_tile_4bpp(vdp, tile_idx, px, py, false, false);

                    if (col_idx != 0u) {
                        if (spr_color_line[sx] == 0u) {
                            spr_color_line[sx] = (uint8_t)((pal * 16u) + col_idx);
                            spr_prio_line[sx]  = prio ? 1u : 0u;
                        } else {
                            /* Two non-zero sprite pixels overlapped */
                            vdp->status |= YD_MD_VDP_STATUS_SCOL;
                        }
                    }
                }
            }
        }

        if (link == 0u || link >= max_total) {
            break;
        }
        cur_idx = link;
    }
}

void yd_md_vdp_render_scanline(yd_md_vdp_t *vdp, uint16_t scanline) {
    if (!vdp || scanline >= vdp->active_height) {
        return;
    }

    uint32_t *line_out = &vdp->framebuffer[(size_t)scanline * vdp->active_width];
    uint32_t  backdrop = vdp->palette_lut[vdp->regs[7] & 0x3Fu];

    /* 1. Fill scanline with Backdrop Color (R7) */
    for (uint16_t x = 0; x < vdp->active_width; x++) {
        line_out[x] = backdrop;
    }

    /* Check Display Enable (R1 bit 6) */
    if ((vdp->regs[1] & 0x40u) == 0u) {
        return;
    }

    uint8_t spr_color[YD_MD_VDP_MAX_WIDTH];
    uint8_t spr_prio[YD_MD_VDP_MAX_WIDTH];
    memset(spr_color, 0, sizeof(spr_color));
    memset(spr_prio, 0, sizeof(spr_prio));
    render_sprites_line(vdp, scanline, spr_color, spr_prio);

    /* 2. Low-priority Sprites */
    for (uint16_t x = 0; x < vdp->active_width; x++) {
        if (spr_color[x] != 0u && spr_prio[x] == 0u) {
            line_out[x] = vdp->palette_lut[spr_color[x] & 0x3Fu];
        }
    }

    /* 3. Low-priority Plane B */
    render_scroll_plane_line(vdp, scanline, true, false, line_out);

    /* 4. Low-priority Plane A / Window */
    render_scroll_plane_line(vdp, scanline, false, false, line_out);

    /* 5. High-priority Sprites */
    for (uint16_t x = 0; x < vdp->active_width; x++) {
        if (spr_color[x] != 0u && spr_prio[x] != 0u) {
            line_out[x] = vdp->palette_lut[spr_color[x] & 0x3Fu];
        }
    }

    /* 6. High-priority Plane B */
    render_scroll_plane_line(vdp, scanline, true, true, line_out);

    /* 7. High-priority Plane A / Window */
    render_scroll_plane_line(vdp, scanline, false, true, line_out);
}

/* ==========================================================================
 * Scanline Timing & Level 4 (H-Blank) / Level 6 (V-Blank) Interrupt Generation
 * ========================================================================== */

void yd_md_vdp_step_scanline(yd_md_vdp_t *vdp, uint16_t scanline) {
    if (!vdp) {
        return;
    }

    vdp->current_scanline = scanline;
    vdp->v_counter        = (scanline <= 0xEAu) ? (uint8_t)scanline : (uint8_t)(scanline - 6u);
    vdp->h_int_pending    = false;

    if (scanline < vdp->active_height) {
        vdp->status &= (uint16_t)(0xFFFFu ^ YD_MD_VDP_STATUS_VBLK);
        if (scanline == 0u) {
            vdp->v_int_pending = false;
        }

        /* H-Interrupt Counter (R10): decremented on active lines 0..active_height-1 */
        if (vdp->h_int_counter == 0u) {
            vdp->h_int_counter = vdp->regs[10];
            if ((vdp->regs[0] & 0x10u) != 0u && vdp->m68k_cpu) {
                if (vdp->m68k_cpu->int_level < 4u) {
                    m68k_set_irq(vdp->m68k_cpu, 4u);
                }
            } else {
                vdp->h_int_pending = true;
            }
        } else {
            vdp->h_int_counter--;
        }
    } else {
        /* Outside active display (V-Blank): continually reload R10 into H-Int counter */
        vdp->h_int_counter = vdp->regs[10];
    }

    /* V-Blank starts at scanline == active_height (line 224 in V28, line 240 in V30) */
    if (scanline == vdp->active_height) {
        vdp->status |= (uint16_t)(YD_MD_VDP_STATUS_VBLK | YD_MD_VDP_STATUS_VIP);
        if ((vdp->regs[1] & 0x20u) != 0u && vdp->m68k_cpu) {
            m68k_set_irq(vdp->m68k_cpu, 6u);
            vdp->v_int_pending = false;
        } else {
            vdp->v_int_pending = true;
        }
    }
}
