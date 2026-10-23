import SwiftUI

struct SaveManagerView: View {
    @ObservedObject var engine: LibretroEmulatorEngine
    let gameFileName: String
    @Binding var isPresented: Bool
    @AppStorage("appTheme") private var appTheme = "system"
    
    @State private var existingSaves: [Int: Date] = [:]
    @State private var slotToDelete: Int?
    @State private var showingDeleteAlert = false
    @State private var isSaving = false

    private var colorScheme: ColorScheme? {
        switch appTheme {
        case "dark": return .dark
        case "light": return .light
        default: return nil
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // ── Compact Floating Header ──────────────────────────────────────
            headerView

            // ── Scrollable Save Slots ────────────────────────────────────────
            ScrollView {
                VStack(spacing: 8) {
                    if existingSaves.isEmpty {
                        emptySavesView
                    } else {
                        ForEach(existingSaves.sorted(by: { $0.value > $1.value }), id: \.key) { slot, date in
                            saveSlotCard(slot: slot, date: date)
                        }
                    }
                }
                .padding(.horizontal, 14)
                .padding(.top, 4)
                .padding(.bottom, 14)
            }
            .scrollContentBackground(.hidden)
        }
        .background(Color.clear)
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
            Text(NSLocalizedString("confirm_delete", comment: "Are you sure you want to delete this save state?"))
        }
        .preferredColorScheme(colorScheme)
    }

    // MARK: – Header View
    private var headerView: some View {
        HStack {
            // Close Button
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isPresented = false
                    if engine.isPaused {
                        engine.setPaused(false)
                    }
                }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 30, height: 30)
            }
            .buttonStyle(.glass)
            .accessibilityLabel(NSLocalizedString("close", comment: "Close"))

            Spacer()

            Text(NSLocalizedString("emulator.saves", comment: "Saves"))
                .font(.headline.weight(.semibold))
                .foregroundStyle(.primary)

            Spacer()

            // New Save Button
            Button(action: addNewSave) {
                HStack(spacing: 5) {
                    if isSaving {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .scaleEffect(0.7)
                    } else {
                        Image(systemName: "plus")
                            .font(.system(size: 13, weight: .bold))
                    }
                    Text(NSLocalizedString("saves.create_now", comment: "New"))
                        .font(.system(size: 13, weight: .semibold))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
            }
            .buttonStyle(.glassProminent)
            .disabled(isSaving)
            .accessibilityLabel(NSLocalizedString("saves.create_now", comment: "New Save"))
        }
        .padding(.horizontal, 14)
        .padding(.top, 12)
        .padding(.bottom, 8)
    }

    // MARK: – Save Slot Card
    private func saveSlotCard(slot: Int, date: Date) -> some View {
        HStack(spacing: 12) {
            // Slot Info
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text("Slot \(slot + 1)")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)

                    Text("STATE")
                        .font(.system(size: 9, weight: .heavy))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1.5)
                        .background(.ultraThinMaterial, in: Capsule())
                }

                HStack(spacing: 4) {
                    Image(systemName: "clock")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                    Text(date, format: .dateTime.month().day().hour().minute().second())
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            // Load Action
            Button {
                Task {
                    let success = await engine.loadState(for: gameFileName, slot: slot)
                    if success {
                        engine.setPaused(false)
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isPresented = false
                        }
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Text("Load")
                        .font(.caption.weight(.semibold))
                    Image(systemName: "play.fill")
                        .font(.system(size: 9))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
            }
            .buttonStyle(.glass)

            // Delete Action
            Button {
                slotToDelete = slot
                showingDeleteAlert = true
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.red)
                    .frame(width: 30, height: 30)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(NSLocalizedString("delete", comment: "Delete"))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    // MARK: – Empty Saves View
    private var emptySavesView: some View {
        VStack(spacing: 10) {
            Image(systemName: "externaldrive.badge.plus")
                .font(.system(size: 28))
                .foregroundStyle(.secondary)
                .padding(.top, 8)

            VStack(spacing: 3) {
                Text(NSLocalizedString("saves.empty.title", comment: "No saves yet"))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)

                Text(NSLocalizedString("saves.empty.subtitle", comment: "Save your gameplay state at any time to resume later."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 12)
            }

            Button(action: addNewSave) {
                HStack(spacing: 5) {
                    if isSaving {
                        ProgressView().tint(.white)
                            .scaleEffect(0.7)
                    } else {
                        Image(systemName: "plus.circle.fill")
                            .font(.caption)
                    }
                    Text(NSLocalizedString("saves.create_now", comment: "Create Save State"))
                        .font(.caption.weight(.semibold))
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
            }
            .buttonStyle(.glassProminent)
            .disabled(isSaving)
            .padding(.bottom, 8)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .padding(.top, 10)
    }

    // MARK: – Data Operations
    private func fetchAllSaves() {
        var saves = [Int: Date]()
        let gameURL = URL(fileURLWithPath: gameFileName)
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
            let safeName = gameFileName.replacingOccurrences(of: "/", with: "_")
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

        existingSaves = saves
    }

    private func addNewSave() {
        guard !isSaving else { return }
        isSaving = true
        let nextSlot = (existingSaves.keys.max() ?? -1) + 1
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
        let gameURL = URL(fileURLWithPath: gameFileName)
        let gameDir = gameURL.deletingLastPathComponent()
        let fileURL = gameDir.appendingPathComponent("slot\(slot).state")
        try? FileManager.default.removeItem(at: fileURL)

        if let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            let legacyURL = docs.appendingPathComponent("Saves").appendingPathComponent("\(gameFileName.replacingOccurrences(of: "/", with: "_"))_slot\(slot).state")
            try? FileManager.default.removeItem(at: legacyURL)
        }
        fetchAllSaves()
    }
}
