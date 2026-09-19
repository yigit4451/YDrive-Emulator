import SwiftUI

struct SaveManagerView: View {
    @ObservedObject var engine: LibretroEmulatorEngine
    let gameFileName: String
    @Binding var isPresented: Bool
    
    @State private var slotDates: [Int: Date] = [:]
    
    var body: some View {
        ZStack {
            // Darkened background for modal feel
            Color.black.opacity(0.5).ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Header
                HStack {
                    Text("Save States")
                        .font(.title2.bold())
                        .foregroundStyle(.white)
                    
                    Spacer()
                    
                    Button(action: { isPresented = false }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title2)
                            .foregroundStyle(.white.opacity(0.8))
                    }
                }
                .padding()
                .background(Color.black.opacity(0.2))
                
                // Slots
                ScrollView {
                    VStack(spacing: 12) {
                        ForEach(0..<10) { slot in
                            slotRow(for: slot)
                        }
                    }
                    .padding()
                }
            }
            .frame(maxWidth: 500, maxHeight: 600)
            .applyLiquidGlass(cornerRadius: 24)
            .padding()
        }
        .onAppear {
            refreshSlots()
        }
    }
    
    private func refreshSlots() {
        var dates = [Int: Date]()
        for i in 0..<10 {
            if let d = engine.getSaveStateDate(for: gameFileName, slot: i) {
                dates[i] = d
            }
        }
        slotDates = dates
    }
    
    private func slotRow(for slot: Int) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Slot \(slot)")
                    .font(.headline)
                    .foregroundStyle(.white)
                
                if let date = slotDates[slot] {
                    (Text(date, style: .date) + Text(" ") + Text(date, style: .time))
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.7))
                } else {
                    Text("Empty")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.5))
                }
            }
            
            Spacer()
            
            HStack(spacing: 12) {
                if slotDates[slot] != nil {
                    Button(action: {
                        engine.loadState(for: gameFileName, slot: slot) { success in
                            if success {
                                engine.setPaused(false)
                                isPresented = false
                            }
                        }
                    }) {
                        Text("Load")
                            .font(.subheadline.bold())
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(Color.blue.opacity(0.8))
                            .clipShape(Capsule())
                            .foregroundStyle(.white)
                    }
                }
                
                Button(action: {
                    engine.saveState(for: gameFileName, slot: slot) { success in
                        if success { refreshSlots() }
                    }
                }) {
                    Text("Save")
                        .font(.subheadline.bold())
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(Color.green.opacity(0.8))
                        .clipShape(Capsule())
                        .foregroundStyle(.white)
                }
            }
        }
        .padding()
        .background(Color.white.opacity(0.05))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
    }
}
