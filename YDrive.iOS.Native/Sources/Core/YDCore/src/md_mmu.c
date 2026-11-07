#include "md_mmu.h"
#include <stdlib.h>
#include <string.h>

/* ==========================================================================
 * Internal Helpers: 3-Button / 6-Button Joypad Multiplexer & Odd-Address Trap
 * ========================================================================== */

static uint8_t yd_md_mmu_read_pad(const yd_md_mmu_t *mmu, int port) {
    const int      p       = port & 1;
    const uint16_t buttons = mmu->pad_state[p];
    const uint8_t  latch   = mmu->io_data[p];
    const bool     th_high = (latch & 0x40u) != 0u;
    const uint8_t  step    = mmu->six_button_enabled ? (mmu->pad_th_counter[p] & 3u) : 0u;

    /* Genesis pad buttons are active-low (0 = pressed, 1 = released) */
    uint8_t result = 0x3Fu;

    if (th_high) {
        result |= 0x40u;
        if (step == 3u) {
            /* 6-Button 3rd TH=1 cycle: [0] [1] [C] [B] [Mode] [X] [Y] [Z] */
            if (buttons & YD_MD_BTN_Z)    result &= 0xFEu;
            if (buttons & YD_MD_BTN_Y)    result &= 0xFDu;
            if (buttons & YD_MD_BTN_X)    result &= 0xFBu;
            if (buttons & YD_MD_BTN_MODE) result &= 0xF7u;
            if (buttons & YD_MD_BTN_B)    result &= 0xEFu;
            if (buttons & YD_MD_BTN_C)    result &= 0xDFu;
        } else {
            /* Standard TH=1 cycle: [0] [1] [C] [B] [Right] [Left] [Down] [Up] */
            if (buttons & YD_MD_BTN_UP)    result &= 0xFEu;
            if (buttons & YD_MD_BTN_DOWN)  result &= 0xFDu;
            if (buttons & YD_MD_BTN_LEFT)  result &= 0xFBu;
            if (buttons & YD_MD_BTN_RIGHT) result &= 0xF7u;
            if (buttons & YD_MD_BTN_B)     result &= 0xEFu;
            if (buttons & YD_MD_BTN_C)     result &= 0xDFu;
        }
    } else {
        /* TH = 0: Start & A in bits 5..4 */
        if (buttons & YD_MD_BTN_A)     result &= 0xEFu;
        if (buttons & YD_MD_BTN_START) result &= 0xDFu;

        if (step == 2u) {
            /* 6-Button detection signature: lower nibble = 0000 */
            result &= 0xF0u;
        } else if (step == 3u) {
            /* 4th TH=0 cycle: lower nibble = 1111 */
            result |= 0x0Fu;
        } else {
            /* Standard TH=0 cycle: [0] [0] [Start] [A] [0] [0] [Down] [Up] */
            result &= 0xF3u;
            if (buttons & YD_MD_BTN_UP)   result &= 0xFEu;
            if (buttons & YD_MD_BTN_DOWN) result &= 0xFDu;
        }
    }

    /* Preserve bit 7 from data latch */
    result |= (uint8_t)(latch & 0x80u);
    return result;
}

static void yd_md_mmu_write_pad_latch(yd_md_mmu_t *mmu, int port, uint8_t val) {
    int     p   = port & 1;
    uint8_t old = mmu->io_data[p];
    mmu->io_data[p]     = val;
    mmu->pad_timeout[p] = 0u;

    /* Detect rising edge on TH (bit 6: 0 -> 1) */
    if (mmu->six_button_enabled && ((old & 0x40u) == 0u) && ((val & 0x40u) != 0u)) {
        mmu->pad_th_counter[p] = (uint8_t)((mmu->pad_th_counter[p] + 1u) & 3u);
    }
}

void yd_md_mmu_step_pad_timeout(yd_md_mmu_t *mmu) {
    if (!mmu) {
        return;
    }
    for (int p = 0; p < 2; p++) {
        if (mmu->pad_th_counter[p] != 0u) {
            mmu->pad_timeout[p]++;
            if (mmu->pad_timeout[p] >= 25u) {
                mmu->pad_th_counter[p] = 0u;
                mmu->pad_timeout[p]    = 0u;
            }
        }
    }
}

static bool yd_md_mmu_check_odd_addr(yd_md_mmu_t *mmu, uint32_t addr, bool is_write) {
    if ((addr & 1u) == 0u) {
        return false;
    }
    mmu->address_error_pending    = true;
    mmu->last_address_error_addr  = addr;
    mmu->last_address_error_write = is_write;

    if (mmu->check_address_error && mmu->bound_cpu != NULL) {
        m68k_raise_exception(mmu->bound_cpu, M68K_VEC_ADDRESS_ERROR);
        return true;
    }
    return false;
}

/* ==========================================================================
 * Lifecycle & Configuration
 * ========================================================================== */

void yd_md_mmu_init(yd_md_mmu_t *mmu) {
    if (!mmu) {
        return;
    }
    memset(mmu, 0, sizeof(*mmu));
    /* Default: Overseas (US) + NTSC (60Hz) + No Expansion Disc (0xA0) */
    mmu->version_reg         = (uint8_t)(YD_MD_VER_OVERSEAS | YD_MD_VER_NO_DISC);
    mmu->check_address_error = true;
    mmu->six_button_enabled  = true;
    mmu->vdp_status_stub     = 0x3400u; /* VDP FIFO Empty bit set */
    memset(mmu->sram, 0xFF, sizeof(mmu->sram));
    yd_md_mmu_reset(mmu);
}

void yd_md_mmu_destroy(yd_md_mmu_t *mmu) {
    if (!mmu) {
        return;
    }
    if (mmu->owns_rom_buffer && mmu->rom_data) {
        free(mmu->rom_data);
    }
    if (mmu->flat_ram) {
        free(mmu->flat_ram);
    }
    mmu->rom_data        = NULL;
    mmu->rom_size        = 0;
    mmu->owns_rom_buffer = false;
    mmu->flat_ram        = NULL;
    mmu->flat_mem_mode   = false;
}

void yd_md_mmu_reset(yd_md_mmu_t *mmu) {
    if (!mmu) {
        return;
    }
    memset(mmu->work_ram, 0, sizeof(mmu->work_ram));
    memset(mmu->z80_ram, 0, sizeof(mmu->z80_ram));
    memset(mmu->ym2612_regs, 0, sizeof(mmu->ym2612_regs));
    mmu->ym2612_regs[1] = 0x2Au; /* Default Z80 Port 0 latch to 0x2A (DAC Data) */
    memset(mmu->io_raw, 0, sizeof(mmu->io_raw));
    memset(mmu->tmss_reg, 0, sizeof(mmu->tmss_reg));

    /* Default controller TH lines high (0x40); io_ctrl cleared to 0x00 for cold-boot detection */
    mmu->io_data[0]        = 0x40u;
    mmu->io_data[1]        = 0x40u;
    mmu->io_data[2]        = 0x40u;
    mmu->io_ctrl[0]        = 0x00u;
    mmu->io_ctrl[1]        = 0x00u;
    mmu->io_ctrl[2]        = 0x00u;
    mmu->pad_state[0]      = 0x0000u;
    mmu->pad_state[1]      = 0x0000u;
    mmu->pad_th_counter[0] = 0u;
    mmu->pad_th_counter[1] = 0u;
    mmu->pad_timeout[0]    = 0u;
    mmu->pad_timeout[1]    = 0u;

    /* Power-on hardware defaults: Z80 BUSREQ asserted (1), Z80 RESET asserted (0 -> held in reset) */
    mmu->z80_busreq    = true;
    mmu->z80_reset     = false;
    mmu->z80_bank_addr = 0u;

    mmu->address_error_pending    = false;
    mmu->last_address_error_addr  = 0u;
    mmu->last_address_error_write = false;
}

bool yd_md_mmu_load_rom(yd_md_mmu_t *mmu, const uint8_t *data, size_t size) {
    if (!mmu || !data || size == 0) {
        return false;
    }

    /* Check for 512-byte Super Magic Drive (.smd) interleaved header */
    bool is_smd = false;
    if (size > 512u && ((size - 512u) % 16384u) == 0u) {
        if (data[8] == 0xAAu && data[9] == 0xBBu && data[10] == 0x06u) {
            is_smd = true;
        }
    }

    const uint8_t *src_ptr  = is_smd ? (data + 512u) : data;
    size_t         raw_size = is_smd ? (size - 512u) : size;
    if (raw_size > YD_MD_MAX_ROM_SIZE) {
        raw_size = YD_MD_MAX_ROM_SIZE;
    }

    /* Pad allocation to an even byte boundary */
    size_t   alloc_size = (raw_size + 1u) & ~(size_t)1u;
    uint8_t *new_rom    = (uint8_t *)calloc(1u, alloc_size);
    if (!new_rom) {
        return false;
    }

    if (is_smd) {
        /* De-interleave 16 KB SMD blocks: odd bytes in [0..8191], even in [8192..16383] */
        size_t num_blocks = raw_size / 16384u;
        for (size_t b = 0; b < num_blocks; b++) {
            const uint8_t *blk_in  = src_ptr + b * 16384u;
            uint8_t       *blk_out = new_rom + b * 16384u;
            for (size_t i = 0; i < 8192u; i++) {
                blk_out[i * 2u + 0u] = blk_in[8192u + i]; /* Even byte (high) */
                blk_out[i * 2u + 1u] = blk_in[i];         /* Odd byte  (low)  */
            }
        }
    } else {
        memcpy(new_rom, src_ptr, raw_size);
    }

    if (mmu->owns_rom_buffer && mmu->rom_data) {
        free(mmu->rom_data);
    }
    mmu->rom_data        = new_rom;
    mmu->rom_size        = alloc_size;
    mmu->owns_rom_buffer = true;

    /* Check SEGA Genesis header at 0x1B0 for "RA" (External Cartridge SRAM) */
    mmu->sram_enabled       = false;
    mmu->sram_write_protect = false;
    if (alloc_size >= 0x200u && new_rom[0x1B0] == 'R' && new_rom[0x1B1] == 'A') {
        if (alloc_size <= 0x200000u) {
            mmu->sram_enabled = true;
        }
    }

    yd_md_mmu_reset(mmu);
    return true;
}

bool yd_md_mmu_set_flat_mode(yd_md_mmu_t *mmu, bool enabled) {
    if (!mmu) {
        return false;
    }
    if (enabled) {
        if (!mmu->flat_ram) {
            mmu->flat_ram = (uint8_t *)calloc(1u, YD_MD_FLAT_RAM_SIZE);
            if (!mmu->flat_ram) {
                return false;
            }
        }
        mmu->flat_mem_mode = true;
    } else {
        mmu->flat_mem_mode = false;
    }
    return true;
}

void yd_md_mmu_set_region(yd_md_mmu_t *mmu, bool is_overseas, bool is_pal) {
    if (!mmu) {
        return;
    }
    uint8_t ver = YD_MD_VER_NO_DISC;
    if (is_overseas) {
        ver |= YD_MD_VER_OVERSEAS;
    }
    if (is_pal) {
        ver |= YD_MD_VER_PAL;
    }
    mmu->version_reg = ver;
}

void yd_md_mmu_set_pad(yd_md_mmu_t *mmu, int port, uint16_t buttons) {
    if (!mmu || port < 0 || port > 1) {
        return;
    }
    mmu->pad_state[port] = buttons;
}

void yd_md_mmu_set_vdp_handlers(yd_md_mmu_t *mmu, const yd_md_vdp_handlers_t *handlers) {
    if (!mmu) {
        return;
    }
    if (handlers) {
        mmu->vdp = *handlers;
    } else {
        memset(&mmu->vdp, 0, sizeof(mmu->vdp));
    }
}

void yd_md_mmu_set_sound_handlers(yd_md_mmu_t *mmu, const yd_md_sound_handlers_t *handlers) {
    if (!mmu) {
        return;
    }
    if (handlers) {
        mmu->sound = *handlers;
    } else {
        memset(&mmu->sound, 0, sizeof(mmu->sound));
    }
}

/* ==========================================================================
 * 8-Bit Memory Read / Write (24-Bit SEGA Genesis Address Map)
 * ========================================================================== */

uint8_t yd_md_mmu_read8(void *ctx, uint32_t addr) {
    yd_md_mmu_t *mmu = (yd_md_mmu_t *)ctx;
    addr &= M68K_ADDR_MASK;

    if (mmu->flat_mem_mode && mmu->flat_ram) {
        return mmu->flat_ram[addr];
    }

    /* 0x000000 - 0x3FFFFF: Cartridge ROM & Battery SRAM (0x200000 - 0x20FFFF) */
    if (addr < 0x400000u) {
        if (addr >= 0x200000u && addr <= 0x20FFFFu) {
            if (mmu->sram_enabled || addr >= mmu->rom_size) {
                return mmu->sram[addr & 0xFFFFu];
            }
        }
        if (mmu->rom_data && addr < mmu->rom_size) {
            return mmu->rom_data[addr];
        }
        return 0xFFu;
    }

    /* 0xE00000 - 0xFFFFFF: 64 KB M68K Work RAM (Mirrored every 64 KB) */
    if (addr >= 0xE00000u) {
        return mmu->work_ram[addr & 0xFFFFu];
    }

    /* 0xA00000 - 0xA0FFFF: Z80 Address Space Window */
    if (addr >= 0xA00000u && addr <= 0xA0FFFFu) {
        uint16_t zaddr = (uint16_t)(addr & 0x7FFFu);
        if (zaddr < 0x4000u) {
            return mmu->z80_ram[zaddr & 0x1FFFu];
        }
        if (zaddr >= 0x4000u && zaddr <= 0x5FFFu) {
            if (mmu->sound.ym_read) {
                return mmu->sound.ym_read(mmu->sound.ctx, (uint8_t)(zaddr & 3u));
            }
            return 0x00u;
        }
        return 0xFFu;
    }

    /* 0xA10000 - 0xA1001F: System & Controller I/O Ports */
    if (addr >= 0xA10000u && addr <= 0xA1001Fu) {
        uint32_t reg = (addr >> 1) & 0x0Fu;
        switch (reg) {
            case 0x0: return mmu->version_reg;
            case 0x1: return yd_md_mmu_read_pad(mmu, 0);
            case 0x2: return yd_md_mmu_read_pad(mmu, 1);
            case 0x3: return mmu->io_data[2];
            case 0x4: return mmu->io_ctrl[0];
            case 0x5: return mmu->io_ctrl[1];
            case 0x6: return mmu->io_ctrl[2];
            default:  return mmu->io_raw[reg];
        }
    }

    /* 0xA11100 - 0xA111FF: Z80 BUSREQ Status */
    if (addr >= 0xA11100u && addr <= 0xA111FFu) {
        if ((addr & 1u) == 0u) {
            /* Bit 0 == 0 when M68K has been granted the Z80 bus (busreq && reset) */
            bool bus_granted = mmu->z80_busreq && mmu->z80_reset;
            return bus_granted ? 0x00u : 0x01u;
        }
        return 0x00u;
    }

    /* 0xA11200 - 0xA112FF: Z80 RESET Status */
    if (addr >= 0xA11200u && addr <= 0xA112FFu) {
        return mmu->z80_reset ? 0x01u : 0x00u;
    }

    /* 0xA130F1: SRAM Control Register */
    if (addr == 0xA130F1u) {
        return mmu->sram_reg;
    }

    /* 0xA14000 - 0xA14003: TMSS Security Register */
    if (addr >= 0xA14000u && addr <= 0xA14003u) {
        return mmu->tmss_reg[addr & 3u];
    }

    /* 0xC00000 - 0xC0001F: Genesis VDP & PSG Window */
    if (addr >= 0xC00000u && addr <= 0xC0001Fu) {
        if (mmu->vdp.read8) {
            return mmu->vdp.read8(mmu->vdp.ctx, addr);
        }
        if (mmu->vdp.read16) {
            uint16_t w = mmu->vdp.read16(mmu->vdp.ctx, addr & ~1u);
            return (addr & 1u) ? (uint8_t)(w & 0xFFu) : (uint8_t)(w >> 8);
        }
        if ((addr & 0x1Cu) == 0x04u) {
            return (addr & 1u) ? (uint8_t)(mmu->vdp_status_stub & 0xFFu)
                               : (uint8_t)(mmu->vdp_status_stub >> 8);
        }
        return 0x00u;
    }

    /* 0x400000 - 0x9FFFFF: Expansion / Alternate SRAM Region */
    if (addr >= 0x400000u && addr <= 0x9FFFFFu) {
        if (mmu->sram_enabled) {
            return mmu->sram[addr & 0xFFFFu];
        }
        return 0xFFu;
    }

    return 0xFFu;
}

void yd_md_mmu_write8(void *ctx, uint32_t addr, uint8_t val) {
    yd_md_mmu_t *mmu = (yd_md_mmu_t *)ctx;
    addr &= M68K_ADDR_MASK;

    if (mmu->flat_mem_mode && mmu->flat_ram) {
        mmu->flat_ram[addr] = val;
        return;
    }

    /* 0xE00000 - 0xFFFFFF: 64 KB M68K Work RAM (Mirrored every 64 KB) */
    if (addr >= 0xE00000u) {
        mmu->work_ram[addr & 0xFFFFu] = val;
        return;
    }

    /* 0x000000 - 0x3FFFFF: Cartridge Space (SRAM writes at 0x200000 - 0x20FFFF) */
    if (addr < 0x400000u) {
        if (addr >= 0x200000u && addr <= 0x20FFFFu) {
            if (!mmu->sram_write_protect && (mmu->sram_enabled || addr >= mmu->rom_size)) {
                mmu->sram[addr & 0xFFFFu] = val;
                mmu->sram_dirty           = true;
            }
        }
        return;
    }

    /* 0xA00000 - 0xA0FFFF: Z80 Address Space Window */
    if (addr >= 0xA00000u && addr <= 0xA0FFFFu) {
        uint16_t zaddr = (uint16_t)(addr & 0x7FFFu);
        if (zaddr < 0x4000u) {
            mmu->z80_ram[zaddr & 0x1FFFu] = val;
        } else if (zaddr >= 0x4000u && zaddr <= 0x5FFFu) {
            uint8_t port = (uint8_t)(zaddr & 3u);
            if ((port & 1u) == 0u) {
                mmu->ym2612_regs[port] = val;
                if (port == 0u && val == 0x2Au) {
                    mmu->ym2612_regs[1] = 0x2Au;
                }
                if (mmu->sound.ym_write) {
                    mmu->sound.ym_write(mmu->sound.ctx, port, val);
                }
            } else {
                if (mmu->sound.ym_write) {
                    mmu->sound.ym_write(mmu->sound.ctx, (uint8_t)(port - 1u), mmu->ym2612_regs[port - 1u]);
                    mmu->sound.ym_write(mmu->sound.ctx, port, val);
                }
            }
        } else if (zaddr >= 0x6000u && zaddr <= 0x6FFFu) {
            mmu->z80_bank_addr = ((mmu->z80_bank_addr >> 1) | ((uint32_t)(val & 1u) << 23)) & 0xFF8000u;
        } else if ((zaddr == 0x7F11u || zaddr == 0x7F13u || zaddr == 0x7F15u || zaddr == 0x7F17u) && mmu->sound.psg_write) {
            mmu->sound.psg_write(mmu->sound.ctx, val);
        }
        return;
    }

    /* 0xA10000 - 0xA1001F: System & Controller I/O Ports */
    if (addr >= 0xA10000u && addr <= 0xA1001Fu) {
        uint32_t reg = (addr >> 1) & 0x0Fu;
        switch (reg) {
            case 0x0: break; /* Version register is read-only */
            case 0x1: yd_md_mmu_write_pad_latch(mmu, 0, val); break;
            case 0x2: yd_md_mmu_write_pad_latch(mmu, 1, val); break;
            case 0x3: mmu->io_data[2] = val; break;
            case 0x4: mmu->io_ctrl[0] = val; break;
            case 0x5: mmu->io_ctrl[1] = val; break;
            case 0x6: mmu->io_ctrl[2] = val; break;
            default:  mmu->io_raw[reg] = val; break;
        }
        return;
    }

    /* 0xA11100 - 0xA111FF: Z80 BUSREQ Control (High byte / even address bit 0) */
    if (addr >= 0xA11100u && addr <= 0xA111FFu) {
        if ((addr & 1u) == 0u) {
            mmu->z80_busreq = (val & 0x01u) != 0u;
        }
        return;
    }

    /* 0xA11200 - 0xA112FF: Z80 RESET Control (High byte / even address bit 0) */
    if (addr >= 0xA11200u && addr <= 0xA112FFu) {
        if ((addr & 1u) == 0u) {
            bool new_reset = (val & 0x01u) != 0u;
            if (!new_reset && mmu->bound_z80) {
                z80_reset(mmu->bound_z80);
                mmu->bound_z80->im = 1u;
            }
            mmu->z80_reset = new_reset;
        }
        return;
    }

    /* 0xA130F0 - 0xA130FF: Cartridge SRAM Control (0xA130F1) */
    if (addr >= 0xA130F0u && addr <= 0xA130FFu) {
        if (addr == 0xA130F1u) {
            mmu->sram_reg           = val;
            mmu->sram_enabled       = (val & 0x01u) != 0u;
            mmu->sram_write_protect = (val & 0x02u) != 0u;
        }
        return;
    }

    /* 0xA14000 - 0xA14003: TMSS Security Register ("SEGA") */
    if (addr >= 0xA14000u && addr <= 0xA14003u) {
        mmu->tmss_reg[addr & 3u] = val;
        return;
    }

    /* 0xC00000 - 0xC0001F: Genesis VDP & PSG Window */
    if (addr >= 0xC00000u && addr <= 0xC0001Fu) {
        uint32_t port = addr & 0x1Fu;
        if ((port == 0x11u || port == 0x13u || port == 0x15u || port == 0x17u) && mmu->sound.psg_write) {
            mmu->sound.psg_write(mmu->sound.ctx, val);
            return;
        }
        if (mmu->vdp.write8) {
            mmu->vdp.write8(mmu->vdp.ctx, addr, val);
        } else if (mmu->vdp.write16) {
            uint16_t dup = (uint16_t)(((uint16_t)val << 8) | val);
            mmu->vdp.write16(mmu->vdp.ctx, addr & ~1u, dup);
        }
        return;
    }

    /* 0x400000 - 0x9FFFFF: Expansion / Alternate SRAM Region */
    if (addr >= 0x400000u && addr <= 0x9FFFFFu) {
        if (mmu->sram_enabled && !mmu->sram_write_protect) {
            mmu->sram[addr & 0xFFFFu] = val;
            mmu->sram_dirty           = true;
        }
    }
}

/* ==========================================================================
 * 16-Bit & 32-Bit Big-Endian Bus Transfers (with Odd-Address Error Detection)
 * ========================================================================== */

uint16_t yd_md_mmu_read16(void *ctx, uint32_t addr) {
    yd_md_mmu_t *mmu = (yd_md_mmu_t *)ctx;
    addr &= M68K_ADDR_MASK;

    if (yd_md_mmu_check_odd_addr(mmu, addr, false)) {
        return 0u;
    }

    if (mmu->flat_mem_mode && mmu->flat_ram) {
        uint8_t hi = mmu->flat_ram[addr];
        uint8_t lo = mmu->flat_ram[(addr + 1u) & M68K_ADDR_MASK];
        return (uint16_t)(((uint16_t)hi << 8) | lo);
    }

    /* Fast path for 64 KB Work RAM (0xE00000 - 0xFFFFFF) */
    if (addr >= 0xE00000u) {
        uint16_t off = (uint16_t)(addr & 0xFFFFu);
        return (uint16_t)(((uint16_t)mmu->work_ram[off] << 8) |
                          (uint16_t)mmu->work_ram[(uint16_t)(off + 1u)]);
    }

    /* Fast path for Cartridge ROM when SRAM is not shadowing */
    if (addr < 0x200000u && mmu->rom_data && (addr + 1u) < mmu->rom_size) {
        return (uint16_t)(((uint16_t)mmu->rom_data[addr] << 8) |
                          (uint16_t)mmu->rom_data[addr + 1u]);
    }

    /* VDP 16-bit native port read (0xC00000 - 0xC0001F) */
    if (addr >= 0xC00000u && addr <= 0xC0001Fu && mmu->vdp.read16) {
        return mmu->vdp.read16(mmu->vdp.ctx, addr);
    }

    uint8_t hi = yd_md_mmu_read8(ctx, addr);
    uint8_t lo = yd_md_mmu_read8(ctx, addr + 1u);
    return (uint16_t)(((uint16_t)hi << 8) | lo);
}

void yd_md_mmu_write16(void *ctx, uint32_t addr, uint16_t val) {
    yd_md_mmu_t *mmu = (yd_md_mmu_t *)ctx;
    addr &= M68K_ADDR_MASK;

    if (yd_md_mmu_check_odd_addr(mmu, addr, true)) {
        return;
    }

    if (mmu->flat_mem_mode && mmu->flat_ram) {
        mmu->flat_ram[addr]                        = (uint8_t)(val >> 8);
        mmu->flat_ram[(addr + 1u) & M68K_ADDR_MASK] = (uint8_t)(val & 0xFFu);
        return;
    }

    /* Fast path for 64 KB Work RAM (0xE00000 - 0xFFFFFF) */
    if (addr >= 0xE00000u) {
        uint16_t off = (uint16_t)(addr & 0xFFFFu);
        mmu->work_ram[off]                  = (uint8_t)(val >> 8);
        mmu->work_ram[(uint16_t)(off + 1u)] = (uint8_t)(val & 0xFFu);
        return;
    }

    /* VDP 16-bit native port write (0xC00000 - 0xC0001F) */
    if (addr >= 0xC00000u && addr <= 0xC0001Fu) {
        uint32_t port = addr & 0x1Fu;
        if (port < 0x10u && mmu->vdp.write16) {
            mmu->vdp.write16(mmu->vdp.ctx, addr, val);
            return;
        }
    }

    /* Z80 16-bit writes to 0xA00000-0xA0FFFF on Genesis only drive the high byte (D15..D8) */
    if (addr >= 0xA00000u && addr <= 0xA0FFFFu) {
        yd_md_mmu_write8(ctx, addr, (uint8_t)(val >> 8));
        return;
    }

    yd_md_mmu_write8(ctx, addr, (uint8_t)(val >> 8));
    yd_md_mmu_write8(ctx, addr + 1u, (uint8_t)(val & 0xFFu));
}

uint32_t yd_md_mmu_read32(void *ctx, uint32_t addr) {
    yd_md_mmu_t *mmu = (yd_md_mmu_t *)ctx;
    addr &= M68K_ADDR_MASK;

    if (yd_md_mmu_check_odd_addr(mmu, addr, false)) {
        return 0u;
    }

    uint16_t hi = yd_md_mmu_read16(ctx, addr);
    uint16_t lo = yd_md_mmu_read16(ctx, addr + 2u);
    return ((uint32_t)hi << 16) | (uint32_t)lo;
}

void yd_md_mmu_write32(void *ctx, uint32_t addr, uint32_t val) {
    yd_md_mmu_t *mmu = (yd_md_mmu_t *)ctx;
    addr &= M68K_ADDR_MASK;

    if (yd_md_mmu_check_odd_addr(mmu, addr, true)) {
        return;
    }

    yd_md_mmu_write16(ctx, addr, (uint16_t)(val >> 16));
    yd_md_mmu_write16(ctx, addr + 2u, (uint16_t)(val & 0xFFFFu));
}

static void yd_md_mmu_reset_peripherals_cb(void *ctx) {
    yd_md_mmu_t *mmu = (yd_md_mmu_t *)ctx;
    if (!mmu) {
        return;
    }
    mmu->z80_reset = false;
    if (mmu->bound_z80) {
        z80_reset(mmu->bound_z80);
        mmu->bound_z80->im = 1u;
    }
}

void yd_md_mmu_bind_m68k_bus(yd_md_mmu_t *mmu, m68k_bus_t *bus, m68k_cpu_t *cpu) {
    if (!mmu || !bus) {
        return;
    }
    mmu->bound_cpu = cpu;

    memset(bus, 0, sizeof(*bus));
    bus->ctx               = mmu;
    bus->read8             = yd_md_mmu_read8;
    bus->read16            = yd_md_mmu_read16;
    bus->read32            = yd_md_mmu_read32;
    bus->write8            = yd_md_mmu_write8;
    bus->write16           = yd_md_mmu_write16;
    bus->write32           = yd_md_mmu_write32;
    bus->reset_peripherals = yd_md_mmu_reset_peripherals_cb;
    bus->int_ack           = NULL;
}

/* ==========================================================================
 * Genesis Z80 Sound Co-Processor 16-Bit Memory & Port Bus (0x0000 - 0xFFFF)
 *
 * 0x0000 - 0x3FFF : 8 KB Z80 RAM (0x0000-0x1FFF, mirrored at 0x2000-0x3FFF)
 * 0x4000 - 0x5FFF : Yamaha YM2612 FM Synthesizer (addr & 3)
 * 0x6000 - 0x60FF : 9-Bit M68K Bank Shift Register
 * 0x7F00 - 0x7FFF : VDP / SN76489 PSG Window
 * 0x8000 - 0xFFFF : 32 KB Banked Window into 24-Bit M68K Bus (z80_bank_addr | (addr & 0x7FFF))
 * ========================================================================== */

uint8_t yd_md_z80_read_mem(void *ctx, uint16_t addr) {
    yd_md_mmu_t *mmu = (yd_md_mmu_t *)ctx;

    if (addr < 0x4000u) {
        return mmu->z80_ram[addr & 0x1FFFu];
    }
    if (addr < 0x6000u) {
        if (mmu->sound.ym_read) {
            return mmu->sound.ym_read(mmu->sound.ctx, (uint8_t)(addr & 3u));
        }
        return 0x00u;
    }
    if (addr >= 0x7F00u && addr <= 0x7F1Fu) {
        return yd_md_mmu_read8(mmu, 0xC00000u | (addr & 0x1Fu));
    }
    if (addr >= 0x8000u) {
        uint32_t bank_9bit = (mmu->z80_bank_addr >> 15) & 0x1FFu;
        uint32_t rom_addr  = (bank_9bit << 15) | (uint32_t)(addr & 0x7FFFu);

        if (mmu->flat_mem_mode && mmu->flat_ram) {
            return mmu->flat_ram[rom_addr & M68K_ADDR_MASK];
        }
        if (rom_addr >= 0xE00000u) {
            return mmu->work_ram[rom_addr & 0xFFFFu];
        }
        if (mmu->rom_data && mmu->rom_size > 0u) {
            if (rom_addr >= (uint32_t)mmu->rom_size) {
                rom_addr %= (uint32_t)mmu->rom_size;
            }
            return mmu->rom_data[rom_addr];
        }
        return 0xFFu;
    }
    return 0xFFu;
}

void yd_md_z80_write_mem(void *ctx, uint16_t addr, uint8_t val) {
    yd_md_mmu_t *mmu = (yd_md_mmu_t *)ctx;

    if (addr < 0x4000u) {
        mmu->z80_ram[addr & 0x1FFFu] = val;
        return;
    }
    if (addr < 0x6000u) {
        uint8_t port = (uint8_t)(addr & 3u);
        if ((port & 1u) == 0u) {
            mmu->ym2612_regs[port | 1u] = val;
            if (mmu->sound.ym_write) {
                mmu->sound.ym_write(mmu->sound.ctx, port, val);
            }
        } else {
            if (mmu->sound.ym_write) {
                mmu->sound.ym_write(mmu->sound.ctx, (uint8_t)(port - 1u), mmu->ym2612_regs[port]);
                mmu->sound.ym_write(mmu->sound.ctx, port, val);
            }
        }
        return;
    }
    if (addr >= 0x6000u && addr <= 0x6FFFu) {
        mmu->z80_bank_addr = ((mmu->z80_bank_addr >> 1) | ((uint32_t)(val & 1u) << 23)) & 0xFF8000u;
        return;
    }
    if (addr >= 0x7F00u && addr <= 0x7F1Fu) {
        yd_md_mmu_write8(mmu, 0xC00000u | (addr & 0x1Fu), val);
        return;
    }
    if (addr >= 0x8000u) {
        uint32_t m68k_addr = mmu->z80_bank_addr | (uint32_t)(addr & 0x7FFFu);
        yd_md_mmu_write8(mmu, m68k_addr, val);
    }
}

uint8_t yd_md_z80_read_port(void *ctx, uint16_t port) {
    (void)ctx;
    (void)port;
    return 0xFFu;
}

void yd_md_z80_write_port(void *ctx, uint16_t port, uint8_t val) {
    (void)ctx;
    (void)port;
    (void)val;
}

void yd_md_mmu_bind_z80_bus(yd_md_mmu_t *mmu, z80_bus_t *bus, z80_cpu_t *z80) {
    if (!mmu || !bus) {
        return;
    }
    mmu->bound_z80  = z80;
    bus->ctx        = mmu;
    bus->read_mem   = yd_md_z80_read_mem;
    bus->write_mem  = yd_md_z80_write_mem;
    bus->read_port  = yd_md_z80_read_port;
    bus->write_port = yd_md_z80_write_port;
}
