#ifndef YD_CORE_PSG_H
#define YD_CORE_PSG_H

#include <stdint.h>
#include <stdbool.h>
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

/* ==========================================================================
 * SEGA SN76489 PSG (Programmable Sound Generator) Constants
 * ========================================================================== */
#define YD_PSG_DEFAULT_SAMPLE_RATE  44100u
#define YD_PSG_MAX_SAMPLES_PER_FRAME 2048u  /* Stereo frames (L+R pairs) capacity */
#define YD_PSG_CLOCK_DIVIDER        16u     /* Z80 clock / 16 = ~223,721.5 Hz PSG clock */

/* ==========================================================================
 * SN76489 PSG State Structure
 * ========================================================================== */
typedef struct yd_psg {
    /* 3 Square-Wave Tone Channels (10-bit period) + 1 Noise Channel */
    uint16_t tone_reg[3];         /* 10-bit frequency period (0..1023) */
    int16_t  tone_counter[3];     /* 10-bit down-counters */
    int8_t   tone_polarity[3];    /* Output polarity (+1 or -1) */

    /* Noise Channel State (Channel 3) */
    uint8_t  noise_reg;           /* Bit 2: White(1)/Periodic(0), Bits 1-0: Shift rate */
    int16_t  noise_counter;       /* Down-counter for noise clock */
    int8_t   noise_polarity;      /* Flip-flop driving LFSR shifts */
    uint16_t lfsr;                /* 16-bit SEGA LFSR (taps at bit 0 and bit 3) */

    /* 4-bit Volume Attenuation Registers (0 = Max Volume, 15 = Silent) */
    uint8_t  volume[4];

    /* Command Latch State */
    uint8_t  latched_chan;        /* Currently latched channel (0..3) */
    bool     latched_is_volume;   /* True if volume register is latched, false if tone/noise */

    /* Game Gear Stereo Panning Control (Port 0x06, default 0xFF = all L+R) */
    uint8_t  stereo_reg;

    /* Audio Output Resampler State */
    uint32_t cpu_clock_hz;        /* Master Z80 clock (3579545 NTSC / 3546895 PAL) */
    uint32_t sample_rate;         /* Target PCM sample rate (e.g., 44100 or 48000 Hz) */
    uint32_t psg_cycle_accum;     /* T-state accumulator for 1/16 PSG clock divider */
    uint64_t sample_phase_accum;  /* Fixed-point accumulator for PCM output rate */

    /* Stereo 16-bit Signed Interleaved PCM Buffer (L, R, L, R...) */
    int16_t  sample_buffer[YD_PSG_MAX_SAMPLES_PER_FRAME * 2u];
    uint32_t sample_count;        /* Number of stereo sample pairs generated in current frame */
} yd_psg_t;

/* ==========================================================================
 * PSG Public API
 * ========================================================================== */

/**
 * Initialize the SN76489 PSG synthesizer with the given Z80 clock and PCM sample rate.
 */
void yd_psg_init(yd_psg_t *psg, uint32_t cpu_clock_hz, uint32_t sample_rate);

/**
 * Reset all PSG channels, volumes (to 0x0F silent), LFSR, and stereo mask.
 */
void yd_psg_reset(yd_psg_t *psg);

/**
 * Update the Z80 clock frequency and/or output PCM sample rate.
 */
void yd_psg_set_clock(yd_psg_t *psg, uint32_t cpu_clock_hz, uint32_t sample_rate);

/**
 * Write a command or data byte to the SN76489 PSG (Ports 0x7E / 0x7F).
 */
void yd_psg_write(yd_psg_t *psg, uint8_t val);

/**
 * Write to the Game Gear Stereo Panning Register (Port 0x06).
 * Bits 7..4 enable Left output for Ch3..Ch0; Bits 3..0 enable Right output for Ch3..Ch0.
 */
void yd_psg_write_stereo(yd_psg_t *psg, uint8_t val);

/**
 * Clear the internal PCM sample buffer at the beginning of a new video frame.
 */
void yd_psg_begin_frame(yd_psg_t *psg);

/**
 * Advance the PSG synthesizer by `cpu_cycles` Z80 T-states and append generated
 * 16-bit stereo PCM sample pairs to `psg->sample_buffer`.
 */
void yd_psg_step_cycles(yd_psg_t *psg, int cpu_cycles);

#ifdef __cplusplus
}
#endif

#endif /* YD_CORE_PSG_H */
