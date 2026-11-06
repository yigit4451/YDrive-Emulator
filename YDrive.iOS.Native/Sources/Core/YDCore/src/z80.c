#include "z80.h"
#include <string.h>

/* ==========================================================================
 * Precomputed Flag Lookup Tables
 * ========================================================================== */
static uint8_t sz53_table[256];
static uint8_t parity_table[256];
static uint8_t sz53p_table[256];
static bool    tables_initialized = false;

static void z80_init_tables(void) {
    if (tables_initialized) {
        return;
    }
    for (int i = 0; i < 256; i++) {
        uint8_t s_z_xy = (uint8_t)(i & (Z80_FLAG_S | Z80_FLAG_Y | Z80_FLAG_X));
        if (i == 0) {
            s_z_xy |= Z80_FLAG_Z;
        }
        sz53_table[i] = s_z_xy;

        /* Calculate even parity (1 if number of set bits is even) */
        int bits = 0;
        for (int b = 0; b < 8; b++) {
            if (i & (1 << b)) {
                bits++;
            }
        }
        parity_table[i] = (bits & 1) ? 0u : Z80_FLAG_PV;
        sz53p_table[i]  = sz53_table[i] | parity_table[i];
    }
    tables_initialized = true;
}

/* ==========================================================================
 * Low-Level Memory & Bus Helpers
 * ========================================================================== */

static inline uint8_t z80_rd8(z80_cpu_t *cpu, uint16_t addr) {
    return cpu->bus.read_mem ? cpu->bus.read_mem(cpu->bus.ctx, addr) : 0xFFu;
}

static inline void z80_wr8(z80_cpu_t *cpu, uint16_t addr, uint8_t val) {
    if (cpu->bus.write_mem) {
        cpu->bus.write_mem(cpu->bus.ctx, addr, val);
    }
}

static inline uint16_t z80_rd16(z80_cpu_t *cpu, uint16_t addr) {
    uint8_t lo = z80_rd8(cpu, addr);
    uint8_t hi = z80_rd8(cpu, (uint16_t)(addr + 1u));
    return (uint16_t)((hi << 8) | lo);
}

static inline void z80_wr16(z80_cpu_t *cpu, uint16_t addr, uint16_t val) {
    z80_wr8(cpu, addr, (uint8_t)(val & 0xFFu));
    z80_wr8(cpu, (uint16_t)(addr + 1u), (uint8_t)(val >> 8));
}

static inline uint8_t z80_fetch8(z80_cpu_t *cpu) {
    return z80_rd8(cpu, cpu->pc++);
}

static inline uint16_t z80_fetch16(z80_cpu_t *cpu) {
    uint8_t lo = z80_fetch8(cpu);
    uint8_t hi = z80_fetch8(cpu);
    return (uint16_t)((hi << 8) | lo);
}

static inline void z80_push16(z80_cpu_t *cpu, uint16_t val) {
    cpu->sp--;
    z80_wr8(cpu, cpu->sp, (uint8_t)(val >> 8));
    cpu->sp--;
    z80_wr8(cpu, cpu->sp, (uint8_t)(val & 0xFFu));
}

static inline uint16_t z80_pop16(z80_cpu_t *cpu) {
    uint8_t lo = z80_rd8(cpu, cpu->sp++);
    uint8_t hi = z80_rd8(cpu, cpu->sp++);
    return (uint16_t)((hi << 8) | lo);
}

static inline uint8_t z80_in_port(z80_cpu_t *cpu, uint16_t port) {
    return cpu->bus.read_port ? cpu->bus.read_port(cpu->bus.ctx, port) : 0xFFu;
}

static inline void z80_out_port(z80_cpu_t *cpu, uint16_t port, uint8_t val) {
    if (cpu->bus.write_port) {
        cpu->bus.write_port(cpu->bus.ctx, port, val);
    }
}

/* ==========================================================================
 * 8-bit & 16-bit ALU Operations
 * ========================================================================== */

static inline void z80_alu_add8(z80_cpu_t *cpu, uint8_t val, uint8_t cy) {
    uint8_t  a   = cpu->af.hi;
    uint16_t res = (uint16_t)a + (uint16_t)val + (uint16_t)cy;
    uint8_t  r8  = (uint8_t)res;

    uint8_t f = sz53_table[r8];
    if (res > 0xFFu) {
        f |= Z80_FLAG_C;
    }
    if ((a ^ val ^ r8) & 0x10u) {
        f |= Z80_FLAG_H;
    }
    if (((a ^ ~val) & (a ^ r8)) & 0x80u) {
        f |= Z80_FLAG_PV;
    }

    cpu->af.hi = r8;
    cpu->af.lo = f;
}

static inline void z80_alu_sub8(z80_cpu_t *cpu, uint8_t val, uint8_t cy) {
    uint8_t  a   = cpu->af.hi;
    uint16_t res = (uint16_t)a - (uint16_t)val - (uint16_t)cy;
    uint8_t  r8  = (uint8_t)res;

    uint8_t f = sz53_table[r8] | Z80_FLAG_N;
    if (res > 0xFFu) {
        f |= Z80_FLAG_C;
    }
    if ((a ^ val ^ r8) & 0x10u) {
        f |= Z80_FLAG_H;
    }
    if (((a ^ val) & (a ^ r8)) & 0x80u) {
        f |= Z80_FLAG_PV;
    }

    cpu->af.hi = r8;
    cpu->af.lo = f;
}

static inline void z80_alu_and8(z80_cpu_t *cpu, uint8_t val) {
    cpu->af.hi &= val;
    cpu->af.lo  = sz53p_table[cpu->af.hi] | Z80_FLAG_H;
}

static inline void z80_alu_xor8(z80_cpu_t *cpu, uint8_t val) {
    cpu->af.hi ^= val;
    cpu->af.lo  = sz53p_table[cpu->af.hi];
}

static inline void z80_alu_or8(z80_cpu_t *cpu, uint8_t val) {
    cpu->af.hi |= val;
    cpu->af.lo  = sz53p_table[cpu->af.hi];
}

static inline void z80_alu_cp8(z80_cpu_t *cpu, uint8_t val) {
    uint8_t  a   = cpu->af.hi;
    uint16_t res = (uint16_t)a - (uint16_t)val;
    uint8_t  r8  = (uint8_t)res;

    /* Hardware detail: In CP, X and Y flags are copied from `val`, not `r8` */
    uint8_t f = (sz53_table[r8] & (Z80_FLAG_S | Z80_FLAG_Z))
              | (val & Z80_FLAG_XY_MASK)
              | Z80_FLAG_N;
    if (res > 0xFFu) {
        f |= Z80_FLAG_C;
    }
    if ((a ^ val ^ r8) & 0x10u) {
        f |= Z80_FLAG_H;
    }
    if (((a ^ val) & (a ^ r8)) & 0x80u) {
        f |= Z80_FLAG_PV;
    }

    cpu->af.lo = f;
}

static inline uint8_t z80_alu_inc8(z80_cpu_t *cpu, uint8_t val) {
    uint8_t res = (uint8_t)(val + 1u);
    uint8_t f   = (cpu->af.lo & Z80_FLAG_C) | sz53_table[res];
    if ((res & 0x0Fu) == 0x00u) {
        f |= Z80_FLAG_H;
    }
    if (val == 0x7Fu) {
        f |= Z80_FLAG_PV;
    }
    cpu->af.lo = f;
    return res;
}

static inline uint8_t z80_alu_dec8(z80_cpu_t *cpu, uint8_t val) {
    uint8_t res = (uint8_t)(val - 1u);
    uint8_t f   = (cpu->af.lo & Z80_FLAG_C) | sz53_table[res] | Z80_FLAG_N;
    if ((val & 0x0Fu) == 0x00u) {
        f |= Z80_FLAG_H;
    }
    if (val == 0x80u) {
        f |= Z80_FLAG_PV;
    }
    cpu->af.lo = f;
    return res;
}

static inline void z80_alu_daa(z80_cpu_t *cpu) {
    uint8_t a    = cpu->af.hi;
    uint8_t f    = cpu->af.lo;
    uint8_t diff = 0u;

    if ((f & Z80_FLAG_H) || ((a & 0x0Fu) > 9u)) {
        diff |= 0x06u;
    }
    if ((f & Z80_FLAG_C) || (a > 0x99u)) {
        diff |= 0x60u;
    }

    uint8_t res = (f & Z80_FLAG_N) ? (uint8_t)(a - diff) : (uint8_t)(a + diff);
    uint8_t nf  = sz53p_table[res] | (f & Z80_FLAG_N);

    if ((f & Z80_FLAG_C) || (a > 0x99u)) {
        nf |= Z80_FLAG_C;
    }
    if ((a ^ res) & 0x10u) {
        nf |= Z80_FLAG_H;
    }

    cpu->af.hi = res;
    cpu->af.lo = nf;
}

static inline uint16_t z80_alu_add16(z80_cpu_t *cpu, uint16_t a, uint16_t b) {
    uint32_t res = (uint32_t)a + (uint32_t)b;
    uint16_t r16 = (uint16_t)res;

    cpu->wz = (uint16_t)(a + 1u);

    uint8_t f = cpu->af.lo & (Z80_FLAG_S | Z80_FLAG_Z | Z80_FLAG_PV);
    f |= ((uint8_t)(r16 >> 8)) & Z80_FLAG_XY_MASK;
    if (res > 0xFFFFu) {
        f |= Z80_FLAG_C;
    }
    if (((a ^ b ^ r16) >> 8) & 0x10u) {
        f |= Z80_FLAG_H;
    }

    cpu->af.lo = f;
    return r16;
}

static inline void z80_alu_adc16(z80_cpu_t *cpu, uint16_t val) {
    uint16_t hl  = cpu->hl.pair;
    uint32_t cy  = (cpu->af.lo & Z80_FLAG_C) ? 1u : 0u;
    uint32_t res = (uint32_t)hl + (uint32_t)val + cy;
    uint16_t r16 = (uint16_t)res;

    cpu->wz = (uint16_t)(hl + 1u);

    uint8_t f = ((uint8_t)(r16 >> 8)) & (Z80_FLAG_S | Z80_FLAG_XY_MASK);
    if (r16 == 0u) {
        f |= Z80_FLAG_Z;
    }
    if (res > 0xFFFFu) {
        f |= Z80_FLAG_C;
    }
    if (((hl ^ val ^ r16) >> 8) & 0x10u) {
        f |= Z80_FLAG_H;
    }
    if (((hl ^ ~val) & (hl ^ r16)) & 0x8000u) {
        f |= Z80_FLAG_PV;
    }

    cpu->hl.pair = r16;
    cpu->af.lo   = f;
}

static inline void z80_alu_sbc16(z80_cpu_t *cpu, uint16_t val) {
    uint16_t hl  = cpu->hl.pair;
    uint32_t cy  = (cpu->af.lo & Z80_FLAG_C) ? 1u : 0u;
    uint32_t res = (uint32_t)hl - (uint32_t)val - cy;
    uint16_t r16 = (uint16_t)res;

    cpu->wz = (uint16_t)(hl + 1u);

    uint8_t f = (((uint8_t)(r16 >> 8)) & (Z80_FLAG_S | Z80_FLAG_XY_MASK)) | Z80_FLAG_N;
    if (r16 == 0u) {
        f |= Z80_FLAG_Z;
    }
    if (res > 0xFFFFu) {
        f |= Z80_FLAG_C;
    }
    if (((hl ^ val ^ r16) >> 8) & 0x10u) {
        f |= Z80_FLAG_H;
    }
    if (((hl ^ val) & (hl ^ r16)) & 0x8000u) {
        f |= Z80_FLAG_PV;
    }

    cpu->hl.pair = r16;
    cpu->af.lo   = f;
}

/* ==========================================================================
 * Shift / Rotate / Bit Manipulation Helpers (CB / DDCB / FDCB)
 * ========================================================================== */

static uint8_t z80_cb_shift_op(z80_cpu_t *cpu, uint8_t op, uint8_t val) {
    uint8_t res = 0u;
    uint8_t cy  = 0u;

    switch (op) {
        case 0: /* RLC */
            cy  = (val >> 7) & 1u;
            res = (uint8_t)((val << 1) | cy);
            break;
        case 1: /* RRC */
            cy  = val & 1u;
            res = (uint8_t)((val >> 1) | (cy << 7));
            break;
        case 2: /* RL */
            cy  = (val >> 7) & 1u;
            res = (uint8_t)((val << 1) | (cpu->af.lo & Z80_FLAG_C));
            break;
        case 3: /* RR */
            cy  = val & 1u;
            res = (uint8_t)((val >> 1) | ((cpu->af.lo & Z80_FLAG_C) << 7));
            break;
        case 4: /* SLA */
            cy  = (val >> 7) & 1u;
            res = (uint8_t)(val << 1);
            break;
        case 5: /* SRA */
            cy  = val & 1u;
            res = (uint8_t)((val >> 1) | (val & 0x80u));
            break;
        case 6: /* SLL (Undocumented: shift left and set bit 0 to 1) */
            cy  = (val >> 7) & 1u;
            res = (uint8_t)((val << 1) | 0x01u);
            break;
        case 7: /* SRL */
            cy  = val & 1u;
            res = (uint8_t)(val >> 1);
            break;
    }

    cpu->af.lo = sz53p_table[res] | (cy ? Z80_FLAG_C : 0u);
    return res;
}

static void z80_cb_bit(z80_cpu_t *cpu, uint8_t bit, uint8_t val, uint8_t xy_source) {
    uint8_t mask = (uint8_t)(1u << bit);
    uint8_t f    = (cpu->af.lo & Z80_FLAG_C) | Z80_FLAG_H | (xy_source & Z80_FLAG_XY_MASK);

    if ((val & mask) == 0u) {
        f |= Z80_FLAG_Z | Z80_FLAG_PV;
    } else if (bit == 7u) {
        f |= Z80_FLAG_S;
    }
    cpu->af.lo = f;
}

/* ==========================================================================
 * Register Table Accessors (r = 0..7: B, C, D, E, H, L, (HL), A)
 * ========================================================================== */

static inline uint8_t z80_get_reg8(z80_cpu_t *cpu, uint8_t r) {
    switch (r & 7u) {
        case 0: return cpu->bc.hi;
        case 1: return cpu->bc.lo;
        case 2: return cpu->de.hi;
        case 3: return cpu->de.lo;
        case 4: return cpu->hl.hi;
        case 5: return cpu->hl.lo;
        case 6: return z80_rd8(cpu, cpu->hl.pair);
        default: return cpu->af.hi;
    }
}

static inline void z80_set_reg8(z80_cpu_t *cpu, uint8_t r, uint8_t val) {
    switch (r & 7u) {
        case 0: cpu->bc.hi = val; break;
        case 1: cpu->bc.lo = val; break;
        case 2: cpu->de.hi = val; break;
        case 3: cpu->de.lo = val; break;
        case 4: cpu->hl.hi = val; break;
        case 5: cpu->hl.lo = val; break;
        case 6: z80_wr8(cpu, cpu->hl.pair, val); break;
        default: cpu->af.hi = val; break;
    }
}

static inline bool z80_check_cond(const z80_cpu_t *cpu, uint8_t cc) {
    switch (cc & 7u) {
        case 0: return !(cpu->af.lo & Z80_FLAG_Z);  /* NZ */
        case 1: return  (cpu->af.lo & Z80_FLAG_Z);  /* Z  */
        case 2: return !(cpu->af.lo & Z80_FLAG_C);  /* NC */
        case 3: return  (cpu->af.lo & Z80_FLAG_C);  /* C  */
        case 4: return !(cpu->af.lo & Z80_FLAG_PV); /* PO */
        case 5: return  (cpu->af.lo & Z80_FLAG_PV); /* PE */
        case 6: return !(cpu->af.lo & Z80_FLAG_S);  /* P  */
        default: return (cpu->af.lo & Z80_FLAG_S);  /* M  */
    }
}

static inline void z80_do_alu8(z80_cpu_t *cpu, uint8_t alu_op, uint8_t val) {
    switch (alu_op & 7u) {
        case 0: z80_alu_add8(cpu, val, 0u); break;
        case 1: z80_alu_add8(cpu, val, (cpu->af.lo & Z80_FLAG_C) ? 1u : 0u); break;
        case 2: z80_alu_sub8(cpu, val, 0u); break;
        case 3: z80_alu_sub8(cpu, val, (cpu->af.lo & Z80_FLAG_C) ? 1u : 0u); break;
        case 4: z80_alu_and8(cpu, val); break;
        case 5: z80_alu_xor8(cpu, val); break;
        case 6: z80_alu_or8(cpu, val);  break;
        default: z80_alu_cp8(cpu, val); break;
    }
}

/* ==========================================================================
 * 0xCB Prefix Executor (Bit, Shift & Rotate Operations)
 * ========================================================================== */

static int z80_exec_cb(z80_cpu_t *cpu) {
    z80_inc_r(cpu);
    uint8_t op  = z80_fetch8(cpu);
    uint8_t grp = (op >> 6) & 3u;
    uint8_t y   = (op >> 3) & 7u;
    uint8_t z   = op & 7u;

    uint8_t val = z80_get_reg8(cpu, z);

    if (grp == 0u) {
        uint8_t res = z80_cb_shift_op(cpu, y, val);
        z80_set_reg8(cpu, z, res);
        return (z == 6u) ? 15 : 8;
    } else if (grp == 1u) {
        /* BIT y, r: For (HL), undocumented X/Y flags come from WZ high byte */
        uint8_t xy_src = (z == 6u) ? (uint8_t)(cpu->wz >> 8) : val;
        z80_cb_bit(cpu, y, val, xy_src);
        return (z == 6u) ? 12 : 8;
    } else if (grp == 2u) {
        /* RES y, r */
        val &= (uint8_t)~(1u << y);
        z80_set_reg8(cpu, z, val);
        return (z == 6u) ? 15 : 8;
    } else {
        /* SET y, r */
        val |= (uint8_t)(1u << y);
        z80_set_reg8(cpu, z, val);
        return (z == 6u) ? 15 : 8;
    }
}

/* ==========================================================================
 * 0xDDCB / 0xFDCB Prefix Executor (Indexed Bit Operations)
 * ========================================================================== */

static int z80_exec_ddcb_fdcb(z80_cpu_t *cpu, z80_regpair_t *idx) {
    /* Note: DDCB/FDCB fetches displacement `d` BEFORE the opcode byte, and
     * does NOT increment R a third time on the opcode byte! */
    int8_t   disp = (int8_t)z80_fetch8(cpu);
    uint8_t  op   = z80_fetch8(cpu);
    uint16_t ea   = (uint16_t)(idx->pair + disp);
    cpu->wz       = ea;

    uint8_t grp = (op >> 6) & 3u;
    uint8_t y   = (op >> 3) & 7u;
    uint8_t z   = op & 7u;
    uint8_t val = z80_rd8(cpu, ea);

    if (grp == 1u) {
        /* BIT y, (IX/IY + d): X/Y flags come from high byte of effective address */
        z80_cb_bit(cpu, y, val, (uint8_t)(ea >> 8));
        return 20;
    }

    uint8_t res;
    if (grp == 0u) {
        res = z80_cb_shift_op(cpu, y, val);
    } else if (grp == 2u) {
        res = val & (uint8_t)~(1u << y);
    } else {
        res = val | (uint8_t)(1u << y);
    }

    z80_wr8(cpu, ea, res);
    /* Undocumented behavior: if z != 6, also copy result into register `z` */
    if (z != 6u) {
        z80_set_reg8(cpu, z, res);
    }
    return 23;
}

/* ==========================================================================
 * 0xED Prefix Executor (Extended Instructions & Block Operations)
 * ========================================================================== */

static int z80_exec_ed(z80_cpu_t *cpu) {
    z80_inc_r(cpu);
    uint8_t op = z80_fetch8(cpu);

    switch (op) {
        /* IN r, (C) and undocumented IN (C) */
        case 0x40: case 0x48: case 0x50: case 0x58:
        case 0x60: case 0x68: case 0x70: case 0x78: {
            uint8_t r   = (op >> 3) & 7u;
            uint8_t val = z80_in_port(cpu, cpu->bc.pair);
            cpu->wz     = (uint16_t)(cpu->bc.pair + 1u);
            cpu->af.lo  = (cpu->af.lo & Z80_FLAG_C) | sz53p_table[val];
            if (r != 6u) {
                z80_set_reg8(cpu, r, val);
            }
            return 12;
        }

        /* OUT (C), r and undocumented OUT (C), 0 */
        case 0x41: case 0x49: case 0x51: case 0x59:
        case 0x61: case 0x69: case 0x71: case 0x79: {
            uint8_t r   = (op >> 3) & 7u;
            uint8_t val = (r == 6u) ? 0u : z80_get_reg8(cpu, r);
            z80_out_port(cpu, cpu->bc.pair, val);
            cpu->wz = (uint16_t)(cpu->bc.pair + 1u);
            return 12;
        }

        /* SBC HL, rr / ADC HL, rr */
        case 0x42: case 0x52: case 0x62: case 0x72:
        case 0x4A: case 0x5A: case 0x6A: case 0x7A: {
            uint16_t rr;
            switch ((op >> 4) & 3u) {
                case 0: rr = cpu->bc.pair; break;
                case 1: rr = cpu->de.pair; break;
                case 2: rr = cpu->hl.pair; break;
                default: rr = cpu->sp;     break;
            }
            if (op & 0x08u) {
                z80_alu_adc16(cpu, rr);
            } else {
                z80_alu_sbc16(cpu, rr);
            }
            return 15;
        }

        /* LD (nn), rr */
        case 0x43: case 0x53: case 0x63: case 0x73: {
            uint16_t addr = z80_fetch16(cpu);
            uint16_t rr;
            switch ((op >> 4) & 3u) {
                case 0: rr = cpu->bc.pair; break;
                case 1: rr = cpu->de.pair; break;
                case 2: rr = cpu->hl.pair; break;
                default: rr = cpu->sp;     break;
            }
            cpu->wz = (uint16_t)(addr + 1u);
            z80_wr16(cpu, addr, rr);
            return 20;
        }

        /* LD rr, (nn) */
        case 0x4B: case 0x5B: case 0x6B: case 0x7B: {
            uint16_t addr = z80_fetch16(cpu);
            uint16_t val  = z80_rd16(cpu, addr);
            cpu->wz       = (uint16_t)(addr + 1u);
            switch ((op >> 4) & 3u) {
                case 0: cpu->bc.pair = val; break;
                case 1: cpu->de.pair = val; break;
                case 2: cpu->hl.pair = val; break;
                default: cpu->sp     = val; break;
            }
            return 20;
        }

        /* NEG (all documented and undocumented encodings) */
        case 0x44: case 0x4C: case 0x54: case 0x5C:
        case 0x64: case 0x6C: case 0x74: case 0x7C: {
            uint8_t a  = cpu->af.hi;
            cpu->af.hi = 0u;
            z80_alu_sub8(cpu, a, 0u);
            return 8;
        }

        /* RETN / RETI */
        case 0x45: case 0x4D: case 0x55: case 0x5D:
        case 0x65: case 0x6D: case 0x75: case 0x7D: {
            cpu->iff1 = cpu->iff2;
            cpu->pc   = z80_pop16(cpu);
            cpu->wz   = cpu->pc;
            return 14;
        }

        /* IM 0 / IM 1 / IM 2 */
        case 0x46: case 0x4E: case 0x66: case 0x6E:
            cpu->im = 0u;
            return 8;
        case 0x56: case 0x76:
            cpu->im = 1u;
            return 8;
        case 0x5E: case 0x7E:
            cpu->im = 2u;
            return 8;

        /* LD I, A / LD R, A / LD A, I / LD A, R */
        case 0x47:
            cpu->i = cpu->af.hi;
            return 9;
        case 0x4F:
            cpu->r = cpu->af.hi;
            return 9;
        case 0x57:
            cpu->af.hi = cpu->i;
            cpu->af.lo = (cpu->af.lo & Z80_FLAG_C)
                       | sz53_table[cpu->i]
                       | (cpu->iff2 ? Z80_FLAG_PV : 0u);
            return 9;
        case 0x5F:
            cpu->af.hi = cpu->r;
            cpu->af.lo = (cpu->af.lo & Z80_FLAG_C)
                       | sz53_table[cpu->r]
                       | (cpu->iff2 ? Z80_FLAG_PV : 0u);
            return 9;

        /* RRD */
        case 0x67: {
            uint8_t m   = z80_rd8(cpu, cpu->hl.pair);
            uint8_t a   = cpu->af.hi;
            cpu->af.hi  = (a & 0xF0u) | (m & 0x0Fu);
            uint8_t res = (uint8_t)((m >> 4) | ((a & 0x0Fu) << 4));
            z80_wr8(cpu, cpu->hl.pair, res);
            cpu->af.lo  = (cpu->af.lo & Z80_FLAG_C) | sz53p_table[cpu->af.hi];
            cpu->wz     = (uint16_t)(cpu->hl.pair + 1u);
            return 18;
        }

        /* RLD */
        case 0x6F: {
            uint8_t m   = z80_rd8(cpu, cpu->hl.pair);
            uint8_t a   = cpu->af.hi;
            cpu->af.hi  = (a & 0xF0u) | (m >> 4);
            uint8_t res = (uint8_t)((m << 4) | (a & 0x0Fu));
            z80_wr8(cpu, cpu->hl.pair, res);
            cpu->af.lo  = (cpu->af.lo & Z80_FLAG_C) | sz53p_table[cpu->af.hi];
            cpu->wz     = (uint16_t)(cpu->hl.pair + 1u);
            return 18;
        }

        /* LDI, LDD, LDIR, LDDR */
        case 0xA0: case 0xA8: case 0xB0: case 0xB8: {
            uint8_t val = z80_rd8(cpu, cpu->hl.pair);
            z80_wr8(cpu, cpu->de.pair, val);

            int16_t step = (op & 0x08u) ? -1 : 1;
            cpu->hl.pair = (uint16_t)(cpu->hl.pair + step);
            cpu->de.pair = (uint16_t)(cpu->de.pair + step);
            cpu->bc.pair--;

            uint8_t n = (uint8_t)(val + cpu->af.hi);
            uint8_t f = cpu->af.lo & (Z80_FLAG_S | Z80_FLAG_Z | Z80_FLAG_C);
            if (cpu->bc.pair != 0u) {
                f |= Z80_FLAG_PV;
            }
            if (n & 0x08u) {
                f |= Z80_FLAG_X;
            }
            if (n & 0x02u) {
                f |= Z80_FLAG_Y;
            }
            cpu->af.lo = f;

            if ((op & 0x10u) && cpu->bc.pair != 0u) {
                cpu->pc -= 2u;
                cpu->wz  = (uint16_t)(cpu->pc + 1u);
                return 21;
            }
            return 16;
        }

        /* CPI, CPD, CPIR, CPDR */
        case 0xA1: case 0xA9: case 0xB1: case 0xB9: {
            uint8_t val  = z80_rd8(cpu, cpu->hl.pair);
            uint8_t a    = cpu->af.hi;
            uint8_t res  = (uint8_t)(a - val);
            int16_t step = (op & 0x08u) ? -1 : 1;

            cpu->hl.pair = (uint16_t)(cpu->hl.pair + step);
            cpu->bc.pair--;
            cpu->wz      = (uint16_t)(cpu->wz + step);

            uint8_t hc = ((a ^ val ^ res) & 0x10u) ? 1u : 0u;
            uint8_t n  = (uint8_t)(res - hc);
            uint8_t f  = (cpu->af.lo & Z80_FLAG_C)
                       | (sz53_table[res] & (Z80_FLAG_S | Z80_FLAG_Z))
                       | Z80_FLAG_N;
            if (hc) {
                f |= Z80_FLAG_H;
            }
            if (cpu->bc.pair != 0u) {
                f |= Z80_FLAG_PV;
            }
            if (n & 0x08u) {
                f |= Z80_FLAG_X;
            }
            if (n & 0x02u) {
                f |= Z80_FLAG_Y;
            }
            cpu->af.lo = f;

            if ((op & 0x10u) && cpu->bc.pair != 0u && res != 0u) {
                cpu->pc -= 2u;
                cpu->wz  = (uint16_t)(cpu->pc + 1u);
                return 21;
            }
            return 16;
        }

        /* INI, IND, INIR, INDR */
        case 0xA2: case 0xAA: case 0xB2: case 0xBA: {
            int16_t step = (op & 0x08u) ? -1 : 1;
            cpu->wz      = (uint16_t)(cpu->bc.pair + step);
            uint8_t val  = z80_in_port(cpu, cpu->bc.pair);
            z80_wr8(cpu, cpu->hl.pair, val);

            cpu->hl.pair = (uint16_t)(cpu->hl.pair + step);
            cpu->bc.hi--;

            uint8_t f = sz53_table[cpu->bc.hi];
            if (val & 0x80u) {
                f |= Z80_FLAG_N;
            }
            uint16_t k = (uint16_t)val + (uint8_t)(cpu->bc.lo + step);
            if (k > 0xFFu) {
                f |= Z80_FLAG_C | Z80_FLAG_H;
            }
            f |= parity_table[(k & 0x07u) ^ cpu->bc.hi];
            cpu->af.lo = f;

            if ((op & 0x10u) && cpu->bc.hi != 0u) {
                cpu->pc -= 2u;
                return 21;
            }
            return 16;
        }

        /* OUTI, OUTD, OTIR, OTDR */
        case 0xA3: case 0xAB: case 0xB3: case 0xBB: {
            int16_t step = (op & 0x08u) ? -1 : 1;
            uint8_t val  = z80_rd8(cpu, cpu->hl.pair);

            cpu->bc.hi--;
            cpu->wz      = (uint16_t)(cpu->bc.pair + step);
            z80_out_port(cpu, cpu->bc.pair, val);
            cpu->hl.pair = (uint16_t)(cpu->hl.pair + step);

            uint8_t f = sz53_table[cpu->bc.hi];
            if (val & 0x80u) {
                f |= Z80_FLAG_N;
            }
            uint16_t k = (uint16_t)val + cpu->hl.lo;
            if (k > 0xFFu) {
                f |= Z80_FLAG_C | Z80_FLAG_H;
            }
            f |= parity_table[(k & 0x07u) ^ cpu->bc.hi];
            cpu->af.lo = f;

            if ((op & 0x10u) && cpu->bc.hi != 0u) {
                cpu->pc -= 2u;
                return 21;
            }
            return 16;
        }

        default:
            /* Undefined ED opcodes act as 2-byte NOPs (8 T-states) */
            return 8;
    }
}

/* ==========================================================================
 * 0xDD / 0xFD Prefix Executor (IX / IY Indexed Instructions)
 * ========================================================================== */

static inline uint8_t z80_get_idx_reg8(z80_cpu_t *cpu, z80_regpair_t *idx, uint8_t r) {
    switch (r & 7u) {
        case 0: return cpu->bc.hi;
        case 1: return cpu->bc.lo;
        case 2: return cpu->de.hi;
        case 3: return cpu->de.lo;
        case 4: return idx->hi; /* IXH / IYH */
        case 5: return idx->lo; /* IXL / IYL */
        default: return cpu->af.hi;
    }
}

static inline void z80_set_idx_reg8(z80_cpu_t *cpu, z80_regpair_t *idx, uint8_t r, uint8_t val) {
    switch (r & 7u) {
        case 0: cpu->bc.hi = val; break;
        case 1: cpu->bc.lo = val; break;
        case 2: cpu->de.hi = val; break;
        case 3: cpu->de.lo = val; break;
        case 4: idx->hi    = val; break; /* IXH / IYH */
        case 5: idx->lo    = val; break; /* IXL / IYL */
        default: cpu->af.hi = val; break;
    }
}

/* Forward declaration for unprefixed fallback */
static int z80_exec_main_op(z80_cpu_t *cpu, uint8_t op);

static int z80_exec_indexed(z80_cpu_t *cpu, z80_regpair_t *idx) {
    int extra_cycles = 0;

    /* Consume any chained DD/FD prefixes without recursion */
    for (;;) {
        z80_inc_r(cpu);
        uint8_t op = z80_fetch8(cpu);

        if (op == 0xDDu) {
            idx = &cpu->ix;
            extra_cycles += 4;
            continue;
        }
        if (op == 0xFDu) {
            idx = &cpu->iy;
            extra_cycles += 4;
            continue;
        }
        if (op == 0xEDu) {
            /* DD/FD followed by ED ignores the index prefix */
            return extra_cycles + 4 + z80_exec_ed(cpu);
        }
        if (op == 0xCBu) {
            return extra_cycles + z80_exec_ddcb_fdcb(cpu, idx);
        }

        switch (op) {
            /* ADD IX/IY, rr */
            case 0x09:
                idx->pair = z80_alu_add16(cpu, idx->pair, cpu->bc.pair);
                return extra_cycles + 15;
            case 0x19:
                idx->pair = z80_alu_add16(cpu, idx->pair, cpu->de.pair);
                return extra_cycles + 15;
            case 0x29:
                idx->pair = z80_alu_add16(cpu, idx->pair, idx->pair);
                return extra_cycles + 15;
            case 0x39:
                idx->pair = z80_alu_add16(cpu, idx->pair, cpu->sp);
                return extra_cycles + 15;

            /* LD IX/IY, nn */
            case 0x21:
                idx->pair = z80_fetch16(cpu);
                return extra_cycles + 14;

            /* LD (nn), IX/IY */
            case 0x22: {
                uint16_t addr = z80_fetch16(cpu);
                cpu->wz       = (uint16_t)(addr + 1u);
                z80_wr16(cpu, addr, idx->pair);
                return extra_cycles + 20;
            }

            /* INC IX/IY */
            case 0x23:
                idx->pair++;
                return extra_cycles + 10;

            /* INC IXH/IYH (Undocumented) */
            case 0x24:
                idx->hi = z80_alu_inc8(cpu, idx->hi);
                return extra_cycles + 8;

            /* DEC IXH/IYH (Undocumented) */
            case 0x25:
                idx->hi = z80_alu_dec8(cpu, idx->hi);
                return extra_cycles + 8;

            /* LD IXH/IYH, n (Undocumented) */
            case 0x26:
                idx->hi = z80_fetch8(cpu);
                return extra_cycles + 11;

            /* LD IX/IY, (nn) */
            case 0x2A: {
                uint16_t addr = z80_fetch16(cpu);
                cpu->wz       = (uint16_t)(addr + 1u);
                idx->pair     = z80_rd16(cpu, addr);
                return extra_cycles + 20;
            }

            /* DEC IX/IY */
            case 0x2B:
                idx->pair--;
                return extra_cycles + 10;

            /* INC IXL/IYL (Undocumented) */
            case 0x2C:
                idx->lo = z80_alu_inc8(cpu, idx->lo);
                return extra_cycles + 8;

            /* DEC IXL/IYL (Undocumented) */
            case 0x2D:
                idx->lo = z80_alu_dec8(cpu, idx->lo);
                return extra_cycles + 8;

            /* LD IXL/IYL, n (Undocumented) */
            case 0x2E:
                idx->lo = z80_fetch8(cpu);
                return extra_cycles + 11;

            /* INC (IX/IY + d) */
            case 0x34: {
                int8_t   d   = (int8_t)z80_fetch8(cpu);
                uint16_t ea  = (uint16_t)(idx->pair + d);
                cpu->wz      = ea;
                uint8_t  val = z80_alu_inc8(cpu, z80_rd8(cpu, ea));
                z80_wr8(cpu, ea, val);
                return extra_cycles + 23;
            }

            /* DEC (IX/IY + d) */
            case 0x35: {
                int8_t   d   = (int8_t)z80_fetch8(cpu);
                uint16_t ea  = (uint16_t)(idx->pair + d);
                cpu->wz      = ea;
                uint8_t  val = z80_alu_dec8(cpu, z80_rd8(cpu, ea));
                z80_wr8(cpu, ea, val);
                return extra_cycles + 23;
            }

            /* LD (IX/IY + d), n */
            case 0x36: {
                int8_t   d   = (int8_t)z80_fetch8(cpu);
                uint8_t  n   = z80_fetch8(cpu);
                uint16_t ea  = (uint16_t)(idx->pair + d);
                cpu->wz      = ea;
                z80_wr8(cpu, ea, n);
                return extra_cycles + 19;
            }

            /* LD r, (IX/IY + d) */
            case 0x46: case 0x4E: case 0x56: case 0x5E:
            case 0x66: case 0x6E: case 0x7E: {
                int8_t   d  = (int8_t)z80_fetch8(cpu);
                uint16_t ea = (uint16_t)(idx->pair + d);
                cpu->wz     = ea;
                uint8_t  r  = (op >> 3) & 7u;
                /* Note: in LD H/L, (IX+d), target is real H/L, not IXH/IXL! */
                z80_set_reg8(cpu, r, z80_rd8(cpu, ea));
                return extra_cycles + 19;
            }

            /* LD (IX/IY + d), r */
            case 0x70: case 0x71: case 0x72: case 0x73:
            case 0x74: case 0x75: case 0x77: {
                int8_t   d  = (int8_t)z80_fetch8(cpu);
                uint16_t ea = (uint16_t)(idx->pair + d);
                cpu->wz     = ea;
                uint8_t  r  = op & 7u;
                /* Note: in LD (IX+d), H/L, source is real H/L, not IXH/IXL! */
                z80_wr8(cpu, ea, z80_get_reg8(cpu, r));
                return extra_cycles + 19;
            }

            /* Undocumented 8-bit loads involving IXH/IXL or IYH/IYL */
            case 0x44: case 0x45: case 0x4C: case 0x4D:
            case 0x54: case 0x55: case 0x5C: case 0x5D:
            case 0x60: case 0x61: case 0x62: case 0x63:
            case 0x64: case 0x65: case 0x67:
            case 0x68: case 0x69: case 0x6A: case 0x6B:
            case 0x6C: case 0x6D: case 0x6F:
            case 0x7C: case 0x7D: {
                uint8_t dst = (op >> 3) & 7u;
                uint8_t src = op & 7u;
                uint8_t val = z80_get_idx_reg8(cpu, idx, src);
                z80_set_idx_reg8(cpu, idx, dst, val);
                return extra_cycles + 8;
            }

            /* ALU A, (IX/IY + d) */
            case 0x86: case 0x8E: case 0x96: case 0x9E:
            case 0xA6: case 0xAE: case 0xB6: case 0xBE: {
                int8_t   d  = (int8_t)z80_fetch8(cpu);
                uint16_t ea = (uint16_t)(idx->pair + d);
                cpu->wz     = ea;
                z80_do_alu8(cpu, (op >> 3) & 7u, z80_rd8(cpu, ea));
                return extra_cycles + 19;
            }

            /* Undocumented ALU A, IXH/IXL/IYH/IYL */
            case 0x84: case 0x85: case 0x8C: case 0x8D:
            case 0x94: case 0x95: case 0x9C: case 0x9D:
            case 0xA4: case 0xA5: case 0xAC: case 0xAD:
            case 0xB4: case 0xB5: case 0xBC: case 0xBD: {
                uint8_t src = op & 7u;
                uint8_t val = (src == 4u) ? idx->hi : idx->lo;
                z80_do_alu8(cpu, (op >> 3) & 7u, val);
                return extra_cycles + 8;
            }

            /* POP IX/IY */
            case 0xE1:
                idx->pair = z80_pop16(cpu);
                return extra_cycles + 14;

            /* EX (SP), IX/IY */
            case 0xE3: {
                uint16_t tmp = z80_rd16(cpu, cpu->sp);
                z80_wr16(cpu, cpu->sp, idx->pair);
                idx->pair    = tmp;
                cpu->wz      = tmp;
                return extra_cycles + 23;
            }

            /* PUSH IX/IY */
            case 0xE5:
                z80_push16(cpu, idx->pair);
                return extra_cycles + 15;

            /* JP (IX/IY) */
            case 0xE9:
                cpu->pc = idx->pair;
                return extra_cycles + 8;

            /* LD SP, IX/IY */
            case 0xF9:
                cpu->sp = idx->pair;
                return extra_cycles + 10;

            default:
                /* Unmapped DD/FD opcode behaves like unprefixed opcode + 4 cycles */
                return extra_cycles + 4 + z80_exec_main_op(cpu, op);
        }
    }
}

/* ==========================================================================
 * Main Opcode Executor (0x00 - 0xFF)
 * ========================================================================== */

static int z80_exec_main_op(z80_cpu_t *cpu, uint8_t op) {
    /* Fast dispatch for 0x40 - 0x7F: LD r, r' and HALT */
    if (op >= 0x40u && op <= 0x7Fu) {
        if (op == 0x76u) {
            /* HALT */
            cpu->halted = true;
            return 4;
        }
        uint8_t dst = (op >> 3) & 7u;
        uint8_t src = op & 7u;
        uint8_t val = z80_get_reg8(cpu, src);
        z80_set_reg8(cpu, dst, val);
        return (dst == 6u || src == 6u) ? 7 : 4;
    }

    /* Fast dispatch for 0x80 - 0xBF: 8-bit ALU A, r */
    if (op >= 0x80u && op <= 0xBFu) {
        uint8_t alu_op = (op >> 3) & 7u;
        uint8_t src    = op & 7u;
        uint8_t val    = z80_get_reg8(cpu, src);
        z80_do_alu8(cpu, alu_op, val);
        return (src == 6u) ? 7 : 4;
    }

    switch (op) {
        /* 0x00: NOP */
        case 0x00:
            return 4;

        /* LD rr, nn */
        case 0x01: cpu->bc.pair = z80_fetch16(cpu); return 10;
        case 0x11: cpu->de.pair = z80_fetch16(cpu); return 10;
        case 0x21: cpu->hl.pair = z80_fetch16(cpu); return 10;
        case 0x31: cpu->sp      = z80_fetch16(cpu); return 10;

        /* LD (BC), A / LD (DE), A */
        case 0x02:
            z80_wr8(cpu, cpu->bc.pair, cpu->af.hi);
            cpu->wz = (uint16_t)((cpu->af.hi << 8) | ((cpu->bc.lo + 1u) & 0xFFu));
            return 7;
        case 0x12:
            z80_wr8(cpu, cpu->de.pair, cpu->af.hi);
            cpu->wz = (uint16_t)((cpu->af.hi << 8) | ((cpu->de.lo + 1u) & 0xFFu));
            return 7;

        /* LD (nn), HL / LD (nn), A */
        case 0x22: {
            uint16_t addr = z80_fetch16(cpu);
            cpu->wz       = (uint16_t)(addr + 1u);
            z80_wr16(cpu, addr, cpu->hl.pair);
            return 16;
        }
        case 0x32: {
            uint16_t addr = z80_fetch16(cpu);
            cpu->wz       = (uint16_t)((cpu->af.hi << 8) | ((addr + 1u) & 0xFFu));
            z80_wr8(cpu, addr, cpu->af.hi);
            return 13;
        }

        /* INC rr */
        case 0x03: cpu->bc.pair++; return 6;
        case 0x13: cpu->de.pair++; return 6;
        case 0x23: cpu->hl.pair++; return 6;
        case 0x33: cpu->sp++;      return 6;

        /* INC r */
        case 0x04: case 0x0C: case 0x14: case 0x1C:
        case 0x24: case 0x2C: case 0x34: case 0x3C: {
            uint8_t r   = (op >> 3) & 7u;
            uint8_t val = z80_alu_inc8(cpu, z80_get_reg8(cpu, r));
            z80_set_reg8(cpu, r, val);
            return (r == 6u) ? 11 : 4;
        }

        /* DEC r */
        case 0x05: case 0x0D: case 0x15: case 0x1D:
        case 0x25: case 0x2D: case 0x35: case 0x3D: {
            uint8_t r   = (op >> 3) & 7u;
            uint8_t val = z80_alu_dec8(cpu, z80_get_reg8(cpu, r));
            z80_set_reg8(cpu, r, val);
            return (r == 6u) ? 11 : 4;
        }

        /* LD r, n */
        case 0x06: case 0x0E: case 0x16: case 0x1E:
        case 0x26: case 0x2E: case 0x36: case 0x3E: {
            uint8_t r = (op >> 3) & 7u;
            uint8_t n = z80_fetch8(cpu);
            z80_set_reg8(cpu, r, n);
            return (r == 6u) ? 10 : 7;
        }

        /* RLCA, RRCA, RLA, RRA */
        case 0x07: { /* RLCA */
            uint8_t a  = cpu->af.hi;
            uint8_t cy = (a >> 7) & 1u;
            a          = (uint8_t)((a << 1) | cy);
            cpu->af.hi = a;
            cpu->af.lo = (cpu->af.lo & (Z80_FLAG_S | Z80_FLAG_Z | Z80_FLAG_PV))
                       | (a & Z80_FLAG_XY_MASK)
                       | (cy ? Z80_FLAG_C : 0u);
            return 4;
        }
        case 0x0F: { /* RRCA */
            uint8_t a  = cpu->af.hi;
            uint8_t cy = a & 1u;
            a          = (uint8_t)((a >> 1) | (cy << 7));
            cpu->af.hi = a;
            cpu->af.lo = (cpu->af.lo & (Z80_FLAG_S | Z80_FLAG_Z | Z80_FLAG_PV))
                       | (a & Z80_FLAG_XY_MASK)
                       | (cy ? Z80_FLAG_C : 0u);
            return 4;
        }
        case 0x17: { /* RLA */
            uint8_t a  = cpu->af.hi;
            uint8_t cy = (a >> 7) & 1u;
            a          = (uint8_t)((a << 1) | (cpu->af.lo & Z80_FLAG_C));
            cpu->af.hi = a;
            cpu->af.lo = (cpu->af.lo & (Z80_FLAG_S | Z80_FLAG_Z | Z80_FLAG_PV))
                       | (a & Z80_FLAG_XY_MASK)
                       | (cy ? Z80_FLAG_C : 0u);
            return 4;
        }
        case 0x1F: { /* RRA */
            uint8_t a  = cpu->af.hi;
            uint8_t cy = a & 1u;
            a          = (uint8_t)((a >> 1) | ((cpu->af.lo & Z80_FLAG_C) << 7));
            cpu->af.hi = a;
            cpu->af.lo = (cpu->af.lo & (Z80_FLAG_S | Z80_FLAG_Z | Z80_FLAG_PV))
                       | (a & Z80_FLAG_XY_MASK)
                       | (cy ? Z80_FLAG_C : 0u);
            return 4;
        }

        /* EX AF, AF' */
        case 0x08: {
            uint16_t tmp     = cpu->af.pair;
            cpu->af.pair     = cpu->af_alt.pair;
            cpu->af_alt.pair = tmp;
            return 4;
        }

        /* ADD HL, rr */
        case 0x09: cpu->hl.pair = z80_alu_add16(cpu, cpu->hl.pair, cpu->bc.pair); return 11;
        case 0x19: cpu->hl.pair = z80_alu_add16(cpu, cpu->hl.pair, cpu->de.pair); return 11;
        case 0x29: cpu->hl.pair = z80_alu_add16(cpu, cpu->hl.pair, cpu->hl.pair); return 11;
        case 0x39: cpu->hl.pair = z80_alu_add16(cpu, cpu->hl.pair, cpu->sp);      return 11;

        /* LD A, (BC) / LD A, (DE) */
        case 0x0A:
            cpu->af.hi = z80_rd8(cpu, cpu->bc.pair);
            cpu->wz    = (uint16_t)(cpu->bc.pair + 1u);
            return 7;
        case 0x1A:
            cpu->af.hi = z80_rd8(cpu, cpu->de.pair);
            cpu->wz    = (uint16_t)(cpu->de.pair + 1u);
            return 7;

        /* LD HL, (nn) / LD A, (nn) */
        case 0x2A: {
            uint16_t addr = z80_fetch16(cpu);
            cpu->wz       = (uint16_t)(addr + 1u);
            cpu->hl.pair  = z80_rd16(cpu, addr);
            return 16;
        }
        case 0x3A: {
            uint16_t addr = z80_fetch16(cpu);
            cpu->wz       = (uint16_t)(addr + 1u);
            cpu->af.hi    = z80_rd8(cpu, addr);
            return 13;
        }

        /* DEC rr */
        case 0x0B: cpu->bc.pair--; return 6;
        case 0x1B: cpu->de.pair--; return 6;
        case 0x2B: cpu->hl.pair--; return 6;
        case 0x3B: cpu->sp--;      return 6;

        /* DJNZ e */
        case 0x10: {
            int8_t disp = (int8_t)z80_fetch8(cpu);
            cpu->bc.hi--;
            if (cpu->bc.hi != 0u) {
                cpu->pc = (uint16_t)(cpu->pc + disp);
                cpu->wz = cpu->pc;
                return 13;
            }
            return 8;
        }

        /* JR e */
        case 0x18: {
            int8_t disp = (int8_t)z80_fetch8(cpu);
            cpu->pc     = (uint16_t)(cpu->pc + disp);
            cpu->wz     = cpu->pc;
            return 12;
        }

        /* JR cc, e */
        case 0x20: case 0x28: case 0x30: case 0x38: {
            int8_t disp = (int8_t)z80_fetch8(cpu);
            if (z80_check_cond(cpu, (op >> 3) & 3u)) {
                cpu->pc = (uint16_t)(cpu->pc + disp);
                cpu->wz = cpu->pc;
                return 12;
            }
            return 7;
        }

        /* DAA */
        case 0x27:
            z80_alu_daa(cpu);
            return 4;

        /* CPL */
        case 0x2F:
            cpu->af.hi = (uint8_t)~cpu->af.hi;
            cpu->af.lo = (cpu->af.lo & (Z80_FLAG_S | Z80_FLAG_Z | Z80_FLAG_PV | Z80_FLAG_C))
                       | (cpu->af.hi & Z80_FLAG_XY_MASK)
                       | Z80_FLAG_H | Z80_FLAG_N;
            return 4;

        /* SCF */
        case 0x37:
            cpu->af.lo = (cpu->af.lo & (Z80_FLAG_S | Z80_FLAG_Z | Z80_FLAG_PV))
                       | ((cpu->af.hi | cpu->af.lo) & Z80_FLAG_XY_MASK)
                       | Z80_FLAG_C;
            return 4;

        /* CCF */
        case 0x3F: {
            uint8_t old_c = (cpu->af.lo & Z80_FLAG_C) ? Z80_FLAG_H : 0u;
            uint8_t new_c = (cpu->af.lo & Z80_FLAG_C) ? 0u : Z80_FLAG_C;
            cpu->af.lo    = (cpu->af.lo & (Z80_FLAG_S | Z80_FLAG_Z | Z80_FLAG_PV))
                          | ((cpu->af.hi | cpu->af.lo) & Z80_FLAG_XY_MASK)
                          | old_c | new_c;
            return 4;
        }

        /* RET cc */
        case 0xC0: case 0xC8: case 0xD0: case 0xD8:
        case 0xE0: case 0xE8: case 0xF0: case 0xF8:
            if (z80_check_cond(cpu, (op >> 3) & 7u)) {
                cpu->pc = z80_pop16(cpu);
                cpu->wz = cpu->pc;
                return 11;
            }
            return 5;

        /* POP rr */
        case 0xC1: cpu->bc.pair = z80_pop16(cpu); return 10;
        case 0xD1: cpu->de.pair = z80_pop16(cpu); return 10;
        case 0xE1: cpu->hl.pair = z80_pop16(cpu); return 10;
        case 0xF1: cpu->af.pair = z80_pop16(cpu); return 10;

        /* JP cc, nn */
        case 0xC2: case 0xCA: case 0xD2: case 0xDA:
        case 0xE2: case 0xEA: case 0xF2: case 0xFA: {
            uint16_t addr = z80_fetch16(cpu);
            cpu->wz       = addr;
            if (z80_check_cond(cpu, (op >> 3) & 7u)) {
                cpu->pc = addr;
            }
            return 10;
        }

        /* JP nn */
        case 0xC3:
            cpu->pc = z80_fetch16(cpu);
            cpu->wz = cpu->pc;
            return 10;

        /* CALL cc, nn */
        case 0xC4: case 0xCC: case 0xD4: case 0xDC:
        case 0xE4: case 0xEC: case 0xF4: case 0xFC: {
            uint16_t addr = z80_fetch16(cpu);
            cpu->wz       = addr;
            if (z80_check_cond(cpu, (op >> 3) & 7u)) {
                z80_push16(cpu, cpu->pc);
                cpu->pc = addr;
                return 17;
            }
            return 10;
        }

        /* PUSH rr */
        case 0xC5: z80_push16(cpu, cpu->bc.pair); return 11;
        case 0xD5: z80_push16(cpu, cpu->de.pair); return 11;
        case 0xE5: z80_push16(cpu, cpu->hl.pair); return 11;
        case 0xF5: z80_push16(cpu, cpu->af.pair); return 11;

        /* ALU A, n */
        case 0xC6: case 0xCE: case 0xD6: case 0xDE:
        case 0xE6: case 0xEE: case 0xF6: case 0xFE: {
            uint8_t n = z80_fetch8(cpu);
            z80_do_alu8(cpu, (op >> 3) & 7u, n);
            return 7;
        }

        /* RST p */
        case 0xC7: case 0xCF: case 0xD7: case 0xDF:
        case 0xE7: case 0xEF: case 0xF7: case 0xFF: {
            uint16_t vec = (uint16_t)(op & 0x38u);
            z80_push16(cpu, cpu->pc);
            cpu->pc = vec;
            cpu->wz = vec;
            return 11;
        }

        /* RET */
        case 0xC9:
            cpu->pc = z80_pop16(cpu);
            cpu->wz = cpu->pc;
            return 10;

        /* Prefix 0xCB */
        case 0xCB:
            return z80_exec_cb(cpu);

        /* CALL nn */
        case 0xCD: {
            uint16_t addr = z80_fetch16(cpu);
            z80_push16(cpu, cpu->pc);
            cpu->pc = addr;
            cpu->wz = addr;
            return 17;
        }

        /* OUT (n), A */
        case 0xD3: {
            uint8_t  port_lo = z80_fetch8(cpu);
            uint16_t port    = (uint16_t)((cpu->af.hi << 8) | port_lo);
            z80_out_port(cpu, port, cpu->af.hi);
            cpu->wz = (uint16_t)((cpu->af.hi << 8) | ((port_lo + 1u) & 0xFFu));
            return 11;
        }

        /* EXX */
        case 0xD9: {
            uint16_t tmp;
            tmp = cpu->bc.pair; cpu->bc.pair = cpu->bc_alt.pair; cpu->bc_alt.pair = tmp;
            tmp = cpu->de.pair; cpu->de.pair = cpu->de_alt.pair; cpu->de_alt.pair = tmp;
            tmp = cpu->hl.pair; cpu->hl.pair = cpu->hl_alt.pair; cpu->hl_alt.pair = tmp;
            return 4;
        }

        /* IN A, (n) */
        case 0xDB: {
            uint8_t  port_lo = z80_fetch8(cpu);
            uint16_t port    = (uint16_t)((cpu->af.hi << 8) | port_lo);
            cpu->wz          = (uint16_t)(port + 1u);
            cpu->af.hi       = z80_in_port(cpu, port);
            return 11;
        }

        /* Prefix 0xDD (IX) */
        case 0xDD:
            return z80_exec_indexed(cpu, &cpu->ix);

        /* EX (SP), HL */
        case 0xE3: {
            uint16_t tmp = z80_rd16(cpu, cpu->sp);
            z80_wr16(cpu, cpu->sp, cpu->hl.pair);
            cpu->hl.pair = tmp;
            cpu->wz      = tmp;
            return 19;
        }

        /* JP (HL) */
        case 0xE9:
            cpu->pc = cpu->hl.pair;
            return 4;

        /* EX DE, HL */
        case 0xEB: {
            uint16_t tmp = cpu->de.pair;
            cpu->de.pair = cpu->hl.pair;
            cpu->hl.pair = tmp;
            return 4;
        }

        /* Prefix 0xED */
        case 0xED:
            return z80_exec_ed(cpu);

        /* DI */
        case 0xF3:
            cpu->iff1     = false;
            cpu->iff2     = false;
            cpu->ei_delay = false;
            return 4;

        /* LD SP, HL */
        case 0xF9:
            cpu->sp = cpu->hl.pair;
            return 6;

        /* EI */
        case 0xFB:
            cpu->iff1     = true;
            cpu->iff2     = true;
            cpu->ei_delay = true;
            return 4;

        /* Prefix 0xFD (IY) */
        case 0xFD:
            return z80_exec_indexed(cpu, &cpu->iy);

        default:
            return 4;
    }
}

/* ==========================================================================
 * Public Lifecycle & Execution API
 * ========================================================================== */

void z80_init(z80_cpu_t *cpu, const z80_bus_t *bus) {
    if (!cpu) {
        return;
    }
    z80_init_tables();
    memset(cpu, 0, sizeof(*cpu));
    if (bus) {
        cpu->bus = *bus;
    }
    z80_reset(cpu);
}

void z80_reset(z80_cpu_t *cpu) {
    if (!cpu) {
        return;
    }
    z80_init_tables();

    cpu->af.pair     = 0xFFFFu;
    cpu->bc.pair     = 0x0000u;
    cpu->de.pair     = 0x0000u;
    cpu->hl.pair     = 0x0000u;

    cpu->af_alt.pair = 0xFFFFu;
    cpu->bc_alt.pair = 0x0000u;
    cpu->de_alt.pair = 0x0000u;
    cpu->hl_alt.pair = 0x0000u;

    cpu->ix.pair     = 0xFFFFu;
    cpu->iy.pair     = 0xFFFFu;

    cpu->sp          = 0xFFFFu;
    cpu->pc          = 0x0000u;
    cpu->wz          = 0x0000u;
    cpu->i           = 0x00u;
    cpu->r           = 0x00u;

    cpu->iff1        = false;
    cpu->iff2        = false;
    cpu->im          = 0u;
    cpu->halted      = false;
    cpu->ei_delay    = false;

    cpu->int_line    = false;
    cpu->nmi_pending = false;
    cpu->int_vector  = 0xFFu;

    cpu->total_cycles = 0u;
}

void z80_reset_sms_post_bios(z80_cpu_t *cpu) {
    if (!cpu) {
        return;
    }
    z80_reset(cpu);

    /* State left by the official SEGA Master System / Game Gear BIOS */
    cpu->af.pair = 0x0000u;
    cpu->sp      = 0xDFF0u;
    cpu->im      = 1u;
}

int z80_step(z80_cpu_t *cpu) {
    /* 1. Non-Maskable Interrupt (/NMI -> 0x0066, e.g., SMS Pause button) */
    if (cpu->nmi_pending && !cpu->ei_delay) {
        cpu->nmi_pending = false;
        cpu->halted      = false;
        cpu->iff2        = cpu->iff1;
        cpu->iff1        = false;

        z80_inc_r(cpu);
        z80_push16(cpu, cpu->pc);
        cpu->pc = 0x0066u;
        cpu->wz = 0x0066u;

        cpu->total_cycles += 11u;
        return 11;
    }

    /* 2. Maskable Interrupt (/INT, gated by IFF1 and 1-instruction EI delay) */
    if (cpu->int_line && cpu->iff1 && !cpu->ei_delay) {
        cpu->halted = false;
        cpu->iff1   = false;
        cpu->iff2   = false;

        z80_inc_r(cpu);

        int irq_cycles;
        if (cpu->im == 2u) {
            /* Interrupt Mode 2: 16-bit vector table lookup ((I << 8) | vector) */
            uint16_t vec_addr = (uint16_t)((cpu->i << 8) | cpu->int_vector);
            uint16_t target   = z80_rd16(cpu, vec_addr);
            z80_push16(cpu, cpu->pc);
            cpu->pc           = target;
            cpu->wz           = target;
            irq_cycles        = 19;
        } else {
            /* Interrupt Mode 1 (standard SMS/GG VDP IRQ -> 0x0038) & Mode 0 (0xFF = RST 38h) */
            uint16_t target = (cpu->im == 1u) ? 0x0038u : (uint16_t)(cpu->int_vector & 0x38u);
            z80_push16(cpu, cpu->pc);
            cpu->pc         = target;
            cpu->wz         = target;
            irq_cycles      = 13;
        }

        cpu->total_cycles += (uint64_t)irq_cycles;
        return irq_cycles;
    }

    /* Clear any pending 1-instruction EI delay before executing next instruction */
    cpu->ei_delay = false;

    /* 3. HALT State: CPU executes internal NOPs (4 T-states, increments R) */
    if (cpu->halted) {
        z80_inc_r(cpu);
        cpu->total_cycles += 4u;
        return 4;
    }

    /* 4. Normal M1 Instruction Fetch & Execute */
    z80_inc_r(cpu);
    uint8_t op     = z80_fetch8(cpu);
    int     cycles = z80_exec_main_op(cpu, op);

    cpu->total_cycles += (uint64_t)cycles;
    return cycles;
}

int z80_run(z80_cpu_t *cpu, int target_cycles) {
    int elapsed = 0;
    while (elapsed < target_cycles) {
        elapsed += z80_step(cpu);
    }
    return elapsed;
}

void z80_set_int_line(z80_cpu_t *cpu, bool asserted) {
    if (cpu) {
        cpu->int_line = asserted;
    }
}

void z80_trigger_nmi(z80_cpu_t *cpu) {
    if (cpu) {
        cpu->nmi_pending = true;
    }
}
