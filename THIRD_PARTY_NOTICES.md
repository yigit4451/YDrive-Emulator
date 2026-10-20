# Third-Party Notices & Open Source Licenses

YDrive incorporates open-source components, emulation cores, and libraries under various open-source licenses. This document acknowledges and honors the upstream authors and their licenses.

---

## 1. PicoDrive (Libretro Core)
- **Description:** Fast, accurate emulation core for SEGA Genesis / Mega Drive, SEGA CD / Mega-CD, SEGA 32X, and SEGA Master System.
- **Authors:** Dave, notaz, and the Libretro / PicoDrive contributors.
- **Upstream:** [https://github.com/libretro/picodrive](https://github.com/libretro/picodrive)
- **License:** MAME / Custom Non-Commercial Open-Source License.
  - *Redistribution and use of this code or any derivative works are permitted provided that redistributions are not sold or used in a commercial product or activity, and modifications include the complete source code.*
- **Build Instructions for iOS:**
  ```bash
  git clone --depth 1 https://github.com/libretro/picodrive.git
  cd picodrive && git submodule update --init --recursive
  make -f Makefile.libretro platform=ios-arm64 STATIC_LINKING_LINK=1 USE_LIBCHDR=1 TARGET=libpicodrive_libretro_ios.a MINVERSION="-miphoneos-version-min=26.0"
  ```
  *(Automated via `.github/workflows/ydrive-ios-build.yml`)*

---

## 2. Genesis Plus GX (Libretro Core)
- **Description:** High-accuracy open-source SEGA 8/16-bit core.
- **Authors:** Charles MacDonald, Eke-Eke (2007-2022), Daniel De Matteis (2012-2016).
- **Upstream:** [https://github.com/libretro/Genesis-Plus-GX](https://github.com/libretro/Genesis-Plus-GX)
- **License:** Genesis Plus GX Non-Commercial License.
  - *Redistribution and use permitted with copyright notices preserved; redistributions may not be sold or used in commercial products.*

---

## 3. Libretro API (`libretro.h`)
- **Description:** Standardized frontend-backend API specification for emulator cores.
- **Upstream:** [https://github.com/libretro/RetroArch](https://github.com/libretro/RetroArch)
- **License:** MIT License.

---

## 4. NAudio
- **Description:** .NET audio library used in the Windows application for real-time sound playback.
- **Authors:** Mark Heath and NAudio contributors.
- **Upstream:** [https://github.com/naudio/NAudio](https://github.com/naudio/NAudio)
- **License:** MIT License.

---

## 5. XcodeGen
- **Description:** Command-line tool that generates Xcode projects from project specs.
- **Authors:** Yonas Kolb and contributors.
- **Upstream:** [https://github.com/yonaskolb/XcodeGen](https://github.com/yonaskolb/XcodeGen)
- **License:** MIT License.

---

## Trademark & Legal Disclaimer
SEGA, Genesis, Mega Drive, SEGA CD, Mega-CD, 32X, and Master System are registered trademarks of SEGA Corporation or its affiliates. YDrive is an independent, non-commercial, fan-made open-source project and is not affiliated with, endorsed by, or sponsored by SEGA Corporation. YDrive does not bundle or distribute proprietary game ROMs or BIOS files.
