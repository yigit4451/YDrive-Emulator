# YDrive.iOS.Native

Saf **Swift & SwiftUI** ile yazılmış, iOS 16+ hedefli yerel YDrive iOS uygulaması.

## Proje Yapısı

```
YDrive.iOS.Native/
├── project.yml                    ← XcodeGen tanım dosyası
├── Sources/
│   ├── App/
│   │   └── YDriveApp.swift        ← @main giriş noktası
│   ├── Models/
│   │   └── GameItem.swift         ← ROM veri modeli
│   ├── ViewModels/
│   │   └── GameLibraryViewModel.swift
│   └── Views/
│       ├── ContentView.swift       ← NavigationStack kökü
│       ├── GameLibraryView.swift   ← Ana kütüphane ekranı (Grid + SearchBar)
│       ├── GameCardView.swift      ← Tek ROM kartı bileşeni
│       ├── GameDetailView.swift    ← Oyun detay ve başlatma ekranı
│       ├── EmulatorView.swift      ← Emülatör yüzeyi + On-Screen Kontroller
│       └── SettingsView.swift      ← Ayarlar
└── Resources/
    ├── Info.plist
    └── Assets.xcassets/
        └── AppIcon.appiconset/
```

## Xcode Projesi Oluşturma (Mac'te)

```bash
cd YDrive.iOS.Native
brew install xcodegen
xcodegen generate
open YDrive.xcodeproj
```

## Tasarım Dili

- `.background(.ultraThinMaterial)` — Apple buzlu cam (Frosted Glass)
- `.clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))` — Sürekli köşe yuvarlaması  
- `.stroke(.white.opacity(0.13), lineWidth: 1)` — İnce cam kenarlık
- `LinearGradient` koyu gece mavisi arka plan  
- `GCController` framework ile MFi kontrolcü otomatik tespiti
- Dokunmatik On-Screen D-Pad + A/B/C/Start butonları
