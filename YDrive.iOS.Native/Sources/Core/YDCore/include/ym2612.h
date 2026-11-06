#ifndef YD_CORE_YM2612_H
#define YD_CORE_YM2612_H

#include <stdint.h>
#include <stdbool.h>
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

/* ==========================================================================
 * Yamaha YM2612 (OPN2) 6-Channel FM Synthesizer Constants
 * ========================================================================== */
#define YD_YM2612_NUM_CHANNELS     6u
#define YD_YM2612_NUM_OPERATORS    4u
#define YD_YM2612_MAX_SAMPLES      2048u /* Max stereo sample pairs per frame */

/* Envelope Generator States */
typedef enum yd_ym_eg_state {
    YD_YM_EG_OFF     = 0,
    YD_YM_EG_ATTACK  = 1,
    YD_YM_EG_DECAY   = 2,
    YD_YM_EG_SUSTAIN = 3,
    YD_YM_EG_RELEASE = 4
} yd_ym_eg_state_t;

/* ==========================================================================
 * Single FM Operator State (`yd_ym2612_op_t`)
 * ========================================================================== */
typedef struct yd_ym2612_op {
    uint8_t          dt;          /* Detune (0..7)                            */
    uint8_t          mul;         /* Frequency Multiplier (0..15, 0 = 0.5x)   */
    uint8_t          tl;          /* Total Level (0..127 attenuation)         */
    uint8_t          ks;          /* Key Scale (0..3)                         */
    uint8_t          ar;          /* Attack Rate (0..31)                      */
    uint8_t          am;          /* Amplitude Modulation Enable (0..1)       */
    uint8_t          d1r;         /* First Decay Rate (0..31)                 */
    uint8_t          d2r;         /* Second Decay / Sustain Rate (0..31)      */
    uint8_t          d1l;         /* Sustain Level (0..15)                    */
    uint8_t          rr;          /* Release Rate (0..15)                     */
    uint8_t          ssg_eg;      /* SSG-EG Mode (0..15)                      */

    /* Phase & Envelope Runtime State */
    uint32_t         phase;       /* 20-bit Phase Accumulator                 */
    uint32_t         phase_step;  /* Per-sample phase increment               */
    yd_ym_eg_state_t eg_state;    /* Current ADSR stage                       */
    int32_t          env_level;   /* 10-bit Attenuation (0 = max, 0x3FF = off)*/
    bool             key_on;      /* Operator Key-On gate                     */
} yd_ym2612_op_t;

/* ==========================================================================
 * Single FM Channel State (`yd_ym2612_channel_t`)
 * ========================================================================== */
typedef struct yd_ym2612_channel {
    yd_ym2612_op_t   ops[YD_YM2612_NUM_OPERATORS];

    uint16_t         f_num;       /* 11-bit Frequency Number (0..2047)        */
    uint8_t          block;       /* 3-bit Octave / Block (0..7)              */
    uint8_t          fnum_hi_latch;/* Latched high byte written to 0xA4..0xA6 */

    uint8_t          alg;         /* 3-bit FM Algorithm (0..7)                */
    uint8_t          fb;          /* 3-bit Operator 1 Feedback Level (0..7)   */
    int32_t          op1_out[2];  /* Previous 2 outputs of Operator 1 for FB  */

    bool             pan_l;       /* Left Stereo Output Enable (Bit 7 of 0xB4)*/
    bool             pan_r;       /* Right Stereo Output Enable(Bit 6 of 0xB4)*/
    uint8_t          ams;         /* Amplitude Modulation Sensitivity         */
    uint8_t          fms;         /* Frequency Modulation Sensitivity         */
} yd_ym2612_channel_t;

/* ==========================================================================
 * Yamaha YM2612 Chip State Structure (`yd_ym2612_t`)
 * ========================================================================== */
typedef struct yd_ym2612 {
    /* Raw Register Banks (Bank 0: Port 0/1, Bank 1: Port 2/3) */
    uint8_t             regs[2][256];
    uint8_t             addr_latch[2];

    /* 6 FM Channels */
    yd_ym2612_channel_t channels[YD_YM2612_NUM_CHANNELS];

    /* Channel 6 8-bit PCM DAC State (Registers 0x2A & 0x2B) */
    uint8_t             dac_data;     /* 0x2A: 8-bit unsigned PCM sample (0x80=center) */
    bool                dac_enabled;  /* 0x2B bit 7: true = Ch6 outputs DAC instead of FM */

    /* LFO & Timers (Registers 0x22, 0x24..0x27) */
    bool                lfo_enabled;
    uint8_t             lfo_freq;
    uint16_t            timer_a_reg;
    uint8_t             timer_b_reg;
    uint8_t             timer_ctrl;
    int32_t             timer_a_cnt;
    int32_t             timer_b_cnt;
    uint8_t             status;       /* Bit 0: Timer A overflow, Bit 1: Timer B overflow */
    uint8_t             ch3_mode;     /* Channel 3 Special Mode (R27 bits 7..6) */

    /* Timing & Audio Synthesis State */
    uint32_t            clock_hz;     /* M68K Master Clock (7670453 NTSC / 7600489 PAL) */
    uint32_t            sample_rate;  /* Output PCM sample rate (e.g. 44100 Hz) */
    uint32_t            step_lut[8];  /* Block 0..7 Q20 phase step LUT for 7.670453 MHz */
    uint16_t            ch3_fnum[3];  /* Ch3 Special Mode F-Num (0xA8=Op3, 0xA9=Op1, 0xAA=Op2) */
    uint8_t             ch3_block[3]; /* Ch3 Special Mode Block (0xAC=Op3, 0xAD=Op1, 0xAE=Op2) */
    uint8_t             ch3_latch[3]; /* Ch3 Special Mode MSB latches (0xAC..0xAE) */
    uint64_t            phase_accum;  /* Fixed-point accumulator for M68K -> PCM rate */
    uint32_t            env_tick;     /* Envelope update divider */

    /* Output Stereo PCM Buffer (Interleaved L, R) */
    int16_t             sample_buffer[YD_YM2612_MAX_SAMPLES * 2u];
    uint32_t            sample_count;
} yd_ym2612_t;

/* ==========================================================================
 * YM2612 Public API
 * ========================================================================== */

/**
 * Initialize a YM2612 instance with the given M68K clock and output sample rate.
 */
void yd_ym2612_init(yd_ym2612_t *ym, uint32_t clock_hz, uint32_t sample_rate);

/**
 * Reset all YM2612 registers, operators, channels, DAC, and timers.
 */
void yd_ym2612_reset(yd_ym2612_t *ym);

/**
 * Update the YM2612 master clock and output audio sample rate.
 */
void yd_ym2612_set_clock(yd_ym2612_t *ym, uint32_t clock_hz, uint32_t sample_rate);

/**
 * Write a byte to one of the 4 YM2612 bus ports (`port` 0..3 corresponding to
 * `0xA04000` .. `0xA04003`).
 */
void yd_ym2612_write(yd_ym2612_t *ym, uint8_t port, uint8_t val);

/**
 * Read the YM2612 Status Register (`0xA04000`).
 */
uint8_t yd_ym2612_read_status(const yd_ym2612_t *ym);

/**
 * Reset the per-frame stereo sample counter at the start of a video frame.
 */
void yd_ym2612_begin_frame(yd_ym2612_t *ym);

/**
 * Advance the YM2612 synthesizer by `m68k_cycles` clocks, updating timers and
 * generating 16-bit signed stereo PCM samples into `sample_buffer`.
 */
void yd_ym2612_step_cycles(yd_ym2612_t *ym, int m68k_cycles);

/**
 * Mix the YM2612 stereo samples generated during the current frame into an
 * existing interleaved 16-bit stereo buffer (`dst_pcm`, with clamping).
 */
void yd_ym2612_mix_into(const yd_ym2612_t *ym, int16_t *dst_pcm, uint32_t num_stereo_samples);

#ifdef __cplusplus
}
#endif

#endif /* YD_CORE_YM2612_H */
