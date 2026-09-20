import SwiftUI

struct SaveManagerView: View {
    @ObservedObject var engine: LibretroEmulatorEngine
    let gameFileName: String
    @Binding var isPresented: Bool
    
    @State private var existingSaves: [Int: Date] = [:]
    @State private var slotToDelete: Int?
    @State private var showingDeleteAlert = false
    
    var body: some View {
        NavigationStack {
            List {
                if existingSaves.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "floppy.disk")
                            .font(.system(size: 40))
                            .foregroundStyle(.secondary)
                        Text("Henüz save kaydedilmedi")
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding()
                } else {
                    // Sort descending by date so newest is at the top
                    ForEach(existingSaves.sorted(by: { $0.value > $1.value }), id: \.key) { slot, date in
                        HStack {
                            Button(action: {
                                Task {
                                    let success = await engine.loadState(for: gameFileName, slot: slot)
                                    if success {
                                        engine.setPaused(false)
                                        isPresented = false
                                    }
                                }
                            }) {
                                HStack(spacing: 12) {
                                    Image(systemName: "floppy.disk")
                                        .foregroundColor(.blue)
                                    
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("Kayıt \(slot + 1)")
                                            .font(.headline)
                                            .foregroundStyle(.primary)
                                        
                                        (Text(date, style: .date) + Text(" ") + Text(date, style: .time))
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                            
                            Spacer()
                            
                            Button {
                                slotToDelete = slot
                                showingDeleteAlert = true
                            } label: {
                                Image(systemName: "trash")
                                    .foregroundColor(.red)
                            }
                            .buttonStyle(.borderless)
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            .navigationTitle("Saves")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Kapat") {
                        isPresented = false
                    }
                }
                
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: addNewSave) {
                        Image(systemName: "plus")
                            .font(.headline)
                    }
                }
            }
        }
        .onAppear {
            fetchAllSaves()
        }
        .alert("Silmek istediğinize emin misiniz?", isPresented: $showingDeleteAlert) {
            Button("İptal", role: .cancel) { }
            Button("Sil", role: .destructive) {
                if let slot = slotToDelete {
                    deleteSave(slot: slot)
                }
            }
        }
    }
    
    private func fetchAllSaves() {
        guard let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        let savesDir = docs.appendingPathComponent("Saves", isDirectory: true)
        let safeName = gameFileName.replacingOccurrences(of: "/", with: "_")
        
        var saves = [Int: Date]()
        
        if let files = try? FileManager.default.contentsOfDirectory(atPath: savesDir.path) {
            for file in files {
                if file.hasPrefix("\(safeName)_slot"), file.hasSuffix(".state") {
                    let numberString = file
                        .replacingOccurrences(of: "\(safeName)_slot", with: "")
                        .replacingOccurrences(of: ".state", with: "")
                    
                    if let slot = Int(numberString) {
                        if let attr = try? FileManager.default.attributesOfItem(atPath: savesDir.appendingPathComponent(file).path),
                           let date = attr[.modificationDate] as? Date {
                            saves[slot] = date
                        }
                    }
                }
            }
        }
        
        existingSaves = saves
    }
    
    private func addNewSave() {
        let nextSlot = (existingSaves.keys.max() ?? -1) + 1
        Task {
            let success = await engine.saveState(for: gameFileName, slot: nextSlot)
            if success {
                fetchAllSaves()
            }
        }
    }
    
    private func deleteSave(slot: Int) {
        guard let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        let savesDir = docs.appendingPathComponent("Saves", isDirectory: true)
        let safeName = gameFileName.replacingOccurrences(of: "/", with: "_")
        
        let fileURL = savesDir.appendingPathComponent("\(safeName)_slot\(slot).state")
        try? FileManager.default.removeItem(at: fileURL)
        fetchAllSaves()
    }
}
