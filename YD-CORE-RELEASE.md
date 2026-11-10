# Introducing YD-Core (Experimental Core)

We are proud to introduce YD-Core v1.2.0 — YDrive's in-house SEGA Mega Drive / Genesis emulation core written in pure C with Libretro API compatibility.

### Key Highlights:
• **Standalone In-House Core:** High-fidelity Motorola 68000 and Zilog Z80 emulation.  
• **Dual-Chip Sound Engine:** Yamaha YM2612 FM synthesis + SN76489 PSG with authentic discrete hardware output.  
• **Hardware Acceleration:** Direct Memory Access (DMA) transfer acceleration.  
• **Ultra-Low Latency:** Zero external dependencies, integrated directly into YDrive.  
• **YDSS v2 State Engine:** Robust state management with FNV-1a checksum validation.  

YD-Core can be enabled inside YDrive under Settings > Experimental.

---

> **Note:** This is an architectural milestone and source announcement release for YD-Core. No standalone binary assets are attached to this release; YD-Core is embedded natively within the YDrive iOS application, and the full source code is available in this repository under [`YDrive.iOS.Native/Sources/Core/YDCore`](https://github.com/yigit4451/YDrive-Emulator/tree/main/YDrive.iOS.Native/Sources/Core/YDCore).

---

## Technical Architecture

- **Clean C & Libretro Compliance:**
  Engineered from the ground up in standard C with clean subsystem boundaries and complete Libretro environment callbacks. No external dynamic dependencies, ensuring deterministic execution and minimal memory footprint.

- **Dual-CPU Emulation Engine:**
  - **Motorola 68000:** Primary 16/32-bit CPU core with high-fidelity instruction decoding, register tracking, and interrupt control.
  - **Zilog Z80:** Sub-CPU core dedicated to audio coordination and legacy backward compatibility.

- **Dual-Chip Sound Synthesis:**
  - **Yamaha YM2612 FM:** Full 6-channel FM synthesis engine with operator envelope calculation, LFO, and PCM DAC playback channel.
  - **Texas Instruments SN76489 PSG:** 3 square wave channels and 1 noise channel delivering authentic discrete hardware output.

- **Video Display Processor (VDP):**
  - Line-accurate rasterization for Plane A, Plane B, Window plane, and hardware sprite generator.
  - Hardware **Direct Memory Access (DMA)** transfer acceleration for rapid VRAM/CRAM/VSRAM updates.

- **YDSS v2 Save State Architecture:**
  Integrated binary state snapshot mechanism featuring FNV-1a checksum validation to ensure save state stability across emulation sessions.

---

## Source Code Reference

The complete C source code is available in the repository:
- Core Coordinator: `YDrive.iOS.Native/Sources/Core/YDCore/src/yd_core.c`
- Libretro Bridge: `YDrive.iOS.Native/Sources/Core/YDCore/src/libretro.c`
- 68000 Processor: `YDrive.iOS.Native/Sources/Core/YDCore/src/m68k.c`
- Z80 Audio Processor: `YDrive.iOS.Native/Sources/Core/YDCore/src/z80.c`
- Video Processor (VDP): `YDrive.iOS.Native/Sources/Core/YDCore/src/vdp.c`
- Yamaha FM Synth: `YDrive.iOS.Native/Sources/Core/YDCore/src/ym2612.c`
- PSG Synth: `YDrive.iOS.Native/Sources/Core/YDCore/src/psg.c`
