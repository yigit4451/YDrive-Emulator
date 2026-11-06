#include "mmu.h"
#include <stdlib.h>
#include <string.h>

/* ==========================================================================
 * Refresh Cached ROM Bank Pointers
 * ========================================================================== */
void yd_mmu_update_banks(yd_mmu_t *mmu) {
    if (!mmu) {
        return;
    }
    if (!mmu->rom_data || mmu->num_rom_banks == 0) {
        mmu->slot0_ptr  = NULL;
        mmu->slot1_ptr  = NULL;
        mmu->slot2_ptr  = NULL;
        mmu->msx_ptr[0] = NULL;
        mmu->msx_ptr[1] = NULL;
        mmu->msx_ptr[2] = NULL;
        mmu->msx_ptr[3] = NULL;
        return;
    }

    uint32_t bank0 = (uint32_t)mmu->reg_slot[0] % mmu->num_rom_banks;
    uint32_t bank1 = (uint32_t)mmu->reg_slot[1] % mmu->num_rom_banks;
    uint32_t bank2 = (uint32_t)mmu->reg_slot[2] % mmu->num_rom_banks;

    mmu->slot0_ptr = mmu->rom_data + (bank0 * YD_MMU_ROM_PAGE_SIZE);
    mmu->slot1_ptr = mmu->rom_data + (bank1 * YD_MMU_ROM_PAGE_SIZE);
    mmu->slot2_ptr = mmu->rom_data + (bank2 * YD_MMU_ROM_PAGE_SIZE);

    if (mmu->num_rom_banks_8k > 0) {
        /* Korean MSX 8 KB mapping:
         * reg 0x0002 -> 0x4000-0x5FFF (msx_ptr[0])
         * reg 0x0003 -> 0x6000-0x7FFF (msx_ptr[1])
         * reg 0x0000 -> 0x8000-0x9FFF (msx_ptr[2])
         * reg 0x0001 -> 0xA000-0xBFFF (msx_ptr[3]) */
        uint32_t b_4000 = (uint32_t)mmu->msx_slot[2] % mmu->num_rom_banks_8k;
        uint32_t b_6000 = (uint32_t)mmu->msx_slot[3] % mmu->num_rom_banks_8k;
        uint32_t b_8000 = (uint32_t)mmu->msx_slot[0] % mmu->num_rom_banks_8k;
        uint32_t b_A000 = (uint32_t)mmu->msx_slot[1] % mmu->num_rom_banks_8k;

        mmu->msx_ptr[0] = mmu->rom_data + (b_4000 * YD_MMU_ROM_PAGE_8K_SIZE);
        mmu->msx_ptr[1] = mmu->rom_data + (b_6000 * YD_MMU_ROM_PAGE_8K_SIZE);
        mmu->msx_ptr[2] = mmu->rom_data + (b_8000 * YD_MMU_ROM_PAGE_8K_SIZE);
        mmu->msx_ptr[3] = mmu->rom_data + (b_A000 * YD_MMU_ROM_PAGE_8K_SIZE);
    }
}

/* ==========================================================================
 * Automatic Cartridge Mapper Detection
 * ========================================================================== */
yd_mapper_type_t yd_mmu_detect_mapper(const uint8_t *rom_data, size_t rom_size) {
    if (!rom_data || rom_size <= 0x8000u) {
        return YD_MAPPER_SEGA;
    }

    bool has_tmr_sega = (memcmp(rom_data + 0x7FF0u, "TMR SEGA", 8) == 0);

    /* 1. Check Codemasters Header Checksum/Complement at 0x7FE6 - 0x7FE9 */
    if (!has_tmr_sega) {
        uint16_t checksum   = (uint16_t)rom_data[0x7FE6u] | ((uint16_t)rom_data[0x7FE7u] << 8);
        uint16_t complement = (uint16_t)rom_data[0x7FE8u] | ((uint16_t)rom_data[0x7FE9u] << 8);
        if (checksum != 0x0000u && checksum != 0xFFFFu &&
            (uint16_t)(checksum + complement) == 0x0000u) {
            return YD_MAPPER_CODEMASTERS;
        }
    }

    /* 2. Heuristic scan of LD (nn), A (0x32 lo hi) instructions in first 32 KB */
    uint32_t sega_writes   = 0;
    uint32_t cm_writes     = 0;
    uint32_t korean_writes = 0;
    uint32_t msx_writes    = 0;

    size_t scan_len = (rom_size < 0x8000u) ? rom_size : 0x8000u;
    for (size_t i = 0; i + 2 < scan_len; i++) {
        if (rom_data[i] == 0x32u) { /* LD (nn), A */
            uint16_t target = (uint16_t)rom_data[i + 1] | ((uint16_t)rom_data[i + 2] << 8);
            if (target >= 0xFFFCu) {
                sega_writes++;
            } else if (target == 0x4000u || target == 0x8000u) {
                cm_writes++;
            } else if (target == 0xA000u) {
                korean_writes++;
            } else if (target >= 0x0001u && target <= 0x0003u) {
                msx_writes++;
            }
        }
    }

    if (sega_writes == 0) {
        if (msx_writes >= 2) {
            return YD_MAPPER_KOREAN_MSX;
        }
        if (cm_writes >= 2) {
            return YD_MAPPER_CODEMASTERS;
        }
        if (korean_writes >= 1) {
            return YD_MAPPER_KOREAN;
        }
    }

    return YD_MAPPER_SEGA;
}

/* ==========================================================================
 * Lifecycle & Configuration Functions
 * ========================================================================== */

void yd_mmu_init(yd_mmu_t *mmu) {
    if (!mmu) {
        return;
    }
    memset(mmu, 0, sizeof(*mmu));
    mmu->mapper_type = YD_MAPPER_SEGA;
    yd_mmu_reset(mmu);
}

void yd_mmu_destroy(yd_mmu_t *mmu) {
    if (!mmu) {
        return;
    }
    if (mmu->owns_rom_buffer && mmu->rom_data) {
        free(mmu->rom_data);
    }
    if (mmu->flat_ram) {
        free(mmu->flat_ram);
    }
    memset(mmu, 0, sizeof(*mmu));
}

void yd_mmu_reset(yd_mmu_t *mmu) {
    if (!mmu) {
        return;
    }

    memset(mmu->sys_ram, 0, sizeof(mmu->sys_ram));

    mmu->reg_ctrl       = 0x00u;
    mmu->reg_slot[0]    = 0x00u;
    mmu->reg_slot[1]    = 0x01u;
    mmu->reg_slot[2]    = (mmu->mapper_type == YD_MAPPER_CODEMASTERS) ? 0x00u : 0x02u;
    mmu->cm_ram_enabled = false;

    /* Default Korean MSX 8 KB sub-slots */
    mmu->msx_slot[0] = 0x04u; /* 0x8000 - 0x9FFF */
    mmu->msx_slot[1] = 0x05u; /* 0xA000 - 0xBFFF */
    mmu->msx_slot[2] = 0x02u; /* 0x4000 - 0x5FFF */
    mmu->msx_slot[3] = 0x03u; /* 0x6000 - 0x7FFF */

    /* Mirror initial mapper values at top of System RAM (0xFFFC - 0xFFFF) */
    mmu->sys_ram[0x1FFCu] = mmu->reg_ctrl;
    mmu->sys_ram[0x1FFDu] = mmu->reg_slot[0];
    mmu->sys_ram[0x1FFEu] = mmu->reg_slot[1];
    mmu->sys_ram[0x1FFFu] = mmu->reg_slot[2];

    yd_mmu_update_banks(mmu);
}

void yd_mmu_set_mapper(yd_mmu_t *mmu, yd_mapper_type_t mapper) {
    if (!mmu) {
        return;
    }
    mmu->mapper_type = mapper;
    yd_mmu_update_banks(mmu);
}

bool yd_mmu_load_rom(yd_mmu_t *mmu, const uint8_t *data, size_t size) {
    if (!mmu || !data || size == 0) {
        return false;
    }

    /* Strip optional 512-byte copier header if present in .sms / .gg file */
    if (size > 512u && (size % YD_MMU_ROM_PAGE_SIZE) == 512u) {
        data += 512u;
        size -= 512u;
    }

    /* Round allocation up to a multiple of 16 KB (minimum 1 bank = 16 KB) */
    size_t aligned_size = ((size + YD_MMU_ROM_PAGE_SIZE - 1u) / YD_MMU_ROM_PAGE_SIZE) * YD_MMU_ROM_PAGE_SIZE;
    if (aligned_size < YD_MMU_ROM_PAGE_SIZE) {
        aligned_size = YD_MMU_ROM_PAGE_SIZE;
    }

    uint8_t *new_buf = (uint8_t *)malloc(aligned_size);
    if (!new_buf) {
        return false;
    }

    memset(new_buf, 0xFF, aligned_size);
    memcpy(new_buf, data, size);

    if (mmu->owns_rom_buffer && mmu->rom_data) {
        free(mmu->rom_data);
    }

    mmu->rom_data         = new_buf;
    mmu->rom_size         = aligned_size;
    mmu->num_rom_banks    = (uint32_t)(aligned_size / YD_MMU_ROM_PAGE_SIZE);
    mmu->num_rom_banks_8k = (uint32_t)(aligned_size / YD_MMU_ROM_PAGE_8K_SIZE);
    mmu->owns_rom_buffer  = true;
    mmu->flat_mem_mode    = false;

    mmu->mapper_type = yd_mmu_detect_mapper(mmu->rom_data, mmu->rom_size);
    yd_mmu_reset(mmu);
    return true;
}

bool yd_mmu_set_flat_mode(yd_mmu_t *mmu, bool enabled) {
    if (!mmu) {
        return false;
    }
    if (enabled && !mmu->flat_ram) {
        mmu->flat_ram = (uint8_t *)calloc(1u, YD_MMU_FLAT_RAM_SIZE);
        if (!mmu->flat_ram) {
            return false;
        }
    }
    mmu->flat_mem_mode = enabled;
    return true;
}

void yd_mmu_set_io_handlers(yd_mmu_t *mmu, const yd_io_handlers_t *handlers) {
    if (!mmu) {
        return;
    }
    if (handlers) {
        mmu->io = *handlers;
    } else {
        memset(&mmu->io, 0, sizeof(mmu->io));
    }
}

/* ==========================================================================
 * Memory Read / Write Dispatch (SEGA, Codemasters, Korean, Korean MSX)
 * ========================================================================== */

uint8_t yd_mmu_read_mem(void *ctx, uint16_t addr) {
    yd_mmu_t *mmu = (yd_mmu_t *)ctx;

    /* 64 KB Flat RAM Mode (for CPU instruction & timing verification suites) */
    if (mmu->flat_mem_mode && mmu->flat_ram) {
        return mmu->flat_ram[addr];
    }

    /* 0x0000 - 0x3FFF: Slot 0 */
    if (addr < 0x4000u) {
        if (!mmu->rom_data) {
            return 0xFFu;
        }
        /* Standard SEGA Mapper pins 0x0000 - 0x03FF to Bank 0;
         * Codemasters banks the entire 0x0000 - 0x3FFF window! */
        if (mmu->mapper_type != YD_MAPPER_CODEMASTERS && addr < YD_MMU_FIXED_ROM_LIMIT) {
            return mmu->rom_data[addr];
        }
        return mmu->slot0_ptr ? mmu->slot0_ptr[addr] : 0xFFu;
    }

    /* Korean MSX 8 KB Sub-Slot Mapper (0x4000 - 0xBFFF) */
    if (mmu->mapper_type == YD_MAPPER_KOREAN_MSX && addr < 0xC000u) {
        uint8_t sub_idx = (uint8_t)((addr - 0x4000u) >> 13); /* 0..3 */
        const uint8_t *ptr = mmu->msx_ptr[sub_idx];
        return ptr ? ptr[addr & 0x1FFFu] : 0xFFu;
    }

    /* 0x4000 - 0x7FFF: Banked Slot 1 */
    if (addr < 0x8000u) {
        return mmu->slot1_ptr ? mmu->slot1_ptr[addr & 0x3FFFu] : 0xFFu;
    }

    /* 0x8000 - 0xBFFF: Banked Slot 2 OR Cartridge RAM */
    if (addr < 0xC000u) {
        if (mmu->mapper_type == YD_MAPPER_CODEMASTERS && mmu->cm_ram_enabled && addr >= 0xA000u) {
            return mmu->cart_ram[addr & 0x1FFFu];
        }
        if (mmu->mapper_type == YD_MAPPER_SEGA && (mmu->reg_ctrl & YD_MAPPER_CTRL_RAM_SLOT2)) {
            uint32_t ram_bank_offset = (mmu->reg_ctrl & YD_MAPPER_CTRL_RAM_BANK)
                                       ? YD_MMU_CART_RAM_BANK_SIZE
                                       : 0u;
            return mmu->cart_ram[ram_bank_offset + (addr & 0x3FFFu)];
        }
        return mmu->slot2_ptr ? mmu->slot2_ptr[addr & 0x3FFFu] : 0xFFu;
    }

    /* 0xC000 - 0xFFFF: 8 KB Internal System RAM (0xC000-0xDFFF) & Mirror (0xE000-0xFFFF) */
    if (mmu->mapper_type == YD_MAPPER_SEGA && (mmu->reg_ctrl & YD_MAPPER_CTRL_RAM_SYSRAM)) {
        uint32_t ram_bank_offset = (mmu->reg_ctrl & YD_MAPPER_CTRL_RAM_BANK)
                                   ? YD_MMU_CART_RAM_BANK_SIZE
                                   : 0u;
        return mmu->cart_ram[ram_bank_offset + (addr & 0x3FFFu)];
    }

    return mmu->sys_ram[addr & 0x1FFFu];
}

void yd_mmu_write_mem(void *ctx, uint16_t addr, uint8_t val) {
    yd_mmu_t *mmu = (yd_mmu_t *)ctx;

    /* 64 KB Flat RAM Mode */
    if (mmu->flat_mem_mode && mmu->flat_ram) {
        mmu->flat_ram[addr] = val;
        return;
    }

    /* 1. Handle Codemasters Mapper Writes (0x0000, 0x4000, 0x8000) */
    if (mmu->mapper_type == YD_MAPPER_CODEMASTERS && addr < 0xC000u) {
        if (addr < 0x4000u) {
            mmu->reg_slot[0] = val & 0x3Fu;
            yd_mmu_update_banks(mmu);
            return;
        }
        if (addr < 0x8000u) {
            mmu->reg_slot[1]    = val & 0x3Fu;
            mmu->cm_ram_enabled = (val & 0x80u) != 0u;
            yd_mmu_update_banks(mmu);
            return;
        }
        /* 0x8000 - 0xBFFF */
        if (mmu->cm_ram_enabled && addr >= 0xA000u) {
            mmu->cart_ram[addr & 0x1FFFu] = val;
            mmu->cart_ram_dirty           = true;
            return;
        }
        mmu->reg_slot[2] = val & 0x3Fu;
        yd_mmu_update_banks(mmu);
        return;
    }

    /* 2. Handle Korean MSX 8 KB Mapper Writes (0x0000 - 0x0003) */
    if (mmu->mapper_type == YD_MAPPER_KOREAN_MSX && addr <= 0x0003u) {
        mmu->msx_slot[addr] = val;
        yd_mmu_update_banks(mmu);
        return;
    }

    /* 3. Handle Korean 16 KB Mapper Write (0xA000) */
    if (mmu->mapper_type == YD_MAPPER_KOREAN && addr == 0xA000u) {
        mmu->reg_slot[2] = val;
        yd_mmu_update_banks(mmu);
        return;
    }

    /* 0x0000 - 0x7FFF: Cartridge ROM Slots 0 & 1 (Read-Only in SEGA/Korean mode) */
    if (addr < 0x8000u) {
        return;
    }

    /* 0x8000 - 0xBFFF: Slot 2 (Writable when SEGA Cartridge RAM is mapped) */
    if (addr < 0xC000u) {
        if (mmu->mapper_type == YD_MAPPER_SEGA && (mmu->reg_ctrl & YD_MAPPER_CTRL_RAM_SLOT2)) {
            uint32_t ram_bank_offset = (mmu->reg_ctrl & YD_MAPPER_CTRL_RAM_BANK)
                                       ? YD_MMU_CART_RAM_BANK_SIZE
                                       : 0u;
            mmu->cart_ram[ram_bank_offset + (addr & 0x3FFFu)] = val;
            mmu->cart_ram_dirty = true;
        }
        return;
    }

    /* 0xC000 - 0xFFFF: Write to 8 KB Internal System RAM (or overridden Cart RAM) */
    if (mmu->mapper_type == YD_MAPPER_SEGA && (mmu->reg_ctrl & YD_MAPPER_CTRL_RAM_SYSRAM)) {
        uint32_t ram_bank_offset = (mmu->reg_ctrl & YD_MAPPER_CTRL_RAM_BANK)
                                   ? YD_MMU_CART_RAM_BANK_SIZE
                                   : 0u;
        mmu->cart_ram[ram_bank_offset + (addr & 0x3FFFu)] = val;
        mmu->cart_ram_dirty = true;
    } else {
        mmu->sys_ram[addr & 0x1FFFu] = val;
    }

    /* 0xFFFC - 0xFFFF: SEGA Mapper Control Registers */
    if (mmu->mapper_type == YD_MAPPER_SEGA && addr >= YD_MAPPER_REG_CTRL) {
        switch (addr) {
            case YD_MAPPER_REG_CTRL:
                mmu->reg_ctrl = val;
                break;
            case YD_MAPPER_REG_SLOT0:
                mmu->reg_slot[0] = val;
                yd_mmu_update_banks(mmu);
                break;
            case YD_MAPPER_REG_SLOT1:
                mmu->reg_slot[1] = val;
                yd_mmu_update_banks(mmu);
                break;
            case YD_MAPPER_REG_SLOT2:
                mmu->reg_slot[2] = val;
                yd_mmu_update_banks(mmu);
                break;
            default:
                break;
        }
    }
}

/* ==========================================================================
 * I/O Port Dispatch & Z80 Bus Binding
 * ========================================================================== */

uint8_t yd_mmu_read_port(void *ctx, uint16_t port) {
    yd_mmu_t *mmu = (yd_mmu_t *)ctx;
    if (mmu && mmu->io.read_port) {
        return mmu->io.read_port(mmu->io.ctx, (uint8_t)(port & 0xFFu));
    }
    return 0xFFu;
}

void yd_mmu_write_port(void *ctx, uint16_t port, uint8_t val) {
    yd_mmu_t *mmu = (yd_mmu_t *)ctx;
    if (mmu && mmu->io.write_port) {
        mmu->io.write_port(mmu->io.ctx, (uint8_t)(port & 0xFFu), val);
    }
}

void yd_mmu_bind_z80_bus(yd_mmu_t *mmu, z80_bus_t *bus) {
    if (!mmu || !bus) {
        return;
    }
    bus->ctx        = mmu;
    bus->read_mem   = yd_mmu_read_mem;
    bus->write_mem  = yd_mmu_write_mem;
    bus->read_port  = yd_mmu_read_port;
    bus->write_port = yd_mmu_write_port;
}
