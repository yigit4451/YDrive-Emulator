import SwiftUI

// MARK: – PNG Icon Generator
@MainActor
private enum IconPNGHelper {
    private static let cache = NSCache<NSString, UIImage>()
    
    static func image(_ name: String, pointSize: CGFloat, weight: UIImage.SymbolWeight = .bold, color: UIColor) -> UIImage {
        let key = "\(name)_\(pointSize)_\(weight.rawValue)_\(color.hashValue)" as NSString
        if let cached = cache.object(forKey: key) {
            return cached
        }
        
        let config = UIImage.SymbolConfiguration(pointSize: pointSize, weight: weight)
        guard let base = UIImage(systemName: name, withConfiguration: config)?
            .withTintColor(color, renderingMode: .alwaysOriginal) else {
            return UIImage()
        }
        
        let format = UIGraphicsImageRendererFormat.preferred()
        format.scale = UIScreen.main.scale
        format.opaque = false
        
        let renderer = UIGraphicsImageRenderer(size: base.size, format: format)
        let pngData = renderer.pngData { _ in
            base.draw(at: .zero)
        }
        
        let result = (UIImage(data: pngData) ?? base).withRenderingMode(.alwaysOriginal)
        cache.setObject(result, forKey: key)
        return result
    }
}

struct SaveManagerView: View {
    let engine: LibretroEmulatorEngine
    let gameFileName: String
    @Binding var isPresented: Bool
    @AppStorage("appTheme") private var appTheme = "system"
    
    @State private var savedSlots: [(slot: Int, date: Date)] = []
    @State private var slotToDelete: Int?
    @State private var showingDeleteAlert = false
    @State private var isSaving = false
    @State private var isLoading = true

    private var colorScheme: ColorScheme? {
        switch appTheme {
        case "dark": return .dark
        case "light": return .light
        default: return nil
        }
    }
    
    var body: some View {
        ZStack {
            // Adaptive background like SettingsView
            Color(UIColor.systemGroupedBackground)
                .ignoresSafeArea()

            ScrollView {
                LazyVStack(spacing: 14) {
                    if isLoading && savedSlots.isEmpty {
                        ProgressView()
                            .padding(.top, 40)
                    } else if savedSlots.isEmpty {
                        emptySavesView
                    } else {
                        // Pre-sorted descending by date
                        ForEach(savedSlots, id: \.slot) { item in
                            liquidGlassSaveCard(slot: item.slot, date: item.date)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 28)
            }
            .scrollContentBackground(.hidden)
        }
        .navigationTitle(NSLocalizedString("emulator.saves", comment: "Saves"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button(action: addNewSave) {
                    ZStack {
                        Circle()
                            .fill(Color(UIColor.secondarySystemGroupedBackground))
                            .frame(width: 32, height: 32)

                        if isSaving {
                            ProgressView()
                                .progressViewStyle(.circular)
                                .scaleEffect(0.8)
                        } else {
                            Image(uiImage: IconPNGHelper.image("plus", pointSize: 14, weight: .bold, color: .systemBlue))
                                .renderingMode(.original)
                        }
                    }
                    .frame(width: 32, height: 32)
                    .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .disabled(isSaving)
                .accessibilityLabel(NSLocalizedString("saves.new", comment: "New Save State"))
            }

            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    isPresented = false
                } label: {
                    ZStack {
                        Circle()
                            .fill(Color(UIColor.secondarySystemGroupedBackground))
                            .frame(width: 32, height: 32)

                        Image(uiImage: IconPNGHelper.image("xmark", pointSize: 12, weight: .bold, color: .secondaryLabel))
                            .renderingMode(.original)
                    }
                    .frame(width: 32, height: 32)
                    .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(NSLocalizedString("close", comment: "Close"))
            }
        }
        .preferredColorScheme(colorScheme)
        .onAppear {
            fetchAllSaves()
        }
        .onDisappear {
            if engine.isPaused {
                engine.setPaused(false)
            }
        }
        .alert(NSLocalizedString("confirm_delete", comment: "Delete?"), isPresented: $showingDeleteAlert) {
            Button(NSLocalizedString("cancel", comment: "Cancel"), role: .cancel) { }
            Button(NSLocalizedString("delete", comment: "Delete"), role: .destructive) {
                if let slot = slotToDelete {
                    deleteSave(slot: slot)
                }
            }
        } message: {
            Text(NSLocalizedString("confirm_delete", comment: "Are you sure you want to delete this?"))
        }
    }

    // MARK: – Liquid Glass Save Card
    private func liquidGlassSaveCard(slot: Int, date: Date) -> some View {
        HStack(spacing: 12) {
            // Main clickable load state action
            Button {
                Task {
                    let success = await engine.loadState(for: gameFileName, slot: slot)
                    if success {
                        engine.setPaused(false)
                        withAnimation(.easeInOut(duration: 0.25)) {
                            isPresented = false
                        }
                    }
                }
            } label: {
                HStack(spacing: 14) {
                    // Native Icon Orb with PNG icon
                    ZStack {
                        Circle()
                            .fill(Color(UIColor.secondarySystemGroupedBackground))
                            .frame(width: 44, height: 44)
                        
                        Image(uiImage: IconPNGHelper.image("externaldrive.fill", pointSize: 18, weight: .semibold, color: .systemBlue))
                            .renderingMode(.original)
                    }

                    // Slot Information
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Slot \(slot + 1)")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(.primary)

                        HStack(spacing: 4) {
                            Image(uiImage: IconPNGHelper.image("clock", pointSize: 11, weight: .regular, color: .secondaryLabel))
                                .renderingMode(.original)
                            Text(date, format: .dateTime.month().day().hour().minute().second())
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Spacer()

                    // Quick Load Indicator Pill with PNG chevron
                    HStack(spacing: 4) {
                        Text("Load")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Color.accentColor)
                        Image(uiImage: IconPNGHelper.image("chevron.right", pointSize: 10, weight: .bold, color: .systemBlue))
                            .renderingMode(.original)
                    }
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(Color(UIColor.secondarySystemGroupedBackground))
                    .clipShape(Capsule())
                }
            }
            .buttonStyle(.plain)

            // Delete Button with PNG trash icon
            Button {
                slotToDelete = slot
                showingDeleteAlert = true
            } label: {
                ZStack {
                    Circle()
                        .fill(Color(UIColor.secondarySystemGroupedBackground))
                        .frame(width: 34, height: 34)

                    Image(uiImage: IconPNGHelper.image("trash.fill", pointSize: 12, weight: .medium, color: .systemRed))
                        .renderingMode(.original)
                }
                .frame(width: 34, height: 34)
                .clipShape(Circle())
            }
            .buttonStyle(.borderless)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    // MARK: – Empty Saves View
    private var emptySavesView: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(Color(UIColor.secondarySystemGroupedBackground))
                    .frame(width: 74, height: 74)

                Image(uiImage: IconPNGHelper.image("externaldrive.badge.plus", pointSize: 32, weight: .semibold, color: .systemBlue))
                    .renderingMode(.original)
            }
            .padding(.top, 14)

            VStack(spacing: 6) {
                Text(NSLocalizedString("saves.empty.title", comment: "No saves yet"))
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.primary)

                Text(NSLocalizedString("saves.empty.subtitle", comment: "Save your gameplay state at any time to resume later."))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 20)
            }

            Button(action: addNewSave) {
                HStack(spacing: 8) {
                    if isSaving {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .tint(.white)
                    } else {
                        Image(uiImage: IconPNGHelper.image("plus.circle.fill", pointSize: 16, weight: .bold, color: .white))
                            .renderingMode(.original)
                    }
                    Text(NSLocalizedString("saves.create_now", comment: "Create Save State"))
                        .font(.headline)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }
            .buttonStyle(.glassProminent)
            .disabled(isSaving)
            .padding(.horizontal, 20)
            .padding(.top, 6)
            .padding(.bottom, 12)
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .padding(.top, 20)
    }
    
    private func fetchAllSaves() {
        let fileName = gameFileName
        Task.detached(priority: .userInitiated) {
            var saves = [Int: Date]()
            let gameURL = URL(fileURLWithPath: fileName)
            let gameDir = gameURL.deletingLastPathComponent()

            // 1. Check game directory (slotX.state)
            if let files = try? FileManager.default.contentsOfDirectory(atPath: gameDir.path) {
                for file in files {
                    if file.hasPrefix("slot") && file.hasSuffix(".state") {
                        let numStr = file.replacingOccurrences(of: "slot", with: "").replacingOccurrences(of: ".state", with: "")
                        if let slot = Int(numStr) {
                            let fileURL = gameDir.appendingPathComponent(file)
                            if let attr = try? FileManager.default.attributesOfItem(atPath: fileURL.path),
                               let date = attr[.modificationDate] as? Date {
                                saves[slot] = date
                            }
                        }
                    }
                }
            }

            // 2. Check legacy Saves/ folder
            if let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
                let savesDir = docs.appendingPathComponent("Saves", isDirectory: true)
                let safeName = fileName.replacingOccurrences(of: "/", with: "_")
                if let files = try? FileManager.default.contentsOfDirectory(atPath: savesDir.path) {
                    for file in files {
                        if file.hasPrefix("\(safeName)_slot"), file.hasSuffix(".state") {
                            let numberString = file
                                .replacingOccurrences(of: "\(safeName)_slot", with: "")
                                .replacingOccurrences(of: ".state", with: "")
                            if let slot = Int(numberString) {
                                let legacyURL = savesDir.appendingPathComponent(file)
                                let newURL = gameDir.appendingPathComponent("slot\(slot).state")
                                if !FileManager.default.fileExists(atPath: newURL.path) {
                                    try? FileManager.default.moveItem(at: legacyURL, to: newURL)
                                    if let attr = try? FileManager.default.attributesOfItem(atPath: newURL.path),
                                       let date = attr[.modificationDate] as? Date {
                                        saves[slot] = date
                                    }
                                } else if saves[slot] == nil {
                                    if let attr = try? FileManager.default.attributesOfItem(atPath: legacyURL.path),
                                       let date = attr[.modificationDate] as? Date {
                                        saves[slot] = date
                                    }
                                }
                            }
                        }
                    }
                }
            }

            let sorted = saves.map { (slot: $0.key, date: $0.value) }.sorted(by: { $0.date > $1.date })
            await MainActor.run {
                self.savedSlots = sorted
                self.isLoading = false
            }
        }
    }
    
    private func addNewSave() {
        guard !isSaving else { return }
        isSaving = true
        let nextSlot = (savedSlots.map(\.slot).max() ?? -1) + 1
        Task {
            let success = await engine.saveState(for: gameFileName, slot: nextSlot)
            await MainActor.run {
                if success {
                    fetchAllSaves()
                }
                isSaving = false
            }
        }
    }
    
    private func deleteSave(slot: Int) {
        let fileName = gameFileName
        Task.detached(priority: .userInitiated) {
            let gameURL = URL(fileURLWithPath: fileName)
            let gameDir = gameURL.deletingLastPathComponent()
            let fileURL = gameDir.appendingPathComponent("slot\(slot).state")
            try? FileManager.default.removeItem(at: fileURL)

            if let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
                let legacyURL = docs.appendingPathComponent("Saves").appendingPathComponent("\(fileName.replacingOccurrences(of: "/", with: "_"))_slot\(slot).state")
                try? FileManager.default.removeItem(at: legacyURL)
            }
            await MainActor.run {
                self.fetchAllSaves()
            }
        }
    }
}
