#include "io.h"
#include <string.h>

static inline void yd_io_sync_vdp_irq(yd_io_t *io) {
    if (io->cpu && io->vdp) {
        z80_set_int_line(io->cpu, yd_vdp_irq_asserted(io->vdp));
    }
}

void yd_io_init(yd_io_t *io, yd_vdp_t *vdp, yd_psg_t *psg, z80_cpu_t *cpu) {
    if (!io) {
        return;
    }
    memset(io, 0, sizeof(*io));
    io->vdp = vdp;
    io->psg = psg;
    io->cpu = cpu;
    yd_io_reset(io);
}

void yd_io_reset(yd_io_t *io) {
    if (!io) {
        return;
    }
    io->pad_state[0]  = 0x00u;
    io->pad_state[1]  = 0x00u;
    io->mem_ctrl      = 0xABu;
    io->io_ctrl       = 0xFFu;
    io->last_psg_byte = 0x00u;

    memset(io->gg_regs, 0, sizeof(io->gg_regs));
    io->gg_regs[0] = 0xC0u; /* Start released (Bit 7=1), Export region (Bit 6=1) */
    io->gg_regs[6] = 0xFFu; /* Stereo panning default: all L+R enabled */
}

void yd_io_set_joypad(yd_io_t *io, int player, uint8_t buttons) {
    if (!io || player < 0 || player > 1) {
        return;
    }
    uint8_t prev           = io->pad_state[player];
    io->pad_state[player]  = buttons;

    /* On Master System, pressing Start/Pause on Player 1 triggers a falling-edge NMI */
    if (!io->is_game_gear && player == 0) {
        bool was_paused = (prev & YD_PAD_START) != 0u;
        bool now_paused = (buttons & YD_PAD_START) != 0u;
        if (!was_paused && now_paused && io->cpu) {
            z80_trigger_nmi(io->cpu);
        }
    }
}

uint8_t yd_io_read_port(void *ctx, uint8_t port) {
    yd_io_t *io = (yd_io_t *)ctx;
    if (!io) {
        return 0xFFu;
    }

    /* Game Gear Specific System Ports (0x00 - 0x06) */
    if (io->is_game_gear && port <= 0x06u) {
        if (port == YD_PORT_GG_START) {
            uint8_t val = 0x3Fu;
            if ((io->pad_state[0] & YD_PAD_START) == 0u) {
                val |= 0x80u; /* Bit 7: Start button (active-low: 1=released, 0=pressed) */
            }
            if (!io->is_domestic_jp) {
                val |= 0x40u; /* Bit 6: Overseas/Export region */
            }
            return val;
        }
        return io->gg_regs[port];
    }

    /* Decode top 2 bits of port address (0x00-0x3F, 0x40-0x7F, 0x80-0xBF, 0xC0-0xFF) */
    switch (port & 0xC0u) {
        case 0x00u:
            return 0xFFu;

        case 0x40u:
            /* 0x40 - 0x7F: Even = V-Counter (0x7E), Odd = H-Counter (0x7F) */
            if (!io->vdp) {
                return 0xFFu;
            }
            return ((port & 1u) == 0u)
                   ? yd_vdp_read_vcounter(io->vdp)
                   : yd_vdp_read_hcounter(io->vdp);

        case 0x80u:
            /* 0x80 - 0xBF: Even = VDP Data (0xBE), Odd = VDP Status (0xBF) */
            if (!io->vdp) {
                return 0xFFu;
            }
            if ((port & 1u) == 0u) {
                return yd_vdp_read_data(io->vdp);
            } else {
                uint8_t status = yd_vdp_read_status(io->vdp);
                yd_io_sync_vdp_irq(io);
                return status;
            }

        default: {
            /* 0xC0 - 0xFF: Even = Joypad Port A (0xDC), Odd = Joypad Port B (0xDD) */
            uint8_t p1 = io->pad_state[0];
            uint8_t p2 = io->pad_state[1];

            if ((port & 1u) == 0u) {
                uint8_t pressed = (uint8_t)((p1 & 0x3Fu) | ((p2 & 0x03u) << 6));
                return (uint8_t)~pressed;
            } else {
                uint8_t val = 0xFFu;
                val &= (uint8_t)~((p2 >> 2) & 0x0Fu);

                if (p1 & YD_PAD_RESET) {
                    val &= 0xEFu; /* Clear Bit 4 (Active-low Reset) */
                }

                if (!io->is_domestic_jp) {
                    val &= 0x3Fu;
                    if ((io->io_ctrl & 0x02u) || (io->io_ctrl & 0x20u)) {
                        val |= (1u << 6);
                    }
                    if ((io->io_ctrl & 0x08u) || (io->io_ctrl & 0x80u)) {
                        val |= (1u << 7);
                    }
                }
                return val;
            }
        }
    }
}

void yd_io_write_port(void *ctx, uint8_t port, uint8_t val) {
    yd_io_t *io = (yd_io_t *)ctx;
    if (!io) {
        return;
    }

    if (io->is_game_gear && port <= 0x06u) {
        io->gg_regs[port] = val;
        if (port == YD_PORT_GG_STEREO && io->psg) {
            yd_psg_write_stereo(io->psg, val);
        }
        return;
    }

    switch (port & 0xC0u) {
        case 0x00u:
            /* 0x00 - 0x3F: Even = Memory Control (0x3E), Odd = I/O Control (0x3F) */
            if ((port & 1u) == 0u) {
                io->mem_ctrl = val;
            } else {
                io->io_ctrl = val;
            }
            break;

        case 0x40u:
            /* 0x40 - 0x7F: SN76489 PSG Sound Generator Port */
            io->last_psg_byte = val;
            if (io->psg) {
                yd_psg_write(io->psg, val);
            }
            break;

        case 0x80u:
            /* 0x80 - 0xBF: Even = VDP Data (0xBE), Odd = VDP Control (0xBF) */
            if (!io->vdp) {
                return;
            }
            if ((port & 1u) == 0u) {
                yd_vdp_write_data(io->vdp, val);
            } else {
                yd_vdp_write_control(io->vdp, val);
                yd_io_sync_vdp_irq(io);
            }
            break;

        default:
            break;
    }
}

void yd_io_bind_mmu(yd_io_t *io, yd_mmu_t *mmu) {
    if (!io || !mmu) {
        return;
    }
    yd_io_handlers_t handlers;
    handlers.ctx        = io;
    handlers.read_port  = yd_io_read_port;
    handlers.write_port = yd_io_write_port;
    yd_mmu_set_io_handlers(mmu, &handlers);
}
