# YDrive.iOS.Native


A native YDrive app for iOS, built entirely with **Swift & SwiftUI** and targeting **iOS 26+**.

## Project Structure

YDrive.iOS.Native/
├── project.yml                    ← XcodeGen project definition
├── Sources/
│   ├── App/
│   │   └── YDriveApp.swift        ← @main app entry point
│   ├── Models/
│   │   └── GameItem.swift         ← ROM data model
│   ├── ViewModels/
│   │   └── GameLibraryViewModel.swift
│   └── Views/
│       ├── ContentView.swift       ← NavigationStack root
│       ├── GameLibraryView.swift   ← Main game library
│       ├── GameCardView.swift      ← Individual game card component
│       ├── GameDetailView.swift    ← Game details and launch screen
│       ├── EmulatorView.swift      ← Emulator surface + on-screen controls
│       └── SettingsView.swift      ← Settings
└── Resources/
    ├── Info.plist
    └── Assets.xcassets/
        └── AppIcon.appiconset/

Generating the Xcode Project
On macOS:
cd YDrive.iOS.Native
brew install xcodegen
xcodegen generate
open YDrive.xcodeproj

Design
YDrive uses native SwiftUI components and the iOS 26 design system.
- Native Liquid Glass UI provided by the system
- SwiftUI NavigationStack, toolbars, forms, search, and other native controls
- Adaptive Light, Dark, and System appearance
- Native SwiftUI game library interface
- Touch-based on-screen D-Pad and SEGA-style action buttons
- Physical controller support using Apple's GCController framework
- Layouts designed to adapt across supported iPhone and iPad configurations
The interface intentionally relies on native system components instead of manually recreating Liquid Glass with custom blur or Material effects.
