#ifndef YD_CORE_MD_MMU_H
#define YD_CORE_MD_MMU_H

#include <stdint.h>
#include <stdbool.h>
#include <stddef.h>
#include "m68k.h"
#include "z80.h"

#ifdef __cplusplus
extern "C" {
#endif

/* ==========================================================================
 * SEGA Genesis / Mega Drive Memory Map Constants (24-bit Address Bus)
 *
 * 0x000000 - 0x3FFFFF : Cartridge ROM (Up to 4 MB, Big-Endian)
 * 0x200000 - 0x20FFFF : Cartridge Battery SRAM (Up to 64 KB when enabled)
 * 0x400000 - 0x9FFFFF : Expansion / Reserved / Alternate SRAM Region
 * 0xA00000 - 0xA0FFFF : Z80 Address Space (8 KB Z80 RAM, YM2612, Bank Reg)
 * 0xA10000 - 0xA1001F : System Version & Controller I/O Registers
 * 0xA11100 - 0xA11101 : Z80 BUSREQ Control Register
 * 0xA11200 - 0xA11201 : Z80 RESET Control Register
 * 0xA130F1            : Cartridge SRAM Control Register
 * 0xA14000 - 0xA14003 : TMSS Security Register ("SEGA")
 * 0xC00000 - 0xC0001F : Genesis VDP (Data, Control/Status, HV Counter) & PSG
 * 0xE00000 - 0xFFFFFF : 64 KB M68K Work RAM (Mirrored every 64 KB)
 * ========================================================================== */
#define YD_MD_MAX_ROM_SIZE     0x400000u  /* 4 MB Maximum Standard Cartridge ROM */
#define YD_MD_WORK_RAM_SIZE    0x010000u  /* 64 KB 68000 Main Work RAM           */
#define YD_MD_Z80_RAM_SIZE     0x002000u  /* 8 KB Z80 Sound RAM                  */
#define YD_MD_SRAM_SIZE        0x010000u  /* 64 KB Cartridge Battery-Backed SRAM */
#define YD_MD_FLAT_RAM_SIZE    0x1000000u /* 16 MB Flat RAM for M68K Unit Tests  */

/* Hardware Version Register (0xA10001) Bitmasks */
#define YD_MD_VER_OVERSEAS     (1u << 7)  /* 1 = Export (US/EU), 0 = Domestic (JP) */
#define YD_MD_VER_PAL          (1u << 6)  /* 1 = PAL (50Hz),     0 = NTSC (60Hz)   */
#define YD_MD_VER_NO_DISC      (1u << 5)  /* 1 = No Sega CD/FDD expansion attached */

/* Genesis 3-Button & 6-Button Joypad Bitmasks (16-bit) */
typedef enum yd_md_button {
    YD_MD_BTN_UP    = (1u << 0),
    YD_MD_BTN_DOWN  = (1u << 1),
    YD_MD_BTN_LEFT  = (1u << 2),
    YD_MD_BTN_RIGHT = (1u << 3),
    YD_MD_BTN_B     = (1u << 4),
    YD_MD_BTN_C     = (1u << 5),
    YD_MD_BTN_A     = (1u << 6),
    YD_MD_BTN_START = (1u << 7),
    YD_MD_BTN_Z     = (1u << 8),
    YD_MD_BTN_Y     = (1u << 9),
    YD_MD_BTN_X     = (1u << 10),
    YD_MD_BTN_MODE  = (1u << 11)
} yd_md_button_t;

/* ==========================================================================
 * External Genesis VDP & Sound Bus Callbacks (0xC00000-0xC0001F, 0xA04000)
 * ========================================================================== */
typedef struct yd_md_vdp_handlers {
    void     *ctx;
    uint8_t  (*read8)(void *ctx, uint32_t addr);
    uint16_t (*read16)(void *ctx, uint32_t addr);
    void     (*write8)(void *ctx, uint32_t addr, uint8_t val);
    void     (*write16)(void *ctx, uint32_t addr, uint16_t val);
} yd_md_vdp_handlers_t;

typedef struct yd_md_sound_handlers {
    void    *ctx;
    uint8_t (*ym_read)(void *ctx, uint8_t port);
    void    (*ym_write)(void *ctx, uint8_t port, uint8_t val);
    void    (*psg_write)(void *ctx, uint8_t val);
} yd_md_sound_handlers_t;

/* ==========================================================================
 * SEGA Genesis / Mega Drive MMU State Structure
 * ========================================================================== */
typedef struct yd_md_mmu {
    /* Cartridge ROM Buffer (stored in native Big-Endian byte order) */
    uint8_t *rom_data;
    size_t   rom_size;
    bool     owns_rom_buffer;

    /* 64 KB 68000 Main Work RAM (0xE00000 - 0xFFFFFF, mirrored via & 0xFFFF) */
    uint8_t  work_ram[YD_MD_WORK_RAM_SIZE];

    /* 8 KB Z80 Sound RAM (0xA00000 - 0xA01FFF, mirrored up to 0xA03FFF) */
    uint8_t  z80_ram[YD_MD_Z80_RAM_SIZE];

    /* 64 KB Cartridge Battery-Backed SRAM */
    uint8_t  sram[YD_MD_SRAM_SIZE];
    uint8_t  sram_reg;            /* 0xA130F1: Bit 0 = Enable, Bit 1 = Write Protect */
    bool     sram_enabled;
    bool     sram_write_protect;
    bool     sram_dirty;

    /* Z80 Bus Arbitration & Reset Registers */
    bool     z80_busreq;          /* 0xA11100: true when 68K requests Z80 bus (0x0100) */
    bool     z80_reset;           /* 0xA11200: true when Z80 reset is deasserted (0x0100)*/
    uint32_t z80_bank_addr;       /* 0xA06000: 9-bit shift register for Z80 32KB window*/
    uint8_t  ym2612_regs[4];      /* 0xA04000-0xA04003 latch shadow */
    z80_cpu_t *bound_z80;         /* Optional pointer to Z80 co-processor for 0xA11200 reset */

    /* System & Controller I/O Registers (0xA10000 - 0xA1001F) */
    uint8_t  version_reg;         /* 0xA10001: Region/Video standard (default 0xA0) */
    uint8_t  io_data[3];          /* 0xA10003, 0xA10005, 0xA10007 data latches (TH bit)*/
    uint8_t  io_ctrl[3];          /* 0xA10009, 0xA1000B, 0xA1000D direction registers  */
    uint8_t  io_raw[16];          /* Raw register backing for serial/misc I/O ports    */
    uint16_t pad_state[2];        /* Active-high 12-bit button bitmask (Up..Mode)      */
    uint8_t  pad_th_counter[2];   /* 6-button TH rising-edge pulse counter (0..3)      */
    uint8_t  pad_timeout[2];      /* Scanline timeout counter for 6-button state reset */
    bool     six_button_enabled;  /* True when 6-button pad mode is enabled (default)  */

    /* TMSS Security Register ("SEGA" at 0xA14000 - 0xA14003) */
    uint8_t  tmss_reg[4];

    /* Odd-Address Alignment Error Tracking (Word/Long accesses on odd address) */
    bool     check_address_error;
    bool     address_error_pending;
    uint32_t last_address_error_addr;
    bool     last_address_error_write;
    m68k_cpu_t *bound_cpu;        /* Optional pointer to M68K CPU for auto-trap */

    /* Optional VDP & Sound Bus Handlers (0xC00000 - 0xC0001F, 0xA04000) */
    yd_md_vdp_handlers_t   vdp;
    yd_md_sound_handlers_t sound;
    uint16_t               vdp_status_stub; /* Default VDP status (0x3400) when VDP unattached */

    /* 16 MB Flat Memory Mode (for standalone M68K CPU test suites) */
    bool     flat_mem_mode;
    uint8_t *flat_ram;
} yd_md_mmu_t;

/* ==========================================================================
 * Genesis MMU Public API
 * ========================================================================== */

void yd_md_mmu_init(yd_md_mmu_t *mmu);
void yd_md_mmu_destroy(yd_md_mmu_t *mmu);
void yd_md_mmu_reset(yd_md_mmu_t *mmu);

bool yd_md_mmu_load_rom(yd_md_mmu_t *mmu, const uint8_t *data, size_t size);
bool yd_md_mmu_set_flat_mode(yd_md_mmu_t *mmu, bool enabled);
void yd_md_mmu_set_region(yd_md_mmu_t *mmu, bool is_overseas, bool is_pal);

/**
 * Update the pressed button bitmask (`yd_md_button_t`, 3-button or 6-button)
 * for Controller 1 (0) or Controller 2 (1).
 */
void yd_md_mmu_set_pad(yd_md_mmu_t *mmu, int port, uint16_t buttons);

/**
 * Advance the 6-button controller TH pulse timeout by one scanline.
 */
void yd_md_mmu_step_pad_timeout(yd_md_mmu_t *mmu);

void yd_md_mmu_set_vdp_handlers(yd_md_mmu_t *mmu, const yd_md_vdp_handlers_t *handlers);
void yd_md_mmu_set_sound_handlers(yd_md_mmu_t *mmu, const yd_md_sound_handlers_t *handlers);

/* M68K Big-Endian 24-bit Bus Operations */
uint8_t  yd_md_mmu_read8(void *ctx, uint32_t addr);
uint16_t yd_md_mmu_read16(void *ctx, uint32_t addr);
uint32_t yd_md_mmu_read32(void *ctx, uint32_t addr);

void     yd_md_mmu_write8(void *ctx, uint32_t addr, uint8_t val);
void     yd_md_mmu_write16(void *ctx, uint32_t addr, uint16_t val);
void     yd_md_mmu_write32(void *ctx, uint32_t addr, uint32_t val);

void     yd_md_mmu_bind_m68k_bus(yd_md_mmu_t *mmu, m68k_bus_t *bus, m68k_cpu_t *cpu);

/* Genesis Z80 Sound Co-Processor 16-bit Bus Operations (0x0000 - 0xFFFF) */
uint8_t  yd_md_z80_read_mem(void *ctx, uint16_t addr);
void     yd_md_z80_write_mem(void *ctx, uint16_t addr, uint8_t val);
uint8_t  yd_md_z80_read_port(void *ctx, uint16_t port);
void     yd_md_z80_write_port(void *ctx, uint16_t port, uint8_t val);
void     yd_md_mmu_bind_z80_bus(yd_md_mmu_t *mmu, z80_bus_t *bus, z80_cpu_t *z80);

#ifdef __cplusplus
}
#endif

#endif /* YD_CORE_MD_MMU_H */
