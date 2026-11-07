#include "psg.h"
#include <string.h>

/* ==========================================================================
 * SN76489 Logarithmic Volume Table (15 Attenuation Steps + Silence, Balanced for YM2612 Mix)
 * ========================================================================== */
static const int16_t psg_vol_table[16] = {
    5600, 4560, 3710, 3020,
    2460, 2000, 1630, 1325,
    1080,  880,  715,  580,
     472,  384,  312,    0
};

/* ==========================================================================
 * Internal Helper: Advance 1 PSG Clock Tick (16 Z80 T-states)
 * ========================================================================== */
static void yd_psg_tick_internal(yd_psg_t *psg) {
    /* 1. Update Tone Channels 0, 1, 2 */
    for (int c = 0; c < 3; c++) {
        if (psg->tone_counter[c] > 0) {
            psg->tone_counter[c]--;
        }
        if (psg->tone_counter[c] <= 0) {
            uint16_t period = psg->tone_reg[c];
            psg->tone_counter[c] = (period > 0u) ? (int16_t)period : 1;
            if (period <= 1u) {
                /* Period 0 or 1 holds output high (+1) for PCM volume modulation */
                psg->tone_polarity[c] = 1;
            } else {
                psg->tone_polarity[c] = (int8_t)-psg->tone_polarity[c];
            }
        }
    }

    /* 2. Update Noise Channel (Channel 3) */
    if (psg->noise_counter > 0) {
        psg->noise_counter--;
    }
    if (psg->noise_counter <= 0) {
        uint8_t rate_sel = psg->noise_reg & 0x03u;
        int16_t period;
        switch (rate_sel) {
            case 0:  period = 0x10; break;
            case 1:  period = 0x20; break;
            case 2:  period = 0x40; break;
            default: period = (psg->tone_reg[2] > 0u) ? (int16_t)psg->tone_reg[2] : 1; break;
        }
        psg->noise_counter  = period;
        psg->noise_polarity = (int8_t)-psg->noise_polarity;

        /* Shift 16-bit SEGA LFSR on positive polarity edge */
        if (psg->noise_polarity > 0) {
            uint16_t lfsr = (psg->lfsr != 0u) ? psg->lfsr : 0x8000u;
            uint16_t fb   = (psg->noise_reg & 0x04u)
                            ? ((lfsr & 1u) ^ ((lfsr >> 3) & 1u)) /* White noise (SEGA taps 0, 3) */
                            : (lfsr & 1u);                        /* Periodic noise (tap 0, 1/16 duty) */
            psg->lfsr     = (uint16_t)((lfsr >> 1) | (fb << 15));
        }
    }
}

/* ==========================================================================
 * Internal Helper: Mix Current Instantaneous Stereo Sample
 * ========================================================================== */
static void yd_psg_mix_stereo(const yd_psg_t *psg, int16_t *out_left, int16_t *out_right) {
    int32_t left  = 0;
    int32_t right = 0;
    uint8_t pan   = psg->stereo_reg;

    /* Mix Tone Channels 0..2 (bipolar square wave) */
    for (int c = 0; c < 3; c++) {
        int16_t amp = psg_vol_table[psg->volume[c] & 0x0Fu];
        int32_t sig = (psg->tone_polarity[c] > 0) ? (int32_t)amp : -(int32_t)amp;

        if (pan & (0x10u << c)) {
            left += sig;
        }
        if (pan & (0x01u << c)) {
            right += sig;
        }
    }

    /* Mix Noise Channel 3 (driven by bit 0 of LFSR) */
    int16_t n_amp = psg_vol_table[psg->volume[3] & 0x0Fu];
    int32_t n_sig = (psg->lfsr & 1u) ? (int32_t)n_amp : -(int32_t)n_amp;
    if (pan & 0x80u) {
        left += n_sig;
    }
    if (pan & 0x08u) {
        right += n_sig;
    }

    *out_left  = (int16_t)left;
    *out_right = (int16_t)right;
}

/* ==========================================================================
 * Lifecycle & Configuration
 * ========================================================================== */

void yd_psg_init(yd_psg_t *psg, uint32_t cpu_clock_hz, uint32_t sample_rate) {
    if (!psg) {
        return;
    }
    memset(psg, 0, sizeof(*psg));
    psg->cpu_clock_hz = (cpu_clock_hz > 0u) ? cpu_clock_hz : 3579545u;
    psg->sample_rate  = (sample_rate > 0u) ? sample_rate : YD_PSG_DEFAULT_SAMPLE_RATE;
    yd_psg_reset(psg);
}

void yd_psg_reset(yd_psg_t *psg) {
    if (!psg) {
        return;
    }
    uint32_t clk  = psg->cpu_clock_hz;
    uint32_t rate = psg->sample_rate;

    memset(psg, 0, sizeof(*psg));
    psg->cpu_clock_hz = clk;
    psg->sample_rate  = rate;

    for (int c = 0; c < 3; c++) {
        psg->tone_reg[c]      = 0u;
        psg->tone_counter[c]  = 1;
        psg->tone_polarity[c] = 1;
        psg->volume[c]        = 0x0Fu; /* Silent on power-up */
    }

    psg->noise_reg      = 0x00u;
    psg->noise_counter  = 0x10;
    psg->noise_polarity = 1;
    psg->lfsr           = 0x8000u;
    psg->volume[3]      = 0x0Fu;       /* Silent on power-up */
    psg->stereo_reg     = 0xFFu;       /* All channels enabled on both L & R */
}

void yd_psg_set_clock(yd_psg_t *psg, uint32_t cpu_clock_hz, uint32_t sample_rate) {
    if (!psg) {
        return;
    }
    if (cpu_clock_hz > 0u) {
        psg->cpu_clock_hz = cpu_clock_hz;
    }
    if (sample_rate > 0u) {
        psg->sample_rate = sample_rate;
    }
}

/* ==========================================================================
 * Register Writes & Sample Generation
 * ========================================================================== */

void yd_psg_write(yd_psg_t *psg, uint8_t val) {
    if (!psg) {
        return;
    }

    if (val & 0x80u) {
        /* Latch/Data Byte: 1 [ch1 ch0] [type] [d3 d2 d1 d0] */
        uint8_t chan = (val >> 5) & 0x03u;
        bool    is_v = (val & 0x10u) != 0u;
        uint8_t data = val & 0x0Fu;

        psg->latched_chan      = chan;
        psg->latched_is_volume = is_v;

        if (is_v) {
            psg->volume[chan] = data;
        } else if (chan < 3u) {
            psg->tone_reg[chan] = (psg->tone_reg[chan] & 0x03F0u) | data;
        } else {
            psg->noise_reg = data & 0x07u;
            /* Seed LFSR: 0xACE1 for immediate white-noise spectrum, 0x8000 for 16-step periodic */
            psg->lfsr      = (psg->noise_reg & 0x04u) ? 0xACE1u : 0x8000u;
        }
    } else {
        /* Data Byte: 0 0 [d5 d4 d3 d2 d1 d0] */
        uint8_t chan = psg->latched_chan;
        if (psg->latched_is_volume) {
            psg->volume[chan] = val & 0x0Fu;
        } else if (chan < 3u) {
            psg->tone_reg[chan] = (psg->tone_reg[chan] & 0x000Fu)
                                | ((uint16_t)(val & 0x3Fu) << 4);
        } else {
            psg->noise_reg = val & 0x07u;
            psg->lfsr      = (psg->noise_reg & 0x04u) ? 0xACE1u : 0x8000u;
        }
    }
}

void yd_psg_write_stereo(yd_psg_t *psg, uint8_t val) {
    if (psg) {
        psg->stereo_reg = val;
    }
}

void yd_psg_begin_frame(yd_psg_t *psg) {
    if (psg) {
        psg->sample_count = 0u;
    }
}

void yd_psg_step_cycles(yd_psg_t *psg, int cpu_cycles) {
    if (!psg || cpu_cycles <= 0) {
        return;
    }

    /* Advance PSG clock (1 PSG tick per 16 Z80 T-states) */
    psg->psg_cycle_accum += (uint32_t)cpu_cycles;
    while (psg->psg_cycle_accum >= YD_PSG_CLOCK_DIVIDER) {
        psg->psg_cycle_accum -= YD_PSG_CLOCK_DIVIDER;
        yd_psg_tick_internal(psg);
    }

    /* Downsample to target PCM sample rate using exact rational phase accumulator */
    psg->sample_phase_accum += (uint64_t)cpu_cycles * (uint64_t)psg->sample_rate;
    while (psg->sample_phase_accum >= (uint64_t)psg->cpu_clock_hz) {
        psg->sample_phase_accum -= (uint64_t)psg->cpu_clock_hz;

        if (psg->sample_count < YD_PSG_MAX_SAMPLES_PER_FRAME) {
            int16_t left  = 0;
            int16_t right = 0;
            yd_psg_mix_stereo(psg, &left, &right);

            psg->sample_buffer[psg->sample_count * 2u + 0u] = left;
            psg->sample_buffer[psg->sample_count * 2u + 1u] = right;
            psg->sample_count++;
        }
    }
}
