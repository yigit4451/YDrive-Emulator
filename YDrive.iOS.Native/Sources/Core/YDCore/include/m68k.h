#ifndef YD_CORE_M68K_H
#define YD_CORE_M68K_H

#include <stdint.h>
#include <stdbool.h>
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

/* ==========================================================================
 * Motorola MC68000 Architectural Constants (SEGA Genesis / Mega Drive)
 *
 * - Internal Registers: 32-bit (D0-D7, A0-A7, PC)
 * - External Address Bus: 24-bit (0x000000 - 0xFFFFFF, 16 MB address space)
 * - External Data Bus: 16-bit Big-Endian
 * - Master Clock (NTSC): ~7.670454 MHz (53.693175 MHz / 7)
 * ========================================================================== */
#define M68K_ADDR_MASK            0x00FFFFFFu /* 24-bit physical address bus mask */
#define M68K_INT_ACK_AUTOVECTOR   (-1)        /* Use standard autovector (24 + level) */
#define M68K_INT_ACK_SPURIOUS     (-2)        /* Use spurious interrupt vector (24) */

/* ==========================================================================
 * 16-bit Status Register (SR) & 8-bit Condition Code Register (CCR) Masks
 *
 * Bit:  15  14  13  12  11  10   9   8 |  7   6   5   4   3   2   1   0
 * SR:  [ T] [0] [ S] [0] [0] [I2][I1][I0]| [0] [0] [0] [ X] [ N] [ Z] [ V] [ C]
 *      |<-------- System Byte --------->| |<----- User Byte (CCR) ----->|
 * ========================================================================== */
typedef enum m68k_sr_bit {
    /* User Byte / Condition Code Register (CCR - Bits 0..4) */
    M68K_SR_C          = (1u << 0),  /* Carry / Borrow Flag           (0x0001) */
    M68K_SR_V          = (1u << 1),  /* Overflow Flag                 (0x0002) */
    M68K_SR_Z          = (1u << 2),  /* Zero Flag                     (0x0004) */
    M68K_SR_N          = (1u << 3),  /* Negative Flag                 (0x0008) */
    M68K_SR_X          = (1u << 4),  /* Extend Flag (Multi-precision) (0x0010) */

    /* System Byte (Supervisor Only - Bits 8..15) */
    M68K_SR_I0         = (1u << 8),  /* Interrupt Priority Mask Bit 0 (0x0100) */
    M68K_SR_I1         = (1u << 9),  /* Interrupt Priority Mask Bit 1 (0x0200) */
    M68K_SR_I2         = (1u << 10), /* Interrupt Priority Mask Bit 2 (0x0400) */
    M68K_SR_S          = (1u << 13), /* Supervisor Mode Flag          (0x2000) */
    M68K_SR_T          = (1u << 15)  /* Trace Mode Flag               (0x8000) */
} m68k_sr_bit_t;

#define M68K_CCR_MASK             0x001Fu /* Implemented CCR bits (X, N, Z, V, C) */
#define M68K_SR_I_MASK            0x0700u /* Interrupt Priority Mask bits (I2..I0) */
#define M68K_SR_I_SHIFT           8u      /* Bit shift for Interrupt Priority Level */
#define M68K_SR_SYS_MASK          0xA700u /* Implemented System Byte bits (T, S, I2..I0) */
#define M68K_SR_VALID_MASK        0xA71Fu /* All valid MC68000 SR bits (unimplemented read 0) */

/* ==========================================================================
 * Operand Size Specifier
 * ========================================================================== */
typedef enum m68k_size {
    M68K_SIZE_BYTE = 1, /* .B : 8-bit operand  */
    M68K_SIZE_WORD = 2, /* .W : 16-bit operand */
    M68K_SIZE_LONG = 4  /* .L : 32-bit operand */
} m68k_size_t;

/* ==========================================================================
 * Standard 4-bit Condition Codes (cc for Bcc, DBcc, Scc)
 * ========================================================================== */
typedef enum m68k_cond {
    M68K_COND_T  = 0x0, /* True                  (1)              */
    M68K_COND_F  = 0x1, /* False                 (0)              */
    M68K_COND_HI = 0x2, /* Higher                (!C && !Z)       */
    M68K_COND_LS = 0x3, /* Lower or Same         (C || Z)         */
    M68K_COND_CC = 0x4, /* Carry Clear (HS)      (!C)             */
    M68K_COND_CS = 0x5, /* Carry Set   (LO)      (C)              */
    M68K_COND_NE = 0x6, /* Not Equal             (!Z)             */
    M68K_COND_EQ = 0x7, /* Equal                 (Z)              */
    M68K_COND_VC = 0x8, /* Overflow Clear        (!V)             */
    M68K_COND_VS = 0x9, /* Overflow Set          (V)              */
    M68K_COND_PL = 0xA, /* Plus                  (!N)             */
    M68K_COND_MI = 0xB, /* Minus                 (N)              */
    M68K_COND_GE = 0xC, /* Greater or Equal      (N == V)         */
    M68K_COND_LT = 0xD, /* Less Than             (N != V)         */
    M68K_COND_GT = 0xE, /* Greater Than          (!Z && (N == V)) */
    M68K_COND_LE = 0xF  /* Less or Equal         (Z || (N != V))  */
} m68k_cond_t;

/* ==========================================================================
 * Motorola 68000 Exception Vector Table Numbers (Vector Offset = num * 4)
 * ========================================================================== */
typedef enum m68k_vector {
    M68K_VEC_RESET_SSP        = 0,  /* 0x000: Initial Supervisor Stack Pointer */
    M68K_VEC_RESET_PC         = 1,  /* 0x004: Initial Program Counter          */
    M68K_VEC_BUS_ERROR        = 2,  /* 0x008: Bus Error                        */
    M68K_VEC_ADDRESS_ERROR    = 3,  /* 0x00C: Odd Word/Long Address Error      */
    M68K_VEC_ILLEGAL_INST     = 4,  /* 0x010: Illegal Instruction              */
    M68K_VEC_ZERO_DIVIDE      = 5,  /* 0x014: Integer Divide by Zero           */
    M68K_VEC_CHK              = 6,  /* 0x018: CHK Instruction Out of Bounds    */
    M68K_VEC_TRAPV            = 7,  /* 0x01C: TRAPV Overflow                   */
    M68K_VEC_PRIVILEGE_VIOL   = 8,  /* 0x020: Privilege Violation              */
    M68K_VEC_TRACE            = 9,  /* 0x024: Trace Exception                  */
    M68K_VEC_LINE_1010        = 10, /* 0x028: Line 1010 Emulator (A-Line)      */
    M68K_VEC_LINE_1111        = 11, /* 0x02C: Line 1111 Emulator (F-Line)      */
    M68K_VEC_SPURIOUS_INT     = 24, /* 0x060: Spurious Interrupt               */
    M68K_VEC_AUTOVEC_LVL1     = 25, /* 0x064: Level 1 Interrupt Autovector     */
    M68K_VEC_AUTOVEC_LVL2     = 26, /* 0x068: Level 2 Interrupt (Genesis EXT)  */
    M68K_VEC_AUTOVEC_LVL3     = 27, /* 0x06C: Level 3 Interrupt Autovector     */
    M68K_VEC_AUTOVEC_LVL4     = 28, /* 0x070: Level 4 Interrupt (Genesis HINT) */
    M68K_VEC_AUTOVEC_LVL5     = 29, /* 0x074: Level 5 Interrupt Autovector     */
    M68K_VEC_AUTOVEC_LVL6     = 30, /* 0x078: Level 6 Interrupt (Genesis VINT) */
    M68K_VEC_AUTOVEC_LVL7     = 31, /* 0x07C: Level 7 Interrupt (NMI)          */
    M68K_VEC_TRAP_BASE        = 32  /* 0x080..0x0BC: TRAP #0 .. TRAP #15       */
} m68k_vector_t;

/* ==========================================================================
 * 32-bit / 16-bit / 8-bit Register Union
 *
 * Allows sub-register partial access (.b, .w, .l) without masking overhead,
 * while preserving upper bits during .B and .W Data Register operations.
 * ========================================================================== */
#ifdef _MSC_VER
#pragma warning(push)
#pragma warning(disable : 4201) /* C11 anonymous struct/union */
#endif

typedef union m68k_reg32 {
    uint32_t l;     /* Full 32-bit Longword (.L) */
    int32_t  sl;    /* Signed 32-bit Longword    */
    struct {
#if defined(__BYTE_ORDER__) && (__BYTE_ORDER__ == __ORDER_BIG_ENDIAN__)
        uint16_t hi_w;
        uint16_t w; /* Low 16-bit Word (.W) */
#else
        uint16_t w; /* Low 16-bit Word (.W) */
        uint16_t hi_w;
#endif
    };
    struct {
#if defined(__BYTE_ORDER__) && (__BYTE_ORDER__ == __ORDER_BIG_ENDIAN__)
        uint8_t b3;
        uint8_t b2;
        uint8_t b1;
        uint8_t b;  /* Low 8-bit Byte (.B) */
#else
        uint8_t b;  /* Low 8-bit Byte (.B) */
        uint8_t b1;
        uint8_t b2;
        uint8_t b3;
#endif
    };
} m68k_reg32_t;

/* ==========================================================================
 * Genesis / M68K Memory Bus Interface (Big-Endian Hardware Bus)
 *
 * - `read8` / `write8`   : 8-bit byte transfer
 * - `read16` / `write16` : 16-bit word transfer (host-endian uint16_t value
 *                          decoded from Big-Endian bus)
 * - `read32` / `write32` : 32-bit longword transfer (optional; if NULL, the
 *                          CPU automatically performs two consecutive 16-bit
 *                          transfers: high word at `addr`, low word at `addr + 2`)
 * - `reset_peripherals`  : Optional hook invoked by the `RESET` instruction
 * - `int_ack`            : Optional Interrupt Acknowledge hook returning vector
 *                          number or `M68K_INT_ACK_AUTOVECTOR`
 * ========================================================================== */
typedef struct m68k_bus {
    void     *ctx;
    uint8_t  (*read8)(void *ctx, uint32_t addr);
    uint16_t (*read16)(void *ctx, uint32_t addr);
    uint32_t (*read32)(void *ctx, uint32_t addr);
    void     (*write8)(void *ctx, uint32_t addr, uint8_t val);
    void     (*write16)(void *ctx, uint32_t addr, uint16_t val);
    void     (*write32)(void *ctx, uint32_t addr, uint32_t val);
    void     (*reset_peripherals)(void *ctx);
    int      (*int_ack)(void *ctx, uint8_t level);
} m68k_bus_t;

/* ==========================================================================
 * Motorola 68000 CPU State Structure
 * ========================================================================== */
typedef struct m68k_cpu {
    /* 8 x 32-bit Data Registers (D0 - D7) */
    union {
        uint32_t     d[8];
        m68k_reg32_t d_reg[8];
        struct {
            uint32_t d0, d1, d2, d3, d4, d5, d6, d7;
        };
    };

    /* 8 x 32-bit Address Registers (A0 - A7, where A7 is the active SP) */
    union {
        uint32_t     a[8];
        m68k_reg32_t a_reg[8];
        struct {
            uint32_t a0, a1, a2, a3, a4, a5, a6, a7;
        };
    };

    /* Dual Stack Pointers (A7 swaps between USP and SSP based on SR.S bit) */
    uint32_t usp;           /* User Stack Pointer (active in A7 when S == 0)       */
    uint32_t ssp;           /* Supervisor Stack Pointer (active in A7 when S == 1) */

    /* Program Counter & Instruction Pipeline State */
    uint32_t pc;            /* 32-bit Program Counter (masked to 24-bit on bus)    */
    uint32_t ppc;           /* Previous PC (address of currently executing opcode) */
    uint16_t ir;            /* Instruction Register (current 16-bit opcode word)   */

    /* 16-bit Status Register (System Byte [15:8] | CCR [4:0]) */
    uint16_t sr;

    /* Execution & Exception Control Flags */
    bool     stopped;       /* True when waiting in STOP #imm state                */
    bool     halted;        /* True when halted due to double bus/address fault    */
    bool     trace_armed;   /* True if SR.T was set at start of current instruction*/
    uint8_t  int_level;     /* Pending external IRQ priority level (0..7)          */
    uint32_t last_vector;   /* Last serviced exception vector number               */

    /* Cycle Timing */
    uint64_t total_cycles;  /* Cumulative M68K clock cycles executed since reset   */
    uint32_t step_cycles;   /* Cycles consumed during the active instruction/trap  */

    /* Memory Bus Interface */
    m68k_bus_t bus;
} m68k_cpu_t;

#ifdef _MSC_VER
#pragma warning(pop)
#endif

/* ==========================================================================
 * Inline Status Register (SR), CCR & Condition Code Helpers
 * ========================================================================== */

/* Check if one or more Status Register / CCR flag bits are set */
static inline bool m68k_get_flag(const m68k_cpu_t *cpu, uint16_t mask) {
    return (cpu->sr & mask) != 0u;
}

/* Set specified Status Register / CCR flag bit(s) */
static inline void m68k_set_flag(m68k_cpu_t *cpu, uint16_t mask) {
    cpu->sr |= (uint16_t)(mask & M68K_SR_VALID_MASK);
}

/* Clear specified Status Register / CCR flag bit(s) */
static inline void m68k_clear_flag(m68k_cpu_t *cpu, uint16_t mask) {
    cpu->sr &= (uint16_t)~mask;
}

/* Conditionally set or clear a Status Register / CCR flag bit */
static inline void m68k_assign_flag(m68k_cpu_t *cpu, uint16_t mask, bool cond) {
    if (cond) {
        cpu->sr |= (uint16_t)(mask & M68K_SR_VALID_MASK);
    } else {
        cpu->sr &= (uint16_t)~mask;
    }
}

/* Return the 8-bit Condition Code Register (user byte of SR) */
static inline uint8_t m68k_get_ccr(const m68k_cpu_t *cpu) {
    return (uint8_t)(cpu->sr & M68K_CCR_MASK);
}

/* Update only the 5 CCR flags (X, N, Z, V, C), preserving the System Byte */
static inline void m68k_set_ccr(m68k_cpu_t *cpu, uint8_t ccr) {
    cpu->sr = (uint16_t)((cpu->sr & M68K_SR_SYS_MASK) | (ccr & M68K_CCR_MASK));
}

/* Return true if the CPU is currently in Supervisor mode (SR bit 13 == 1) */
static inline bool m68k_is_supervisor(const m68k_cpu_t *cpu) {
    return (cpu->sr & M68K_SR_S) != 0u;
}

/* Return the current 3-bit Interrupt Priority Mask (0..7) from SR bits 10..8 */
static inline uint8_t m68k_get_ipl(const m68k_cpu_t *cpu) {
    return (uint8_t)((cpu->sr & M68K_SR_I_MASK) >> M68K_SR_I_SHIFT);
}

/* Evaluate a 4-bit M68K condition code (`m68k_cond_t`, 0x0..0xF) against current CCR */
static inline bool m68k_eval_cond(const m68k_cpu_t *cpu, uint8_t cond) {
    const bool c = (cpu->sr & M68K_SR_C) != 0u;
    const bool v = (cpu->sr & M68K_SR_V) != 0u;
    const bool z = (cpu->sr & M68K_SR_Z) != 0u;
    const bool n = (cpu->sr & M68K_SR_N) != 0u;

    switch (cond & 0x0Fu) {
        case M68K_COND_T:  return true;
        case M68K_COND_F:  return false;
        case M68K_COND_HI: return !c && !z;
        case M68K_COND_LS: return c || z;
        case M68K_COND_CC: return !c;
        case M68K_COND_CS: return c;
        case M68K_COND_NE: return !z;
        case M68K_COND_EQ: return z;
        case M68K_COND_VC: return !v;
        case M68K_COND_VS: return v;
        case M68K_COND_PL: return !n;
        case M68K_COND_MI: return n;
        case M68K_COND_GE: return n == v;
        case M68K_COND_LT: return n != v;
        case M68K_COND_GT: return !z && (n == v);
        case M68K_COND_LE: return z || (n != v);
        default:           return false;
    }
}

/* ==========================================================================
 * Core Lifecycle, Interrupt & Execution API Prototypes
 * ========================================================================== */

/**
 * Initialize a Motorola 68000 CPU instance and attach the memory bus callbacks.
 */
void m68k_init(m68k_cpu_t *cpu, const m68k_bus_t *bus);

/**
 * Perform a hardware power-on / reset of the Motorola 68000 CPU:
 * - Enters Supervisor mode (S = 1, T = 0, Interrupt Mask = 7 -> SR = 0x2700)
 * - Fetches initial SSP (A7) from Big-Endian address 0x000000
 * - Fetches initial PC from Big-Endian address 0x000004
 * - Clears stopped and halted states
 */
void m68k_reset(m68k_cpu_t *cpu);

/**
 * Update the full 16-bit Status Register (`SR`), masking unimplemented bits
 * and automatically banking `A7` between `SSP` and `USP` if the Supervisor (`S`)
 * bit changes.
 */
void m68k_set_sr(m68k_cpu_t *cpu, uint16_t new_sr);

/**
 * Synchronize the active `A7` register into `SSP` or `USP` (and vice versa)
 * when switching between Supervisor and User modes.
 */
void m68k_set_supervisor(m68k_cpu_t *cpu, bool supervisor);

/**
 * Set the pending external interrupt priority level (0 = none, 1..6 = maskable
 * autovector levels, 7 = non-maskable level 7).
 */
void m68k_set_irq(m68k_cpu_t *cpu, uint8_t level);

/**
 * Raise a synchronous or asynchronous M68K exception by vector number (0..255):
 * switches to Supervisor mode, pushes PC and SR onto SSP, and loads the target
 * handler address from `(uint32_t)vector * 4`.
 */
uint32_t m68k_raise_exception(m68k_cpu_t *cpu, uint8_t vector);

/**
 * Execute a single Motorola 68000 instruction (or service a pending interrupt /
 * trace exception) and return the number of M68K clock cycles consumed.
 */
int m68k_step(m68k_cpu_t *cpu);

/**
 * Execute M68K instructions until at least `target_cycles` clock cycles have
 * elapsed. Returns the actual number of clock cycles executed.
 */
int m68k_run(m68k_cpu_t *cpu, int target_cycles);

#ifdef __cplusplus
}
#endif

#endif /* YD_CORE_M68K_H */
