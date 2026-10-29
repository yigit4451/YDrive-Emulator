#!/usr/bin/env python3
"""
Patch PicoDrive source before building libpicodrive_libretro_ios.a:
1. In pico/memory.c (PortRead):
   Guard the Sega mouse TL latency delay (in ^= 0x10) with `if (port_type[i] == PICO_INPUT_MOUSE)`.
   Root cause: Without this guard, in ^= 0x10 runs unconditionally on standard 3-button and
   6-button pads whenever cycles < padTLLatency[i] (which happens across session cycle resets
   where cycles resets to 0 but padTLLatency retains the previous session's cycle count).
   Pin 4 (bit 0x10) is Button A (TH=0) / Button B (TH=1). Inverting it causes Button A to be
   seen as held when unpressed, released when touched down, and pressed when released (jumping
   only on release).
2. In pico/pico.c:
   Call io_ports_reset() in PicoPower() and PicoReset() so port cycle timestamps
   (padTLLatency, padTHLatency, padTHTimeout) are reset to SekCyclesDone() (0) on session start
   and console reset.
"""

import sys
import os

def patch_file(path, search_str, replace_str, description):
    if not os.path.isfile(path):
        print(f"[-] ERROR: File not found: {path}")
        sys.exit(1)

    with open(path, "r", encoding="utf-8") as f:
        content = f.read()

    # Normalize CRLF to LF for consistent matching
    original_crlf = "\r\n" in content
    normalized_content = content.replace("\r\n", "\n")
    search_norm = search_str.replace("\r\n", "\n")
    replace_norm = replace_str.replace("\r\n", "\n")

    if search_norm not in normalized_content:
        print(f"[-] ERROR: Could not find target pattern for: '{description}' in {path}")
        sys.exit(1)

    patched_content = normalized_content.replace(search_norm, replace_norm, 1)

    if original_crlf:
        patched_content = patched_content.replace("\n", "\r\n")

    with open(path, "w", encoding="utf-8") as f:
        f.write(patched_content)

    print(f"[+] SUCCESS: {description}")

def main():
    pico_dir = sys.argv[1] if len(sys.argv) > 1 else "picodrive"
    mem_c = os.path.join(pico_dir, "pico", "memory.c")
    pico_c = os.path.join(pico_dir, "pico", "pico.c")

    print(f"=== Applying PicoDrive input fix patches to '{pico_dir}' ===")

    # Patch 1: pico/memory.c — guard TL latency check with port_type[i] == PICO_INPUT_MOUSE
    search_tl = (
        "  // Sega mouse uses the TL/TR lines for req/ack. For buggy drivers, make sure\n"
        "  // there's some delay before ack is sent by taking over the new TL line level\n"
        "  if (CYCLES_GE(cycles, padTLLatency[i]))\n"
        "    padTLLatency[i] = cycles;\n"
        "  else\n"
        "    in ^= 0x10; // TL"
    )
    replace_tl = (
        "  // Sega mouse uses the TL/TR lines for req/ack. For buggy drivers, make sure\n"
        "  // there's some delay before ack is sent by taking over the new TL line level\n"
        "  if (port_type[i] == PICO_INPUT_MOUSE) {\n"
        "    if (CYCLES_GE(cycles, padTLLatency[i]))\n"
        "      padTLLatency[i] = cycles;\n"
        "    else\n"
        "      in ^= 0x10; // TL\n"
        "  }"
    )
    patch_file(mem_c, search_tl, replace_tl, "Guard mouse TL latency delay in PortRead")

    # Patch 2: pico/pico.c — call io_ports_reset() in PicoPower()
    search_power = "  Pico.t.m68c_cnt = Pico.t.m68c_aim = 0;\n"
    replace_power = "  Pico.t.m68c_cnt = Pico.t.m68c_aim = 0;\n  io_ports_reset();\n"
    patch_file(pico_c, search_power, replace_power, "Call io_ports_reset() in PicoPower()")

    # Patch 3: pico/pico.c — call io_ports_reset() in PicoReset()
    search_reset = "int PicoReset(void)\n{\n"
    replace_reset = "int PicoReset(void)\n{\n  io_ports_reset();\n"
    patch_file(pico_c, search_reset, replace_reset, "Call io_ports_reset() in PicoReset()")

    print("=== All PicoDrive patches applied successfully ===")

if __name__ == "__main__":
    main()
