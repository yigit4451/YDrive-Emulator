# YDrive 1.0.3 (iOS)

YDrive 1.0.3 is a major feature and refinement release bringing comprehensive multi-language internationalization, Apple Liquid Glass save state redesign, in-house YD-Core experimental integration, and enhanced user experience.

---

## What's New in 1.0.3

### 🌍 Multi-Language Internationalization & Localization
- Fully localized into **7 languages**:
  - **English (`en`)** — Default / Base
  - **Turkish (`tr`)**
  - **German (`de`)**
  - **Spanish (`es`)**
  - **Japanese (`ja`)**
  - **Arabic (`ar`)** — Complete Right-to-Left (RTL) layout support while preserving controller layout direction
  - **Russian (`ru`)**
- Seamless integration with iOS Per-App Language settings in the Apple Settings app (`Settings > YDrive > Preferred Language`), removing redundant in-app language pickers.

### 💾 Liquid Glass Save States & Streamlined Loading
- Redesigned save cards utilizing native Apple **Liquid Glass** material styling.
- **Instant Single-Tap Load:** Tapping any save card now immediately loads your saved state without unnecessary intermediate option sheets.
- **Optimized Landscape Layout:** Save cards are resized and left-aligned (`leading`) for cleaner navigation in landscape mode.
- **Refined Deletion Prompts:** Simplified single-heading confirmation alerts across all supported languages.

### 📸 Screenshot Notification Toast
- Added a top-to-bottom sliding animated blue feedback banner confirming screenshots are saved to the Photos library.
- Layered at the highest z-index above the navigation bar and toolbar buttons for optimal visibility in both portrait and landscape orientations.

### ⚡ Experimental Settings & YD-Core Integration
- Enabling experimental settings now automatically engages **YD-Core**, YDrive's standalone in-house SEGA Mega Drive / Genesis emulation engine.
- Removed manual core selectors in favor of automatic, seamless switching between PicoDrive (stable) and YD-Core (experimental).
- Toggleable Direct Memory Access (DMA), 44.1 kHz audio interpolation, and 6-button controller forcing.

---

## Installation via AltStore
Add the YDrive AltStore source:
```
https://yigit4451.github.io/YDrive-Emulator/altstore.json
```
