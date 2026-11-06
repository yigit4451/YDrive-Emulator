#ifndef YD_CORE_MMU_H
#define YD_CORE_MMU_H

#include <stdint.h>
#include <stdbool.h>
#include <stddef.h>
#include "z80.h"

#ifdef __cplusplus
extern "C" {
#endif

/* ==========================================================================
 * SEGA Master System / Game Gear Memory Map Constants
 * ========================================================================== */
#define YD_MMU_ROM_PAGE_SIZE      0x4000u  /* 16 KB per standard ROM bank */
#define YD_MMU_ROM_PAGE_8K_SIZE   0x2000u  /* 8 KB per Korean MSX sub-bank */
#define YD_MMU_FIXED_ROM_LIMIT    0x0400u  /* 0x0000 - 0x03FF: Fixed 1 KB Bank 0 (SEGA Mapper) */
#define YD_MMU_SYS_RAM_SIZE       0x2000u  /* 8 KB Internal System RAM (0xC000-0xDFFF) */
#define YD_MMU_CART_RAM_BANK_SIZE 0x4000u  /* 16 KB per Cartridge SRAM bank */
#define YD_MMU_CART_RAM_SIZE      0x8000u  /* 32 KB Total Cartridge SRAM (2 banks) */
#define YD_MMU_FLAT_RAM_SIZE      0x10000u /* 64 KB Flat RAM for CPU test suites */

/* SEGA Mapper Control Register Addresses (Mirrored at 0xFFFC - 0xFFFF) */
#define YD_MAPPER_REG_CTRL        0xFFFCu
#define YD_MAPPER_REG_SLOT0       0xFFFDu
#define YD_MAPPER_REG_SLOT1       0xFFFEu
#define YD_MAPPER_REG_SLOT2       0xFFFFu

/* Bitmasks for 0xFFFC Mapper Control Register */
#define YD_MAPPER_CTRL_SHIFT_MASK 0x03u    /* Bits 0-1: Bank shift */
#define YD_MAPPER_CTRL_RAM_BANK   (1u << 2)/* Bit 2: Cart RAM page select (0 or 1) */
#define YD_MAPPER_CTRL_RAM_SLOT2  (1u << 3)/* Bit 3: Enable Cart RAM at 0x8000-0xBFFF */
#define YD_MAPPER_CTRL_RAM_SYSRAM (1u << 4)/* Bit 4: Enable Cart RAM at 0xC000-0xFFFF */
#define YD_MAPPER_CTRL_RO_ENABLE  (1u << 7)/* Bit 7: Write protection flag */

/* ==========================================================================
 * Supported Cartridge Mapper Types
 * ========================================================================== */
typedef enum yd_mapper_type {
    YD_MAPPER_SEGA        = 0, /* Standard SEGA Mapper (0xFFFC - 0xFFFF) */
    YD_MAPPER_CODEMASTERS = 1, /* Codemasters Mapper (0x0000, 0x4000, 0x8000) */
    YD_MAPPER_KOREAN      = 2, /* Korean 16KB Mapper (0xA000 switches Slot 2) */
    YD_MAPPER_KOREAN_MSX  = 3  /* Korean MSX 8KB Mapper (0x0000 - 0x0003) */
} yd_mapper_type_t;

/* ==========================================================================
 * External I/O Port Handler Callbacks (VDP, PSG, Joypad, Gear-to-Gear)
 * ========================================================================== */
typedef struct yd_io_handlers {
    void    *ctx;
    uint8_t (*read_port)(void *ctx, uint8_t port);
    void    (*write_port)(void *ctx, uint8_t port, uint8_t val);
} yd_io_handlers_t;

/* ==========================================================================
 * MMU & Cartridge Mapper State Structure
 * ========================================================================== */
typedef struct yd_mmu {
    /* Cartridge ROM Buffer (owned copy or external pointer) */
    uint8_t *rom_data;
    size_t   rom_size;
    uint32_t num_rom_banks;       /* Number of 16 KB banks */
    uint32_t num_rom_banks_8k;    /* Number of 8 KB banks (for Korean MSX mapper) */
    bool     owns_rom_buffer;

    /* Active Mapper Type */
    yd_mapper_type_t mapper_type;

    /* Cached Pointers for Fast 16 KB Slot Lookups */
    const uint8_t *slot0_ptr;     /* 0x0000/0x0400 - 0x3FFF base pointer */
    const uint8_t *slot1_ptr;     /* 0x4000 - 0x7FFF base pointer */
    const uint8_t *slot2_ptr;     /* 0x8000 - 0xBFFF base pointer */

    /* Cached Pointers for Korean MSX 8 KB Sub-Slots (0x4000 - 0xBFFF) */
    const uint8_t *msx_ptr[4];    /* [0]=4000-5FFF, [1]=6000-7FFF, [2]=8000-9FFF, [3]=A000-BFFF */

    /* Mapper Bank & Control Registers */
    uint8_t  reg_ctrl;            /* 0xFFFC: RAM / Mapper Control */
    uint8_t  reg_slot[3];         /* 16 KB Bank numbers for Slots 0, 1, 2 */
    uint8_t  msx_slot[4];         /* 8 KB Bank numbers for Korean MSX (0x0000 - 0x0003) */
    bool     cm_ram_enabled;      /* Codemasters on-cartridge RAM enable (0xA000-0xBFFF) */

    /* Cartridge Battery-Backed SRAM (2 x 16 KB = 32 KB) */
    uint8_t  cart_ram[YD_MMU_CART_RAM_SIZE];
    bool     cart_ram_dirty;      /* Set true if Cartridge SRAM has been written to */

    /* Internal 8 KB System RAM (0xC000 - 0xDFFF, mirrored at 0xE000 - 0xFFFF) */
    uint8_t  sys_ram[YD_MMU_SYS_RAM_SIZE];

    /* Optional 64 KB Flat Memory Mode (for Z80 CPU unit & compliance tests) */
    bool     flat_mem_mode;
    uint8_t *flat_ram;

    /* Optional I/O Port Dispatchers */
    yd_io_handlers_t io;
} yd_mmu_t;

/* ==========================================================================
 * MMU Public API
 * ========================================================================== */

/**
 * Initialize the MMU state to power-on defaults.
 */
void yd_mmu_init(yd_mmu_t *mmu);

/**
 * Free any dynamically allocated ROM or flat-RAM buffers owned by the MMU.
 */
void yd_mmu_destroy(yd_mmu_t *mmu);

/**
 * Reset the Mapper registers and clear internal System RAM.
 */
void yd_mmu_reset(yd_mmu_t *mmu);

/**
 * Recompute cached bank pointers (`slot0_ptr`..`slot2_ptr`, `msx_ptr`) from current register state.
 */
void yd_mmu_update_banks(yd_mmu_t *mmu);

/**
 * Explicitly set the active cartridge mapper type and refresh bank pointers.
 */
void yd_mmu_set_mapper(yd_mmu_t *mmu, yd_mapper_type_t mapper);

/**
 * Auto-detect the cartridge mapper type from a ROM image buffer.
 */
yd_mapper_type_t yd_mmu_detect_mapper(const uint8_t *rom_data, size_t rom_size);

/**
 * Load a Cartridge ROM image into the MMU, auto-detecting the mapper type.
 * Automatically detects and strips an optional 512-byte copier header if present.
 */
bool yd_mmu_load_rom(yd_mmu_t *mmu, const uint8_t *data, size_t size);

/**
 * Enable or disable 64 KB flat RAM mode (used by standalone Z80 CPU tests).
 */
bool yd_mmu_set_flat_mode(yd_mmu_t *mmu, bool enabled);

/**
 * Attach I/O port handlers (VDP, PSG, Joypad) to the MMU.
 */
void yd_mmu_set_io_handlers(yd_mmu_t *mmu, const yd_io_handlers_t *handlers);

/**
 * Read a byte from the 16-bit Z80 memory address space.
 */
uint8_t yd_mmu_read_mem(void *ctx, uint16_t addr);

/**
 * Write a byte to the 16-bit Z80 memory address space (handles SEGA, Codemasters, Korean mappers).
 */
void yd_mmu_write_mem(void *ctx, uint16_t addr, uint8_t val);

/**
 * Read a byte from an 8-bit Z80 I/O port (ports 0x00 - 0xFF).
 */
uint8_t yd_mmu_read_port(void *ctx, uint16_t port);

/**
 * Write a byte to an 8-bit Z80 I/O port (ports 0x00 - 0xFF).
 */
void yd_mmu_write_port(void *ctx, uint16_t port, uint8_t val);

/**
 * Populate a `z80_bus_t` descriptor so a `z80_cpu_t` communicates directly
 * with this MMU instance.
 */
void yd_mmu_bind_z80_bus(yd_mmu_t *mmu, z80_bus_t *bus);

#ifdef __cplusplus
}
#endif

#endif /* YD_CORE_MMU_H */
