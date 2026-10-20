# 🎮 YDrive Emulator

**YDrive** is a modern, high-performance, open-source **SEGA Console Emulator** and game library manager developed for **Windows** and **iOS**.

Designed with sleek aesthetics, automated metadata scraping, low-latency audio, and accurate Libretro emulation cores, YDrive brings retro SEGA classics to modern devices.

---

## 🌟 Supported Systems

| System | Supported Core | Notes |
|---|---|---|
| **SEGA Genesis / Mega Drive** | PicoDrive / Genesis Plus GX | Full support, 3-button & 6-button controller mapping |
| **SEGA CD / Mega-CD** | PicoDrive / Genesis Plus GX | ISO/BIN/CUE/CHD format, requires BIOS (`bios_CD_U.bin`, etc.) |
| **SEGA 32X** | PicoDrive | Full support with 32X BIOS or High-Level Emulation |
| **SEGA Master System** | PicoDrive / Genesis Plus GX | 2-button controller layout, cartridge & ROM support |

---

## 📱 Platform Editions

### 🍏 iOS (Native Swift & SwiftUI)
Built from the ground up for modern iOS (iOS 26+) using native Apple frameworks:
- **Architecture:** Pure Swift 6 with SwiftUI and Liquid Glass UI components.
- **Renderer:** Metal and MetalKit hardware acceleration for zero-tearing frame rendering.
- **Audio Engine:** Low-latency real-time PCM audio streaming via `AVAudioEngine`.
- **Controls:** Multi-touch virtual on-screen gamepad with haptic feedback, plus physical gamepad support via `GCController` 
- **Library & Scraper:** Integrated TheGamesDB artwork and metadata scraper, quick search, and visual game cards.
- **Saves & BIOS:** Full save state management with visual slots and built-in BIOS verification manager.
- **Distribution:** Distributed via GitHub Releases (`.ipa`) and official **AltStore Classic Source**.

### 💻 Windows (.NET 8 & WPF)
- **Architecture:** C# (.NET 8) with WPF (Windows Presentation Foundation) and MVVM pattern.
- **Audio:** High-resolution audio output via `NAudio`.
- **Renderer:** Direct WriteableBitmap frame rendering.
- **Scraper:** Automatic box art and title metadata downloader using TheGamesDB API.
- **Languages:** Full dynamic localization in **English** and **Turkish**.

---

## 🚀 Installation & Distribution

### iOS (via AltStore Classic)
1. In AltStore Classic, open **Browse** → **Sources** and tap **+**.
2. Add the official YDrive source URL:
   ```text
   https://yigit4451.github.io/YDrive-Emulator/altstore.json
   ```
3. Or tap **Add to AltStore** directly on the [YDrive AltStore Page](https://yigit4451.github.io/YDrive-Emulator/).
4. Sideload and enjoy with automated 7-day refreshing.

### iOS (Direct IPA Sideloading)
Download the latest pre-built `.ipa` from the [GitHub Releases](https://github.com/yigit4451/YDrive-Emulator/releases) page:
- `YDrive.ipa` (Ad-hoc signed for AltStore, Sideloadly, or TrollStore)
- `YDrive.unsigned.ipa` (Unsigned for custom signing workflows)

### Windows
1. Download the latest `YDrive_Emulator_v*.zip` from [GitHub Releases](https://github.com/yigit4451/YDrive-Emulator/releases).
2. Extract the archive to any folder.
3. Launch `YDrive.exe`.

---

## 🛠️ Building from Source

### Building the Windows Project
Prerequisites: [.NET 8.0 SDK](https://dotnet.microsoft.com/download/dotnet/8.0)
```bash
dotnet build YDrive.sln -c Release
```
The compiled application and cores will be output to `bin/Release/win-x64/`.

### Building the Native iOS Project
Prerequisites: macOS with Xcode 16+ and [XcodeGen](https://github.com/yonaskolb/XcodeGen)
```bash
cd YDrive.iOS.Native
xcodegen generate --spec project.yml
open YDrive.xcodeproj
```

---

## 📂 Repository Structure

```text
├── .github/workflows/          # CI/CD: iOS build, AltStore validation, automated releases
├── altstore/                   # AltStore Classic source generator & web landing page
├── src/
│   └── YDrive/                 # Windows WPF (.NET 8) application source code
│       ├── Audio/              # NAudio playback implementation
│       ├── Core/               # Libretro C# wrapper & callbacks
│       ├── Models/             # App data models
│       ├── Resources/          # Internationalization strings (en, tr)
│       ├── Services/           # Game library and TheGamesDB scraper
│       ├── ViewModels/         # MVVM view models
│       └── Views/              # WPF XAML windows and dialogs
├── YDrive.iOS.Native/          # Native iOS Swift/SwiftUI application source code
│   ├── Resources/              # Asset catalogs, Info.plist, Settings.bundle, l10n
│   ├── Sources/                # Swift & Metal emulation engine, UI views, services
│   └── project.yml             # XcodeGen project specification
└── YDrive.sln                  # Root solution file for Windows development
```

---

## 🔒 Security & Privacy

- YDrive does not collect or transmit personal telemetry or user data.
- TheGamesDB requests only send game titles to query public artwork and descriptions.
- Game ROMs and BIOS files are stored locally in the application's isolated document sandbox.

---

## 📜 Licenses & Attribution

- YDrive is licensed under the [MIT License](LICENSE).
- Emulation cores (PicoDrive, Genesis Plus GX) are open-source and subject to their respective non-commercial licenses.
- See [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) for full license texts and upstream references.

---

*SEGA, Genesis, Mega Drive, SEGA CD, Mega-CD, 32X, and Master System are trademarks of SEGA Corporation. YDrive is an independent, non-commercial open-source project and is not affiliated with or endorsed by SEGA.*
