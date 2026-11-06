#include "ym2612.h"
#include <string.h>

/* ==========================================================================
 * Internal Sine LUT, Key-Code, Detune & ADSR Rate Tables (Zero Dependencies)
 * ========================================================================== */

#define YD_YM2612_DEFAULT_CLOCK_HZ 7670453u
#define YD_YM2612_PHASE_MASK       0xFFFFFu

static int16_t ym_sin_lut[1024];
static bool    ym_lut_initialized = false;

/* Initialize 1024-entry sine lookup table in [-4096, +4096] using Bhaskara I's
 * rational approximation so no <math.h> / libm link is required. */
static void yd_ym2612_init_lut(void) {
    if (ym_lut_initialized) {
        return;
    }
    for (int i = 0; i < 512; i++) {
        /* Map i in [0..511] to [0..180] in fixed point (x100) */
        int64_t x     = ((int64_t)i * 18000) / 512;
        int64_t p     = x * (18000 - x);
        int64_t numer = 4 * p * 4096;
        int64_t denom = 405000000LL - p;
        int16_t val   = (denom != 0) ? (int16_t)(numer / denom) : 0;
        ym_sin_lut[i]       = val;
        ym_sin_lut[i + 512] = (int16_t)(-val);
    }
    ym_lut_initialized = true;
}

/* YM2612 F-Number upper 4 bits (bits 10..7) to 2-bit Key-Code note index */
static const uint8_t ym_fn_note[16] = {
    0u, 0u, 0u, 0u, 0u, 0u, 0u, 1u,
    2u, 3u, 3u, 3u, 3u, 3u, 3u, 3u
};

/* YM2612 hardware 4x32 Detune (DT1) frequency delta table indexed by [dt & 3][kc] */
static const int32_t ym_dt_tab[4][32] = {
    { 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
      0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 },
    { 0, 0, 0, 0, 1, 1, 1, 1, 1, 1, 1, 1, 2, 2, 2, 2,
      2, 3, 3, 3, 4, 4, 4, 5, 5, 6, 6, 7, 8, 8, 8, 8 },
    { 1, 1, 1, 1, 2, 2, 2, 2, 2, 3, 3, 3, 4, 4, 4, 5,
      5, 6, 6, 7, 8, 8, 9, 10, 11, 12, 13, 14, 16, 16, 16, 16 },
    { 2, 2, 2, 2, 2, 3, 3, 3, 4, 4, 4, 5, 5, 6, 6, 7,
      8, 8, 9, 10, 11, 12, 13, 14, 16, 17, 19, 20, 22, 22, 22, 22 }
};

/* YM2612 Envelope Generator 8-step increment patterns for rate sub-steps */
static const uint8_t ym_eg_inc_tab[19][8] = {
    /*0: 0 0*/ { 0, 0, 0, 0, 0, 0, 0, 0 },
    /*1: 0 1*/ { 0, 0, 0, 0, 0, 0, 0, 0 },
    /*2: 1 0*/ { 0, 1, 0, 1, 0, 1, 0, 1 },
    /*3: 1 1*/ { 0, 1, 0, 1, 0, 1, 0, 1 },
    /*4: R+0*/ { 0, 1, 0, 1, 0, 1, 0, 1 },
    /*5: R+1*/ { 0, 1, 0, 1, 1, 1, 0, 1 },
    /*6: R+2*/ { 0, 1, 1, 1, 0, 1, 1, 1 },
    /*7: R+3*/ { 0, 1, 1, 1, 1, 1, 1, 1 },
    /*8: 12+0*/{ 1, 1, 1, 1, 1, 1, 1, 1 },
    /*9: 12+1*/{ 1, 1, 1, 2, 1, 1, 1, 2 },
    /*10:12+2*/{ 1, 2, 1, 2, 1, 2, 1, 2 },
    /*11:12+3*/{ 1, 2, 2, 2, 1, 2, 2, 2 },
    /*12:13+0*/{ 2, 2, 2, 2, 2, 2, 2, 2 },
    /*13:13+1*/{ 2, 2, 2, 4, 2, 2, 2, 4 },
    /*14:13+2*/{ 2, 4, 2, 4, 2, 4, 2, 4 },
    /*15:13+3*/{ 2, 4, 4, 4, 2, 4, 4, 4 },
    /*16:14+0*/{ 4, 4, 4, 4, 4, 4, 4, 4 },
    /*17:14+1*/{ 4, 4, 4, 8, 4, 4, 4, 8 },
    /*18:15+x*/{ 8, 8, 8, 8, 8, 8, 8, 8 }
};

static inline uint8_t ym_calc_key_code(uint16_t f_num, uint8_t block) {
    return (uint8_t)(((block & 7u) << 2) | ym_fn_note[(f_num >> 7) & 0x0Fu]);
}

static inline uint8_t ym_calc_effective_rate(uint8_t base_rate_5bit, uint8_t ks, uint8_t kc) {
    if (base_rate_5bit == 0u) {
        return 0u;
    }
    uint32_t r = ((uint32_t)base_rate_5bit << 1) + ((uint32_t)(kc & 0x1Fu) >> (3u - (ks & 3u)));
    return (r > 63u) ? 63u : (uint8_t)r;
}

/* Apply 10-bit logarithmic attenuation (0 = 0 dB full amplitude, >= 0x3FF = 0)
 * using sign-magnitude arithmetic so negative samples decay cleanly to 0. */
static inline int32_t ym_apply_attenuation(int32_t sample, int32_t att_10bit) {
    if (att_10bit >= 0x3FF || sample == 0) {
        return 0;
    }
    if (att_10bit <= 0) {
        return sample;
    }
    bool     neg    = (sample < 0);
    uint32_t mag    = neg ? (uint32_t)(-sample) : (uint32_t)sample;
    uint32_t shift  = (uint32_t)(att_10bit >> 6);   /* 0..15 whole 6 dB halvings */
    uint32_t frac   = (uint32_t)(att_10bit & 0x3F); /* 0..63 sub-step            */
    uint32_t scaled = (mag * (64u - (frac >> 1))) >> (6u + shift);
    return neg ? -(int32_t)scaled : (int32_t)scaled;
}

/* Rebuild Q20 block step lookup table calibrated to YM2612 Master Clock (7.670453 MHz) */
static void yd_ym2612_rebuild_step_lut(yd_ym2612_t *ym) {
    uint64_t clk = (ym->clock_hz > 0u) ? (uint64_t)ym->clock_hz : (uint64_t)YD_YM2612_DEFAULT_CLOCK_HZ;
    uint64_t sr  = (ym->sample_rate > 0u) ? (uint64_t)ym->sample_rate : 44100ULL;
    uint64_t den = 144ULL * sr;

    for (uint32_t b = 0; b < 8u; b++) {
        uint64_t num = (clk << (19u + b)) + (den >> 1);
        ym->step_lut[b] = (uint32_t)(num / den);
    }
}

static void yd_ym2612_recalc_op_with_freq(const yd_ym2612_t *ym,
                                          uint16_t f_num,
                                          uint8_t block,
                                          yd_ym2612_op_t *op) {
    /* 1. Base step from Q20 step_lut[block]: ((F_NUM * step_lut[block]) >> 20) */
    uint32_t base_inc = (uint32_t)(((uint64_t)(f_num & 0x07FFu) *
                                    (uint64_t)ym->step_lut[block & 7u]) >> 20);

    /* 2. Hardware 5-bit Key-Code Detune (DT1: bits 1..0 = index, bit 2 = sign) */
    uint8_t kc        = ym_calc_key_code(f_num, block);
    int32_t dt_raw    = ym_dt_tab[op->dt & 3u][kc & 0x1Fu];
    int32_t dt_scaled = (int32_t)(((int64_t)dt_raw * (int64_t)ym->step_lut[1]) >> 20);
    int32_t detuned   = ((op->dt & 4u) != 0u) ? ((int32_t)base_inc - dt_scaled)
                                              : ((int32_t)base_inc + dt_scaled);
    if (detuned < 0) {
        detuned = 0;
    }

    /* 3. Frequency Multiplier: MUL == 0 -> 0.5x (>> 1), MUL 1..15 -> * MUL */
    uint32_t phase_inc = (op->mul == 0u) ? ((uint32_t)detuned >> 1)
                                         : ((uint32_t)detuned * (uint32_t)op->mul);
    op->phase_step = phase_inc & YD_YM2612_PHASE_MASK;
}

static void yd_ym2612_recalc_channel(yd_ym2612_t *ym, uint8_t ch_idx) {
    yd_ym2612_channel_t *ch = &ym->channels[ch_idx];

    /* Channel 3 Special Mode (R27 bits 7..6 != 0): independent frequencies per operator */
    if (ch_idx == 2u && (ym->ch3_mode & 0x03u) != 0u) {
        /* 0xA9/0xAD -> Op1 (ops[0]), 0xAA/0xAE -> Op2 (ops[1]),
         * 0xA8/0xAC -> Op3 (ops[2]), 0xA2/0xA6 -> Op4 (ops[3]) */
        yd_ym2612_recalc_op_with_freq(ym, ym->ch3_fnum[1], ym->ch3_block[1], &ch->ops[0]);
        yd_ym2612_recalc_op_with_freq(ym, ym->ch3_fnum[2], ym->ch3_block[2], &ch->ops[1]);
        yd_ym2612_recalc_op_with_freq(ym, ym->ch3_fnum[0], ym->ch3_block[0], &ch->ops[2]);
        yd_ym2612_recalc_op_with_freq(ym, ch->f_num, ch->block, &ch->ops[3]);
        return;
    }

    for (uint32_t i = 0; i < YD_YM2612_NUM_OPERATORS; i++) {
        yd_ym2612_recalc_op_with_freq(ym, ch->f_num, ch->block, &ch->ops[i]);
    }
}

/* ==========================================================================
 * Lifecycle & Configuration
 * ========================================================================== */

void yd_ym2612_init(yd_ym2612_t *ym, uint32_t clock_hz, uint32_t sample_rate) {
    if (!ym) {
        return;
    }
    yd_ym2612_init_lut();
    memset(ym, 0, sizeof(*ym));
    ym->clock_hz    = (clock_hz > 0u) ? clock_hz : YD_YM2612_DEFAULT_CLOCK_HZ;
    ym->sample_rate = (sample_rate > 0u) ? sample_rate : 44100u;
    yd_ym2612_reset(ym);
}

void yd_ym2612_reset(yd_ym2612_t *ym) {
    if (!ym) {
        return;
    }
    uint32_t clk = (ym->clock_hz > 0u) ? ym->clock_hz : YD_YM2612_DEFAULT_CLOCK_HZ;
    uint32_t sr  = (ym->sample_rate > 0u) ? ym->sample_rate : 44100u;

    memset(ym, 0, sizeof(*ym));
    ym->clock_hz    = clk;
    ym->sample_rate = sr;
    ym->dac_data    = 0x80u; /* Unsigned 8-bit center silence */
    ym->dac_enabled = false;

    yd_ym2612_rebuild_step_lut(ym);

    for (uint32_t c = 0; c < YD_YM2612_NUM_CHANNELS; c++) {
        ym->channels[c].pan_l = true;
        ym->channels[c].pan_r = true;
        for (uint32_t o = 0; o < YD_YM2612_NUM_OPERATORS; o++) {
            ym->channels[c].ops[o].eg_state  = YD_YM_EG_OFF;
            ym->channels[c].ops[o].env_level = 0x3FF;
            ym->channels[c].ops[o].tl        = 127u;
        }
    }
}

void yd_ym2612_set_clock(yd_ym2612_t *ym, uint32_t clock_hz, uint32_t sample_rate) {
    if (!ym) {
        return;
    }
    if (clock_hz > 0u) {
        ym->clock_hz = clock_hz;
    }
    if (sample_rate > 0u) {
        ym->sample_rate = sample_rate;
    }
    yd_ym2612_rebuild_step_lut(ym);
    for (uint8_t c = 0; c < YD_YM2612_NUM_CHANNELS; c++) {
        yd_ym2612_recalc_channel(ym, c);
    }
}

/* ==========================================================================
 * Register Write Decoder & Key-On / Key-Off Engine
 * ========================================================================== */

static void yd_ym2612_key_on(const yd_ym2612_channel_t *ch, yd_ym2612_op_t *op) {
    if (!op->key_on) {
        op->key_on   = true;
        op->phase    = 0u;
        uint8_t kc   = ym_calc_key_code(ch->f_num, ch->block);
        uint8_t rate = ym_calc_effective_rate(op->ar, op->ks, kc);
        if (rate >= 62u) {
            op->env_level = 0;
            op->eg_state  = YD_YM_EG_DECAY;
        } else {
            op->eg_state  = YD_YM_EG_ATTACK;
        }
    }
}

static void yd_ym2612_key_off(yd_ym2612_op_t *op) {
    if (op->key_on) {
        op->key_on = false;
        if (op->eg_state != YD_YM_EG_OFF) {
            op->eg_state = YD_YM_EG_RELEASE;
        }
    }
}

static void yd_ym2612_write_reg(yd_ym2612_t *ym, uint8_t bank, uint8_t reg, uint8_t val) {
    ym->regs[bank & 1u][reg] = val;

    /* 1. Global Registers (Bank 0, 0x22 .. 0x2B) */
    if (bank == 0u && reg < 0x30u) {
        switch (reg) {
            case 0x22: /* LFO */
                ym->lfo_enabled = (val & 0x08u) != 0u;
                ym->lfo_freq    = (uint8_t)(val & 0x07u);
                break;

            case 0x24: /* Timer A High (bits 9..2) */
                ym->timer_a_reg = (uint16_t)(((uint16_t)val << 2) | (ym->timer_a_reg & 0x03u));
                break;

            case 0x25: /* Timer A Low (bits 1..0) */
                ym->timer_a_reg = (uint16_t)((ym->timer_a_reg & 0x03FCu) | (val & 0x03u));
                break;

            case 0x26: /* Timer B (8-bit) */
                ym->timer_b_reg = val;
                break;

            case 0x27: /* Timer Control & Ch3 Mode */
                ym->timer_ctrl = val;
                ym->ch3_mode   = (uint8_t)((val >> 6) & 0x03u);
                yd_ym2612_recalc_channel(ym, 2u);
                if (val & 0x10u) {
                    ym->status &= 0xFEu; /* Reset Timer A overflow flag */
                }
                if (val & 0x20u) {
                    ym->status &= 0xFDu; /* Reset Timer B overflow flag */
                }
                if (val & 0x01u) {
                    ym->timer_a_cnt = (int32_t)(1024 - ym->timer_a_reg) * 144;
                }
                if (val & 0x02u) {
                    ym->timer_b_cnt = (int32_t)(256 - ym->timer_b_reg) * 2304;
                }
                break;

            case 0x28: { /* Key On / Key Off (Bits 7..4 = Op4, Op3, Op2, Op1) */
                uint8_t ch_low = (uint8_t)(val & 0x03u);
                if (ch_low == 3u) {
                    break;
                }
                uint8_t ch_idx = ((val & 0x04u) != 0u) ? (uint8_t)(ch_low + 3u) : ch_low;
                yd_ym2612_channel_t *ch = &ym->channels[ch_idx];
                for (uint8_t o = 0; o < 4u; o++) {
                    if ((val & (1u << (4u + o))) != 0u) {
                        yd_ym2612_key_on(ch, &ch->ops[o]);
                    } else {
                        yd_ym2612_key_off(&ch->ops[o]);
                    }
                }
                break;
            }

            case 0x2A: /* DAC Data (8-bit PCM sample) */
                ym->dac_data = val;
                break;

            case 0x2B: /* DAC Enable (Bit 7) */
                ym->dac_enabled = (val & 0x80u) != 0u;
                break;

            default:
                break;
        }
        return;
    }

    /* 2. Operator Registers (0x30 .. 0x9F)
     * Hardware offset mapping within each channel:
     *   Slot 1 (+0x00, slot_raw=0) -> Op 1 (ops[0])
     *   Slot 2 (+0x04, slot_raw=1) -> Op 3 (ops[2])
     *   Slot 3 (+0x08, slot_raw=2) -> Op 2 (ops[1])
     *   Slot 4 (+0x0C, slot_raw=3) -> Op 4 (ops[3]) */
    if (reg >= 0x30u && reg <= 0x9Fu) {
        uint8_t ch_in_bank = (uint8_t)(reg & 0x03u);
        if (ch_in_bank == 3u) {
            return;
        }
        uint8_t ch_idx   = (uint8_t)(bank * 3u + ch_in_bank);
        uint8_t slot_raw = (uint8_t)((reg >> 2) & 0x03u);
        static const uint8_t slot_map[4] = { 0u, 2u, 1u, 3u };
        uint8_t op_idx = slot_map[slot_raw];

        yd_ym2612_channel_t *ch = &ym->channels[ch_idx];
        yd_ym2612_op_t      *op = &ch->ops[op_idx];

        switch (reg & 0xF0u) {
            case 0x30u: /* DT1 (bits 6..4) & MUL (bits 3..0) */
                op->dt  = (uint8_t)((val >> 4) & 0x07u);
                op->mul = (uint8_t)(val & 0x0Fu);
                yd_ym2612_recalc_channel(ym, ch_idx);
                break;
            case 0x40u: /* TL (bits 6..0) */
                op->tl = (uint8_t)(val & 0x7Fu);
                break;
            case 0x50u: /* KS (bits 7..6) & AR (bits 4..0) */
                op->ks = (uint8_t)((val >> 6) & 0x03u);
                op->ar = (uint8_t)(val & 0x1Fu);
                break;
            case 0x60u: /* AM (bit 7) & D1R (bits 4..0) */
                op->am  = (uint8_t)((val >> 7) & 0x01u);
                op->d1r = (uint8_t)(val & 0x1Fu);
                break;
            case 0x70u: /* D2R (bits 4..0) */
                op->d2r = (uint8_t)(val & 0x1Fu);
                break;
            case 0x80u: /* D1L (bits 7..4) & RR (bits 3..0) */
                op->d1l = (uint8_t)((val >> 4) & 0x0Fu);
                op->rr  = (uint8_t)(val & 0x0Fu);
                break;
            case 0x90u: /* SSG-EG (bits 3..0) */
                op->ssg_eg = (uint8_t)(val & 0x0Fu);
                break;
            default:
                break;
        }
        return;
    }

    /* 3. Channel Registers (0xA0 .. 0xB6) */
    if (reg >= 0xA0u && reg <= 0xB6u) {
        /* Channel 3 Special Mode Frequency Registers (Bank 0, 0xA8..0xAE) */
        if (bank == 0u && reg >= 0xA8u && reg <= 0xAEu) {
            uint8_t sp_idx = (uint8_t)(reg & 0x03u);
            if (sp_idx == 3u) {
                return;
            }
            if (reg >= 0xACu) {
                ym->ch3_latch[sp_idx] = val;
            } else {
                uint8_t hi            = ym->ch3_latch[sp_idx];
                ym->ch3_fnum[sp_idx]  = (uint16_t)(((uint16_t)(hi & 0x07u) << 8) | val);
                ym->ch3_block[sp_idx] = (uint8_t)((hi >> 3) & 0x07u);
                yd_ym2612_recalc_channel(ym, 2u);
            }
            return;
        }

        uint8_t ch_in_bank = (uint8_t)(reg & 0x03u);
        if (ch_in_bank == 3u) {
            return;
        }
        uint8_t              ch_idx = (uint8_t)(bank * 3u + ch_in_bank);
        yd_ym2612_channel_t *ch     = &ym->channels[ch_idx];

        if (reg >= 0xA0u && reg <= 0xA2u) {
            /* Frequency Number Low Byte (latches combined with 0xA4..0xA6) */
            ch->f_num = (uint16_t)(((uint16_t)(ch->fnum_hi_latch & 0x07u) << 8) | val);
            ch->block = (uint8_t)((ch->fnum_hi_latch >> 3) & 0x07u);
            yd_ym2612_recalc_channel(ym, ch_idx);
        } else if (reg >= 0xA4u && reg <= 0xA6u) {
            /* Block & Frequency Number High Latch */
            ch->fnum_hi_latch = val;
        } else if (reg >= 0xB0u && reg <= 0xB2u) {
            /* Feedback (bits 5..3) & Algorithm (bits 2..0) */
            ch->fb  = (uint8_t)((val >> 3) & 0x07u);
            ch->alg = (uint8_t)(val & 0x07u);
        } else if (reg >= 0xB4u && reg <= 0xB6u) {
            /* Stereo L/R Panning (bits 7..6), AMS (bits 5..4), FMS (bits 2..0) */
            ch->pan_l = (val & 0x80u) != 0u;
            ch->pan_r = (val & 0x40u) != 0u;
            ch->ams   = (uint8_t)((val >> 4) & 0x03u);
            ch->fms   = (uint8_t)(val & 0x07u);
        }
    }
}

void yd_ym2612_write(yd_ym2612_t *ym, uint8_t port, uint8_t val) {
    if (!ym) {
        return;
    }
    switch (port & 3u) {
        case 0: /* Port 0 Address (Bank 0) */
            ym->addr_latch[0] = val;
            break;
        case 1: /* Port 0 Data    (Bank 0) */
            yd_ym2612_write_reg(ym, 0u, ym->addr_latch[0], val);
            break;
        case 2: /* Port 1 Address (Bank 1) */
            ym->addr_latch[1] = val;
            break;
        case 3: /* Port 1 Data    (Bank 1) */
            yd_ym2612_write_reg(ym, 1u, ym->addr_latch[1], val);
            break;
    }
}

uint8_t yd_ym2612_read_status(const yd_ym2612_t *ym) {
    if (!ym) {
        return 0u;
    }
    return ym->status;
}

/* ==========================================================================
 * FM Operator, Hardware-Calibrated Envelope & 8-Algorithm Synthesis Core
 * ========================================================================== */

static uint8_t ym_get_eg_increment(uint8_t rate, uint32_t env_cnt) {
    if (rate < 4u) {
        return 0u;
    }
    uint8_t shift = (uint8_t)(rate >> 2); /* 1..15 */
    uint8_t sub   = (uint8_t)(rate & 3u); /* 0..3  */

    if (shift < 12u) {
        uint32_t div_shift = 11u - shift;
        if ((env_cnt & ((1u << div_shift) - 1u)) != 0u) {
            return 0u;
        }
        uint8_t step = (uint8_t)((env_cnt >> div_shift) & 7u);
        uint8_t row  = (rate < 8u) ? sub : (uint8_t)(4u + sub);
        return ym_eg_inc_tab[row][step];
    } else {
        uint8_t step = (uint8_t)(env_cnt & 7u);
        uint8_t row  = (uint8_t)(8u + ((shift - 12u) * 4u) + sub);
        if (row > 18u) {
            row = 18u;
        }
        return ym_eg_inc_tab[row][step];
    }
}

static void yd_ym2612_step_op_envelope(const yd_ym2612_channel_t *ch,
                                       yd_ym2612_op_t *op,
                                       uint32_t env_cnt) {
    uint8_t kc = ym_calc_key_code(ch->f_num, ch->block);

    switch (op->eg_state) {
        case YD_YM_EG_OFF:
            op->env_level = 0x3FF;
            break;

        case YD_YM_EG_ATTACK: {
            uint8_t rate = ym_calc_effective_rate(op->ar, op->ks, kc);
            if (rate >= 62u) {
                op->env_level = 0;
                op->eg_state  = YD_YM_EG_DECAY;
                break;
            }
            uint8_t inc = ym_get_eg_increment(rate, env_cnt);
            if (inc > 0u) {
                /* Hardware exponential attack: ~env_level * inc >> 4 */
                op->env_level += ((~op->env_level) * (int32_t)inc) >> 4;
                if (op->env_level <= 0) {
                    op->env_level = 0;
                    op->eg_state  = YD_YM_EG_DECAY;
                }
            }
            break;
        }

        case YD_YM_EG_DECAY: {
            int32_t sl = (op->d1l == 15u) ? 0x3E0 : ((int32_t)op->d1l << 5);
            if (op->env_level >= sl) {
                op->env_level = sl;
                op->eg_state  = YD_YM_EG_SUSTAIN;
                break;
            }
            uint8_t rate = ym_calc_effective_rate(op->d1r, op->ks, kc);
            uint8_t inc  = ym_get_eg_increment(rate, env_cnt);
            if (inc > 0u) {
                op->env_level += (int32_t)inc;
                if (op->env_level >= sl) {
                    op->env_level = sl;
                    op->eg_state  = YD_YM_EG_SUSTAIN;
                }
            }
            break;
        }

        case YD_YM_EG_SUSTAIN: {
            uint8_t rate = ym_calc_effective_rate(op->d2r, op->ks, kc);
            uint8_t inc  = ym_get_eg_increment(rate, env_cnt);
            if (inc > 0u) {
                op->env_level += (int32_t)inc;
                if (op->env_level >= 0x3FF) {
                    op->env_level = 0x3FF;
                }
            }
            break;
        }

        case YD_YM_EG_RELEASE: {
            uint8_t rr_5bit = (uint8_t)(((op->rr & 0x0Fu) << 1) | 1u);
            uint8_t rate    = ym_calc_effective_rate(rr_5bit, op->ks, kc);
            uint8_t inc     = ym_get_eg_increment(rate, env_cnt);
            if (inc > 0u) {
                op->env_level += (int32_t)inc;
                if (op->env_level >= 0x3FF) {
                    op->env_level = 0x3FF;
                    op->eg_state  = YD_YM_EG_OFF;
                }
            }
            break;
        }
    }
}

static inline int32_t eval_fm_operator(yd_ym2612_op_t *op, int32_t phase_mod) {
    /* 20-bit phase accumulator wrap */
    op->phase = (op->phase + op->phase_step) & YD_YM2612_PHASE_MASK;
    if (op->eg_state == YD_YM_EG_OFF) {
        return 0;
    }

    uint32_t phase_idx = ((op->phase >> 10) + (uint32_t)phase_mod) & 0x3FFu;
    int32_t  raw_sin   = ym_sin_lut[phase_idx];
    int32_t  total_att = op->env_level + ((int32_t)op->tl << 3);
    return ym_apply_attenuation(raw_sin, total_att);
}

static inline int32_t clamp_ch14(int32_t v) {
    if (v > 8191)  return 8191;
    if (v < -8192) return -8192;
    return v;
}

static int32_t synth_fm_channel(yd_ym2612_channel_t *ch) {
    /* Operator 1 (Slot 1, +0x00) with Self-Feedback: (prev1 + prev2) >> (10 - fb) */
    int32_t fb_mod = 0;
    if (ch->fb > 0u) {
        fb_mod = (ch->op1_out[0] + ch->op1_out[1]) >> (10u - (ch->fb & 7u));
    }
    int32_t out1   = eval_fm_operator(&ch->ops[0], fb_mod);
    ch->op1_out[1] = ch->op1_out[0];
    ch->op1_out[0] = out1;

    int32_t out2 = 0, out3 = 0, out4 = 0, final_out = 0;

    /* 8 Standard YM2612 FM Algorithms
     * ops[0] = Op1 (+0x00), ops[1] = Op2 (+0x08), ops[2] = Op3 (+0x04), ops[3] = Op4 (+0x0C) */
    switch (ch->alg & 7u) {
        case 0: /* Op1 -> Op2 -> Op3 -> Op4 (Carrier: Op4) */
            out2      = eval_fm_operator(&ch->ops[1], out1 >> 1);
            out3      = eval_fm_operator(&ch->ops[2], out2 >> 1);
            final_out = eval_fm_operator(&ch->ops[3], out3 >> 1);
            break;

        case 1: /* (Op1 + Op2) -> Op3 -> Op4 (Carrier: Op4) */
            out2      = eval_fm_operator(&ch->ops[1], 0);
            out3      = eval_fm_operator(&ch->ops[2], (out1 + out2) >> 1);
            final_out = eval_fm_operator(&ch->ops[3], out3 >> 1);
            break;

        case 2: /* (Op1 + (Op2 -> Op3)) -> Op4 (Carrier: Op4) */
            out2      = eval_fm_operator(&ch->ops[1], 0);
            out3      = eval_fm_operator(&ch->ops[2], out2 >> 1);
            final_out = eval_fm_operator(&ch->ops[3], (out1 + out3) >> 1);
            break;

        case 3: /* ((Op1 -> Op2) + Op3) -> Op4 (Carrier: Op4) */
            out2      = eval_fm_operator(&ch->ops[1], out1 >> 1);
            out3      = eval_fm_operator(&ch->ops[2], 0);
            final_out = eval_fm_operator(&ch->ops[3], (out2 + out3) >> 1);
            break;

        case 4: /* (Op1 -> Op2) + (Op3 -> Op4) (Carriers: Op2 + Op4) */
            out2      = eval_fm_operator(&ch->ops[1], out1 >> 1);
            out3      = eval_fm_operator(&ch->ops[2], 0);
            out4      = eval_fm_operator(&ch->ops[3], out3 >> 1);
            final_out = clamp_ch14(out2 + out4);
            break;

        case 5: /* Op1 -> (Op2 + Op3 + Op4) (Carriers: Op2 + Op3 + Op4) */
            out2      = eval_fm_operator(&ch->ops[1], out1 >> 1);
            out3      = eval_fm_operator(&ch->ops[2], out1 >> 1);
            out4      = eval_fm_operator(&ch->ops[3], out1 >> 1);
            final_out = clamp_ch14(out2 + out3 + out4);
            break;

        case 6: /* (Op1 -> Op2) + Op3 + Op4 (Carriers: Op2 + Op3 + Op4) */
            out2      = eval_fm_operator(&ch->ops[1], out1 >> 1);
            out3      = eval_fm_operator(&ch->ops[2], 0);
            out4      = eval_fm_operator(&ch->ops[3], 0);
            final_out = clamp_ch14(out2 + out3 + out4);
            break;

        case 7: /* Op1 + Op2 + Op3 + Op4 (Carriers: Op1 + Op2 + Op3 + Op4) */
            out2      = eval_fm_operator(&ch->ops[1], 0);
            out3      = eval_fm_operator(&ch->ops[2], 0);
            out4      = eval_fm_operator(&ch->ops[3], 0);
            final_out = clamp_ch14(out1 + out2 + out3 + out4);
            break;
    }

    return final_out;
}

static inline int16_t clamp_pcm16(int32_t v) {
    if (v > 32767)  return 32767;
    if (v < -32768) return -32768;
    return (int16_t)v;
}

static void yd_ym2612_generate_one_sample(yd_ym2612_t *ym) {
    if (ym->sample_count >= YD_YM2612_MAX_SAMPLES) {
        return;
    }

    /* Advance ADSR envelopes at ~1/3 of internal FM rate (every 2 output samples) */
    ym->env_tick++;
    if ((ym->env_tick & 1u) == 0u) {
        uint32_t eg_cnt = ym->env_tick >> 1;
        for (uint32_t c = 0; c < YD_YM2612_NUM_CHANNELS; c++) {
            for (uint32_t o = 0; o < YD_YM2612_NUM_OPERATORS; o++) {
                yd_ym2612_step_op_envelope(&ym->channels[c], &ym->channels[c].ops[o], eg_cnt);
            }
        }
    }

    int32_t mix_l = 0;
    int32_t mix_r = 0;

    for (uint32_t c = 0; c < YD_YM2612_NUM_CHANNELS; c++) {
        yd_ym2612_channel_t *ch = &ym->channels[c];
        int32_t ch_out = 0;

        /* Channel 6 (index 5) outputs 8-bit PCM DAC when Register 0x2B bit 7 is set */
        if (c == 5u && ym->dac_enabled) {
            ch_out = ((int32_t)ym->dac_data - 128) * 32;
        } else {
            ch_out = synth_fm_channel(ch);
        }

        if (ch->pan_l) {
            mix_l += ch_out;
        }
        if (ch->pan_r) {
            mix_r += ch_out;
        }
    }

    uint32_t idx = ym->sample_count * 2u;
    ym->sample_buffer[idx + 0u] = clamp_pcm16(mix_l);
    ym->sample_buffer[idx + 1u] = clamp_pcm16(mix_r);
    ym->sample_count++;
}

void yd_ym2612_begin_frame(yd_ym2612_t *ym) {
    if (!ym) {
        return;
    }
    ym->sample_count = 0u;
}

void yd_ym2612_step_cycles(yd_ym2612_t *ym, int m68k_cycles) {
    if (!ym || m68k_cycles <= 0) {
        return;
    }

    /* Update Timer A & Timer B if loaded */
    if ((ym->timer_ctrl & 0x01u) != 0u) {
        ym->timer_a_cnt -= m68k_cycles;
        if (ym->timer_a_cnt <= 0) {
            if ((ym->timer_ctrl & 0x04u) != 0u) {
                ym->status |= 0x01u;
            }
            ym->timer_a_cnt += (int32_t)(1024 - ym->timer_a_reg) * 144;
        }
    }
    if ((ym->timer_ctrl & 0x02u) != 0u) {
        ym->timer_b_cnt -= m68k_cycles;
        if (ym->timer_b_cnt <= 0) {
            if ((ym->timer_ctrl & 0x08u) != 0u) {
                ym->status |= 0x02u;
            }
            ym->timer_b_cnt += (int32_t)(256 - ym->timer_b_reg) * 2304;
        }
    }

    /* Downsample M68K clock cycles to output sample_rate */
    ym->phase_accum += (uint64_t)m68k_cycles * (uint64_t)ym->sample_rate;
    while (ym->phase_accum >= (uint64_t)ym->clock_hz) {
        ym->phase_accum -= (uint64_t)ym->clock_hz;
        yd_ym2612_generate_one_sample(ym);
    }
}

void yd_ym2612_mix_into(const yd_ym2612_t *ym, int16_t *dst_pcm, uint32_t num_stereo_samples) {
    if (!ym || !dst_pcm || num_stereo_samples == 0u) {
        return;
    }
    uint32_t count = (num_stereo_samples < ym->sample_count) ? num_stereo_samples : ym->sample_count;
    for (uint32_t i = 0; i < count * 2u; i++) {
        int32_t mixed = (int32_t)dst_pcm[i] + (int32_t)ym->sample_buffer[i];
        dst_pcm[i]    = clamp_pcm16(mixed);
    }
}
