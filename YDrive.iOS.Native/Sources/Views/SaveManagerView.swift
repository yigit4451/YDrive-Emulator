import SwiftUI

struct SaveSlotItem: Identifiable, Sendable {
    let id: Int
    let slot: Int
    let date: Date
    let thumbnail: UIImage?
    let coreInfo: String?
}

struct SaveManagerView: View {
    let engine: LibretroEmulatorEngine
    let gameFileName: String
    @Binding var isPresented: Bool
    @AppStorage("appTheme") private var appTheme = "system"
    @AppStorage("appLanguage") private var appLanguage = "system"
    
    @State private var savedSlots: [SaveSlotItem] = []
    @State private var selectedSlotForAction: SaveSlotItem?
    @State private var showingActionSheet = false
    @State private var slotToDelete: Int?
    @State private var showingDeleteAlert = false
    @State private var isSaving = false
    @State private var isLoading = true
    @ObservedObject private var shareManager = RomShareManager.shared

    @Environment(\.colorScheme) private var envColorScheme

    private let gridColumns = [
        GridItem(.flexible(), spacing: 14),
        GridItem(.flexible(), spacing: 14)
    ]

    private var colorScheme: ColorScheme? {
        switch appTheme {
        case "dark": return .dark
        case "light": return .light
        default:
            let style = UIScreen.main.traitCollection.userInterfaceStyle
            if style == .light { return .light }
            if style == .dark { return .dark }
            return nil
        }
    }

    private var isLightMode: Bool {
        if appTheme == "light" { return true }
        if appTheme == "dark" { return false }
        return colorScheme == .light || envColorScheme == .light
    }

    private static func rasterizedIcon(_ systemName: String, pointSize: CGFloat, weight: UIImage.SymbolWeight, color: UIColor) -> UIImage {
        let cfg = UIImage.SymbolConfiguration(pointSize: pointSize, weight: weight)
        guard let symbol = UIImage(systemName: systemName, withConfiguration: cfg)?
            .withTintColor(color, renderingMode: .alwaysOriginal) else {
            return UIImage()
        }
        let img = UIGraphicsImageRenderer(size: symbol.size).image { _ in
            symbol.draw(at: .zero)
        }
        return img.withRenderingMode(.alwaysOriginal)
    }
    
    var body: some View {
        ZStack {
            // Adaptive grouped background
            Color(UIColor.systemGroupedBackground)
                .ignoresSafeArea()

            ScrollView {
                if isLoading && savedSlots.isEmpty {
                    ProgressView()
                        .padding(.top, 40)
                } else if savedSlots.isEmpty {
                    emptySavesView
                        .padding(.horizontal, 16)
                } else {
                    LazyVGrid(columns: gridColumns, spacing: 14) {
                        ForEach(savedSlots) { item in
                            saveCard(item: item)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 14)
                    .padding(.bottom, 28)
                }
            }
            .scrollContentBackground(.hidden)
        }
        .navigationTitle(LocalizationHelper.string("emulator.saves", default: "Saves"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(isLightMode ? .light : .dark, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                if !savedSlots.isEmpty {
                    Button(action: addNewSave) {
                        if isSaving {
                            ProgressView()
                                .progressViewStyle(.circular)
                                .tint(isLightMode ? .black : .blue)
                                .scaleEffect(0.8)
                        } else if isLightMode {
                            Image(uiImage: Self.rasterizedIcon("plus", pointSize: 15, weight: .bold, color: .black))
                                .renderingMode(.original)
                        } else {
                            Image(systemName: "plus")
                                .font(.system(size: 15, weight: .bold))
                                .foregroundStyle(Color.blue)
                        }
                    }
                    .tint(isLightMode ? .black : .blue)
                    .disabled(isSaving)
                    .accessibilityLabel(LocalizationHelper.string("saves.new", default: "New Save State"))
                }
            }

            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    isPresented = false
                } label: {
                    if isLightMode {
                        Image(uiImage: Self.rasterizedIcon("xmark", pointSize: 14, weight: .bold, color: .black))
                            .renderingMode(.original)
                    } else {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(Color.white)
                    }
                }
                .tint(isLightMode ? .black : .white)
                .accessibilityLabel(LocalizationHelper.string("close", default: "Close"))
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
        .confirmationDialog(
            selectedSlotForAction.map { "Slot \($0.slot + 1)" } ?? LocalizationHelper.string("saves.title", default: "Saves"),
            isPresented: $showingActionSheet,
            titleVisibility: .visible,
            presenting: selectedSlotForAction
        ) { item in
            Button(LocalizationHelper.string("saves.load", default: "Load")) {
                loadState(slot: item.slot)
            }
            Button(LocalizationHelper.string("saves.overwrite", default: "Overwrite")) {
                overwriteSave(slot: item.slot)
            }
            Button(LocalizationHelper.string("share", default: "Share")) {
                shareManager.shareSaveState(gameFileName: gameFileName, slot: item.slot)
            }
            Button(LocalizationHelper.string("delete", default: "Delete"), role: .destructive) {
                slotToDelete = item.slot
                showingDeleteAlert = true
            }
            Button(LocalizationHelper.string("cancel", default: "Cancel"), role: .cancel) { }
        }
        .alert(LocalizationHelper.string("confirm_delete", default: "Are you sure you want to delete this?"), isPresented: $showingDeleteAlert) {
            Button(LocalizationHelper.string("cancel", default: "Cancel"), role: .cancel) { }
            Button(LocalizationHelper.string("delete", default: "Delete"), role: .destructive) {
                if let slot = slotToDelete {
                    deleteSave(slot: slot)
                }
            }
        } message: {
            Text(LocalizationHelper.string("confirm_delete", default: "Are you sure you want to delete this?"))
        }
        .sheet(item: $shareManager.shareItem) { item in
            ActivityViewController(activityItems: [item.url])
                .ignoresSafeArea()
        }
        .overlay {
            if shareManager.isArchiving {
                ShareLoadingHUD()
            }
        }
        .animation(.easeInOut(duration: 0.2), value: shareManager.isArchiving)
    }

    // MARK: – Save Card (2-Column Grid Item)
    private func saveCard(item: SaveSlotItem) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // 4:3 Rounded Thumbnail Preview
            ZStack {
                Color(UIColor.secondarySystemFill)

                if let img = item.thumbnail {
                    Image(uiImage: img)
                        .resizable()
                        .aspectRatio(4.0 / 3.0, contentMode: .fill)
                } else {
                    VStack(spacing: 6) {
                        Image(systemName: "photo")
                            .font(.system(size: 26, weight: .light))
                            .foregroundStyle(.tertiary)
                        Text(LocalizationHelper.string("saves.no_preview", default: "No Preview"))
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .aspectRatio(4.0 / 3.0, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .padding(8)

            // Slot Details
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Slot \(item.slot + 1)")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.primary)

                    Spacer()

                    if let info = item.coreInfo {
                        Text(info)
                            .font(.system(size: 9, weight: .bold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.accentColor.opacity(0.12), in: Capsule())
                            .foregroundStyle(Color.accentColor)
                    }
                }

                HStack(spacing: 4) {
                    Image(systemName: "clock")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                    Text(item.date, format: .dateTime.month().day().hour().minute())
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 10)
        }
        .background(Color(UIColor.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.primary.opacity(0.06), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.08), radius: 6, y: 2)
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .onTapGesture {
            selectedSlotForAction = item
            showingActionSheet = true
        }
        .contextMenu {
            Button {
                loadState(slot: item.slot)
            } label: {
                Label(LocalizationHelper.string("saves.load", default: "Load"), systemImage: "play.fill")
            }

            Button {
                overwriteSave(slot: item.slot)
            } label: {
                Label(LocalizationHelper.string("saves.overwrite", default: "Overwrite"), systemImage: "arrow.triangle.2.circlepath")
            }

            Button {
                shareManager.shareSaveState(gameFileName: gameFileName, slot: item.slot)
            } label: {
                Label(LocalizationHelper.string("share", default: "Share"), systemImage: "square.and.arrow.up")
            }

            Button(role: .destructive) {
                slotToDelete = item.slot
                showingDeleteAlert = true
            } label: {
                Label(LocalizationHelper.string("delete", default: "Delete"), systemImage: "trash")
            }
        }
    }

    // MARK: – Empty Saves View
    private var emptySavesView: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.12))
                    .frame(width: 74, height: 74)

                Image(systemName: "externaldrive.badge.plus")
                    .font(.system(size: 32, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
            }
            .padding(.top, 14)

            VStack(spacing: 6) {
                Text(LocalizationHelper.string("saves.empty.title", default: "No Saves Yet"))
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.primary)

                Text(LocalizationHelper.string("saves.empty.subtitle", default: "Save your gameplay state at any time to resume later."))
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
                        Image(systemName: "plus.circle.fill")
                            .font(.headline)
                    }
                    Text(LocalizationHelper.string("saves.create_now", default: "Create Save State"))
                        .font(.headline)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }
            .buttonStyle(.borderedProminent)
            .tint(Color.accentColor)
            .disabled(isSaving)
            .padding(.horizontal, 20)
            .padding(.top, 6)
            .padding(.bottom, 12)
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .background(Color(UIColor.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .shadow(color: Color.black.opacity(0.08), radius: 8, y: 3)
        .padding(.top, 20)
    }

    private func loadState(slot: Int) {
        Task {
            let success = await engine.loadState(for: gameFileName, slot: slot)
            if success {
                engine.setPaused(false)
                withAnimation(.easeInOut(duration: 0.25)) {
                    isPresented = false
                }
            }
        }
    }

    private func overwriteSave(slot: Int) {
        guard !isSaving else { return }
        isSaving = true
        Task {
            let success = await engine.saveState(for: gameFileName, slot: slot)
            await MainActor.run {
                if success {
                    fetchAllSaves()
                }
                isSaving = false
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
            let extensions = [".state", "_ydcore.state", ".jpg", ".png"]
            for ext in extensions {
                let fileURL = gameDir.appendingPathComponent("slot\(slot)\(ext)")
                try? FileManager.default.removeItem(at: fileURL)
            }

            if let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
                let savesDir = docs.appendingPathComponent("Saves")
                let safeName = fileName.replacingOccurrences(of: "/", with: "_")
                for ext in extensions {
                    let fileURL = savesDir.appendingPathComponent("\(safeName)_slot\(slot)\(ext)")
                    try? FileManager.default.removeItem(at: fileURL)
                }
            }
            await MainActor.run {
                self.fetchAllSaves()
            }
        }
    }
    
    private func fetchAllSaves() {
        let fileName = gameFileName
        let currentEngine = self.engine
        Task.detached(priority: .userInitiated) {
            var rawSaves = [Int: (date: Date, isYdCore: Bool)]()
            let gameURL = URL(fileURLWithPath: fileName)
            let gameDir = gameURL.deletingLastPathComponent()

            // 1. Check game directory (slotX.state, slotX_ydcore.state)
            if let files = try? FileManager.default.contentsOfDirectory(atPath: gameDir.path) {
                for file in files {
                    if file.hasPrefix("slot") {
                        let isYd = file.hasSuffix("_ydcore.state")
                        let isState = file.hasSuffix(".state")
                        if isYd || isState {
                            let numStr = file.replacingOccurrences(of: "slot", with: "")
                                .replacingOccurrences(of: "_ydcore.state", with: "")
                                .replacingOccurrences(of: ".state", with: "")
                            if let slot = Int(numStr) {
                                let fileURL = gameDir.appendingPathComponent(file)
                                if let attr = try? FileManager.default.attributesOfItem(atPath: fileURL.path),
                                   let date = attr[.modificationDate] as? Date {
                                    rawSaves[slot] = (date: date, isYdCore: isYd)
                                }
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
                                        rawSaves[slot] = (date: date, isYdCore: false)
                                    }
                                } else if rawSaves[slot] == nil {
                                    if let attr = try? FileManager.default.attributesOfItem(atPath: legacyURL.path),
                                       let date = attr[.modificationDate] as? Date {
                                        rawSaves[slot] = (date: date, isYdCore: false)
                                    }
                                }
                            }
                        }
                    }
                }
            }

            var items: [SaveSlotItem] = []
            for (slot, saveInfo) in rawSaves {
                let thumbnail = await currentEngine.loadScreenshot(for: fileName, slot: slot)
                let coreTag = saveInfo.isYdCore ? "YD-Core" : "PicoDrive"
                items.append(SaveSlotItem(
                    id: slot,
                    slot: slot,
                    date: saveInfo.date,
                    thumbnail: thumbnail,
                    coreInfo: coreTag
                ))
            }

            let sorted = items.sorted(by: { $0.date > $1.date })
            await MainActor.run {
                self.savedSlots = sorted
                self.isLoading = false
            }
        }
    }
}
