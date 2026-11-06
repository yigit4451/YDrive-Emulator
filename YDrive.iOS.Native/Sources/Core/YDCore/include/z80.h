#ifndef YD_CORE_Z80_H
#define YD_CORE_Z80_H

#include <stdint.h>
#include <stdbool.h>
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

/* ==========================================================================
 * Zilog Z80 Flag Bitmasks (F Register)
 *
 * Bit:   7   6   5   4   3    2   1   0
 * Flag: [S] [Z] [Y] [H] [X] [P/V] [N] [C]
 * ========================================================================== */
typedef enum z80_flag_bit {
    Z80_FLAG_C  = (1u << 0), /* Carry Flag                (Bit 0: 0x01) */
    Z80_FLAG_N  = (1u << 1), /* Add/Subtract Flag         (Bit 1: 0x02) */
    Z80_FLAG_PV = (1u << 2), /* Parity / Overflow Flag    (Bit 2: 0x04) */
    Z80_FLAG_X  = (1u << 3), /* Undocumented F3 Flag      (Bit 3: 0x08) */
    Z80_FLAG_H  = (1u << 4), /* Half-Carry Flag           (Bit 4: 0x10) */
    Z80_FLAG_Y  = (1u << 5), /* Undocumented F5 Flag      (Bit 5: 0x20) */
    Z80_FLAG_Z  = (1u << 6), /* Zero Flag                 (Bit 6: 0x40) */
    Z80_FLAG_S  = (1u << 7)  /* Sign Flag                 (Bit 7: 0x80) */
} z80_flag_bit_t;

/* Convenience mask for undocumented X/Y flag bits (bits 3 and 5) */
#define Z80_FLAG_XY_MASK (Z80_FLAG_X | Z80_FLAG_Y)

/* ==========================================================================
 * 16-bit / 8-bit Dual Register Pair Union
 *
 * Supports direct 16-bit access (.pair) as well as 8-bit high/low byte access
 * (.hi / .lo), including undocumented IXH/IXL and IYH/IYL byte access.
 * ========================================================================== */
#ifdef _MSC_VER
#pragma warning(push)
#pragma warning(disable : 4201) /* C11 anonymous struct inside union */
#endif
typedef union z80_regpair {
    uint16_t pair;
    struct {
#if defined(__BYTE_ORDER__) && (__BYTE_ORDER__ == __ORDER_BIG_ENDIAN__)
        uint8_t hi;
        uint8_t lo;
#else
        uint8_t lo;
        uint8_t hi;
#endif
    };
} z80_regpair_t;
#ifdef _MSC_VER
#pragma warning(pop)
#endif

/* ==========================================================================
 * Z80 Bus Interface (Memory & I/O Port Callbacks)
 *
 * Decouples the Z80 CPU from the underlying system MMU/VDP/PSG hardware.
 * Note: During 8-bit I/O instructions, the full 16-bit address bus value
 * (e.g., BC or (A << 8) | port) is passed in `port`.
 * ========================================================================== */
typedef struct z80_bus {
    void    *ctx;
    uint8_t (*read_mem)(void *ctx, uint16_t addr);
    void    (*write_mem)(void *ctx, uint16_t addr, uint8_t val);
    uint8_t (*read_port)(void *ctx, uint16_t port);
    void    (*write_port)(void *ctx, uint16_t port, uint8_t val);
} z80_bus_t;

/* ==========================================================================
 * Zilog Z80 CPU State Structure
 * ========================================================================== */
typedef struct z80_cpu {
    /* Main Register Set (AF, BC, DE, HL) */
    z80_regpair_t af;      /* hi = A (Accumulator), lo = F (Flags) */
    z80_regpair_t bc;      /* hi = B, lo = C */
    z80_regpair_t de;      /* hi = D, lo = E */
    z80_regpair_t hl;      /* hi = H, lo = L */

    /* Alternate / Shadow Register Set (AF', BC', DE', HL') */
    z80_regpair_t af_alt;
    z80_regpair_t bc_alt;
    z80_regpair_t de_alt;
    z80_regpair_t hl_alt;

    /* Index Registers (IX, IY) */
    z80_regpair_t ix;      /* hi = IXH, lo = IXL */
    z80_regpair_t iy;      /* hi = IYH, lo = IYL */

    /* Special Purpose Registers */
    uint16_t sp;           /* Stack Pointer */
    uint16_t pc;           /* Program Counter */
    uint16_t wz;           /* Internal hidden register (MEMPTR / WZ) */
    uint8_t  i;            /* Interrupt Vector Base Register */
    uint8_t  r;            /* Memory Refresh Register (bit 7 preserved on M1) */

    /* Interrupt & Execution Control State */
    bool     iff1;         /* Interrupt Flip-Flop 1 (maskable IRQ enable) */
    bool     iff2;         /* Interrupt Flip-Flop 2 (saved IFF1 during NMI) */
    uint8_t  im;           /* Interrupt Mode (0, 1, or 2) */
    bool     halted;       /* True when CPU is executing HALT state */
    bool     ei_delay;     /* True for 1 instruction after EI (delays IRQ) */

    /* External Interrupt Lines */
    bool     int_line;     /* Level-triggered maskable /INT line state */
    bool     nmi_pending;  /* Edge-triggered non-maskable /NMI latch */
    uint8_t  int_vector;   /* Data bus value placed during IRQ ack (default 0xFF) */

    /* Cycle Timing */
    uint64_t total_cycles; /* Cumulative T-states executed since reset */

    /* Memory & I/O Bus Interface */
    z80_bus_t bus;
} z80_cpu_t;

/* ==========================================================================
 * Inline Register & Flag Helpers
 * ========================================================================== */

/* Check if one or more flag bits are set in F */
static inline bool z80_get_flag(const z80_cpu_t *cpu, uint8_t flag_mask) {
    return (cpu->af.lo & flag_mask) != 0;
}

/* Set specified flag bit(s) in F */
static inline void z80_set_flag(z80_cpu_t *cpu, uint8_t flag_mask) {
    cpu->af.lo |= flag_mask;
}

/* Clear specified flag bit(s) in F */
static inline void z80_clear_flag(z80_cpu_t *cpu, uint8_t flag_mask) {
    cpu->af.lo &= (uint8_t)~flag_mask;
}

/* Conditionally set or clear flag bit(s) in F */
static inline void z80_assign_flag(z80_cpu_t *cpu, uint8_t flag_mask, bool cond) {
    if (cond) {
        cpu->af.lo |= flag_mask;
    } else {
        cpu->af.lo &= (uint8_t)~flag_mask;
    }
}

/* Update undocumented X (bit 3) and Y (bit 5) flags from an 8-bit result */
static inline void z80_update_xy_flags(z80_cpu_t *cpu, uint8_t val) {
    cpu->af.lo = (cpu->af.lo & (uint8_t)~Z80_FLAG_XY_MASK) | (val & Z80_FLAG_XY_MASK);
}

/* Increment the lower 7 bits of the R (Refresh) register on an M1 fetch cycle,
 * preserving bit 7 as required by Zilog Z80 hardware. */
static inline void z80_inc_r(z80_cpu_t *cpu) {
    cpu->r = (cpu->r & 0x80u) | ((cpu->r + 1u) & 0x7Fu);
}

/* ==========================================================================
 * Core Lifecycle & Execution API
 * ========================================================================== */

/**
 * Initialize a Z80 CPU instance and attach the memory/IO bus callbacks.
 */
void z80_init(z80_cpu_t *cpu, const z80_bus_t *bus);

/**
 * Perform a hardware power-on / reset of the Z80 CPU:
 * PC = 0x0000, SP = 0xFFFF, AF = 0xFFFF, I = 0x00, R = 0x00, IFF1/2 = false, IM = 0.
 */
void z80_reset(z80_cpu_t *cpu);

/**
 * Reset the Z80 CPU into the post-BIOS state expected by SEGA Master System
 * and Game Gear cartridges when running without a physical bootstrap ROM
 * (SP = 0xDFF0, IM = 1).
 */
void z80_reset_sms_post_bios(z80_cpu_t *cpu);

/**
 * Execute a single Z80 instruction (or service a pending NMI/IRQ) and
 * return the number of T-states (clock cycles) consumed.
 */
int z80_step(z80_cpu_t *cpu);

/**
 * Execute instructions until at least `target_cycles` T-states have elapsed.
 * Returns the actual number of T-states executed.
 */
int z80_run(z80_cpu_t *cpu, int target_cycles);

/**
 * Assert or deassert the level-triggered maskable interrupt line (/INT).
 */
void z80_set_int_line(z80_cpu_t *cpu, bool asserted);

/**
 * Trigger a negative-edge non-maskable interrupt (/NMI -> vector 0x0066).
 * Used by the SEGA Master System Pause button.
 */
void z80_trigger_nmi(z80_cpu_t *cpu);

#ifdef __cplusplus
}
#endif

#endif /* YD_CORE_Z80_H */
