# YDrive for iOS (Native)

A native SEGA console emulator for iOS, built with **Swift 6 & SwiftUI** and targeting **iOS 26+**.

## Features

- **PicoDrive Libretro Core:** Accurate, optimized emulation for SEGA Genesis / Mega Drive, SEGA CD / Mega-CD, SEGA 32X, and SEGA Master System.
- **Metal Hardware Acceleration:** High-performance GPU rendering via Metal and MetalKit.
- **Low-Latency Audio:** Real-time audio synthesis using Apple's `AVAudioEngine`.
- **Modern UI:** Built using native SwiftUI controls, NavigationStack, and the iOS 26 Liquid Glass design language.
- **Gamepad Support:** Physical controller support via Apple's GameController framework (`GCController`) alongside on-screen touch controls with haptic feedback.
- **Save State & Screenshots:** Quick save, quick load, visual save slots, and screenshot capture.
- **Metadata Scraper:** Automatic cover art and game information via TheGamesDB API.
- **Multi-Language Support:** Full English and Turkish localization with dynamic language switching.

## Project Structure

```text
YDrive.iOS.Native/
├── project.yml                     # XcodeGen project specification
├── README.md                       # iOS developer documentation
├── Resources/
│   ├── Assets.xcassets/            # Application icons and asset catalog
│   ├── Info.plist                  # Bundle properties and permissions
│   ├── Settings.bundle/            # iOS System Settings integration
│   ├── en.lproj/Localizable.strings # English localization
│   └── tr.lproj/Localizable.strings # Turkish localization
└── Sources/
    ├── App/
    │   └── YDriveApp.swift         # @main entry point
    ├── Core/
    │   ├── LibretroBridge.h        # C/Objective-C Libretro API bridge
    │   ├── LibretroBridge.m        # Core lifecycle implementation
    │   ├── LibretroEmulatorEngine.swift # Swift emulation engine loop
    │   └── YDriveAudioEngine.swift # AVAudioEngine audio driver
    ├── Models/
    │   └── GameItem.swift          # Game model and console metadata
    ├── Services/
    │   └── TheGamesDBClient.swift  # Metadata scraper client
    ├── ViewModels/
    │   ├── BiosManager.swift       # BIOS verification and management
    │   └── GameLibraryViewModel.swift # Library state and sorting
    └── Views/
        ├── BiosManagerView.swift   # BIOS files UI
        ├── ContentView.swift       # Root NavigationStack
        ├── EmulatorView.swift      # In-game emulator screen and controls
        ├── GameCardView.swift      # Library game card component
        ├── GameDetailView.swift    # Game info and launching view
        ├── GameLibraryView.swift   # Library grid and search view
        ├── MetalEmulatorView.swift # Metal frame presentation surface
        ├── MultiTouchControls.swift# Multi-touch virtual D-Pad and action buttons
        ├── SaveManagerView.swift   # Save states manager
        └── SettingsView.swift      # Emulator settings view
```

## Generating the Xcode Project

Requirements:
- macOS with Xcode 16+ (Xcode 26+ recommended for latest Liquid Glass styling)
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`)

```bash
cd YDrive.iOS.Native
xcodegen generate --spec project.yml
open YDrive.xcodeproj
```

## Distribution & AltStore

YDrive for iOS is distributed through GitHub Releases and the official AltStore Classic Source:
- **AltStore Source:** `https://yigit4451.github.io/YDrive-Emulator/altstore.json`
- **Releases:** Published automatically via GitHub Actions workflow upon pushing a tag matching `ios-v*`.
