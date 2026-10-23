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
            // Header Bar
            HStack {
                Button {
                    isPresented = false
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 32, height: 32)
                        .glassEffect(.regular, in: Circle())
                }
                .buttonStyle(.plain)

                Spacer()

                Text(NSLocalizedString("emulator.saves", comment: "Saves"))
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.primary)

                Spacer()

                Button(action: addNewSave) {
                    HStack(spacing: 5) {
                        if isSaving {
                            ProgressView()
                                .progressViewStyle(.circular)
                                .scaleEffect(0.7)
                                .tint(.white)
                        } else {
                            Image(systemName: "plus")
                                .font(.system(size: 12, weight: .bold))
                        }
                        Text("New")
                            .font(.system(size: 14, weight: .semibold))
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                }
                .buttonStyle(.glassProminent)
                .disabled(isSaving)
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 8)

            ZStack {
                // Subtle ambient glass glow at the top
                RadialGradient(
                    colors: [Color.blue.opacity(0.12), Color.clear],
                    center: .top,
                    startRadius: 20,
                    endRadius: 360
                )
                .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 14) {
                        if existingSaves.isEmpty {
                            emptySavesView
                        } else {
                            // Sort descending by date so newest is at the top
                            ForEach(existingSaves.sorted(by: { $0.value > $1.value }), id: \.key) { slot, date in
                                liquidGlassSaveCard(slot: slot, date: date)
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 28)
                }
                .scrollContentBackground(.hidden)
            }
        }
        .background(Color.clear)
        .presentationBackground(.ultraThinMaterial)
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
        .preferredColorScheme(colorScheme)
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
                    // Glass Icon Orb
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color.blue.opacity(0.30),
                                        Color.cyan.opacity(0.12)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 44, height: 44)
                        
                        Circle()
                            .strokeBorder(
                                LinearGradient(
                                    colors: [Color.white.opacity(0.55), Color.white.opacity(0.12)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1
                            )
                            .frame(width: 44, height: 44)
                        
                        Image(systemName: "externaldrive.fill")
                            .font(.system(size: 19, weight: .semibold))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [Color.white, Color(red: 120/255, green: 220/255, blue: 255/255)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                    }

                    // Slot Information
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 8) {
                            Text("Slot \(slot + 1)")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundStyle(.primary)

                            // Glass pill badge
                            Text("STATE")
                                .font(.system(size: 9, weight: .heavy))
                                .foregroundStyle(Color.cyan)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.cyan.opacity(0.15))
                                .clipShape(Capsule())
                                .overlay(Capsule().strokeBorder(Color.cyan.opacity(0.35), lineWidth: 0.8))
                        }

                        HStack(spacing: 4) {
                            Image(systemName: "clock")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                            Text(date, format: .dateTime.month().day().hour().minute().second())
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Spacer()

                    // Quick Load Indicator Pill
                    HStack(spacing: 3) {
                        Text("Load")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Color.blue)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(Color.blue.opacity(0.8))
                    }
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4.5)
                    .glassEffect(.regular, in: Capsule())
                }
            }
            .buttonStyle(.plain)

            // Glass Delete Button
            Button {
                slotToDelete = slot
                showingDeleteAlert = true
            } label: {
                Image(systemName: "trash.fill")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.red)
                    .frame(width: 34, height: 34)
                    .glassEffect(.regular, in: Circle())
            }
            .buttonStyle(.borderless)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        stops: [
                            .init(color: .white.opacity(0.45), location: 0.0),
                            .init(color: .white.opacity(0.12), location: 0.35),
                            .init(color: Color.blue.opacity(0.35), location: 0.70),
                            .init(color: .white.opacity(0.15), location: 1.0)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1.2
                )
        )
        .shadow(color: Color.black.opacity(0.18), radius: 10, x: 0, y: 5)
    }

    // MARK: – Empty Saves View
    private var emptySavesView: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color.blue.opacity(0.25), Color.cyan.opacity(0.08)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 74, height: 74)
                Circle()
                    .strokeBorder(
                        LinearGradient(
                            colors: [Color.white.opacity(0.45), Color.white.opacity(0.10)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
                    .frame(width: 74, height: 74)

                Image(systemName: "externaldrive.badge.plus")
                    .font(.system(size: 32, weight: .semibold))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Color.white, Color(red: 120/255, green: 220/255, blue: 255/255)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
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
                        Image(systemName: "plus.circle.fill")
                            .font(.headline)
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
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        stops: [
                            .init(color: .white.opacity(0.45), location: 0.0),
                            .init(color: .white.opacity(0.12), location: 0.35),
                            .init(color: Color.blue.opacity(0.35), location: 0.70),
                            .init(color: .white.opacity(0.15), location: 1.0)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1.2
                )
        )
        .shadow(color: Color.black.opacity(0.18), radius: 12, x: 0, y: 6)
        .padding(.top, 20)
    }
    
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
