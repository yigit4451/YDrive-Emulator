#include "m68k.h"
#include <string.h>

/* ==========================================================================
 * Internal Operand Size & Sign-Extension Helpers
 * ========================================================================== */

static inline uint32_t m68k_size_mask(m68k_size_t size) {
    switch (size) {
        case M68K_SIZE_BYTE: return 0x000000FFu;
        case M68K_SIZE_WORD: return 0x0000FFFFu;
        case M68K_SIZE_LONG: return 0xFFFFFFFFu;
        default:             return 0xFFFFFFFFu;
    }
}

static inline uint32_t m68k_size_msb(m68k_size_t size) {
    switch (size) {
        case M68K_SIZE_BYTE: return 0x00000080u;
        case M68K_SIZE_WORD: return 0x00008000u;
        case M68K_SIZE_LONG: return 0x80000000u;
        default:             return 0x80000000u;
    }
}

static inline uint32_t m68k_read_d_sized(const m68k_cpu_t *cpu, uint8_t reg, m68k_size_t size) {
    return cpu->d[reg & 7u] & m68k_size_mask(size);
}

static inline void m68k_write_d_sized(m68k_cpu_t *cpu, uint8_t reg, m68k_size_t size, uint32_t val) {
    uint32_t mask = m68k_size_mask(size);
    cpu->d[reg & 7u] = (cpu->d[reg & 7u] & ~mask) | (val & mask);
}

/* ==========================================================================
 * Bus Read / Write & Instruction Stream Fetch Helpers
 * ========================================================================== */

static inline uint8_t m68k_bus_read8(m68k_cpu_t *cpu, uint32_t addr) {
    cpu->step_cycles += 4u;
    if (cpu->bus.read8) {
        return cpu->bus.read8(cpu->bus.ctx, addr & M68K_ADDR_MASK);
    }
    return 0xFFu;
}

static inline uint16_t m68k_bus_read16(m68k_cpu_t *cpu, uint32_t addr) {
    cpu->step_cycles += 4u;
    if (cpu->bus.read16) {
        return cpu->bus.read16(cpu->bus.ctx, addr & M68K_ADDR_MASK);
    }
    if (cpu->bus.read8) {
        uint8_t hi = cpu->bus.read8(cpu->bus.ctx, addr & M68K_ADDR_MASK);
        uint8_t lo = cpu->bus.read8(cpu->bus.ctx, (addr + 1u) & M68K_ADDR_MASK);
        return (uint16_t)(((uint16_t)hi << 8) | lo);
    }
    return 0xFFFFu;
}

static inline uint32_t m68k_bus_read32(m68k_cpu_t *cpu, uint32_t addr) {
    if (cpu->bus.read32) {
        cpu->step_cycles += 8u;
        return cpu->bus.read32(cpu->bus.ctx, addr & M68K_ADDR_MASK);
    }
    uint16_t hi = m68k_bus_read16(cpu, addr);
    uint16_t lo = m68k_bus_read16(cpu, addr + 2u);
    return ((uint32_t)hi << 16) | (uint32_t)lo;
}

static inline void m68k_bus_write8(m68k_cpu_t *cpu, uint32_t addr, uint8_t val) {
    cpu->step_cycles += 4u;
    if (cpu->bus.write8) {
        cpu->bus.write8(cpu->bus.ctx, addr & M68K_ADDR_MASK, val);
    }
}

static inline void m68k_bus_write16(m68k_cpu_t *cpu, uint32_t addr, uint16_t val) {
    cpu->step_cycles += 4u;
    if (cpu->bus.write16) {
        cpu->bus.write16(cpu->bus.ctx, addr & M68K_ADDR_MASK, val);
        return;
    }
    if (cpu->bus.write8) {
        cpu->bus.write8(cpu->bus.ctx, addr & M68K_ADDR_MASK, (uint8_t)(val >> 8));
        cpu->bus.write8(cpu->bus.ctx, (addr + 1u) & M68K_ADDR_MASK, (uint8_t)(val & 0xFFu));
    }
}

static inline void m68k_bus_write32(m68k_cpu_t *cpu, uint32_t addr, uint32_t val) {
    if (cpu->bus.write32) {
        cpu->step_cycles += 8u;
        cpu->bus.write32(cpu->bus.ctx, addr & M68K_ADDR_MASK, val);
        return;
    }
    m68k_bus_write16(cpu, addr, (uint16_t)(val >> 16));
    m68k_bus_write16(cpu, addr + 2u, (uint16_t)(val & 0xFFFFu));
}

static uint32_t m68k_bus_read_sized(m68k_cpu_t *cpu, uint32_t addr, m68k_size_t size) {
    switch (size) {
        case M68K_SIZE_BYTE: return m68k_bus_read8(cpu, addr);
        case M68K_SIZE_WORD: return m68k_bus_read16(cpu, addr);
        case M68K_SIZE_LONG: return m68k_bus_read32(cpu, addr);
        default:             return 0u;
    }
}

static void m68k_bus_write_sized(m68k_cpu_t *cpu, uint32_t addr, m68k_size_t size, uint32_t val) {
    switch (size) {
        case M68K_SIZE_BYTE: m68k_bus_write8(cpu, addr, (uint8_t)(val & 0xFFu)); break;
        case M68K_SIZE_WORD: m68k_bus_write16(cpu, addr, (uint16_t)(val & 0xFFFFu)); break;
        case M68K_SIZE_LONG: m68k_bus_write32(cpu, addr, val); break;
        default: break;
    }
}

static inline uint16_t m68k_fetch16(m68k_cpu_t *cpu) {
    uint16_t w = m68k_bus_read16(cpu, cpu->pc);
    cpu->pc = (cpu->pc + 2u) & M68K_ADDR_MASK;
    return w;
}

static inline uint32_t m68k_fetch32(m68k_cpu_t *cpu) {
    uint16_t hi = m68k_fetch16(cpu);
    uint16_t lo = m68k_fetch16(cpu);
    return ((uint32_t)hi << 16) | (uint32_t)lo;
}

static inline void m68k_push16(m68k_cpu_t *cpu, uint16_t val) {
    cpu->a[7] -= 2u;
    m68k_bus_write16(cpu, cpu->a[7], val);
}

static inline void m68k_push32(m68k_cpu_t *cpu, uint32_t val) {
    cpu->a[7] -= 4u;
    m68k_bus_write32(cpu, cpu->a[7], val);
}

static inline uint16_t m68k_pop16(m68k_cpu_t *cpu) {
    uint16_t val = m68k_bus_read16(cpu, cpu->a[7]);
    cpu->a[7] += 2u;
    return val;
}

static inline uint32_t m68k_pop32(m68k_cpu_t *cpu) {
    uint32_t val = m68k_bus_read32(cpu, cpu->a[7]);
    cpu->a[7] += 4u;
    return val;
}

/* ==========================================================================
 * Effective Address (EA) Resolver
 * ========================================================================== */

typedef enum m68k_ea_kind {
    M68K_EA_DATA_REG,
    M68K_EA_ADDR_REG,
    M68K_EA_MEMORY,
    M68K_EA_IMMEDIATE
} m68k_ea_kind_t;

typedef struct m68k_ea {
    m68k_ea_kind_t kind;
    m68k_size_t    size;
    uint8_t        reg;
    uint32_t       addr;
    uint32_t       imm_val;
} m68k_ea_t;

static int32_t m68k_decode_index_ext(m68k_cpu_t *cpu, uint16_t ext) {
    uint8_t  idx_reg = (uint8_t)((ext >> 12) & 7u);
    bool     is_addr = (ext & 0x8000u) != 0u;
    bool     is_long = (ext & 0x0800u) != 0u;
    uint32_t raw_idx = is_addr ? cpu->a[idx_reg] : cpu->d[idx_reg];
    int32_t  idx_val = is_long ? (int32_t)raw_idx : (int32_t)(int16_t)(raw_idx & 0xFFFFu);
    int32_t  disp8   = (int32_t)(int8_t)(ext & 0xFFu);
    cpu->step_cycles += 2u;
    return idx_val + disp8;
}

/* Resolve an Effective Address descriptor once (handles -(An), (An)+, and A7 +2 byte rule) */
static m68k_ea_t m68k_resolve_ea(m68k_cpu_t *cpu, uint8_t mode, uint8_t reg, m68k_size_t size) {
    m68k_ea_t ea;
    memset(&ea, 0, sizeof(ea));
    ea.size = size;
    ea.reg  = reg & 7u;

    switch (mode & 7u) {
        case 0: /* Data Register Direct: Dn */
            ea.kind = M68K_EA_DATA_REG;
            break;

        case 1: /* Address Register Direct: An */
            ea.kind = M68K_EA_ADDR_REG;
            break;

        case 2: /* Address Register Indirect: (An) */
            ea.kind = M68K_EA_MEMORY;
            ea.addr = cpu->a[ea.reg];
            break;

        case 3: { /* Address Register Indirect with Post-increment: (An)+ */
            uint32_t step = (ea.reg == 7u && size == M68K_SIZE_BYTE) ? 2u : (uint32_t)size;
            ea.kind       = M68K_EA_MEMORY;
            ea.addr       = cpu->a[ea.reg];
            cpu->a[ea.reg] += step;
            break;
        }

        case 4: { /* Address Register Indirect with Pre-decrement: -(An) */
            uint32_t step = (ea.reg == 7u && size == M68K_SIZE_BYTE) ? 2u : (uint32_t)size;
            cpu->a[ea.reg] -= step;
            ea.kind       = M68K_EA_MEMORY;
            ea.addr       = cpu->a[ea.reg];
            cpu->step_cycles += 2u;
            break;
        }

        case 5: { /* Address Register Indirect with 16-bit Displacement: (d16, An) */
            int16_t d16 = (int16_t)m68k_fetch16(cpu);
            ea.kind     = M68K_EA_MEMORY;
            ea.addr     = cpu->a[ea.reg] + (uint32_t)(int32_t)d16;
            break;
        }

        case 6: { /* Address Register Indirect with Index: (d8, An, Xn) */
            uint16_t ext = m68k_fetch16(cpu);
            ea.kind      = M68K_EA_MEMORY;
            ea.addr      = cpu->a[ea.reg] + (uint32_t)m68k_decode_index_ext(cpu, ext);
            break;
        }

        case 7:
            switch (ea.reg) {
                case 0: { /* Absolute Short: (xxx).W */
                    int16_t addr16 = (int16_t)m68k_fetch16(cpu);
                    ea.kind        = M68K_EA_MEMORY;
                    ea.addr        = (uint32_t)(int32_t)addr16;
                    break;
                }
                case 1: /* Absolute Long: (xxx).L */
                    ea.kind = M68K_EA_MEMORY;
                    ea.addr = m68k_fetch32(cpu);
                    break;

                case 2: { /* PC Relative with 16-bit Displacement: (d16, PC) */
                    uint32_t base_pc = cpu->pc;
                    int16_t  d16     = (int16_t)m68k_fetch16(cpu);
                    ea.kind          = M68K_EA_MEMORY;
                    ea.addr          = base_pc + (uint32_t)(int32_t)d16;
                    break;
                }
                case 3: { /* PC Relative with Index: (d8, PC, Xn) */
                    uint32_t base_pc = cpu->pc;
                    uint16_t ext     = m68k_fetch16(cpu);
                    ea.kind          = M68K_EA_MEMORY;
                    ea.addr          = base_pc + (uint32_t)m68k_decode_index_ext(cpu, ext);
                    break;
                }
                case 4: /* Immediate: #<data> */
                    ea.kind = M68K_EA_IMMEDIATE;
                    if (size == M68K_SIZE_BYTE) {
                        ea.imm_val = m68k_fetch16(cpu) & 0xFFu;
                    } else if (size == M68K_SIZE_WORD) {
                        ea.imm_val = m68k_fetch16(cpu);
                    } else {
                        ea.imm_val = m68k_fetch32(cpu);
                    }
                    break;

                default:
                    ea.kind = M68K_EA_IMMEDIATE;
                    break;
            }
            break;
    }
    return ea;
}

static uint32_t m68k_read_ea(m68k_cpu_t *cpu, const m68k_ea_t *ea) {
    switch (ea->kind) {
        case M68K_EA_DATA_REG:  return m68k_read_d_sized(cpu, ea->reg, ea->size);
        case M68K_EA_ADDR_REG:  return cpu->a[ea->reg] & m68k_size_mask(ea->size);
        case M68K_EA_MEMORY:    return m68k_bus_read_sized(cpu, ea->addr, ea->size);
        case M68K_EA_IMMEDIATE: return ea->imm_val & m68k_size_mask(ea->size);
        default:                return 0u;
    }
}

static void m68k_write_ea(m68k_cpu_t *cpu, const m68k_ea_t *ea, uint32_t val) {
    switch (ea->kind) {
        case M68K_EA_DATA_REG:
            m68k_write_d_sized(cpu, ea->reg, ea->size, val);
            break;
        case M68K_EA_ADDR_REG:
            if (ea->size == M68K_SIZE_WORD) {
                cpu->a[ea->reg] = (uint32_t)(int32_t)(int16_t)(val & 0xFFFFu);
            } else {
                cpu->a[ea->reg] = val;
            }
            break;
        case M68K_EA_MEMORY:
            m68k_bus_write_sized(cpu, ea->addr, ea->size, val);
            break;
        case M68K_EA_IMMEDIATE:
            break;
    }
}

/* ==========================================================================
 * ALU & Condition Code Register (CCR) Flag Calculators
 * ========================================================================== */

/* Update N and Z, clear V and C, preserve X (used by MOVE, AND, OR, EOR, NOT, TST, EXT, SWAP) */
static inline void m68k_flags_logic(m68k_cpu_t *cpu, uint32_t res, m68k_size_t size) {
    uint32_t mask = m68k_size_mask(size);
    uint32_t msb  = m68k_size_msb(size);
    res &= mask;

    m68k_assign_flag(cpu, M68K_SR_N, (res & msb) != 0u);
    m68k_assign_flag(cpu, M68K_SR_Z, res == 0u);
    m68k_clear_flag(cpu, M68K_SR_V | M68K_SR_C);
}

static uint32_t m68k_alu_add(m68k_cpu_t *cpu, uint32_t dst, uint32_t src, m68k_size_t size, bool set_x) {
    uint32_t mask = m68k_size_mask(size);
    uint32_t msb  = m68k_size_msb(size);
    dst &= mask;
    src &= mask;
    uint32_t res = (dst + src) & mask;

    bool c = (((dst & src) | (~res & (dst | src))) & msb) != 0u;
    bool v = (((dst ^ res) & (src ^ res)) & msb) != 0u;

    m68k_assign_flag(cpu, M68K_SR_C, c);
    m68k_assign_flag(cpu, M68K_SR_V, v);
    m68k_assign_flag(cpu, M68K_SR_Z, res == 0u);
    m68k_assign_flag(cpu, M68K_SR_N, (res & msb) != 0u);
    if (set_x) {
        m68k_assign_flag(cpu, M68K_SR_X, c);
    }
    return res;
}

static uint32_t m68k_alu_sub(m68k_cpu_t *cpu, uint32_t dst, uint32_t src, m68k_size_t size, bool set_x) {
    uint32_t mask = m68k_size_mask(size);
    uint32_t msb  = m68k_size_msb(size);
    dst &= mask;
    src &= mask;
    uint32_t res = (dst - src) & mask;

    bool c = (((src & ~dst) | (res & (~dst | src))) & msb) != 0u;
    bool v = (((dst ^ src) & (dst ^ res)) & msb) != 0u;

    m68k_assign_flag(cpu, M68K_SR_C, c);
    m68k_assign_flag(cpu, M68K_SR_V, v);
    m68k_assign_flag(cpu, M68K_SR_Z, res == 0u);
    m68k_assign_flag(cpu, M68K_SR_N, (res & msb) != 0u);
    if (set_x) {
        m68k_assign_flag(cpu, M68K_SR_X, c);
    }
    return res;
}

static uint32_t m68k_alu_addx(m68k_cpu_t *cpu, uint32_t dst, uint32_t src, m68k_size_t size) {
    uint32_t mask = m68k_size_mask(size);
    uint32_t msb  = m68k_size_msb(size);
    uint64_t x_in = m68k_get_flag(cpu, M68K_SR_X) ? 1u : 0u;
    dst &= mask;
    src &= mask;

    uint32_t res = (uint32_t)((uint64_t)dst + (uint64_t)src + x_in) & mask;
    bool     c   = (((dst & src) | (~res & (dst | src))) & msb) != 0u;
    bool     v   = (((dst ^ res) & (src ^ res)) & msb) != 0u;

    m68k_assign_flag(cpu, M68K_SR_C | M68K_SR_X, c);
    m68k_assign_flag(cpu, M68K_SR_V, v);
    m68k_assign_flag(cpu, M68K_SR_N, (res & msb) != 0u);
    /* Multi-precision Z rule: cleared if non-zero, unchanged if zero */
    if (res != 0u) {
        m68k_clear_flag(cpu, M68K_SR_Z);
    }
    return res;
}

static uint32_t m68k_alu_subx(m68k_cpu_t *cpu, uint32_t dst, uint32_t src, m68k_size_t size) {
    uint32_t mask = m68k_size_mask(size);
    uint32_t msb  = m68k_size_msb(size);
    uint64_t x_in = m68k_get_flag(cpu, M68K_SR_X) ? 1u : 0u;
    dst &= mask;
    src &= mask;

    uint32_t res = (uint32_t)((uint64_t)dst - (uint64_t)src - x_in) & mask;
    bool     c   = (((src & ~dst) | (res & (~dst | src))) & msb) != 0u;
    bool     v   = (((dst ^ src) & (dst ^ res)) & msb) != 0u;

    m68k_assign_flag(cpu, M68K_SR_C | M68K_SR_X, c);
    m68k_assign_flag(cpu, M68K_SR_V, v);
    m68k_assign_flag(cpu, M68K_SR_N, (res & msb) != 0u);
    if (res != 0u) {
        m68k_clear_flag(cpu, M68K_SR_Z);
    }
    return res;
}

/* ==========================================================================
 * Core Lifecycle, Supervisor/USP/SSP Banking & Exception Processing
 * ========================================================================== */

void m68k_init(m68k_cpu_t *cpu, const m68k_bus_t *bus) {
    if (!cpu) {
        return;
    }
    memset(cpu, 0, sizeof(*cpu));
    if (bus) {
        cpu->bus = *bus;
    }
    cpu->sr = (uint16_t)(M68K_SR_S | M68K_SR_I_MASK); /* 0x2700 */
}

void m68k_set_supervisor(m68k_cpu_t *cpu, bool supervisor) {
    bool was_super = m68k_is_supervisor(cpu);
    if (was_super == supervisor) {
        /* Keep shadow SP synced with active A7 */
        if (was_super) {
            cpu->ssp = cpu->a[7];
        } else {
            cpu->usp = cpu->a[7];
        }
        return;
    }

    if (supervisor) {
        /* User -> Supervisor: save A7 into USP, load SSP into A7 */
        cpu->usp   = cpu->a[7];
        cpu->sr   |= M68K_SR_S;
        cpu->a[7]  = cpu->ssp;
    } else {
        /* Supervisor -> User: save A7 into SSP, load USP into A7 */
        cpu->ssp   = cpu->a[7];
        cpu->sr   &= (uint16_t)~M68K_SR_S;
        cpu->a[7]  = cpu->usp;
    }
}

void m68k_set_sr(m68k_cpu_t *cpu, uint16_t new_sr) {
    new_sr &= M68K_SR_VALID_MASK;
    bool new_super = (new_sr & M68K_SR_S) != 0u;
    m68k_set_supervisor(cpu, new_super);
    cpu->sr = new_sr;
}

void m68k_reset(m68k_cpu_t *cpu) {
    if (!cpu) {
        return;
    }
    for (int i = 0; i < 8; i++) {
        cpu->d[i] = 0u;
        cpu->a[i] = 0u;
    }
    cpu->usp          = 0u;
    cpu->ssp          = 0u;
    cpu->sr           = (uint16_t)(M68K_SR_S | M68K_SR_I_MASK); /* 0x2700 */
    cpu->stopped      = false;
    cpu->halted       = false;
    cpu->trace_armed  = false;
    cpu->int_level    = 0u;
    cpu->last_vector  = 0u;
    cpu->total_cycles = 0u;
    cpu->step_cycles  = 0u;

    /* Fetch initial SSP from 0x000000 and initial PC from 0x000004 */
    cpu->ssp  = m68k_bus_read32(cpu, 0x000000u);
    cpu->a[7] = cpu->ssp;
    cpu->pc   = m68k_bus_read32(cpu, 0x000004u) & M68K_ADDR_MASK;
    cpu->ppc  = cpu->pc;
    cpu->step_cycles = 0u;
}

void m68k_set_irq(m68k_cpu_t *cpu, uint8_t level) {
    if (!cpu) {
        return;
    }
    cpu->int_level = (uint8_t)(level & 7u);
}

uint32_t m68k_raise_exception(m68k_cpu_t *cpu, uint8_t vector) {
    uint16_t old_sr = cpu->sr;

    /* Switch to Supervisor mode and clear Trace bit */
    m68k_set_supervisor(cpu, true);
    cpu->sr &= (uint16_t)~M68K_SR_T;

    /* Push 32-bit PC and 16-bit old SR onto Supervisor Stack (SSP / A7) */
    m68k_push32(cpu, cpu->pc);
    m68k_push16(cpu, old_sr);

    /* Address Error (3) and Bus Error (2) push an additional 4-word Group 0 frame */
    if (vector == M68K_VEC_BUS_ERROR || vector == M68K_VEC_ADDRESS_ERROR) {
        m68k_push16(cpu, cpu->ir);
        m68k_push32(cpu, cpu->ppc);
        m68k_push16(cpu, 0x0000u);
    }

    uint32_t vec_addr = (uint32_t)vector * 4u;
    uint32_t target   = m68k_bus_read32(cpu, vec_addr);
    cpu->pc           = target & M68K_ADDR_MASK;
    cpu->ssp          = cpu->a[7];
    cpu->stopped      = false;
    cpu->trace_armed  = false;
    cpu->last_vector  = vector;

    cpu->step_cycles += 26u;
    return 34u;
}

static bool m68k_check_interrupts(m68k_cpu_t *cpu) {
    uint8_t level = cpu->int_level;
    if (level == 0u) {
        return false;
    }

    uint8_t mask = m68k_get_ipl(cpu);
    /* Level 7 is non-maskable; levels 1..6 trigger when level > current mask */
    if (level < 7u && level <= mask) {
        return false;
    }

    uint8_t vector = (uint8_t)(M68K_VEC_SPURIOUS_INT + level); /* Autovector 24 + level */
    if (cpu->bus.int_ack) {
        int ack = cpu->bus.int_ack(cpu->bus.ctx, level);
        if (ack >= 0 && ack <= 255) {
            vector = (uint8_t)ack;
        } else if (ack == M68K_INT_ACK_SPURIOUS) {
            vector = M68K_VEC_SPURIOUS_INT;
        }
    }

    /* Acknowledge clears pending request level and raises IPL to `level` */
    cpu->int_level = 0u;
    uint16_t old_sr = cpu->sr;
    m68k_set_supervisor(cpu, true);
    cpu->sr = (uint16_t)((cpu->sr & ~(M68K_SR_T | M68K_SR_I_MASK)) |
                         ((uint16_t)level << M68K_SR_I_SHIFT));

    m68k_push32(cpu, cpu->pc);
    m68k_push16(cpu, old_sr);

    uint32_t target  = m68k_bus_read32(cpu, (uint32_t)vector * 4u);
    cpu->pc          = target & M68K_ADDR_MASK;
    cpu->ssp         = cpu->a[7];
    cpu->stopped     = false;
    cpu->trace_armed = false;
    cpu->last_vector = vector;

    cpu->step_cycles += 32u; /* Total 44 cycles with stack push + vector read */
    return true;
}

/* ==========================================================================
 * Opcode Group Handlers (Lines 0x0 .. 0xF)
 * ========================================================================== */

static m68k_size_t m68k_decode_size_bits(uint8_t bits) {
    switch (bits & 3u) {
        case 0:  return M68K_SIZE_BYTE;
        case 1:  return M68K_SIZE_WORD;
        default: return M68K_SIZE_LONG;
    }
}

/* Line 0x0: Bit Operations, MOVEP, and Immediate ALU Operations */
static void m68k_exec_line0(m68k_cpu_t *cpu, uint16_t op) {
    uint8_t mode = (uint8_t)((op >> 3) & 7u);
    uint8_t reg  = (uint8_t)(op & 7u);

    /* Check for MOVEP (0000 ddd1 mm00 1aaa) */
    if ((op & 0x0138u) == 0x0108u) {
        uint8_t  dreg    = (uint8_t)((op >> 9) & 7u);
        uint8_t  areg    = reg;
        bool     to_mem  = (op & 0x0080u) != 0u;
        bool     is_long = (op & 0x0040u) != 0u;
        int16_t  disp    = (int16_t)m68k_fetch16(cpu);
        uint32_t addr    = cpu->a[areg] + (uint32_t)(int32_t)disp;

        if (to_mem) {
            uint32_t val = cpu->d[dreg];
            if (is_long) {
                m68k_bus_write8(cpu, addr + 0u, (uint8_t)(val >> 24));
                m68k_bus_write8(cpu, addr + 2u, (uint8_t)(val >> 16));
                m68k_bus_write8(cpu, addr + 4u, (uint8_t)(val >> 8));
                m68k_bus_write8(cpu, addr + 6u, (uint8_t)val);
            } else {
                m68k_bus_write8(cpu, addr + 0u, (uint8_t)(val >> 8));
                m68k_bus_write8(cpu, addr + 2u, (uint8_t)val);
            }
        } else {
            if (is_long) {
                uint32_t b3 = m68k_bus_read8(cpu, addr + 0u);
                uint32_t b2 = m68k_bus_read8(cpu, addr + 2u);
                uint32_t b1 = m68k_bus_read8(cpu, addr + 4u);
                uint32_t b0 = m68k_bus_read8(cpu, addr + 6u);
                cpu->d[dreg] = (b3 << 24) | (b2 << 16) | (b1 << 8) | b0;
            } else {
                uint16_t b1 = m68k_bus_read8(cpu, addr + 0u);
                uint16_t b0 = m68k_bus_read8(cpu, addr + 2u);
                m68k_write_d_sized(cpu, dreg, M68K_SIZE_WORD, (uint32_t)((b1 << 8) | b0));
            }
        }
        return;
    }

    /* Dynamic or Static Bit Operations: BTST (0), BCHG (1), BCLR (2), BSET (3) */
    if ((op & 0x0100u) != 0u || ((op >> 9) & 7u) == 4u) {
        uint32_t bit_num;
        if ((op & 0x0100u) != 0u) {
            uint8_t dreg = (uint8_t)((op >> 9) & 7u);
            bit_num = cpu->d[dreg];
        } else {
            bit_num = m68k_fetch16(cpu) & 0xFFu;
        }

        uint8_t     bit_op = (uint8_t)((op >> 6) & 3u);
        m68k_size_t bsize  = (mode == 0u) ? M68K_SIZE_LONG : M68K_SIZE_BYTE;
        uint32_t    modulo = (mode == 0u) ? 31u : 7u;
        uint32_t    mask   = 1u << (bit_num & modulo);

        m68k_ea_t ea  = m68k_resolve_ea(cpu, mode, reg, bsize);
        uint32_t  val = m68k_read_ea(cpu, &ea);
        m68k_assign_flag(cpu, M68K_SR_Z, (val & mask) == 0u);

        switch (bit_op) {
            case 0: /* BTST */
                break;
            case 1: /* BCHG */
                m68k_write_ea(cpu, &ea, val ^ mask);
                cpu->step_cycles += 4u;
                break;
            case 2: /* BCLR */
                m68k_write_ea(cpu, &ea, val & ~mask);
                cpu->step_cycles += 4u;
                break;
            case 3: /* BSET */
                m68k_write_ea(cpu, &ea, val | mask);
                cpu->step_cycles += 4u;
                break;
        }
        return;
    }

    /* Immediate Operations to CCR or SR */
    if (op == 0x003Cu || op == 0x023Cu || op == 0x0A3Cu) {
        uint8_t imm = (uint8_t)(m68k_fetch16(cpu) & 0xFFu);
        uint8_t ccr = m68k_get_ccr(cpu);
        if (op == 0x003Cu)      ccr |= imm;
        else if (op == 0x023Cu) ccr &= imm;
        else                    ccr ^= imm;
        m68k_set_ccr(cpu, ccr);
        cpu->step_cycles += 12u;
        return;
    }
    if (op == 0x007Cu || op == 0x027Cu || op == 0x0A7Cu) {
        if (!m68k_is_supervisor(cpu)) {
            cpu->pc = cpu->ppc;
            m68k_raise_exception(cpu, M68K_VEC_PRIVILEGE_VIOL);
            return;
        }
        uint16_t imm = m68k_fetch16(cpu);
        uint16_t sr  = cpu->sr;
        if (op == 0x007Cu)      sr |= imm;
        else if (op == 0x027Cu) sr &= imm;
        else                    sr ^= imm;
        m68k_set_sr(cpu, sr);
        cpu->step_cycles += 12u;
        return;
    }

    /* Immediate ALU: ORI (0), ANDI (1), SUBI (2), ADDI (3), EORI (5), CMPI (6) */
    uint8_t     alu_op = (uint8_t)((op >> 9) & 7u);
    m68k_size_t size   = m68k_decode_size_bits((uint8_t)((op >> 6) & 3u));
    uint32_t    imm    = (size == M68K_SIZE_LONG) ? m68k_fetch32(cpu)
                                                  : (m68k_fetch16(cpu) & m68k_size_mask(size));

    m68k_ea_t ea  = m68k_resolve_ea(cpu, mode, reg, size);
    uint32_t  dst = m68k_read_ea(cpu, &ea);
    uint32_t  res = dst;

    switch (alu_op) {
        case 0: /* ORI */
            res = (dst | imm) & m68k_size_mask(size);
            m68k_flags_logic(cpu, res, size);
            m68k_write_ea(cpu, &ea, res);
            break;
        case 1: /* ANDI */
            res = (dst & imm) & m68k_size_mask(size);
            m68k_flags_logic(cpu, res, size);
            m68k_write_ea(cpu, &ea, res);
            break;
        case 2: /* SUBI */
            res = m68k_alu_sub(cpu, dst, imm, size, true);
            m68k_write_ea(cpu, &ea, res);
            break;
        case 3: /* ADDI */
            res = m68k_alu_add(cpu, dst, imm, size, true);
            m68k_write_ea(cpu, &ea, res);
            break;
        case 5: /* EORI */
            res = (dst ^ imm) & m68k_size_mask(size);
            m68k_flags_logic(cpu, res, size);
            m68k_write_ea(cpu, &ea, res);
            break;
        case 6: /* CMPI */
            (void)m68k_alu_sub(cpu, dst, imm, size, false);
            break;
        default:
            cpu->pc = cpu->ppc;
            m68k_raise_exception(cpu, M68K_VEC_ILLEGAL_INST);
            break;
    }
}

/* Lines 0x1 (.B), 0x2 (.L), 0x3 (.W): MOVE and MOVEA */
static void m68k_exec_move(m68k_cpu_t *cpu, uint16_t op, m68k_size_t size) {
    uint8_t src_mode = (uint8_t)((op >> 3) & 7u);
    uint8_t src_reg  = (uint8_t)(op & 7u);
    uint8_t dst_mode = (uint8_t)((op >> 6) & 7u);
    uint8_t dst_reg  = (uint8_t)((op >> 9) & 7u);

    m68k_ea_t src_ea = m68k_resolve_ea(cpu, src_mode, src_reg, size);
    uint32_t  val    = m68k_read_ea(cpu, &src_ea);

    /* MOVEA: Destination mode == 1 (Address Register Direct) does not affect CCR flags */
    if (dst_mode == 1u) {
        if (size == M68K_SIZE_WORD) {
            cpu->a[dst_reg] = (uint32_t)(int32_t)(int16_t)(val & 0xFFFFu);
        } else {
            cpu->a[dst_reg] = val;
        }
        return;
    }

    m68k_ea_t dst_ea = m68k_resolve_ea(cpu, dst_mode, dst_reg, size);
    m68k_flags_logic(cpu, val, size);
    m68k_write_ea(cpu, &dst_ea, val);
}

/* Line 0x4: Miscellaneous (LEA, PEA, MOVEM,CLR/NEG/NOT/TST, EXT, SWAP, JSR/JMP/RTS/RTE, TRAP) */
static void m68k_exec_line4(m68k_cpu_t *cpu, uint16_t op) {
    uint8_t mode = (uint8_t)((op >> 3) & 7u);
    uint8_t reg  = (uint8_t)(op & 7u);

    /* Fixed Opcodes in 0x4E70..0x4E77 & ILLEGAL */
    if (op == 0x4AFCu) {
        cpu->pc = cpu->ppc;
        m68k_raise_exception(cpu, M68K_VEC_ILLEGAL_INST);
        return;
    }
    if (op == 0x4E70u) { /* RESET */
        if (!m68k_is_supervisor(cpu)) {
            cpu->pc = cpu->ppc;
            m68k_raise_exception(cpu, M68K_VEC_PRIVILEGE_VIOL);
            return;
        }
        if (cpu->bus.reset_peripherals) {
            cpu->bus.reset_peripherals(cpu->bus.ctx);
        }
        cpu->step_cycles += 128u;
        return;
    }
    if (op == 0x4E71u) { /* NOP */
        return;
    }
    if (op == 0x4E72u) { /* STOP #imm */
        if (!m68k_is_supervisor(cpu)) {
            cpu->pc = cpu->ppc;
            m68k_raise_exception(cpu, M68K_VEC_PRIVILEGE_VIOL);
            return;
        }
        uint16_t imm = m68k_fetch16(cpu);
        m68k_set_sr(cpu, imm);
        cpu->stopped = true;
        return;
    }
    if (op == 0x4E73u) { /* RTE */
        if (!m68k_is_supervisor(cpu)) {
            cpu->pc = cpu->ppc;
            m68k_raise_exception(cpu, M68K_VEC_PRIVILEGE_VIOL);
            return;
        }
        uint16_t new_sr = m68k_pop16(cpu);
        uint32_t new_pc = m68k_pop32(cpu);
        cpu->pc         = new_pc & M68K_ADDR_MASK;
        m68k_set_sr(cpu, new_sr);
        cpu->step_cycles += 8u;
        return;
    }
    if (op == 0x4E75u) { /* RTS */
        cpu->pc = m68k_pop32(cpu) & M68K_ADDR_MASK;
        cpu->step_cycles += 4u;
        return;
    }
    if (op == 0x4E76u) { /* TRAPV */
        if (m68k_get_flag(cpu, M68K_SR_V)) {
            m68k_raise_exception(cpu, M68K_VEC_TRAPV);
        }
        return;
    }
    if (op == 0x4E77u) { /* RTR */
        uint16_t ccr    = m68k_pop16(cpu);
        uint32_t new_pc = m68k_pop32(cpu);
        m68k_set_ccr(cpu, (uint8_t)(ccr & 0xFFu));
        cpu->pc = new_pc & M68K_ADDR_MASK;
        cpu->step_cycles += 4u;
        return;
    }

    /* TRAP #0..#15 (0100 1110 0100 vvvv) */
    if ((op & 0xFFF0u) == 0x4E40u) {
        uint8_t vec = (uint8_t)(M68K_VEC_TRAP_BASE + (op & 0x0Fu));
        m68k_raise_exception(cpu, vec);
        return;
    }

    /* LINK An, #<d16> (0100 1110 0101 0aaa) */
    if ((op & 0xFFF8u) == 0x4E50u) {
        int16_t disp = (int16_t)m68k_fetch16(cpu);
        m68k_push32(cpu, cpu->a[reg]);
        cpu->a[reg] = cpu->a[7];
        cpu->a[7]   = cpu->a[7] + (uint32_t)(int32_t)disp;
        return;
    }

    /* UNLK An (0100 1110 0101 1aaa) */
    if ((op & 0xFFF8u) == 0x4E58u) {
        cpu->a[7]   = cpu->a[reg];
        cpu->a[reg] = m68k_pop32(cpu);
        return;
    }

    /* MOVE USP (0100 1110 0110 daaa) */
    if ((op & 0xFFF0u) == 0x4E60u) {
        if (!m68k_is_supervisor(cpu)) {
            cpu->pc = cpu->ppc;
            m68k_raise_exception(cpu, M68K_VEC_PRIVILEGE_VIOL);
            return;
        }
        if ((op & 0x0008u) != 0u) {
            cpu->a[reg] = cpu->usp;
        } else {
            cpu->usp = cpu->a[reg];
        }
        return;
    }

    /* JSR <ea> (0100 1110 10mm mrrr) & JMP <ea> (0100 1110 11mm mrrr) */
    if ((op & 0xFFC0u) == 0x4E80u) {
        m68k_ea_t ea = m68k_resolve_ea(cpu, mode, reg, M68K_SIZE_LONG);
        m68k_push32(cpu, cpu->pc);
        cpu->pc = ea.addr & M68K_ADDR_MASK;
        cpu->step_cycles += 6u;
        return;
    }
    if ((op & 0xFFC0u) == 0x4EC0u) {
        m68k_ea_t ea = m68k_resolve_ea(cpu, mode, reg, M68K_SIZE_LONG);
        cpu->pc = ea.addr & M68K_ADDR_MASK;
        cpu->step_cycles += 4u;
        return;
    }

    /* LEA <ea>, An (0100 aaa1 11mm mrrr) */
    if ((op & 0xF1C0u) == 0x41C0u) {
        uint8_t   areg = (uint8_t)((op >> 9) & 7u);
        m68k_ea_t ea   = m68k_resolve_ea(cpu, mode, reg, M68K_SIZE_LONG);
        cpu->a[areg]   = ea.addr;
        return;
    }

    /* CHK.W <ea>, Dn (0100 ddd1 10mm mrrr) */
    if ((op & 0xF1C0u) == 0x4180u) {
        uint8_t   dreg  = (uint8_t)((op >> 9) & 7u);
        m68k_ea_t ea    = m68k_resolve_ea(cpu, mode, reg, M68K_SIZE_WORD);
        int16_t   bound = (int16_t)m68k_read_ea(cpu, &ea);
        int16_t   val   = (int16_t)(cpu->d[dreg] & 0xFFFFu);
        m68k_clear_flag(cpu, M68K_SR_Z | M68K_SR_V | M68K_SR_C);
        if (val < 0) {
            m68k_set_flag(cpu, M68K_SR_N);
            m68k_raise_exception(cpu, M68K_VEC_CHK);
        } else if (val > bound) {
            m68k_clear_flag(cpu, M68K_SR_N);
            m68k_raise_exception(cpu, M68K_VEC_CHK);
        }
        return;
    }

    /* SWAP Dn (0100 1000 0100 0ddd) */
    if ((op & 0xFFF8u) == 0x4840u) {
        uint32_t v   = cpu->d[reg];
        uint32_t res = (v >> 16) | (v << 16);
        cpu->d[reg]  = res;
        m68k_flags_logic(cpu, res, M68K_SIZE_LONG);
        return;
    }

    /* PEA <ea> (0100 1000 01mm mrrr, mode != 0) */
    if ((op & 0xFFC0u) == 0x4840u && mode != 0u) {
        m68k_ea_t ea = m68k_resolve_ea(cpu, mode, reg, M68K_SIZE_LONG);
        m68k_push32(cpu, ea.addr);
        return;
    }

    /* EXT.W Dn (0100 1000 1000 0ddd) & EXT.L Dn (0100 1000 1100 0ddd) */
    if ((op & 0xFFF8u) == 0x4880u) {
        uint16_t res = (uint16_t)(int16_t)(int8_t)(cpu->d[reg] & 0xFFu);
        m68k_write_d_sized(cpu, reg, M68K_SIZE_WORD, res);
        m68k_flags_logic(cpu, res, M68K_SIZE_WORD);
        return;
    }
    if ((op & 0xFFF8u) == 0x48C0u) {
        uint32_t res = (uint32_t)(int32_t)(int16_t)(cpu->d[reg] & 0xFFFFu);
        cpu->d[reg]  = res;
        m68k_flags_logic(cpu, res, M68K_SIZE_LONG);
        return;
    }

    /* MOVEM (0100 1d00 1smm mrrr, where mode >= 2) */
    if ((op & 0xFB80u) == 0x4880u && mode >= 2u) {
        bool        to_reg = (op & 0x0400u) != 0u;
        m68k_size_t msize  = ((op & 0x0040u) != 0u) ? M68K_SIZE_LONG : M68K_SIZE_WORD;
        uint32_t    step   = (uint32_t)msize;
        uint16_t    mask   = m68k_fetch16(cpu);

        if (!to_reg && mode == 4u) {
            /* Pre-decrement -(An): bit 0 = A7 .. bit 7 = A0, bit 8 = D7 .. bit 15 = D0 */
            uint32_t addr = cpu->a[reg];
            for (int i = 0; i < 16; i++) {
                if ((mask & (1u << i)) != 0u) {
                    addr -= step;
                    int      r_idx = 15 - i;
                    uint32_t val   = (r_idx < 8) ? cpu->d[r_idx] : cpu->a[r_idx - 8];
                    m68k_bus_write_sized(cpu, addr, msize, val);
                }
            }
            cpu->a[reg] = addr;
        } else {
            uint32_t addr;
            if (mode == 2u || mode == 3u) {
                addr = cpu->a[reg];
            } else {
                m68k_ea_t ea = m68k_resolve_ea(cpu, mode, reg, msize);
                addr = ea.addr;
            }
            for (int i = 0; i < 16; i++) {
                if ((mask & (1u << i)) != 0u) {
                    if (to_reg) {
                        uint32_t val = m68k_bus_read_sized(cpu, addr, msize);
                        if (msize == M68K_SIZE_WORD) {
                            val = (uint32_t)(int32_t)(int16_t)(val & 0xFFFFu);
                        }
                        if (i < 8) {
                            cpu->d[i] = val;
                        } else {
                            cpu->a[i - 8] = val;
                        }
                    } else {
                        uint32_t val = (i < 8) ? cpu->d[i] : cpu->a[i - 8];
                        m68k_bus_write_sized(cpu, addr, msize, val);
                    }
                    addr += step;
                }
            }
            if (mode == 3u) {
                cpu->a[reg] = addr;
            }
        }
        return;
    }

    /* MOVE from SR (0100 0000 11mm mrrr) */
    if ((op & 0xFFC0u) == 0x40C0u) {
        m68k_ea_t ea = m68k_resolve_ea(cpu, mode, reg, M68K_SIZE_WORD);
        m68k_write_ea(cpu, &ea, cpu->sr);
        return;
    }
    /* MOVE to CCR (0100 0100 11mm mrrr) */
    if ((op & 0xFFC0u) == 0x44C0u) {
        m68k_ea_t ea  = m68k_resolve_ea(cpu, mode, reg, M68K_SIZE_WORD);
        uint16_t  val = (uint16_t)m68k_read_ea(cpu, &ea);
        m68k_set_ccr(cpu, (uint8_t)(val & 0xFFu));
        cpu->step_cycles += 8u;
        return;
    }
    /* MOVE to SR (0100 0110 11mm mrrr) */
    if ((op & 0xFFC0u) == 0x46C0u) {
        if (!m68k_is_supervisor(cpu)) {
            cpu->pc = cpu->ppc;
            m68k_raise_exception(cpu, M68K_VEC_PRIVILEGE_VIOL);
            return;
        }
        m68k_ea_t ea  = m68k_resolve_ea(cpu, mode, reg, M68K_SIZE_WORD);
        uint16_t  val = (uint16_t)m68k_read_ea(cpu, &ea);
        m68k_set_sr(cpu, val);
        cpu->step_cycles += 8u;
        return;
    }

    /* NBCD <ea> (0100 1000 00mm mrrr) */
    if ((op & 0xFFC0u) == 0x4800u) {
        m68k_ea_t ea  = m68k_resolve_ea(cpu, mode, reg, M68K_SIZE_BYTE);
        uint8_t   val = (uint8_t)m68k_read_ea(cpu, &ea);
        uint8_t   x   = m68k_get_flag(cpu, M68K_SR_X) ? 1u : 0u;
        uint16_t  lo  = (uint16_t)(0u - (val & 0x0Fu) - x);
        if (lo > 9u) lo -= 6u;
        uint16_t  hi  = (uint16_t)(0u - (val >> 4) - ((lo > 9u) ? 1u : 0u));
        bool      c   = (hi > 9u) || (val != 0u) || (x != 0u);
        if (hi > 9u) hi -= 6u;
        uint8_t   res = (uint8_t)(((hi & 0x0Fu) << 4) | (lo & 0x0Fu));
        m68k_assign_flag(cpu, M68K_SR_C | M68K_SR_X, c);
        m68k_assign_flag(cpu, M68K_SR_N, (res & 0x80u) != 0u);
        if (res != 0u) m68k_clear_flag(cpu, M68K_SR_Z);
        m68k_write_ea(cpu, &ea, res);
        return;
    }

    /* TAS <ea> (0100 1010 11mm mrrr) */
    if ((op & 0xFFC0u) == 0x4AC0u) {
        m68k_ea_t ea  = m68k_resolve_ea(cpu, mode, reg, M68K_SIZE_BYTE);
        uint8_t   val = (uint8_t)m68k_read_ea(cpu, &ea);
        m68k_flags_logic(cpu, val, M68K_SIZE_BYTE);
        m68k_write_ea(cpu, &ea, (uint32_t)(val | 0x80u));
        return;
    }

    /* Single-Operand ALU: NEGX (0), CLR (1), NEG (2), NOT (3), TST (5) */
    uint8_t     sub_op = (uint8_t)((op >> 9) & 7u);
    m68k_size_t size   = m68k_decode_size_bits((uint8_t)((op >> 6) & 3u));
    m68k_ea_t   ea     = m68k_resolve_ea(cpu, mode, reg, size);

    switch (sub_op) {
        case 0: { /* NEGX */
            uint32_t val = m68k_read_ea(cpu, &ea);
            uint32_t res = m68k_alu_subx(cpu, 0u, val, size);
            m68k_write_ea(cpu, &ea, res);
            break;
        }
        case 1: /* CLR */
            (void)m68k_read_ea(cpu, &ea);
            m68k_write_ea(cpu, &ea, 0u);
            m68k_clear_flag(cpu, M68K_SR_N | M68K_SR_V | M68K_SR_C);
            m68k_set_flag(cpu, M68K_SR_Z);
            break;
        case 2: { /* NEG */
            uint32_t val = m68k_read_ea(cpu, &ea);
            uint32_t res = m68k_alu_sub(cpu, 0u, val, size, true);
            m68k_write_ea(cpu, &ea, res);
            break;
        }
        case 3: { /* NOT */
            uint32_t val = m68k_read_ea(cpu, &ea);
            uint32_t res = (~val) & m68k_size_mask(size);
            m68k_flags_logic(cpu, res, size);
            m68k_write_ea(cpu, &ea, res);
            break;
        }
        case 5: { /* TST */
            uint32_t val = m68k_read_ea(cpu, &ea);
            m68k_flags_logic(cpu, val, size);
            break;
        }
        default:
            cpu->pc = cpu->ppc;
            m68k_raise_exception(cpu, M68K_VEC_ILLEGAL_INST);
            break;
    }
}

/* Line 0x5: ADDQ, SUBQ, Scc, DBcc */
static void m68k_exec_line5(m68k_cpu_t *cpu, uint16_t op) {
    uint8_t mode = (uint8_t)((op >> 3) & 7u);
    uint8_t reg  = (uint8_t)(op & 7u);

    /* Scc and DBcc when bits 7..6 == 3 (11) */
    if (((op >> 6) & 3u) == 3u) {
        uint8_t cond    = (uint8_t)((op >> 8) & 0x0Fu);
        bool    is_true = m68k_eval_cond(cpu, cond);

        if (mode == 1u) {
            /* DBcc Dn, <d16> */
            uint32_t base_pc = cpu->pc;
            int16_t  disp    = (int16_t)m68k_fetch16(cpu);
            if (!is_true) {
                uint16_t cnt = (uint16_t)((cpu->d[reg] & 0xFFFFu) - 1u);
                m68k_write_d_sized(cpu, reg, M68K_SIZE_WORD, cnt);
                if (cnt != 0xFFFFu) {
                    cpu->pc = (base_pc + (uint32_t)(int32_t)disp) & M68K_ADDR_MASK;
                    cpu->step_cycles += 2u;
                } else {
                    cpu->step_cycles += 6u;
                }
            } else {
                cpu->step_cycles += 4u;
            }
        } else {
            /* Scc <ea> */
            m68k_ea_t ea = m68k_resolve_ea(cpu, mode, reg, M68K_SIZE_BYTE);
            (void)m68k_read_ea(cpu, &ea);
            m68k_write_ea(cpu, &ea, is_true ? 0xFFu : 0x00u);
        }
        return;
    }

    /* ADDQ / SUBQ #<1..8>, <ea> */
    uint32_t    imm    = (uint32_t)((op >> 9) & 7u);
    if (imm == 0u) imm = 8u;
    bool        is_sub = (op & 0x0100u) != 0u;
    m68k_size_t size   = m68k_decode_size_bits((uint8_t)((op >> 6) & 3u));

    /* ADDQ/SUBQ on Address Register Direct operates on full 32 bits and preserves CCR */
    if (mode == 1u) {
        if (is_sub) {
            cpu->a[reg] -= imm;
        } else {
            cpu->a[reg] += imm;
        }
        cpu->step_cycles += 4u;
        return;
    }

    m68k_ea_t ea  = m68k_resolve_ea(cpu, mode, reg, size);
    uint32_t  dst = m68k_read_ea(cpu, &ea);
    uint32_t  res = is_sub ? m68k_alu_sub(cpu, dst, imm, size, true)
                           : m68k_alu_add(cpu, dst, imm, size, true);
    m68k_write_ea(cpu, &ea, res);
}

/* Line 0x6: BRA, BSR, Bcc */
static void m68k_exec_line6(m68k_cpu_t *cpu, uint16_t op) {
    uint8_t  cond    = (uint8_t)((op >> 8) & 0x0Fu);
    uint32_t base_pc = cpu->pc;
    int32_t  disp    = (int32_t)(int8_t)(op & 0xFFu);

    if (disp == 0) {
        disp = (int32_t)(int16_t)m68k_fetch16(cpu);
    }

    if (cond == 0u) {
        /* BRA */
        cpu->pc = (base_pc + (uint32_t)disp) & M68K_ADDR_MASK;
        cpu->step_cycles += 6u;
    } else if (cond == 1u) {
        /* BSR */
        m68k_push32(cpu, cpu->pc);
        cpu->pc = (base_pc + (uint32_t)disp) & M68K_ADDR_MASK;
        cpu->step_cycles += 6u;
    } else {
        /* Bcc */
        if (m68k_eval_cond(cpu, cond)) {
            cpu->pc = (base_pc + (uint32_t)disp) & M68K_ADDR_MASK;
            cpu->step_cycles += 6u;
        } else {
            cpu->step_cycles += 4u;
        }
    }
}

/* Line 0x7: MOVEQ #<d8>, Dn */
static void m68k_exec_line7(m68k_cpu_t *cpu, uint16_t op) {
    if ((op & 0x0100u) != 0u) {
        cpu->pc = cpu->ppc;
        m68k_raise_exception(cpu, M68K_VEC_ILLEGAL_INST);
        return;
    }
    uint8_t  dreg = (uint8_t)((op >> 9) & 7u);
    uint32_t val  = (uint32_t)(int32_t)(int8_t)(op & 0xFFu);
    cpu->d[dreg]  = val;
    m68k_flags_logic(cpu, val, M68K_SIZE_LONG);
}

/* Line 0x8: OR, DIVU, DIVS, SBCD */
static void m68k_exec_line8(m68k_cpu_t *cpu, uint16_t op) {
    uint8_t dreg   = (uint8_t)((op >> 9) & 7u);
    uint8_t opmode = (uint8_t)((op >> 6) & 7u);
    uint8_t mode   = (uint8_t)((op >> 3) & 7u);
    uint8_t reg    = (uint8_t)(op & 7u);

    /* DIVU.W <ea>, Dn (opmode == 3) & DIVS.W <ea>, Dn (opmode == 7) */
    if (opmode == 3u || opmode == 7u) {
        m68k_ea_t ea  = m68k_resolve_ea(cpu, mode, reg, M68K_SIZE_WORD);
        uint16_t  src = (uint16_t)m68k_read_ea(cpu, &ea);
        if (src == 0u) {
            m68k_raise_exception(cpu, M68K_VEC_ZERO_DIVIDE);
            return;
        }
        m68k_clear_flag(cpu, M68K_SR_C);
        if (opmode == 3u) {
            uint32_t num  = cpu->d[dreg];
            uint32_t quot = num / (uint32_t)src;
            uint32_t rem  = num % (uint32_t)src;
            if (quot > 0xFFFFu) {
                m68k_set_flag(cpu, M68K_SR_V);
            } else {
                cpu->d[dreg] = ((rem & 0xFFFFu) << 16) | (quot & 0xFFFFu);
                m68k_flags_logic(cpu, quot & 0xFFFFu, M68K_SIZE_WORD);
            }
            cpu->step_cycles += 132u;
        } else {
            int32_t num  = (int32_t)cpu->d[dreg];
            int32_t den  = (int32_t)(int16_t)src;
            int32_t quot = num / den;
            int32_t rem  = num % den;
            if (quot < -32768 || quot > 32767) {
                m68k_set_flag(cpu, M68K_SR_V);
            } else {
                cpu->d[dreg] = (((uint32_t)(uint16_t)rem) << 16) | ((uint32_t)(uint16_t)quot);
                m68k_flags_logic(cpu, (uint32_t)(uint16_t)quot, M68K_SIZE_WORD);
            }
            cpu->step_cycles += 150u;
        }
        return;
    }

    /* SBCD Dy, Dx or SBCD -(Ay), -(Ax) (1000 xxx1 0000 mrrr) */
    if ((op & 0x01F0u) == 0x0100u) {
        bool    mem = (op & 0x0008u) != 0u;
        uint8_t src, dst;
        if (mem) {
            m68k_ea_t src_ea = m68k_resolve_ea(cpu, 4u, reg, M68K_SIZE_BYTE);
            m68k_ea_t dst_ea = m68k_resolve_ea(cpu, 4u, dreg, M68K_SIZE_BYTE);
            src = (uint8_t)m68k_read_ea(cpu, &src_ea);
            dst = (uint8_t)m68k_read_ea(cpu, &dst_ea);
            uint8_t  x  = m68k_get_flag(cpu, M68K_SR_X) ? 1u : 0u;
            uint16_t lo = (uint16_t)((dst & 0x0Fu) - (src & 0x0Fu) - x);
            bool     bc = (lo > 9u);
            if (bc) lo -= 6u;
            uint16_t hi = (uint16_t)((dst >> 4) - (src >> 4) - (bc ? 1u : 0u));
            bool     c  = (hi > 9u);
            if (c) hi -= 6u;
            uint8_t res = (uint8_t)(((hi & 0x0Fu) << 4) | (lo & 0x0Fu));
            m68k_assign_flag(cpu, M68K_SR_C | M68K_SR_X, c);
            m68k_assign_flag(cpu, M68K_SR_N, (res & 0x80u) != 0u);
            if (res != 0u) m68k_clear_flag(cpu, M68K_SR_Z);
            m68k_write_ea(cpu, &dst_ea, res);
        } else {
            src = (uint8_t)(cpu->d[reg] & 0xFFu);
            dst = (uint8_t)(cpu->d[dreg] & 0xFFu);
            uint8_t  x  = m68k_get_flag(cpu, M68K_SR_X) ? 1u : 0u;
            uint16_t lo = (uint16_t)((dst & 0x0Fu) - (src & 0x0Fu) - x);
            bool     bc = (lo > 9u);
            if (bc) lo -= 6u;
            uint16_t hi = (uint16_t)((dst >> 4) - (src >> 4) - (bc ? 1u : 0u));
            bool     c  = (hi > 9u);
            if (c) hi -= 6u;
            uint8_t res = (uint8_t)(((hi & 0x0Fu) << 4) | (lo & 0x0Fu));
            m68k_assign_flag(cpu, M68K_SR_C | M68K_SR_X, c);
            m68k_assign_flag(cpu, M68K_SR_N, (res & 0x80u) != 0u);
            if (res != 0u) m68k_clear_flag(cpu, M68K_SR_Z);
            m68k_write_d_sized(cpu, dreg, M68K_SIZE_BYTE, res);
        }
        return;
    }

    /* OR <ea>, Dn or OR Dn, <ea> */
    m68k_size_t size   = m68k_decode_size_bits(opmode & 3u);
    bool        to_ea  = (opmode & 4u) != 0u;
    m68k_ea_t   ea     = m68k_resolve_ea(cpu, mode, reg, size);
    uint32_t    ea_val = m68k_read_ea(cpu, &ea);
    uint32_t    dn_val = m68k_read_d_sized(cpu, dreg, size);
    uint32_t    res    = (ea_val | dn_val) & m68k_size_mask(size);

    m68k_flags_logic(cpu, res, size);
    if (to_ea) {
        m68k_write_ea(cpu, &ea, res);
    } else {
        m68k_write_d_sized(cpu, dreg, size, res);
    }
}

/* Line 0x9 (SUB/SUBA/SUBX) & Line 0xD (ADD/ADDA/ADDX) */
static void m68k_exec_add_sub(m68k_cpu_t *cpu, uint16_t op, bool is_sub) {
    uint8_t dreg   = (uint8_t)((op >> 9) & 7u);
    uint8_t opmode = (uint8_t)((op >> 6) & 7u);
    uint8_t mode   = (uint8_t)((op >> 3) & 7u);
    uint8_t reg    = (uint8_t)(op & 7u);

    /* ADDA / SUBA (opmode == 3 for .W, opmode == 7 for .L) */
    if (opmode == 3u || opmode == 7u) {
        m68k_size_t size = (opmode == 3u) ? M68K_SIZE_WORD : M68K_SIZE_LONG;
        m68k_ea_t   ea   = m68k_resolve_ea(cpu, mode, reg, size);
        uint32_t    src  = m68k_read_ea(cpu, &ea);
        if (size == M68K_SIZE_WORD) {
            src = (uint32_t)(int32_t)(int16_t)(src & 0xFFFFu);
        }
        if (is_sub) {
            cpu->a[dreg] -= src;
        } else {
            cpu->a[dreg] += src;
        }
        cpu->step_cycles += 4u;
        return;
    }

    m68k_size_t size = m68k_decode_size_bits(opmode & 3u);

    /* ADDX / SUBX when bit 8 == 1 and mode is 0 (Dn) or 1 (-(An)) */
    if ((opmode & 4u) != 0u && (mode == 0u || mode == 1u)) {
        if (mode == 0u) {
            uint32_t src = m68k_read_d_sized(cpu, reg, size);
            uint32_t dst = m68k_read_d_sized(cpu, dreg, size);
            uint32_t res = is_sub ? m68k_alu_subx(cpu, dst, src, size)
                                  : m68k_alu_addx(cpu, dst, src, size);
            m68k_write_d_sized(cpu, dreg, size, res);
        } else {
            m68k_ea_t src_ea = m68k_resolve_ea(cpu, 4u, reg, size);
            m68k_ea_t dst_ea = m68k_resolve_ea(cpu, 4u, dreg, size);
            uint32_t  src    = m68k_read_ea(cpu, &src_ea);
            uint32_t  dst    = m68k_read_ea(cpu, &dst_ea);
            uint32_t  res    = is_sub ? m68k_alu_subx(cpu, dst, src, size)
                                      : m68k_alu_addx(cpu, dst, src, size);
            m68k_write_ea(cpu, &dst_ea, res);
        }
        return;
    }

    /* Standard ADD / SUB */
    bool      to_ea  = (opmode & 4u) != 0u;
    m68k_ea_t ea     = m68k_resolve_ea(cpu, mode, reg, size);
    uint32_t  ea_val = m68k_read_ea(cpu, &ea);
    uint32_t  dn_val = m68k_read_d_sized(cpu, dreg, size);

    if (to_ea) {
        uint32_t res = is_sub ? m68k_alu_sub(cpu, ea_val, dn_val, size, true)
                              : m68k_alu_add(cpu, ea_val, dn_val, size, true);
        m68k_write_ea(cpu, &ea, res);
    } else {
        uint32_t res = is_sub ? m68k_alu_sub(cpu, dn_val, ea_val, size, true)
                              : m68k_alu_add(cpu, dn_val, ea_val, size, true);
        m68k_write_d_sized(cpu, dreg, size, res);
    }
}

/* Line 0xB: CMP, CMPA, CMPM, EOR */
static void m68k_exec_lineB(m68k_cpu_t *cpu, uint16_t op) {
    uint8_t dreg   = (uint8_t)((op >> 9) & 7u);
    uint8_t opmode = (uint8_t)((op >> 6) & 7u);
    uint8_t mode   = (uint8_t)((op >> 3) & 7u);
    uint8_t reg    = (uint8_t)(op & 7u);

    /* CMPA.W (opmode == 3) & CMPA.L (opmode == 7) */
    if (opmode == 3u || opmode == 7u) {
        m68k_size_t size = (opmode == 3u) ? M68K_SIZE_WORD : M68K_SIZE_LONG;
        m68k_ea_t   ea   = m68k_resolve_ea(cpu, mode, reg, size);
        uint32_t    src  = m68k_read_ea(cpu, &ea);
        if (size == M68K_SIZE_WORD) {
            src = (uint32_t)(int32_t)(int16_t)(src & 0xFFFFu);
        }
        (void)m68k_alu_sub(cpu, cpu->a[dreg], src, M68K_SIZE_LONG, false);
        return;
    }

    m68k_size_t size = m68k_decode_size_bits(opmode & 3u);

    /* CMPM (Ay)+, (Ax)+ when bit 8 == 1 and mode == 1 */
    if ((opmode & 4u) != 0u && mode == 1u) {
        m68k_ea_t src_ea = m68k_resolve_ea(cpu, 3u, reg, size);
        m68k_ea_t dst_ea = m68k_resolve_ea(cpu, 3u, dreg, size);
        uint32_t  src    = m68k_read_ea(cpu, &src_ea);
        uint32_t  dst    = m68k_read_ea(cpu, &dst_ea);
        (void)m68k_alu_sub(cpu, dst, src, size, false);
        return;
    }

    if ((opmode & 4u) != 0u) {
        /* EOR Dn, <ea> */
        m68k_ea_t ea  = m68k_resolve_ea(cpu, mode, reg, size);
        uint32_t  dst = m68k_read_ea(cpu, &ea);
        uint32_t  src = m68k_read_d_sized(cpu, dreg, size);
        uint32_t  res = (dst ^ src) & m68k_size_mask(size);
        m68k_flags_logic(cpu, res, size);
        m68k_write_ea(cpu, &ea, res);
    } else {
        /* CMP <ea>, Dn */
        m68k_ea_t ea  = m68k_resolve_ea(cpu, mode, reg, size);
        uint32_t  src = m68k_read_ea(cpu, &ea);
        uint32_t  dst = m68k_read_d_sized(cpu, dreg, size);
        (void)m68k_alu_sub(cpu, dst, src, size, false);
    }
}

/* Line 0xC: AND, MULU, MULS, ABCD, EXG */
static void m68k_exec_lineC(m68k_cpu_t *cpu, uint16_t op) {
    uint8_t dreg   = (uint8_t)((op >> 9) & 7u);
    uint8_t opmode = (uint8_t)((op >> 6) & 7u);
    uint8_t mode   = (uint8_t)((op >> 3) & 7u);
    uint8_t reg    = (uint8_t)(op & 7u);

    /* MULU.W <ea>, Dn (opmode == 3) & MULS.W <ea>, Dn (opmode == 7) */
    if (opmode == 3u || opmode == 7u) {
        m68k_ea_t ea  = m68k_resolve_ea(cpu, mode, reg, M68K_SIZE_WORD);
        uint16_t  src = (uint16_t)m68k_read_ea(cpu, &ea);
        uint16_t  dst = (uint16_t)(cpu->d[dreg] & 0xFFFFu);
        uint32_t  res = (opmode == 3u)
                            ? ((uint32_t)dst * (uint32_t)src)
                            : (uint32_t)((int32_t)(int16_t)dst * (int32_t)(int16_t)src);
        cpu->d[dreg] = res;
        m68k_flags_logic(cpu, res, M68K_SIZE_LONG);
        cpu->step_cycles += 66u;
        return;
    }

    /* ABCD (1100 xxx1 0000 mrrr) */
    if ((op & 0x01F0u) == 0x0100u) {
        bool    mem = (op & 0x0008u) != 0u;
        uint8_t src, dst;
        m68k_ea_t dst_ea;
        if (mem) {
            m68k_ea_t src_ea = m68k_resolve_ea(cpu, 4u, reg, M68K_SIZE_BYTE);
            dst_ea           = m68k_resolve_ea(cpu, 4u, dreg, M68K_SIZE_BYTE);
            src              = (uint8_t)m68k_read_ea(cpu, &src_ea);
            dst              = (uint8_t)m68k_read_ea(cpu, &dst_ea);
        } else {
            memset(&dst_ea, 0, sizeof(dst_ea));
            src = (uint8_t)(cpu->d[reg] & 0xFFu);
            dst = (uint8_t)(cpu->d[dreg] & 0xFFu);
        }
        uint8_t  x  = m68k_get_flag(cpu, M68K_SR_X) ? 1u : 0u;
        uint16_t lo = (uint16_t)((dst & 0x0Fu) + (src & 0x0Fu) + x);
        bool     hc = (lo > 9u);
        if (hc) lo += 6u;
        uint16_t hi = (uint16_t)((dst >> 4) + (src >> 4) + (hc ? 1u : 0u));
        bool     c  = (hi > 9u);
        if (c) hi += 6u;
        uint8_t res = (uint8_t)(((hi & 0x0Fu) << 4) | (lo & 0x0Fu));
        m68k_assign_flag(cpu, M68K_SR_C | M68K_SR_X, c);
        m68k_assign_flag(cpu, M68K_SR_N, (res & 0x80u) != 0u);
        if (res != 0u) m68k_clear_flag(cpu, M68K_SR_Z);
        if (mem) {
            m68k_write_ea(cpu, &dst_ea, res);
        } else {
            m68k_write_d_sized(cpu, dreg, M68K_SIZE_BYTE, res);
        }
        return;
    }

    /* EXG Rx, Ry */
    if ((op & 0x0130u) == 0x0100u && (mode == 1u || opmode == 5u || opmode == 6u)) {
        uint8_t exg_mode = (uint8_t)((op >> 3) & 0x1Fu);
        if (exg_mode == 0x08u) { /* Dx, Dy */
            uint32_t tmp = cpu->d[dreg];
            cpu->d[dreg] = cpu->d[reg];
            cpu->d[reg]  = tmp;
            return;
        }
        if (exg_mode == 0x09u) { /* Ax, Ay */
            uint32_t tmp = cpu->a[dreg];
            cpu->a[dreg] = cpu->a[reg];
            cpu->a[reg]  = tmp;
            return;
        }
        if (exg_mode == 0x11u) { /* Dx, Ay */
            uint32_t tmp = cpu->d[dreg];
            cpu->d[dreg] = cpu->a[reg];
            cpu->a[reg]  = tmp;
            return;
        }
    }

    /* AND <ea>, Dn or AND Dn, <ea> */
    m68k_size_t size   = m68k_decode_size_bits(opmode & 3u);
    bool        to_ea  = (opmode & 4u) != 0u;
    m68k_ea_t   ea     = m68k_resolve_ea(cpu, mode, reg, size);
    uint32_t    ea_val = m68k_read_ea(cpu, &ea);
    uint32_t    dn_val = m68k_read_d_sized(cpu, dreg, size);
    uint32_t    res    = (ea_val & dn_val) & m68k_size_mask(size);

    m68k_flags_logic(cpu, res, size);
    if (to_ea) {
        m68k_write_ea(cpu, &ea, res);
    } else {
        m68k_write_d_sized(cpu, dreg, size, res);
    }
}

/* Line 0xE: Shifts and Rotates (ASL/ASR, LSL/LSR, ROXL/ROXR, ROL/ROR) */
static uint32_t m68k_shift_rotate_core(m68k_cpu_t *cpu, uint8_t type, bool left,
                                       uint32_t val, uint32_t count, m68k_size_t size) {
    uint32_t mask = m68k_size_mask(size);
    uint32_t msb  = m68k_size_msb(size);
    val &= mask;

    bool last_out = false;
    bool ovf      = false;
    bool x_flag   = m68k_get_flag(cpu, M68K_SR_X);

    if (count == 0u) {
        /* Shift count == 0: C is cleared (except ROXL/ROXR sets C = X), X is unchanged */
        m68k_assign_flag(cpu, M68K_SR_C, (type == 2u) ? x_flag : false);
        m68k_clear_flag(cpu, M68K_SR_V);
        m68k_assign_flag(cpu, M68K_SR_Z, val == 0u);
        m68k_assign_flag(cpu, M68K_SR_N, (val & msb) != 0u);
        return val;
    }

    for (uint32_t i = 0; i < count; i++) {
        if (left) {
            last_out = (val & msb) != 0u;
            switch (type) {
                case 0: { /* ASL */
                    uint32_t before = val;
                    val = (val << 1) & mask;
                    if (((before ^ val) & msb) != 0u) {
                        ovf = true;
                    }
                    break;
                }
                case 1: /* LSL */
                    val = (val << 1) & mask;
                    break;
                case 2: /* ROXL */
                    val    = ((val << 1) | (x_flag ? 1u : 0u)) & mask;
                    x_flag = last_out;
                    break;
                case 3: /* ROL */
                    val = ((val << 1) | (last_out ? 1u : 0u)) & mask;
                    break;
            }
        } else {
            last_out = (val & 1u) != 0u;
            switch (type) {
                case 0: /* ASR */
                    val = ((val >> 1) | (val & msb)) & mask;
                    break;
                case 1: /* LSR */
                    val = (val >> 1) & mask;
                    break;
                case 2: /* ROXR */
                    val    = ((val >> 1) | (x_flag ? msb : 0u)) & mask;
                    x_flag = last_out;
                    break;
                case 3: /* ROR */
                    val = ((val >> 1) | (last_out ? msb : 0u)) & mask;
                    break;
            }
        }
    }

    m68k_assign_flag(cpu, M68K_SR_C, last_out);
    if (type != 3u) {
        /* ASL/ASR, LSL/LSR, ROXL/ROXR update X; ROL/ROR preserve X */
        m68k_assign_flag(cpu, M68K_SR_X, (type == 2u) ? x_flag : last_out);
    }
    m68k_assign_flag(cpu, M68K_SR_V, ovf);
    m68k_assign_flag(cpu, M68K_SR_Z, val == 0u);
    m68k_assign_flag(cpu, M68K_SR_N, (val & msb) != 0u);
    return val;
}

static void m68k_exec_lineE(m68k_cpu_t *cpu, uint16_t op) {
    bool left = (op & 0x0100u) != 0u;

    /* Memory 1-bit shift/rotate when bits 7..6 == 3 */
    if (((op >> 6) & 3u) == 3u) {
        uint8_t   type = (uint8_t)((op >> 9) & 3u);
        uint8_t   mode = (uint8_t)((op >> 3) & 7u);
        uint8_t   reg  = (uint8_t)(op & 7u);
        m68k_ea_t ea   = m68k_resolve_ea(cpu, mode, reg, M68K_SIZE_WORD);
        uint32_t  val  = m68k_read_ea(cpu, &ea);
        uint32_t  res  = m68k_shift_rotate_core(cpu, type, left, val, 1u, M68K_SIZE_WORD);
        m68k_write_ea(cpu, &ea, res);
        return;
    }

    /* Register shift/rotate */
    m68k_size_t size = m68k_decode_size_bits((uint8_t)((op >> 6) & 3u));
    uint8_t     type = (uint8_t)((op >> 3) & 3u);
    uint8_t     dreg = (uint8_t)(op & 7u);
    uint32_t    cnt  = (uint32_t)((op >> 9) & 7u);

    if ((op & 0x0020u) != 0u) {
        cnt = cpu->d[cnt] & 63u;
    } else if (cnt == 0u) {
        cnt = 8u;
    }

    uint32_t val = m68k_read_d_sized(cpu, dreg, size);
    uint32_t res = m68k_shift_rotate_core(cpu, type, left, val, cnt, size);
    m68k_write_d_sized(cpu, dreg, size, res);
    cpu->step_cycles += 2u * cnt;
}

/* ==========================================================================
 * Public Execution Loop (`m68k_step` / `m68k_run`)
 * ========================================================================== */

int m68k_step(m68k_cpu_t *cpu) {
    if (!cpu || cpu->halted) {
        return 4;
    }

    cpu->step_cycles = 0u;

    /* Check for pending external interrupts */
    if (m68k_check_interrupts(cpu)) {
        cpu->total_cycles += cpu->step_cycles;
        return (int)cpu->step_cycles;
    }

    /* If CPU is in STOP state, consume 4 idle cycles until an interrupt wakes it */
    if (cpu->stopped) {
        cpu->total_cycles += 4u;
        return 4;
    }

    /* Latch Trace state before fetching the instruction */
    cpu->trace_armed = m68k_get_flag(cpu, M68K_SR_T);
    cpu->ppc         = cpu->pc;
    uint16_t op      = m68k_fetch16(cpu);
    cpu->ir          = op;

    switch ((op >> 12) & 0x0Fu) {
        case 0x0: m68k_exec_line0(cpu, op); break;
        case 0x1: m68k_exec_move(cpu, op, M68K_SIZE_BYTE); break;
        case 0x2: m68k_exec_move(cpu, op, M68K_SIZE_LONG); break;
        case 0x3: m68k_exec_move(cpu, op, M68K_SIZE_WORD); break;
        case 0x4: m68k_exec_line4(cpu, op); break;
        case 0x5: m68k_exec_line5(cpu, op); break;
        case 0x6: m68k_exec_line6(cpu, op); break;
        case 0x7: m68k_exec_line7(cpu, op); break;
        case 0x8: m68k_exec_line8(cpu, op); break;
        case 0x9: m68k_exec_add_sub(cpu, op, true); break;
        case 0xA:
            cpu->pc = cpu->ppc;
            m68k_raise_exception(cpu, M68K_VEC_LINE_1010);
            break;
        case 0xB: m68k_exec_lineB(cpu, op); break;
        case 0xC: m68k_exec_lineC(cpu, op); break;
        case 0xD: m68k_exec_add_sub(cpu, op, false); break;
        case 0xE: m68k_exec_lineE(cpu, op); break;
        case 0xF:
            cpu->pc = cpu->ppc;
            m68k_raise_exception(cpu, M68K_VEC_LINE_1111);
            break;
    }

    /* Keep shadow SSP / USP synchronized with A7 */
    if (m68k_is_supervisor(cpu)) {
        cpu->ssp = cpu->a[7];
    } else {
        cpu->usp = cpu->a[7];
    }

    /* If Trace was armed at the start of this instruction, raise Trace Exception (Vector 9) */
    if (cpu->trace_armed && !cpu->stopped) {
        m68k_raise_exception(cpu, M68K_VEC_TRACE);
    }

    if (cpu->step_cycles < 4u) {
        cpu->step_cycles = 4u;
    }
    cpu->total_cycles += cpu->step_cycles;
    return (int)cpu->step_cycles;
}

int m68k_run(m68k_cpu_t *cpu, int target_cycles) {
    int executed = 0;
    while (executed < target_cycles) {
        executed += m68k_step(cpu);
    }
    return executed;
}
