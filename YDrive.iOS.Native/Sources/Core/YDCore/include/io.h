#ifndef YD_CORE_IO_H
#define YD_CORE_IO_H

#include <stdint.h>
#include <stdbool.h>
#include "z80.h"
#include "mmu.h"
#include "vdp.h"
#include "psg.h"

#ifdef __cplusplus
extern "C" {
#endif

/* ==========================================================================
 * SEGA Master System / Game Gear I/O Port Addresses
 * ========================================================================== */
#define YD_PORT_GG_START       0x00u /* Game Gear Start & Region Register */
#define YD_PORT_GG_STEREO      0x06u /* Game Gear Stereo Panning Register */
#define YD_PORT_MEM_CTRL       0x3Eu /* Memory Control Register */
#define YD_PORT_IO_CTRL        0x3Fu /* I/O Port Nationalization / TH Control */
#define YD_PORT_VCOUNTER       0x7Eu /* VDP V-Counter (Read) / PSG (Write) */
#define YD_PORT_HCOUNTER       0x7Fu /* VDP H-Counter (Read) / PSG (Write) */
#define YD_PORT_VDP_DATA       0xBEu /* VDP Data Port (Read/Write) */
#define YD_PORT_VDP_CTRL       0xBFu /* VDP Control (Write) / Status (Read) */
#define YD_PORT_JOYPAD_A       0xDCu /* Controller Port A (P1 + P2 Up/Down) */
#define YD_PORT_JOYPAD_B       0xDDu /* Controller Port B (P2 + Reset + TH) */

/* ==========================================================================
 * Controller Button Bitmasks (Active-High in API, Converted to Active-Low on Bus)
 * ========================================================================== */
typedef enum yd_joypad_button {
    YD_PAD_UP    = (1u << 0),
    YD_PAD_DOWN  = (1u << 1),
    YD_PAD_LEFT  = (1u << 2),
    YD_PAD_RIGHT = (1u << 3),
    YD_PAD_BTN1  = (1u << 4), /* Button 1 (Start/A) */
    YD_PAD_BTN2  = (1u << 5), /* Button 2 (B)       */
    YD_PAD_START = (1u << 6), /* Game Gear Start / SMS Pause (NMI) */
    YD_PAD_RESET = (1u << 7)  /* Master System Console Reset Button */
} yd_joypad_button_t;

/* ==========================================================================
 * I/O Subsystem State Structure
 * ========================================================================== */
typedef struct yd_io {
    yd_vdp_t  *vdp;
    yd_psg_t  *psg;
    z80_cpu_t *cpu;

    uint8_t    pad_state[2];   /* Active-high button state for Player 0 & Player 1 */
    uint8_t    mem_ctrl;       /* Port 0x3E value */
    uint8_t    io_ctrl;        /* Port 0x3F value (TH direction & level) */
    uint8_t    gg_regs[7];     /* Game Gear system ports 0x00 - 0x06 */
    uint8_t    last_psg_byte;  /* Most recent byte written to PSG port 0x7E/0x7F */

    bool       is_game_gear;
    bool       is_domestic_jp; /* False = Export (US/EU), True = Japanese Domestic */
} yd_io_t;

/* ==========================================================================
 * I/O Subsystem Public API
 * ========================================================================== */

/**
 * Initialize the I/O router and connect it to the VDP, PSG, and Z80 CPU instances.
 */
void yd_io_init(yd_io_t *io, yd_vdp_t *vdp, yd_psg_t *psg, z80_cpu_t *cpu);

/**
 * Reset I/O port latches and controller states to power-on defaults.
 */
void yd_io_reset(yd_io_t *io);

/**
 * Set the active-high button state mask for `player` (0 = Player 1, 1 = Player 2).
 */
void yd_io_set_joypad(yd_io_t *io, int player, uint8_t buttons);

/**
 * Read a byte from an 8-bit Z80 I/O port (`0x00 - 0xFF`).
 */
uint8_t yd_io_read_port(void *ctx, uint8_t port);

/**
 * Write a byte to an 8-bit Z80 I/O port (`0x00 - 0xFF`).
 */
void yd_io_write_port(void *ctx, uint8_t port, uint8_t val);

/**
 * Bind this I/O router to an MMU instance's I/O handler callbacks.
 */
void yd_io_bind_mmu(yd_io_t *io, yd_mmu_t *mmu);

#ifdef __cplusplus
}
#endif

#endif /* YD_CORE_IO_H */
