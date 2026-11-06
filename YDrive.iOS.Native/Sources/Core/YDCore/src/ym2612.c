#include "ym2612.h"
#include <string.h>

/* ==========================================================================
 * Internal Sine LUT & Detune / Multiplier Tables (Zero External Dependencies)
 * ========================================================================== */

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

/* Detune frequency delta table indexed by (dt & 3) and key-code octave */
static const int32_t ym_dt_table[4][8] = {
    { 0, 0, 0, 0, 0, 0, 0, 0 },
    { 0, 1, 1, 1, 2, 2, 2, 3 },
    { 1, 1, 2, 2, 3, 4, 5, 6 },
    { 1, 2, 3, 4, 5, 6, 8, 9 }
};

/* Apply 10-bit logarithmic attenuation (0 = 0 dB full amplitude, >= 0x3FF = 0) */
static inline int32_t ym_apply_attenuation(int32_t sample, int32_t att_10bit) {
    if (att_10bit >= 0x3FF) {
        return 0;
    }
    if (att_10bit <= 0) {
        return sample;
    }
    int32_t shift = att_10bit >> 6;         /* 0..15 whole 6 dB halvings */
    int32_t frac  = att_10bit & 0x3F;       /* 0..63 linear sub-step     */
    int32_t scaled = (sample * (64 - (frac >> 1))) >> 6;
    return scaled >> shift;
}

static void yd_ym2612_recalc_op_phase_step(const yd_ym2612_t *ym,
                                           const yd_ym2612_channel_t *ch,
                                           yd_ym2612_op_t *op) {
    uint32_t base_freq = ((uint32_t)ch->f_num << ch->block) >> 1;

    /* Apply Detune (bits 1..0 = magnitude, bit 2 = negative sign) */
    int32_t dt_mag = ym_dt_table[op->dt & 3u][ch->block & 7u];
    int32_t detuned = ((op->dt & 4u) != 0u) ? ((int32_t)base_freq - dt_mag)
                                            : ((int32_t)base_freq + dt_mag);
    if (detuned < 0) {
        detuned = 0;
    }

    /* Apply Multiplier (0 -> 0.5x, 1..15 -> 1x..15x) */
    uint32_t multiplied = (op->mul == 0u) ? ((uint32_t)detuned >> 1)
                                          : ((uint32_t)detuned * (uint32_t)op->mul);

    /* Convert YM2612 internal FM rate (~53267 Hz at 7.67 MHz) to output sample_rate */
    uint32_t sr = (ym->sample_rate > 0u) ? ym->sample_rate : 44100u;
    op->phase_step = (uint32_t)(((uint64_t)multiplied * 53267u) / (uint64_t)sr);
}

static void yd_ym2612_recalc_channel(yd_ym2612_t *ym, yd_ym2612_channel_t *ch) {
    for (uint32_t i = 0; i < YD_YM2612_NUM_OPERATORS; i++) {
        yd_ym2612_recalc_op_phase_step(ym, ch, &ch->ops[i]);
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
    ym->clock_hz    = (clock_hz > 0u) ? clock_hz : 7670454u;
    ym->sample_rate = (sample_rate > 0u) ? sample_rate : 44100u;
    yd_ym2612_reset(ym);
}

void yd_ym2612_reset(yd_ym2612_t *ym) {
    if (!ym) {
        return;
    }
    uint32_t clk = ym->clock_hz;
    uint32_t sr  = ym->sample_rate;

    memset(ym, 0, sizeof(*ym));
    ym->clock_hz    = clk;
    ym->sample_rate = sr;
    ym->dac_data    = 0x80u; /* Unsigned 8-bit center silence */
    ym->dac_enabled = false;

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
    for (uint32_t c = 0; c < YD_YM2612_NUM_CHANNELS; c++) {
        yd_ym2612_recalc_channel(ym, &ym->channels[c]);
    }
}

/* ==========================================================================
 * Register Write Decoder & Key-On / Key-Off Engine
 * ========================================================================== */

static void yd_ym2612_key_on(yd_ym2612_op_t *op) {
    if (!op->key_on) {
        op->key_on   = true;
        op->phase    = 0u;
        op->eg_state = YD_YM_EG_ATTACK;
        if (op->ar >= 31u) {
            op->env_level = 0;
            op->eg_state  = YD_YM_EG_DECAY;
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

            case 0x28: { /* Key On / Key Off */
                uint8_t ch_low = (uint8_t)(val & 0x03u);
                if (ch_low == 3u) {
                    break;
                }
                uint8_t ch_idx = ((val & 0x04u) != 0u) ? (uint8_t)(ch_low + 3u) : ch_low;
                yd_ym2612_channel_t *ch = &ym->channels[ch_idx];
                for (uint8_t o = 0; o < 4u; o++) {
                    if ((val & (1u << (4u + o))) != 0u) {
                        yd_ym2612_key_on(&ch->ops[o]);
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

    /* 2. Operator Registers (0x30 .. 0x9F) */
    if (reg >= 0x30u && reg <= 0x9Fu) {
        uint8_t ch_in_bank = (uint8_t)(reg & 0x03u);
        if (ch_in_bank == 3u) {
            return;
        }
        uint8_t ch_idx   = (uint8_t)(bank * 3u + ch_in_bank);
        uint8_t slot_raw = (uint8_t)((reg >> 2) & 0x03u);
        /* YM2612 hardware register slot order: 0->Op1(0), 1->Op3(2), 2->Op2(1), 3->Op4(3) */
        static const uint8_t slot_map[4] = { 0u, 2u, 1u, 3u };
        uint8_t op_idx = slot_map[slot_raw];

        yd_ym2612_channel_t *ch = &ym->channels[ch_idx];
        yd_ym2612_op_t      *op = &ch->ops[op_idx];

        switch (reg & 0xF0u) {
            case 0x30u: /* DT1 (bits 6..4) & MUL (bits 3..0) */
                op->dt  = (uint8_t)((val >> 4) & 0x07u);
                op->mul = (uint8_t)(val & 0x0Fu);
                yd_ym2612_recalc_op_phase_step(ym, ch, op);
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
            yd_ym2612_recalc_channel(ym, ch);
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
 * FM Operator, Envelope & 8-Algorithm Synthesis Core
 * ========================================================================== */

static void yd_ym2612_step_op_envelope(yd_ym2612_op_t *op) {
    switch (op->eg_state) {
        case YD_YM_EG_OFF:
            op->env_level = 0x3FF;
            break;

        case YD_YM_EG_ATTACK:
            if (op->ar > 0u) {
                int32_t step = ((0x400 - op->env_level) * (int32_t)op->ar) >> 6;
                if (step < 1) {
                    step = 1;
                }
                op->env_level -= step;
                if (op->env_level <= 0) {
                    op->env_level = 0;
                    op->eg_state  = YD_YM_EG_DECAY;
                }
            }
            break;

        case YD_YM_EG_DECAY: {
            int32_t sl = (op->d1l == 15u) ? 0x3E0 : ((int32_t)op->d1l << 5);
            if (op->env_level >= sl) {
                op->env_level = sl;
                op->eg_state  = YD_YM_EG_SUSTAIN;
            } else if (op->d1r > 0u) {
                op->env_level += (int32_t)(op->d1r >> 1) + 1;
                if (op->env_level >= sl) {
                    op->env_level = sl;
                    op->eg_state  = YD_YM_EG_SUSTAIN;
                }
            }
            break;
        }

        case YD_YM_EG_SUSTAIN:
            if (op->d2r > 0u) {
                op->env_level += (int32_t)(op->d2r >> 2) + 1;
                if (op->env_level >= 0x3FF) {
                    op->env_level = 0x3FF;
                }
            }
            break;

        case YD_YM_EG_RELEASE: {
            int32_t r_step = (int32_t)op->rr * 2 + 1;
            op->env_level += r_step;
            if (op->env_level >= 0x3FF) {
                op->env_level = 0x3FF;
                op->eg_state  = YD_YM_EG_OFF;
            }
            break;
        }
    }
}

static inline int32_t eval_fm_operator(yd_ym2612_op_t *op, int32_t phase_mod) {
    op->phase = (op->phase + op->phase_step) & 0xFFFFFu;
    if (op->eg_state == YD_YM_EG_OFF) {
        return 0;
    }

    uint32_t phase_idx = ((op->phase >> 10) + (uint32_t)(phase_mod >> 2)) & 0x3FFu;
    int32_t  raw_sin   = ym_sin_lut[phase_idx];
    int32_t  total_att = op->env_level + ((int32_t)op->tl << 3);
    return ym_apply_attenuation(raw_sin, total_att);
}

static int32_t synth_fm_channel(yd_ym2612_channel_t *ch) {
    /* Operator 1 with Self-Feedback (fb = 1..7) */
    int32_t fb_mod = 0;
    if (ch->fb > 0u) {
        fb_mod = (ch->op1_out[0] + ch->op1_out[1]) >> (9u - ch->fb);
    }
    int32_t out1   = eval_fm_operator(&ch->ops[0], fb_mod);
    ch->op1_out[1] = ch->op1_out[0];
    ch->op1_out[0] = out1;

    int32_t out2 = 0, out3 = 0, out4 = 0, final_out = 0;

    /* 8 Standard YM2612 FM Algorithms */
    switch (ch->alg & 7u) {
        case 0: /* Op1 -> Op2 -> Op3 -> Op4 */
            out2      = eval_fm_operator(&ch->ops[1], out1);
            out3      = eval_fm_operator(&ch->ops[2], out2);
            final_out = eval_fm_operator(&ch->ops[3], out3);
            break;

        case 1: /* (Op1 + Op2) -> Op3 -> Op4 */
            out2      = eval_fm_operator(&ch->ops[1], 0);
            out3      = eval_fm_operator(&ch->ops[2], out1 + out2);
            final_out = eval_fm_operator(&ch->ops[3], out3);
            break;

        case 2: /* (Op1 + (Op2 -> Op3)) -> Op4 */
            out2      = eval_fm_operator(&ch->ops[1], 0);
            out3      = eval_fm_operator(&ch->ops[2], out2);
            final_out = eval_fm_operator(&ch->ops[3], out1 + out3);
            break;

        case 3: /* ((Op1 -> Op2) + Op3) -> Op4 */
            out2      = eval_fm_operator(&ch->ops[1], out1);
            out3      = eval_fm_operator(&ch->ops[2], 0);
            final_out = eval_fm_operator(&ch->ops[3], out2 + out3);
            break;

        case 4: /* (Op1 -> Op2) + (Op3 -> Op4) */
            out2      = eval_fm_operator(&ch->ops[1], out1);
            out3      = eval_fm_operator(&ch->ops[2], 0);
            out4      = eval_fm_operator(&ch->ops[3], out3);
            final_out = (out2 + out4) >> 1;
            break;

        case 5: /* Op1 -> (Op2 + Op3 + Op4) */
            out2      = eval_fm_operator(&ch->ops[1], out1);
            out3      = eval_fm_operator(&ch->ops[2], out1);
            out4      = eval_fm_operator(&ch->ops[3], out1);
            final_out = (out2 + out3 + out4) / 3;
            break;

        case 6: /* (Op1 -> Op2) + Op3 + Op4 */
            out2      = eval_fm_operator(&ch->ops[1], out1);
            out3      = eval_fm_operator(&ch->ops[2], 0);
            out4      = eval_fm_operator(&ch->ops[3], 0);
            final_out = (out2 + out3 + out4) / 3;
            break;

        case 7: /* Op1 + Op2 + Op3 + Op4 (Additive) */
            out2      = eval_fm_operator(&ch->ops[1], 0);
            out3      = eval_fm_operator(&ch->ops[2], 0);
            out4      = eval_fm_operator(&ch->ops[3], 0);
            final_out = (out1 + out2 + out3 + out4) >> 2;
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

    /* Advance ADSR envelopes every 16 output samples (~2.7 kHz envelope rate) */
    ym->env_tick++;
    if ((ym->env_tick & 15u) == 0u) {
        for (uint32_t c = 0; c < YD_YM2612_NUM_CHANNELS; c++) {
            for (uint32_t o = 0; o < YD_YM2612_NUM_OPERATORS; o++) {
                yd_ym2612_step_op_envelope(&ym->channels[c].ops[o]);
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
