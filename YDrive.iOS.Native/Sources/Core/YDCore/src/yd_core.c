#include "yd_core.h"
#include <stdlib.h>
#include <string.h>

/* ==========================================================================
 * Pointer-Free Binary Save State Blob ("YDSS" Format v2)
 * ========================================================================== */
typedef struct yd_save_state_blob {
    /* Header */
    uint32_t magic;
    uint32_t version;
    uint32_t blob_size;
    uint32_t checksum;

    /* Core Metadata & Timing */
    uint32_t system;
    uint32_t region;
    uint64_t frame_count;
    int32_t  cycle_deficit;

    /* Z80 CPU State (Used as main CPU in SMS/GG and sound co-processor in Genesis) */
    uint16_t af, bc, de, hl;
    uint16_t af_alt, bc_alt, de_alt, hl_alt;
    uint16_t ix, iy, sp, pc, wz;
    uint8_t  i, r;
    uint8_t  iff1, iff2, im, halted, ei_delay;
    uint8_t  int_line, nmi_pending, int_vector;
    uint64_t total_cycles;

    /* 8-bit SMS/GG MMU & Mapper State */
    uint32_t mapper_type;
    uint8_t  reg_ctrl;
    uint8_t  reg_slot[3];
    uint8_t  msx_slot[4];
    uint8_t  cm_ram_enabled;
    uint8_t  cart_ram_dirty;
    uint8_t  sys_ram[YD_MMU_SYS_RAM_SIZE];
    uint8_t  cart_ram[YD_MMU_CART_RAM_SIZE];

    /* 8-bit SMS/GG VDP State */
    uint8_t  vram[YD_VDP_VRAM_SIZE];
    uint8_t  cram[YD_VDP_CRAM_SIZE_GG];
    uint8_t  vdp_regs[YD_VDP_NUM_REGS];
    uint16_t addr_reg;
    uint8_t  code_reg;
    uint8_t  read_buffer;
    uint8_t  cmd_low_byte;
    uint8_t  cram_latch;
    uint8_t  first_byte_latched;
    uint8_t  vdp_status;
    uint8_t  line_irq_pending;
    uint8_t  line_counter;
    uint8_t  v_scroll_latch;
    uint16_t current_scanline;
    uint8_t  v_counter;
    uint8_t  h_counter;
    uint16_t active_height;

    /* SN76489 PSG State */
    uint16_t tone_reg[3];
    int16_t  tone_counter[3];
    int8_t   tone_polarity[3];
    uint8_t  noise_reg;
    int16_t  noise_counter;
    int8_t   noise_polarity;
    uint16_t lfsr;
    uint8_t  volume[4];
    uint8_t  latched_chan;
    uint8_t  latched_is_volume;
    uint8_t  stereo_reg;
    uint32_t psg_cycle_accum;
    uint64_t sample_phase_accum;

    /* 8-bit SMS/GG I/O State */
    uint8_t  pad_state[2];
    uint8_t  mem_ctrl;
    uint8_t  io_ctrl;
    uint8_t  gg_regs[7];
    uint8_t  last_psg_byte;

    /* 16/32-bit Genesis Motorola 68000 CPU State */
    uint32_t md_d[8];
    uint32_t md_a[8];
    uint32_t md_usp;
    uint32_t md_ssp;
    uint32_t md_pc;
    uint32_t md_ppc;
    uint16_t md_ir;
    uint16_t md_sr;
    uint8_t  md_stopped;
    uint8_t  md_halted;
    uint8_t  md_trace_armed;
    uint8_t  md_int_level;
    uint32_t md_last_vector;
    uint64_t md_total_cycles;

    /* Genesis MMU, RAM, Z80 RAM, SRAM & 6-Button I/O State */
    uint8_t  md_work_ram[YD_MD_WORK_RAM_SIZE];
    uint8_t  md_z80_ram[YD_MD_Z80_RAM_SIZE];
    uint8_t  md_sram[YD_MD_SRAM_SIZE];
    uint8_t  md_sram_reg;
    uint8_t  md_sram_enabled;
    uint8_t  md_sram_write_protect;
    uint8_t  md_sram_dirty;
    uint8_t  md_z80_busreq;
    uint8_t  md_z80_reset;
    uint32_t md_z80_bank_addr;
    uint8_t  md_ym2612_regs[4];
    uint8_t  md_version_reg;
    uint8_t  md_io_data[3];
    uint8_t  md_io_ctrl[3];
    uint8_t  md_io_raw[16];
    uint16_t md_pad_state[2];
    uint8_t  md_pad_th_counter[2];
    uint8_t  md_pad_timeout[2];
    uint8_t  md_six_button_enabled;
    uint8_t  md_tmss_reg[4];

    /* Genesis Mode 5 VDP State */
    uint8_t  md_vram[YD_MD_VDP_VRAM_SIZE];
    uint16_t md_cram[YD_MD_VDP_CRAM_WORDS];
    uint16_t md_vsram[YD_MD_VDP_VSRAM_WORDS];
    uint8_t  md_vdp_regs[YD_MD_VDP_NUM_REGS];
    uint16_t md_vdp_addr_reg;
    uint8_t  md_vdp_code_reg;
    uint8_t  md_vdp_pending_second_word;
    uint8_t  md_vdp_dma_fill_pending;
    uint16_t md_vdp_read_buffer;
    uint16_t md_vdp_status;
    uint8_t  md_vdp_h_int_counter;
    uint8_t  md_vdp_h_int_pending;
    uint8_t  md_vdp_v_int_pending;
    uint16_t md_vdp_current_scanline;
    uint8_t  md_vdp_v_counter;
    uint8_t  md_vdp_h_counter;
    uint16_t md_vdp_active_width;
    uint16_t md_vdp_active_height;

    /* Genesis Yamaha YM2612 FM & DAC State */
    uint8_t             ym_regs[2][256];
    uint8_t             ym_addr_latch[2];
    yd_ym2612_channel_t ym_channels[YD_YM2612_NUM_CHANNELS];
    uint8_t             ym_dac_data;
    uint8_t             ym_dac_enabled;
    uint8_t             ym_lfo_enabled;
    uint8_t             ym_lfo_freq;
    uint16_t            ym_timer_a_reg;
    uint8_t             ym_timer_b_reg;
    uint8_t             ym_timer_ctrl;
    int32_t             ym_timer_a_cnt;
    int32_t             ym_timer_b_cnt;
    uint8_t             ym_status;
    uint8_t             ym_ch3_mode;
    uint64_t            ym_phase_accum;
    uint32_t            ym_env_tick;
} yd_save_state_blob_t;

static uint32_t yd_compute_fnv1a(const uint8_t *data, size_t len) {
    uint32_t hash = 2166136261u;
    for (size_t i = 0; i < len; i++) {
        hash ^= data[i];
        hash *= 16777619u;
    }
    return hash;
}

/* ==========================================================================
 * Core Lifecycle & Subsystem Wiring
 * ========================================================================== */

static uint8_t yd_md_sound_ym_read_cb(void *ctx, uint8_t port) {
    yd_core_t *core = (yd_core_t *)ctx;
    (void)port;
    return yd_ym2612_read_status(&core->ym2612);
}

static void yd_md_sound_ym_write_cb(void *ctx, uint8_t port, uint8_t val) {
    yd_core_t *core = (yd_core_t *)ctx;
    yd_ym2612_write(&core->ym2612, port, val);
}

static void yd_md_sound_psg_write_cb(void *ctx, uint8_t val) {
    yd_core_t *core = (yd_core_t *)ctx;
    yd_psg_write(&core->psg, val);
}

void yd_core_init(yd_core_t *core) {
    if (!core) {
        return;
    }
    memset(core, 0, sizeof(*core));

    core->system = YD_SYSTEM_SMS;
    core->region = YD_REGION_NTSC;

    /* 1. Initialize 8-bit SMS / Game Gear Subsystem */
    yd_mmu_init(&core->mmu);
    yd_vdp_init(&core->vdp);
    yd_psg_init(&core->psg, YD_SMS_CPU_CLOCK_NTSC, YD_PSG_DEFAULT_SAMPLE_RATE);
    yd_io_init(&core->io, &core->vdp, &core->psg, &core->cpu);
    yd_io_bind_mmu(&core->io, &core->mmu);

    z80_bus_t zbus;
    yd_mmu_bind_z80_bus(&core->mmu, &zbus);
    z80_init(&core->cpu, &zbus);
    z80_reset_sms_post_bios(&core->cpu);

    /* 2. Initialize 16/32-bit SEGA Genesis / Mega Drive Subsystem */
    yd_md_mmu_init(&core->md_mmu);
    yd_md_vdp_init(&core->md_vdp);
    yd_ym2612_init(&core->ym2612, YD_MD_CPU_CLOCK_NTSC, YD_PSG_DEFAULT_SAMPLE_RATE);

    m68k_bus_t mbus;
    yd_md_mmu_bind_m68k_bus(&core->md_mmu, &mbus, &core->md_cpu);
    m68k_init(&core->md_cpu, &mbus);

    /* Ensure VDP has pointer to persistent core->md_cpu.bus */
    yd_md_vdp_attach_m68k(&core->md_vdp, &core->md_cpu.bus, &core->md_cpu);

    yd_md_vdp_handlers_t md_vdp_handlers;
    yd_md_vdp_bind_mmu_handlers(&core->md_vdp, &md_vdp_handlers);
    yd_md_mmu_set_vdp_handlers(&core->md_mmu, &md_vdp_handlers);

    yd_md_sound_handlers_t md_sound_handlers;
    md_sound_handlers.ctx       = core;
    md_sound_handlers.ym_read   = yd_md_sound_ym_read_cb;
    md_sound_handlers.ym_write  = yd_md_sound_ym_write_cb;
    md_sound_handlers.psg_write = yd_md_sound_psg_write_cb;
    yd_md_mmu_set_sound_handlers(&core->md_mmu, &md_sound_handlers);
}

yd_core_t *yd_core_create(void) {
    yd_core_t *core = (yd_core_t *)malloc(sizeof(yd_core_t));
    if (!core) {
        return NULL;
    }
    yd_core_init(core);
    return core;
}

void yd_core_destroy(yd_core_t *core) {
    if (!core) {
        return;
    }
    yd_mmu_destroy(&core->mmu);
    yd_md_mmu_destroy(&core->md_mmu);
    free(core);
}

void yd_core_set_system(yd_core_t *core, yd_system_type_t system, yd_region_t region) {
    if (!core) {
        return;
    }
    core->system          = system;
    core->region          = region;
    core->io.is_game_gear = (system == YD_SYSTEM_GG);

    uint32_t clk    = (region == YD_REGION_PAL) ? YD_SMS_CPU_CLOCK_PAL : YD_SMS_CPU_CLOCK_NTSC;
    uint32_t md_clk = (region == YD_REGION_PAL) ? YD_MD_CPU_CLOCK_PAL  : YD_MD_CPU_CLOCK_NTSC;
    yd_psg_set_clock(&core->psg, clk, core->psg.sample_rate);
    yd_ym2612_set_clock(&core->ym2612, md_clk, core->psg.sample_rate);

    yd_vdp_set_config(&core->vdp,
                      (system == YD_SYSTEM_GG),
                      (region == YD_REGION_PAL));

    yd_md_mmu_set_region(&core->md_mmu, true, (region == YD_REGION_PAL));
    yd_md_vdp_set_pal(&core->md_vdp, (region == YD_REGION_PAL));

    /* Bind Z80 bus either to Genesis sound subsystem or 8-bit SMS/GG MMU */
    if (system == YD_SYSTEM_MD) {
        yd_md_mmu_bind_z80_bus(&core->md_mmu, &core->cpu.bus, &core->cpu);
    } else {
        yd_mmu_bind_z80_bus(&core->mmu, &core->cpu.bus);
    }
}

void yd_core_set_audio_sample_rate(yd_core_t *core, uint32_t sample_rate) {
    if (!core || sample_rate == 0u) {
        return;
    }
    yd_psg_set_clock(&core->psg, core->psg.cpu_clock_hz, sample_rate);
    yd_ym2612_set_clock(&core->ym2612, core->ym2612.clock_hz, sample_rate);
}

/* ==========================================================================
 * Automatic Console Detection (Genesis vs Master System vs Game Gear)
 * ========================================================================== */

yd_system_type_t yd_core_detect_system(const uint8_t *rom_data, size_t rom_size) {
    if (!rom_data || rom_size < 0x200u) {
        return YD_SYSTEM_SMS;
    }

    /* 1. Check for Super Magic Drive (.smd) 512-byte interleaved header */
    if (rom_size > 512u && ((rom_size - 512u) % 16384u) == 0u) {
        if (rom_data[8] == 0xAAu && rom_data[9] == 0xBBu && rom_data[10] == 0x06u) {
            return YD_SYSTEM_MD;
        }
    }

    /* 2. Check for "SEGA MEGA DRIVE" or "SEGA GENESIS" at 0x000100 (or 0x000300 with copier hdr) */
    static const size_t md_offsets[2] = { 0x0100u, 0x0300u };
    for (int i = 0; i < 2; i++) {
        size_t off = md_offsets[i];
        if (rom_size >= off + 16u) {
            if (memcmp(rom_data + off, "SEGA MEGA DRIVE", 15u) == 0 ||
                memcmp(rom_data + off, "SEGA GENESIS", 12u) == 0 ||
                memcmp(rom_data + off, "SEGA 32X", 8u) == 0 ||
                memcmp(rom_data + off, "SEGA EVERDRIVE", 14u) == 0) {
                return YD_SYSTEM_MD;
            }
        }
    }

    /* 3. Check SMS / Game Gear "TMR SEGA" header for region nibble (5, 6, 7 = Game Gear) */
    size_t        hdr_base = ((rom_size & 0x3FFu) == 0x200u) ? 0x200u : 0u;
    const uint8_t *body    = rom_data + hdr_base;
    size_t         bsize   = rom_size - hdr_base;

    static const size_t tmr_offsets[3] = { 0x7FF0u, 0x3FF0u, 0x1FF0u };
    for (int i = 0; i < 3; i++) {
        size_t off = tmr_offsets[i];
        if (bsize >= off + 16u && memcmp(body + off, "TMR SEGA", 8u) == 0) {
            uint8_t region_code = (uint8_t)(body[off + 15u] >> 4);
            if (region_code == 5u || region_code == 6u || region_code == 7u) {
                return YD_SYSTEM_GG;
            }
            return YD_SYSTEM_SMS;
        }
    }

    return YD_SYSTEM_SMS;
}

bool yd_core_load_rom(yd_core_t *core, const uint8_t *rom_data, size_t rom_size) {
    if (!core || !rom_data || rom_size == 0) {
        return false;
    }

    yd_system_type_t detected = yd_core_detect_system(rom_data, rom_size);
    if (detected == YD_SYSTEM_MD || core->system == YD_SYSTEM_MD) {
        yd_core_set_system(core, YD_SYSTEM_MD, core->region);
        if (!yd_md_mmu_load_rom(&core->md_mmu, rom_data, rom_size)) {
            return false;
        }
        core->rom_loaded = true;
        yd_core_reset(core);
        return true;
    }

    if (core->system != YD_SYSTEM_GG && detected == YD_SYSTEM_GG) {
        yd_core_set_system(core, YD_SYSTEM_GG, core->region);
    }

    if (!yd_mmu_load_rom(&core->mmu, rom_data, rom_size)) {
        return false;
    }
    core->rom_loaded = true;
    yd_core_reset(core);
    return true;
}

void yd_core_reset(yd_core_t *core) {
    if (!core) {
        return;
    }

    if (core->system == YD_SYSTEM_MD) {
        yd_md_mmu_reset(&core->md_mmu);
        memset(core->md_mmu.z80_ram, 0, 0x2000u);
        core->md_mmu.z80_bank_addr = 0u;
        core->md_mmu.z80_busreq    = true;
        core->md_mmu.z80_reset     = false;
        yd_md_vdp_reset(&core->md_vdp);
        yd_ym2612_reset(&core->ym2612);
        yd_psg_reset(&core->psg);
        m68k_reset(&core->md_cpu);
        z80_reset(&core->cpu);
        core->cpu.im = 1u;
    } else {
        yd_mmu_reset(&core->mmu);
        yd_vdp_reset(&core->vdp);
        yd_psg_reset(&core->psg);
        yd_io_reset(&core->io);
        z80_reset_sms_post_bios(&core->cpu);
    }

    core->cycle_deficit = 0;
    core->frame_count   = 0u;
}

int yd_core_step(yd_core_t *core) {
    if (!core) {
        return 0;
    }
    if (core->system == YD_SYSTEM_MD) {
        int mcyc = m68k_step(&core->md_cpu);
        yd_ym2612_step_cycles(&core->ym2612, mcyc);
        return mcyc;
    }
    int cyc = z80_step(&core->cpu);
    yd_psg_step_cycles(&core->psg, cyc);
    return cyc;
}

int yd_core_run_frame(yd_core_t *core) {
    if (!core) {
        return 0;
    }

    yd_psg_begin_frame(&core->psg);

    /* ======================================================================
     * SEGA Genesis / Mega Drive Frame Execution (M68K + Mode 5 VDP + YM2612 + PSG)
     * ====================================================================== */
    if (core->system == YD_SYSTEM_MD) {
        yd_ym2612_begin_frame(&core->ym2612);

        uint16_t total_lines = (core->region == YD_REGION_PAL)
                               ? YD_MD_SCANLINES_PAL_TOTAL
                               : YD_MD_SCANLINES_NTSC_TOTAL;
        int frame_executed = 0;

        for (uint16_t line = 0; line < total_lines; line++) {
            yd_md_mmu_step_pad_timeout(&core->md_mmu);

            if (line >= core->md_vdp.active_height) {
                yd_md_vdp_step_scanline(&core->md_vdp, line);
            } else {
                core->md_vdp.current_scanline = line;
                core->md_vdp.v_counter        = (line <= 0xEAu) ? (uint8_t)line : (uint8_t)(line - 6u);
                core->md_vdp.status          &= (uint16_t)(0xFFFFu ^ YD_MD_VDP_STATUS_VBLK);
                if (line == 0u) {
                    core->md_vdp.v_int_pending = false;
                }
            }

            z80_set_int_line(&core->cpu, (line == core->md_vdp.active_height));

            int  line_target    = YD_MD_CYCLES_PER_SCANLINE - core->cycle_deficit;
            int  hblank_trigger = (line_target * 400) / YD_MD_CYCLES_PER_SCANLINE;
            int  line_exec      = 0;
            int  z80_line_exec  = 0;
            bool hblank_entered = false;

            core->md_vdp.status &= (uint16_t)(0xFFFFu ^ YD_MD_VDP_STATUS_HBLK);

            while (line_exec < line_target) {
                if (!hblank_entered && line_exec >= hblank_trigger) {
                    hblank_entered = true;
                    core->md_vdp.status |= YD_MD_VDP_STATUS_HBLK;
                    if (line < core->md_vdp.active_height) {
                        yd_md_vdp_render_scanline(&core->md_vdp, line);
                        yd_md_vdp_step_scanline(&core->md_vdp, line);
                    }
                }

                core->md_vdp.h_counter = (uint8_t)(((uint32_t)line_exec * 171u) / YD_MD_CYCLES_PER_SCANLINE);
                int step_cyc = m68k_step(&core->md_cpu);
                line_exec   += step_cyc;

                /* Interleave Genesis Z80 sound co-processor & SN76489 PSG in lockstep with M68K */
                int z80_target = (line_exec * YD_SMS_CYCLES_PER_SCANLINE) / YD_MD_CYCLES_PER_SCANLINE;
                if (z80_target > YD_SMS_CYCLES_PER_SCANLINE) {
                    z80_target = YD_SMS_CYCLES_PER_SCANLINE;
                }
                int z80_prev = z80_line_exec;
                while (z80_line_exec < z80_target) {
                    if (!core->md_mmu.z80_busreq && core->md_mmu.z80_reset) {
                        bool prev_iff1 = core->cpu.iff1;
                        int  zcyc      = z80_step(&core->cpu);
                        if (core->cpu.int_line && prev_iff1 && !core->cpu.iff1) {
                            z80_set_int_line(&core->cpu, false);
                        }
                        z80_line_exec += zcyc;
                    } else {
                        z80_line_exec = z80_target;
                    }
                }
                if (z80_line_exec > z80_prev) {
                    yd_psg_step_cycles(&core->psg, z80_line_exec - z80_prev);
                }

                /* Step YM2612 FM/DAC immediately per instruction so 0x2A PCM writes have zero lag */
                yd_ym2612_step_cycles(&core->ym2612, step_cyc);
            }

            if (!hblank_entered) {
                core->md_vdp.status |= YD_MD_VDP_STATUS_HBLK;
                if (line < core->md_vdp.active_height) {
                    yd_md_vdp_render_scanline(&core->md_vdp, line);
                    yd_md_vdp_step_scanline(&core->md_vdp, line);
                }
            }
            core->md_vdp.status &= (uint16_t)(0xFFFFu ^ YD_MD_VDP_STATUS_HBLK);
            z80_set_int_line(&core->cpu, false);

            if (z80_line_exec < YD_SMS_CYCLES_PER_SCANLINE) {
                yd_psg_step_cycles(&core->psg, YD_SMS_CYCLES_PER_SCANLINE - z80_line_exec);
            }

            core->cycle_deficit = line_exec - line_target;
            frame_executed     += line_exec;
        }

        /* Mix YM2612 stereo PCM output into the frame's master stereo audio buffer */
        yd_ym2612_mix_into(&core->ym2612, core->psg.sample_buffer, core->psg.sample_count);

        core->frame_count++;
        return frame_executed;
    }

    /* ======================================================================
     * SEGA Master System / Game Gear Frame Execution (Z80 + Mode 4 VDP)
     * ====================================================================== */
    uint16_t total_lines = (core->region == YD_REGION_PAL)
                           ? YD_SMS_SCANLINES_PAL
                           : YD_SMS_SCANLINES_NTSC;

    int frame_executed = 0;

    for (uint16_t line = 0; line < total_lines; line++) {
        if (line < core->vdp.active_height) {
            yd_vdp_render_scanline(&core->vdp, line);
        }

        yd_vdp_step_scanline(&core->vdp, line);
        z80_set_int_line(&core->cpu, yd_vdp_irq_asserted(&core->vdp));

        int line_target = YD_SMS_CYCLES_PER_SCANLINE - core->cycle_deficit;
        int line_exec   = 0;

        while (line_exec < line_target) {
            core->vdp.h_counter = (uint8_t)(((uint32_t)line_exec * 171u) / YD_SMS_CYCLES_PER_SCANLINE);
            int step_cyc        = z80_step(&core->cpu);
            yd_psg_step_cycles(&core->psg, step_cyc);
            line_exec          += step_cyc;
        }

        core->cycle_deficit = line_exec - line_target;
        frame_executed     += line_exec;
    }

    core->frame_count++;
    return frame_executed;
}

/* ==========================================================================
 * Save State Serialization Implementation
 * ========================================================================== */

size_t yd_core_get_state_size(const yd_core_t *core) {
    (void)core;
    return sizeof(yd_save_state_blob_t);
}

bool yd_core_save_state(const yd_core_t *core, uint8_t *buffer, size_t size) {
    if (!core || !buffer || size < sizeof(yd_save_state_blob_t)) {
        return false;
    }

    yd_save_state_blob_t *blob = (yd_save_state_blob_t *)calloc(1u, sizeof(yd_save_state_blob_t));
    if (!blob) {
        return false;
    }

    blob->magic         = YD_STATE_MAGIC;
    blob->version       = YD_STATE_VERSION;
    blob->blob_size     = (uint32_t)sizeof(yd_save_state_blob_t);

    blob->system        = (uint32_t)core->system;
    blob->region        = (uint32_t)core->region;
    blob->frame_count   = core->frame_count;
    blob->cycle_deficit = core->cycle_deficit;

    /* Z80 CPU */
    blob->af           = core->cpu.af.pair;
    blob->bc           = core->cpu.bc.pair;
    blob->de           = core->cpu.de.pair;
    blob->hl           = core->cpu.hl.pair;
    blob->af_alt       = core->cpu.af_alt.pair;
    blob->bc_alt       = core->cpu.bc_alt.pair;
    blob->de_alt       = core->cpu.de_alt.pair;
    blob->hl_alt       = core->cpu.hl_alt.pair;
    blob->ix           = core->cpu.ix.pair;
    blob->iy           = core->cpu.iy.pair;
    blob->sp           = core->cpu.sp;
    blob->pc           = core->cpu.pc;
    blob->wz           = core->cpu.wz;
    blob->i            = core->cpu.i;
    blob->r            = core->cpu.r;
    blob->iff1         = core->cpu.iff1 ? 1u : 0u;
    blob->iff2         = core->cpu.iff2 ? 1u : 0u;
    blob->im           = core->cpu.im;
    blob->halted       = core->cpu.halted ? 1u : 0u;
    blob->ei_delay     = core->cpu.ei_delay ? 1u : 0u;
    blob->int_line     = core->cpu.int_line ? 1u : 0u;
    blob->nmi_pending  = core->cpu.nmi_pending ? 1u : 0u;
    blob->int_vector   = core->cpu.int_vector;
    blob->total_cycles = core->cpu.total_cycles;

    /* 8-bit SMS/GG MMU */
    blob->mapper_type    = (uint32_t)core->mmu.mapper_type;
    blob->reg_ctrl       = core->mmu.reg_ctrl;
    memcpy(blob->reg_slot, core->mmu.reg_slot, sizeof(blob->reg_slot));
    memcpy(blob->msx_slot, core->mmu.msx_slot, sizeof(blob->msx_slot));
    blob->cm_ram_enabled = core->mmu.cm_ram_enabled ? 1u : 0u;
    blob->cart_ram_dirty = core->mmu.cart_ram_dirty ? 1u : 0u;
    memcpy(blob->sys_ram, core->mmu.sys_ram, sizeof(blob->sys_ram));
    memcpy(blob->cart_ram, core->mmu.cart_ram, sizeof(blob->cart_ram));

    /* 8-bit SMS/GG VDP */
    memcpy(blob->vram, core->vdp.vram, sizeof(blob->vram));
    memcpy(blob->cram, core->vdp.cram, sizeof(blob->cram));
    memcpy(blob->vdp_regs, core->vdp.regs, sizeof(blob->vdp_regs));
    blob->addr_reg           = core->vdp.addr_reg;
    blob->code_reg           = core->vdp.code_reg;
    blob->read_buffer        = core->vdp.read_buffer;
    blob->cmd_low_byte       = core->vdp.cmd_low_byte;
    blob->cram_latch         = core->vdp.cram_latch;
    blob->first_byte_latched = core->vdp.first_byte_latched ? 1u : 0u;
    blob->vdp_status         = core->vdp.status;
    blob->line_irq_pending   = core->vdp.line_irq_pending ? 1u : 0u;
    blob->line_counter       = core->vdp.line_counter;
    blob->v_scroll_latch     = core->vdp.v_scroll_latch;
    blob->current_scanline   = core->vdp.current_scanline;
    blob->v_counter          = core->vdp.v_counter;
    blob->h_counter          = core->vdp.h_counter;
    blob->active_height      = core->vdp.active_height;

    /* SN76489 PSG */
    memcpy(blob->tone_reg, core->psg.tone_reg, sizeof(blob->tone_reg));
    memcpy(blob->tone_counter, core->psg.tone_counter, sizeof(blob->tone_counter));
    memcpy(blob->tone_polarity, core->psg.tone_polarity, sizeof(blob->tone_polarity));
    blob->noise_reg          = core->psg.noise_reg;
    blob->noise_counter      = core->psg.noise_counter;
    blob->noise_polarity     = core->psg.noise_polarity;
    blob->lfsr               = core->psg.lfsr;
    memcpy(blob->volume, core->psg.volume, sizeof(blob->volume));
    blob->latched_chan       = core->psg.latched_chan;
    blob->latched_is_volume  = core->psg.latched_is_volume ? 1u : 0u;
    blob->stereo_reg         = core->psg.stereo_reg;
    blob->psg_cycle_accum    = core->psg.psg_cycle_accum;
    blob->sample_phase_accum = core->psg.sample_phase_accum;

    /* 8-bit SMS/GG I/O */
    memcpy(blob->pad_state, core->io.pad_state, sizeof(blob->pad_state));
    blob->mem_ctrl      = core->io.mem_ctrl;
    blob->io_ctrl       = core->io.io_ctrl;
    memcpy(blob->gg_regs, core->io.gg_regs, sizeof(blob->gg_regs));
    blob->last_psg_byte = core->io.last_psg_byte;

    /* Genesis Motorola 68000 CPU */
    memcpy(blob->md_d, core->md_cpu.d, sizeof(blob->md_d));
    memcpy(blob->md_a, core->md_cpu.a, sizeof(blob->md_a));
    blob->md_usp          = core->md_cpu.usp;
    blob->md_ssp          = core->md_cpu.ssp;
    blob->md_pc           = core->md_cpu.pc;
    blob->md_ppc          = core->md_cpu.ppc;
    blob->md_ir           = core->md_cpu.ir;
    blob->md_sr           = core->md_cpu.sr;
    blob->md_stopped      = core->md_cpu.stopped ? 1u : 0u;
    blob->md_halted       = core->md_cpu.halted ? 1u : 0u;
    blob->md_trace_armed  = core->md_cpu.trace_armed ? 1u : 0u;
    blob->md_int_level    = core->md_cpu.int_level;
    blob->md_last_vector  = core->md_cpu.last_vector;
    blob->md_total_cycles = core->md_cpu.total_cycles;

    /* Genesis MMU, Work RAM, Z80 RAM, SRAM & 6-Button I/O */
    memcpy(blob->md_work_ram, core->md_mmu.work_ram, sizeof(blob->md_work_ram));
    memcpy(blob->md_z80_ram, core->md_mmu.z80_ram, sizeof(blob->md_z80_ram));
    memcpy(blob->md_sram, core->md_mmu.sram, sizeof(blob->md_sram));
    blob->md_sram_reg            = core->md_mmu.sram_reg;
    blob->md_sram_enabled        = core->md_mmu.sram_enabled ? 1u : 0u;
    blob->md_sram_write_protect  = core->md_mmu.sram_write_protect ? 1u : 0u;
    blob->md_sram_dirty          = core->md_mmu.sram_dirty ? 1u : 0u;
    blob->md_z80_busreq          = core->md_mmu.z80_busreq ? 1u : 0u;
    blob->md_z80_reset           = core->md_mmu.z80_reset ? 1u : 0u;
    blob->md_z80_bank_addr       = core->md_mmu.z80_bank_addr;
    memcpy(blob->md_ym2612_regs, core->md_mmu.ym2612_regs, sizeof(blob->md_ym2612_regs));
    blob->md_version_reg         = core->md_mmu.version_reg;
    memcpy(blob->md_io_data, core->md_mmu.io_data, sizeof(blob->md_io_data));
    memcpy(blob->md_io_ctrl, core->md_mmu.io_ctrl, sizeof(blob->md_io_ctrl));
    memcpy(blob->md_io_raw, core->md_mmu.io_raw, sizeof(blob->md_io_raw));
    memcpy(blob->md_pad_state, core->md_mmu.pad_state, sizeof(blob->md_pad_state));
    memcpy(blob->md_pad_th_counter, core->md_mmu.pad_th_counter, sizeof(blob->md_pad_th_counter));
    memcpy(blob->md_pad_timeout, core->md_mmu.pad_timeout, sizeof(blob->md_pad_timeout));
    blob->md_six_button_enabled  = core->md_mmu.six_button_enabled ? 1u : 0u;
    memcpy(blob->md_tmss_reg, core->md_mmu.tmss_reg, sizeof(blob->md_tmss_reg));

    /* Genesis Mode 5 VDP */
    memcpy(blob->md_vram, core->md_vdp.vram, sizeof(blob->md_vram));
    memcpy(blob->md_cram, core->md_vdp.cram, sizeof(blob->md_cram));
    memcpy(blob->md_vsram, core->md_vdp.vsram, sizeof(blob->md_vsram));
    memcpy(blob->md_vdp_regs, core->md_vdp.regs, sizeof(blob->md_vdp_regs));
    blob->md_vdp_addr_reg            = core->md_vdp.addr_reg;
    blob->md_vdp_code_reg            = core->md_vdp.code_reg;
    blob->md_vdp_pending_second_word = core->md_vdp.pending_second_word ? 1u : 0u;
    blob->md_vdp_dma_fill_pending    = core->md_vdp.dma_fill_pending ? 1u : 0u;
    blob->md_vdp_read_buffer         = core->md_vdp.read_buffer;
    blob->md_vdp_status              = core->md_vdp.status;
    blob->md_vdp_h_int_counter       = core->md_vdp.h_int_counter;
    blob->md_vdp_h_int_pending       = core->md_vdp.h_int_pending ? 1u : 0u;
    blob->md_vdp_v_int_pending       = core->md_vdp.v_int_pending ? 1u : 0u;
    blob->md_vdp_current_scanline    = core->md_vdp.current_scanline;
    blob->md_vdp_v_counter           = core->md_vdp.v_counter;
    blob->md_vdp_h_counter           = core->md_vdp.h_counter;
    blob->md_vdp_active_width        = core->md_vdp.active_width;
    blob->md_vdp_active_height       = core->md_vdp.active_height;

    /* Genesis Yamaha YM2612 */
    memcpy(blob->ym_regs, core->ym2612.regs, sizeof(blob->ym_regs));
    memcpy(blob->ym_addr_latch, core->ym2612.addr_latch, sizeof(blob->ym_addr_latch));
    memcpy(blob->ym_channels, core->ym2612.channels, sizeof(blob->ym_channels));
    blob->ym_dac_data    = core->ym2612.dac_data;
    blob->ym_dac_enabled = core->ym2612.dac_enabled ? 1u : 0u;
    blob->ym_lfo_enabled = core->ym2612.lfo_enabled ? 1u : 0u;
    blob->ym_lfo_freq    = core->ym2612.lfo_freq;
    blob->ym_timer_a_reg = core->ym2612.timer_a_reg;
    blob->ym_timer_b_reg = core->ym2612.timer_b_reg;
    blob->ym_timer_ctrl  = core->ym2612.timer_ctrl;
    blob->ym_timer_a_cnt = core->ym2612.timer_a_cnt;
    blob->ym_timer_b_cnt = core->ym2612.timer_b_cnt;
    blob->ym_status      = core->ym2612.status;
    blob->ym_ch3_mode    = core->ym2612.ch3_mode;
    blob->ym_phase_accum = core->ym2612.phase_accum;
    blob->ym_env_tick    = core->ym2612.env_tick;

    /* Compute FNV-1a checksum over everything after `checksum` field */
    size_t hdr_offset = offsetof(yd_save_state_blob_t, system);
    blob->checksum    = yd_compute_fnv1a(((const uint8_t *)blob) + hdr_offset,
                                         sizeof(*blob) - hdr_offset);

    memcpy(buffer, blob, sizeof(*blob));
    free(blob);
    return true;
}

bool yd_core_load_state(yd_core_t *core, const uint8_t *buffer, size_t size) {
    if (!core || !buffer || size < sizeof(yd_save_state_blob_t)) {
        return false;
    }

    yd_save_state_blob_t *blob = (yd_save_state_blob_t *)malloc(sizeof(yd_save_state_blob_t));
    if (!blob) {
        return false;
    }
    memcpy(blob, buffer, sizeof(*blob));

    if (blob->magic != YD_STATE_MAGIC ||
        blob->version != YD_STATE_VERSION ||
        blob->blob_size != (uint32_t)sizeof(yd_save_state_blob_t)) {
        free(blob);
        return false;
    }

    size_t   hdr_offset = offsetof(yd_save_state_blob_t, system);
    uint32_t expected   = yd_compute_fnv1a(((const uint8_t *)blob) + hdr_offset,
                                           sizeof(*blob) - hdr_offset);
    if (blob->checksum != expected) {
        free(blob);
        return false;
    }

    yd_core_set_system(core, (yd_system_type_t)blob->system, (yd_region_t)blob->region);
    core->frame_count   = blob->frame_count;
    core->cycle_deficit = blob->cycle_deficit;

    /* Restore Z80 CPU */
    core->cpu.af.pair      = blob->af;
    core->cpu.bc.pair      = blob->bc;
    core->cpu.de.pair      = blob->de;
    core->cpu.hl.pair      = blob->hl;
    core->cpu.af_alt.pair  = blob->af_alt;
    core->cpu.bc_alt.pair  = blob->bc_alt;
    core->cpu.de_alt.pair  = blob->de_alt;
    core->cpu.hl_alt.pair  = blob->hl_alt;
    core->cpu.ix.pair      = blob->ix;
    core->cpu.iy.pair      = blob->iy;
    core->cpu.sp           = blob->sp;
    core->cpu.pc           = blob->pc;
    core->cpu.wz           = blob->wz;
    core->cpu.i            = blob->i;
    core->cpu.r            = blob->r;
    core->cpu.iff1         = (blob->iff1 != 0u);
    core->cpu.iff2         = (blob->iff2 != 0u);
    core->cpu.im           = blob->im;
    core->cpu.halted       = (blob->halted != 0u);
    core->cpu.ei_delay     = (blob->ei_delay != 0u);
    core->cpu.int_line     = (blob->int_line != 0u);
    core->cpu.nmi_pending  = (blob->nmi_pending != 0u);
    core->cpu.int_vector   = blob->int_vector;
    core->cpu.total_cycles = blob->total_cycles;

    /* Restore 8-bit SMS/GG MMU & Rebind Cached Bank Pointers */
    core->mmu.mapper_type    = (yd_mapper_type_t)blob->mapper_type;
    core->mmu.reg_ctrl       = blob->reg_ctrl;
    memcpy(core->mmu.reg_slot, blob->reg_slot, sizeof(core->mmu.reg_slot));
    memcpy(core->mmu.msx_slot, blob->msx_slot, sizeof(core->mmu.msx_slot));
    core->mmu.cm_ram_enabled = (blob->cm_ram_enabled != 0u);
    core->mmu.cart_ram_dirty = (blob->cart_ram_dirty != 0u);
    memcpy(core->mmu.sys_ram, blob->sys_ram, sizeof(core->mmu.sys_ram));
    memcpy(core->mmu.cart_ram, blob->cart_ram, sizeof(core->mmu.cart_ram));
    yd_mmu_update_banks(&core->mmu);

    /* Restore 8-bit SMS/GG VDP & Rebuild Palette Cache */
    memcpy(core->vdp.vram, blob->vram, sizeof(core->vdp.vram));
    memcpy(core->vdp.cram, blob->cram, sizeof(core->vdp.cram));
    memcpy(core->vdp.regs, blob->vdp_regs, sizeof(core->vdp.regs));
    core->vdp.addr_reg           = blob->addr_reg;
    core->vdp.code_reg           = blob->code_reg;
    core->vdp.read_buffer        = blob->read_buffer;
    core->vdp.cmd_low_byte       = blob->cmd_low_byte;
    core->vdp.cram_latch         = blob->cram_latch;
    core->vdp.first_byte_latched = (blob->first_byte_latched != 0u);
    core->vdp.status             = blob->vdp_status;
    core->vdp.line_irq_pending   = (blob->line_irq_pending != 0u);
    core->vdp.line_counter       = blob->line_counter;
    core->vdp.v_scroll_latch     = blob->v_scroll_latch;
    core->vdp.current_scanline   = blob->current_scanline;
    core->vdp.v_counter          = blob->v_counter;
    core->vdp.h_counter          = blob->h_counter;
    core->vdp.active_height      = blob->active_height;
    yd_vdp_refresh_palette(&core->vdp);

    /* Restore SN76489 PSG */
    memcpy(core->psg.tone_reg, blob->tone_reg, sizeof(core->psg.tone_reg));
    memcpy(core->psg.tone_counter, blob->tone_counter, sizeof(core->psg.tone_counter));
    memcpy(core->psg.tone_polarity, blob->tone_polarity, sizeof(core->psg.tone_polarity));
    core->psg.noise_reg          = blob->noise_reg;
    core->psg.noise_counter      = blob->noise_counter;
    core->psg.noise_polarity     = blob->noise_polarity;
    core->psg.lfsr               = blob->lfsr;
    memcpy(core->psg.volume, blob->volume, sizeof(core->psg.volume));
    core->psg.latched_chan       = blob->latched_chan;
    core->psg.latched_is_volume  = (blob->latched_is_volume != 0u);
    core->psg.stereo_reg         = blob->stereo_reg;
    core->psg.psg_cycle_accum    = blob->psg_cycle_accum;
    core->psg.sample_phase_accum = blob->sample_phase_accum;

    /* Restore 8-bit SMS/GG I/O */
    memcpy(core->io.pad_state, blob->pad_state, sizeof(core->io.pad_state));
    core->io.mem_ctrl      = blob->mem_ctrl;
    core->io.io_ctrl       = blob->io_ctrl;
    memcpy(core->io.gg_regs, blob->gg_regs, sizeof(core->io.gg_regs));
    core->io.last_psg_byte = blob->last_psg_byte;

    /* Restore Genesis Motorola 68000 CPU */
    memcpy(core->md_cpu.d, blob->md_d, sizeof(core->md_cpu.d));
    memcpy(core->md_cpu.a, blob->md_a, sizeof(core->md_cpu.a));
    core->md_cpu.usp          = blob->md_usp;
    core->md_cpu.ssp          = blob->md_ssp;
    core->md_cpu.pc           = blob->md_pc;
    core->md_cpu.ppc          = blob->md_ppc;
    core->md_cpu.ir           = blob->md_ir;
    core->md_cpu.sr           = blob->md_sr;
    core->md_cpu.stopped      = (blob->md_stopped != 0u);
    core->md_cpu.halted       = (blob->md_halted != 0u);
    core->md_cpu.trace_armed  = (blob->md_trace_armed != 0u);
    core->md_cpu.int_level    = blob->md_int_level;
    core->md_cpu.last_vector  = blob->md_last_vector;
    core->md_cpu.total_cycles = blob->md_total_cycles;

    /* Restore Genesis MMU, Work RAM, Z80 RAM, SRAM & 6-Button I/O */
    memcpy(core->md_mmu.work_ram, blob->md_work_ram, sizeof(core->md_mmu.work_ram));
    memcpy(core->md_mmu.z80_ram, blob->md_z80_ram, sizeof(core->md_mmu.z80_ram));
    memcpy(core->md_mmu.sram, blob->md_sram, sizeof(core->md_mmu.sram));
    core->md_mmu.sram_reg           = blob->md_sram_reg;
    core->md_mmu.sram_enabled       = (blob->md_sram_enabled != 0u);
    core->md_mmu.sram_write_protect = (blob->md_sram_write_protect != 0u);
    core->md_mmu.sram_dirty         = (blob->md_sram_dirty != 0u);
    core->md_mmu.z80_busreq         = (blob->md_z80_busreq != 0u);
    core->md_mmu.z80_reset          = (blob->md_z80_reset != 0u);
    core->md_mmu.z80_bank_addr      = blob->md_z80_bank_addr;
    memcpy(core->md_mmu.ym2612_regs, blob->md_ym2612_regs, sizeof(core->md_mmu.ym2612_regs));
    core->md_mmu.version_reg        = blob->md_version_reg;
    memcpy(core->md_mmu.io_data, blob->md_io_data, sizeof(core->md_mmu.io_data));
    memcpy(core->md_mmu.io_ctrl, blob->md_io_ctrl, sizeof(core->md_mmu.io_ctrl));
    memcpy(core->md_mmu.io_raw, blob->md_io_raw, sizeof(core->md_mmu.io_raw));
    memcpy(core->md_mmu.pad_state, blob->md_pad_state, sizeof(core->md_mmu.pad_state));
    memcpy(core->md_mmu.pad_th_counter, blob->md_pad_th_counter, sizeof(core->md_mmu.pad_th_counter));
    memcpy(core->md_mmu.pad_timeout, blob->md_pad_timeout, sizeof(core->md_mmu.pad_timeout));
    core->md_mmu.six_button_enabled = (blob->md_six_button_enabled != 0u);
    memcpy(core->md_mmu.tmss_reg, blob->md_tmss_reg, sizeof(core->md_mmu.tmss_reg));

    /* Restore Genesis Mode 5 VDP & Rebuild Palette Caches */
    memcpy(core->md_vdp.vram, blob->md_vram, sizeof(core->md_vdp.vram));
    memcpy(core->md_vdp.cram, blob->md_cram, sizeof(core->md_vdp.cram));
    memcpy(core->md_vdp.vsram, blob->md_vsram, sizeof(core->md_vdp.vsram));
    memcpy(core->md_vdp.regs, blob->md_vdp_regs, sizeof(core->md_vdp.regs));
    core->md_vdp.addr_reg            = blob->md_vdp_addr_reg;
    core->md_vdp.code_reg            = blob->md_vdp_code_reg;
    core->md_vdp.pending_second_word = (blob->md_vdp_pending_second_word != 0u);
    core->md_vdp.dma_fill_pending    = (blob->md_vdp_dma_fill_pending != 0u);
    core->md_vdp.read_buffer         = blob->md_vdp_read_buffer;
    core->md_vdp.status              = blob->md_vdp_status;
    core->md_vdp.h_int_counter       = blob->md_vdp_h_int_counter;
    core->md_vdp.h_int_pending       = (blob->md_vdp_h_int_pending != 0u);
    core->md_vdp.v_int_pending       = (blob->md_vdp_v_int_pending != 0u);
    core->md_vdp.current_scanline    = blob->md_vdp_current_scanline;
    core->md_vdp.v_counter           = blob->md_vdp_v_counter;
    core->md_vdp.h_counter           = blob->md_vdp_h_counter;
    core->md_vdp.active_width        = blob->md_vdp_active_width;
    core->md_vdp.active_height       = blob->md_vdp_active_height;
    yd_md_vdp_refresh_palette(&core->md_vdp);

    /* Restore Genesis Yamaha YM2612 */
    memcpy(core->ym2612.regs, blob->ym_regs, sizeof(core->ym2612.regs));
    memcpy(core->ym2612.addr_latch, blob->ym_addr_latch, sizeof(core->ym2612.addr_latch));
    memcpy(core->ym2612.channels, blob->ym_channels, sizeof(core->ym2612.channels));
    core->ym2612.dac_data    = blob->ym_dac_data;
    core->ym2612.dac_enabled = (blob->ym_dac_enabled != 0u);
    core->ym2612.lfo_enabled = (blob->ym_lfo_enabled != 0u);
    core->ym2612.lfo_freq    = blob->ym_lfo_freq;
    core->ym2612.timer_a_reg = blob->ym_timer_a_reg;
    core->ym2612.timer_b_reg = blob->ym_timer_b_reg;
    core->ym2612.timer_ctrl  = blob->ym_timer_ctrl;
    core->ym2612.timer_a_cnt = blob->ym_timer_a_cnt;
    core->ym2612.timer_b_cnt = blob->ym_timer_b_cnt;
    core->ym2612.status      = blob->ym_status;
    core->ym2612.ch3_mode    = blob->ym_ch3_mode;
    core->ym2612.phase_accum = blob->ym_phase_accum;
    core->ym2612.env_tick    = blob->ym_env_tick;

    free(blob);
    return true;
}

/* ==========================================================================
 * Video, Audio & Input Accessors
 * ========================================================================== */

const uint32_t *yd_core_get_framebuffer(const yd_core_t *core) {
    if (!core) {
        return NULL;
    }
    if (core->system == YD_SYSTEM_MD) {
        return core->md_vdp.framebuffer;
    }
    return core->vdp.framebuffer;
}

const int16_t *yd_core_get_audio_buffer(const yd_core_t *core, uint32_t *out_stereo_samples) {
    if (!core) {
        if (out_stereo_samples) {
            *out_stereo_samples = 0u;
        }
        return NULL;
    }
    if (out_stereo_samples) {
        *out_stereo_samples = core->psg.sample_count;
    }
    return core->psg.sample_buffer;
}

uint16_t yd_core_get_screen_width(const yd_core_t *core) {
    if (!core) {
        return YD_VDP_WIDTH;
    }
    if (core->system == YD_SYSTEM_MD) {
        return core->md_vdp.active_width;
    }
    return YD_VDP_WIDTH;
}

uint16_t yd_core_get_screen_height(const yd_core_t *core) {
    if (!core) {
        return YD_VDP_HEIGHT_STD;
    }
    if (core->system == YD_SYSTEM_MD) {
        return core->md_vdp.active_height;
    }
    return core->vdp.active_height;
}

void yd_core_set_joypad(yd_core_t *core, int player, uint16_t buttons) {
    if (!core) {
        return;
    }
    if (core->system == YD_SYSTEM_MD) {
        yd_md_mmu_set_pad(&core->md_mmu, player, buttons);
    } else {
        yd_io_set_joypad(&core->io, player, (uint8_t)(buttons & 0xFFu));
    }
}

const char *yd_core_version(void) {
    return YD_CORE_VERSION_STRING;
}
