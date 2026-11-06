#include "vdp.h"
#include <string.h>

/* ==========================================================================
 * Internal Helpers: Palette & Mode Updates
 * ========================================================================== */

static void yd_vdp_update_palette_entry(yd_vdp_t *vdp, uint8_t index) {
    index &= 0x1Fu;

    if (!vdp->is_game_gear) {
        /* SEGA Master System: 6-bit RGB (--BBGGRR), 2 bits per channel */
        uint8_t raw = vdp->cram[index] & 0x3Fu;
        uint8_t r2  = raw & 0x03u;
        uint8_t g2  = (raw >> 2) & 0x03u;
        uint8_t b2  = (raw >> 4) & 0x03u;

        uint32_t r8 = (uint32_t)(r2 * 85u);
        uint32_t g8 = (uint32_t)(g2 * 85u);
        uint32_t b8 = (uint32_t)(b2 * 85u);

        vdp->palette_lut[index] = 0xFF000000u | (r8 << 16) | (g8 << 8) | b8;
    } else {
        /* SEGA Game Gear: 12-bit RGB (----BBBBGGGGRRRR), 4 bits per channel */
        uint8_t lo = vdp->cram[(index * 2u) + 0u];
        uint8_t hi = vdp->cram[(index * 2u) + 1u] & 0x0Fu;

        uint8_t r4 = lo & 0x0Fu;
        uint8_t g4 = (lo >> 4) & 0x0Fu;
        uint8_t b4 = hi & 0x0Fu;

        uint32_t r8 = (uint32_t)((r4 << 4) | r4);
        uint32_t g8 = (uint32_t)((g4 << 4) | g4);
        uint32_t b8 = (uint32_t)((b4 << 4) | b4);

        vdp->palette_lut[index] = 0xFF000000u | (r8 << 16) | (g8 << 8) | b8;
    }
}

static void yd_vdp_rebuild_palette(yd_vdp_t *vdp) {
    for (uint8_t i = 0; i < 32u; i++) {
        yd_vdp_update_palette_entry(vdp, i);
    }
}

static void yd_vdp_update_mode(yd_vdp_t *vdp) {
    uint8_t r0 = vdp->regs[0];
    uint8_t r1 = vdp->regs[1];

    /* Check Mode 4 (R0 bit 2) + Extended Height Enable M2 (R0 bit 1) */
    if ((r0 & 0x06u) == 0x06u) {
        if ((r1 & 0x18u) == 0x10u) {
            vdp->active_height = YD_VDP_HEIGHT_EXT224;
            return;
        }
        if ((r1 & 0x18u) == 0x08u) {
            vdp->active_height = YD_VDP_HEIGHT_EXT240;
            return;
        }
    }
    vdp->active_height = YD_VDP_HEIGHT_STD;
}

static uint8_t yd_vdp_compute_vcounter(const yd_vdp_t *vdp, uint16_t scanline) {
    if (!vdp->is_pal) {
        /* NTSC 262-line V-Counter jump table */
        if (vdp->active_height == YD_VDP_HEIGHT_EXT224) {
            return (scanline <= 0xEAu) ? (uint8_t)scanline : (uint8_t)(scanline - 6u);
        }
        /* Standard 192-line NTSC: 0x00..0xDA, then jumps back to 0xD5..0xFF */
        return (scanline <= 0xDAu) ? (uint8_t)scanline : (uint8_t)(scanline - 6u);
    } else {
        /* PAL 313-line V-Counter jump table */
        if (vdp->active_height == YD_VDP_HEIGHT_EXT240) {
            return (scanline <= 0xFFu) ? (uint8_t)scanline
                 : (scanline <= 0x10Au) ? (uint8_t)(scanline - 0x100u)
                 : (uint8_t)(scanline - 57u);
        }
        if (vdp->active_height == YD_VDP_HEIGHT_EXT224) {
            return (scanline <= 0xFFu) ? (uint8_t)scanline
                 : (scanline <= 0x102u) ? (uint8_t)(scanline - 0x100u)
                 : (uint8_t)(scanline - 57u);
        }
        return (scanline <= 0xF2u) ? (uint8_t)scanline : (uint8_t)(scanline - 57u);
    }
}

/* ==========================================================================
 * Lifecycle & Configuration
 * ========================================================================== */

void yd_vdp_init(yd_vdp_t *vdp) {
    if (!vdp) {
        return;
    }
    memset(vdp, 0, sizeof(*vdp));
    yd_vdp_reset(vdp);
}

void yd_vdp_reset(yd_vdp_t *vdp) {
    if (!vdp) {
        return;
    }
    bool is_gg  = vdp->is_game_gear;
    bool is_pal = vdp->is_pal;

    memset(vdp, 0, sizeof(*vdp));
    vdp->is_game_gear = is_gg;
    vdp->is_pal       = is_pal;

    /* Power-on / Post-BIOS sensible defaults for Mode 4 */
    vdp->regs[0]  = 0x04u; /* Mode 4 enabled */
    vdp->regs[1]  = 0x00u;
    vdp->regs[2]  = 0xFFu; /* Name Table at 0x3800 */
    vdp->regs[3]  = 0xFFu;
    vdp->regs[4]  = 0xFFu;
    vdp->regs[5]  = 0xFFu; /* Sprite Attribute Table at 0x3F00 */
    vdp->regs[6]  = 0xFFu; /* Sprite Patterns at 0x2000 */
    vdp->regs[10] = 0xFFu; /* Line Counter reload = 0xFF */

    vdp->line_counter  = 0xFFu;
    vdp->active_height = YD_VDP_HEIGHT_STD;

    yd_vdp_rebuild_palette(vdp);

    for (size_t i = 0; i < YD_VDP_FB_SIZE; i++) {
        vdp->framebuffer[i] = 0xFF000000u;
    }
}

void yd_vdp_set_config(yd_vdp_t *vdp, bool is_game_gear, bool is_pal) {
    if (!vdp) {
        return;
    }
    vdp->is_game_gear = is_game_gear;
    vdp->is_pal       = is_pal;
    yd_vdp_rebuild_palette(vdp);
}

void yd_vdp_refresh_palette(yd_vdp_t *vdp) {
    if (!vdp) {
        return;
    }
    yd_vdp_rebuild_palette(vdp);
}

/* ==========================================================================
 * VDP Data (0xBE) & Control/Status (0xBF) Port Access
 * ========================================================================== */

uint8_t yd_vdp_read_data(yd_vdp_t *vdp) {
    vdp->first_byte_latched = false;

    uint8_t ret       = vdp->read_buffer;
    vdp->read_buffer  = vdp->vram[vdp->addr_reg & 0x3FFFu];
    vdp->addr_reg     = (vdp->addr_reg + 1u) & 0x3FFFu;
    return ret;
}

void yd_vdp_write_data(yd_vdp_t *vdp, uint8_t val) {
    vdp->first_byte_latched = false;
    vdp->read_buffer        = val;

    if (vdp->code_reg == YD_VDP_CODE_CRAM_WRITE) {
        if (!vdp->is_game_gear) {
            uint8_t idx    = (uint8_t)(vdp->addr_reg & 0x1Fu);
            vdp->cram[idx] = val;
            yd_vdp_update_palette_entry(vdp, idx);
        } else {
            uint8_t byte_addr = (uint8_t)(vdp->addr_reg & 0x3Fu);
            if ((byte_addr & 1u) == 0u) {
                vdp->cram_latch = val;
            } else {
                vdp->cram[byte_addr & 0x3Eu] = vdp->cram_latch;
                vdp->cram[byte_addr]         = val;
                yd_vdp_update_palette_entry(vdp, byte_addr >> 1);
            }
        }
    } else {
        vdp->vram[vdp->addr_reg & 0x3FFFu] = val;
    }

    vdp->addr_reg = (vdp->addr_reg + 1u) & 0x3FFFu;
}

uint8_t yd_vdp_read_status(yd_vdp_t *vdp) {
    uint8_t ret             = vdp->status;
    vdp->status             = 0u;
    vdp->line_irq_pending   = false;
    vdp->first_byte_latched = false;
    return ret;
}

void yd_vdp_write_control(yd_vdp_t *vdp, uint8_t val) {
    if (!vdp->first_byte_latched) {
        vdp->cmd_low_byte       = val;
        vdp->addr_reg           = (vdp->addr_reg & 0x3F00u) | val;
        vdp->first_byte_latched = true;
        return;
    }

    vdp->first_byte_latched = false;
    vdp->code_reg           = (val >> 6) & 0x03u;
    vdp->addr_reg           = ((uint16_t)(val & 0x3Fu) << 8) | vdp->cmd_low_byte;

    if (vdp->code_reg == YD_VDP_CODE_VRAM_READ) {
        vdp->read_buffer = vdp->vram[vdp->addr_reg & 0x3FFFu];
        vdp->addr_reg    = (vdp->addr_reg + 1u) & 0x3FFFu;
    } else if (vdp->code_reg == YD_VDP_CODE_REG_WRITE) {
        uint8_t reg_idx    = val & 0x0Fu;
        vdp->regs[reg_idx] = vdp->cmd_low_byte;
        yd_vdp_update_mode(vdp);
    }
}

uint8_t yd_vdp_read_vcounter(const yd_vdp_t *vdp) {
    return vdp->v_counter;
}

uint8_t yd_vdp_read_hcounter(const yd_vdp_t *vdp) {
    return vdp->h_counter;
}

/* ==========================================================================
 * Scanline Renderer (Mode 4 Background Tiles + Sprites)
 * ========================================================================== */

void yd_vdp_render_scanline(yd_vdp_t *vdp, uint16_t scanline) {
    if (scanline >= vdp->active_height || scanline >= YD_VDP_MAX_HEIGHT) {
        return;
    }

    uint32_t *line_dst      = &vdp->framebuffer[(size_t)scanline * YD_VDP_WIDTH];
    uint32_t  backdrop_rgba = vdp->palette_lut[16u + (vdp->regs[7] & 0x0Fu)];

    /* If display is blanked (R1 bit 6 == 0), fill scanline with backdrop color */
    if ((vdp->regs[1] & 0x40u) == 0u) {
        for (uint32_t x = 0; x < YD_VDP_WIDTH; x++) {
            line_dst[x] = backdrop_rgba;
        }
        return;
    }

    uint8_t bg_priority[YD_VDP_WIDTH];
    memset(bg_priority, 0, sizeof(bg_priority));

    /* 1. Compute Name Table Base Address */
    uint16_t name_table_base;
    uint16_t v_wrap;
    if (vdp->active_height == YD_VDP_HEIGHT_STD) {
        name_table_base = (uint16_t)(vdp->regs[2] & 0x0Eu) << 10; /* 0x3800 default */
        v_wrap          = 224u; /* 28 tile rows */
    } else {
        name_table_base = ((uint16_t)(vdp->regs[2] & 0x0Cu) << 10) | 0x0700u;
        v_wrap          = 256u; /* 32 tile rows */
    }

    /* Horizontal scroll (locked to 0 on top 2 rows if R0 bit 6 is set) */
    uint8_t h_scroll     = ((vdp->regs[0] & 0x40u) && (scanline < 16u)) ? 0u : vdp->regs[8];
    uint8_t fine_x       = h_scroll & 0x07u;
    uint8_t start_column = (uint8_t)((32u - (h_scroll >> 3)) & 0x1Fu);

    /* 2. Render Background Tiles across the 32 columns */
    for (uint32_t col = 0; col < 32u; col++) {
        /* Vertical scroll (locked to 0 for right 8 columns [24..31] if R0 bit 7 is set) */
        uint8_t  v_scroll = ((vdp->regs[0] & 0x80u) && (col >= 24u)) ? 0u : vdp->v_scroll_latch;
        uint16_t eff_y    = (uint16_t)((scanline + v_scroll) % v_wrap);
        uint16_t tile_row = eff_y >> 3;
        uint16_t fine_y   = eff_y & 0x07u;

        uint16_t map_col  = (start_column + col) & 0x1Fu;
        uint16_t nt_addr  = (name_table_base + ((tile_row * 32u + map_col) * 2u)) & 0x3FFFu;

        uint16_t entry    = (uint16_t)vdp->vram[nt_addr]
                          | ((uint16_t)vdp->vram[(nt_addr + 1u) & 0x3FFFu] << 8);

        uint16_t tile_idx = entry & 0x01FFu;
        bool     h_flip   = (entry & 0x0200u) != 0u;
        bool     v_flip   = (entry & 0x0400u) != 0u;
        uint8_t  pal_base = (entry & 0x0800u) ? 16u : 0u;
        bool     prio     = (entry & 0x1000u) != 0u;

        uint16_t row_in_tile = v_flip ? (7u - fine_y) : fine_y;
        uint16_t patt_addr   = ((tile_idx * 32u) + (row_in_tile * 4u)) & 0x3FFFu;

        uint8_t bp0 = vdp->vram[patt_addr + 0u];
        uint8_t bp1 = vdp->vram[patt_addr + 1u];
        uint8_t bp2 = vdp->vram[patt_addr + 2u];
        uint8_t bp3 = vdp->vram[patt_addr + 3u];

        for (uint32_t px = 0; px < 8u; px++) {
            uint32_t screen_x = ((col * 8u) + px + fine_x) & 0xFFu;
            uint8_t  bit      = (uint8_t)(h_flip ? px : (7u - px));

            uint8_t color_idx = (uint8_t)(((bp0 >> bit) & 1u)
                              | (((bp1 >> bit) & 1u) << 1)
                              | (((bp2 >> bit) & 1u) << 2)
                              | (((bp3 >> bit) & 1u) << 3));

            line_dst[screen_x] = vdp->palette_lut[pal_base + color_idx];
            if (prio && color_idx != 0u) {
                bg_priority[screen_x] = 1u;
            }
        }
    }

    /* 3. Evaluate & Render Sprites from Sprite Attribute Table (SAT) */
    uint16_t sat_base = (uint16_t)(vdp->regs[5] & 0x7Eu) << 7;
    uint16_t sg_base  = (vdp->regs[6] & 0x04u) ? 0x2000u : 0x0000u;

    bool     tall_sprites   = (vdp->regs[1] & 0x02u) != 0u;
    bool     zoomed_sprites = (vdp->regs[1] & 0x01u) != 0u;
    uint16_t spr_height     = tall_sprites ? 16u : 8u;
    uint16_t disp_height    = zoomed_sprites ? (spr_height * 2u) : spr_height;
    int16_t  x_shift        = (vdp->regs[0] & 0x08u) ? -8 : 0;

    uint8_t active_sprites[8];
    uint8_t sprite_count = 0u;

    for (uint8_t i = 0; i < 64u; i++) {
        uint8_t raw_y = vdp->vram[(sat_base + i) & 0x3FFFu];
        if (vdp->active_height == YD_VDP_HEIGHT_STD && raw_y == 0xD0u) {
            break; /* 0xD0 terminates sprite list in 192-line mode */
        }

        int16_t sy = (int16_t)((raw_y + 1u) & 0xFFu);
        if (sy >= 240) {
            sy -= 256;
        }

        if ((int16_t)scanline >= sy && (int16_t)scanline < (sy + (int16_t)disp_height)) {
            if (sprite_count >= 8u) {
                vdp->status |= YD_VDP_STATUS_OVR;
                break;
            }
            active_sprites[sprite_count++] = i;
        }
    }

    uint8_t sprite_drawn[YD_VDP_WIDTH];
    memset(sprite_drawn, 0, sizeof(sprite_drawn));

    for (uint8_t s = 0; s < sprite_count; s++) {
        uint8_t idx   = active_sprites[s];
        uint8_t raw_y = vdp->vram[(sat_base + idx) & 0x3FFFu];
        int16_t sy    = (int16_t)((raw_y + 1u) & 0xFFu);
        if (sy >= 240) {
            sy -= 256;
        }

        uint16_t xn_addr  = (sat_base + 0x80u + (idx * 2u)) & 0x3FFFu;
        int16_t  sx       = (int16_t)vdp->vram[xn_addr] + x_shift;
        uint8_t  tile_num = vdp->vram[(xn_addr + 1u) & 0x3FFFu];

        if (tall_sprites) {
            tile_num &= 0xFEu;
        }

        uint16_t row = (uint16_t)((int16_t)scanline - sy);
        if (zoomed_sprites) {
            row >>= 1;
        }

        uint16_t patt_addr = (sg_base + (tile_num * 32u) + (row * 4u)) & 0x3FFFu;
        uint8_t  bp0       = vdp->vram[patt_addr + 0u];
        uint8_t  bp1       = vdp->vram[patt_addr + 1u];
        uint8_t  bp2       = vdp->vram[patt_addr + 2u];
        uint8_t  bp3       = vdp->vram[patt_addr + 3u];

        uint16_t spr_width = zoomed_sprites ? 16u : 8u;
        for (uint16_t px = 0; px < spr_width; px++) {
            int16_t screen_x = sx + (int16_t)px;
            if (screen_x < 0 || screen_x >= (int16_t)YD_VDP_WIDTH) {
                continue;
            }

            uint8_t bit       = (uint8_t)(7u - (zoomed_sprites ? (px >> 1) : px));
            uint8_t color_idx = (uint8_t)(((bp0 >> bit) & 1u)
                              | (((bp1 >> bit) & 1u) << 1)
                              | (((bp2 >> bit) & 1u) << 2)
                              | (((bp3 >> bit) & 1u) << 3));

            if (color_idx == 0u) {
                continue; /* Color 0 is transparent for sprites */
            }

            if (sprite_drawn[screen_x]) {
                /* Two non-transparent sprites overlapped -> set Collision flag */
                vdp->status |= YD_VDP_STATUS_COL;
                continue;
            }

            sprite_drawn[screen_x] = 1u;
            if (!bg_priority[screen_x]) {
                line_dst[screen_x] = vdp->palette_lut[16u + color_idx];
            }
        }
    }

    /* 4. Mask Leftmost Column (Pixels 0..7) with Backdrop Color if R0 Bit 5 is set */
    if (vdp->regs[0] & 0x20u) {
        for (uint32_t x = 0; x < 8u; x++) {
            line_dst[x] = backdrop_rgba;
        }
    }
}

/* ==========================================================================
 * Scanline Timing, Line Counter & Interrupt Generation
 * ========================================================================== */

void yd_vdp_step_scanline(yd_vdp_t *vdp, uint16_t scanline) {
    vdp->current_scanline = scanline;
    vdp->v_counter        = yd_vdp_compute_vcounter(vdp, scanline);

    if (scanline == 0u) {
        /* Latch vertical scroll register (R9) at start of active frame */
        vdp->v_scroll_latch = vdp->regs[9];
    }

    if (scanline <= vdp->active_height) {
        /* Active display lines (0..191) and first border line (192) decrement line counter */
        if (vdp->line_counter == 0u) {
            vdp->line_counter     = vdp->regs[10];
            vdp->line_irq_pending = true;
        } else {
            vdp->line_counter--;
        }
    } else {
        /* Outside active display, line counter is continually reloaded with R10 */
        vdp->line_counter = vdp->regs[10];
    }

    /* V-Blank Interrupt Flag (Status Bit 7) is set at scanline active_height + 1 */
    if (scanline == (uint16_t)(vdp->active_height + 1u)) {
        vdp->status |= YD_VDP_STATUS_VBLANK;
    }
}

bool yd_vdp_irq_asserted(const yd_vdp_t *vdp) {
    bool vblank_irq = ((vdp->status & YD_VDP_STATUS_VBLANK) != 0u)
                   && ((vdp->regs[1] & 0x20u) != 0u);
    bool line_irq   = vdp->line_irq_pending
                   && ((vdp->regs[0] & 0x10u) != 0u);
    return vblank_irq || line_irq;
}
