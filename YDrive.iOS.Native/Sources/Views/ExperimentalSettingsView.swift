import SwiftUI

struct ExperimentalSettingsView: View {
    @AppStorage("enableExperimentalCore")           private var enableExperimentalCore: Bool = false
    @AppStorage(CoreSettings.selectedCoreKey)       private var selectedCore: EmulationCoreType = .picodrive
    @AppStorage(CoreSettings.fastMemoryKey)         private var fastMemory: Bool = true
    @AppStorage(CoreSettings.audioInterpolationKey) private var audioInterpolation: Bool = true
    @AppStorage(CoreSettings.forceSixButtonKey)     private var forceSixButton: Bool = false

    @State private var showConfirmationAlert: Bool = false

    private var experimentalCoreBinding: Binding<Bool> {
        Binding(
            get: { enableExperimentalCore },
            set: { newValue in
                if newValue {
                    showConfirmationAlert = true
                } else {
                    enableExperimentalCore = false
                    selectedCore = .picodrive
                }
            }
        )
    }

    var body: some View {
        Form {
            // ── ANA DENEYSEL ANAHTAR ──────────────────────────────────────────
            Section(
                footer: Text("Deneysel çekirdek etkinleştirildiğinde YD-Core v1.2.0 motoru ve gelişmiş donanım seçenekleri açılır.")
            ) {
                Toggle("Deneysel Çekirdek (YD-Core)", isOn: experimentalCoreBinding)
                    .tint(.blue)
            }

            // ── EMÜLASYON ÇEKİRDEĞİ ───────────────────────────────────────────
            Section(
                header: Text("Emülasyon Çekirdeği"),
                footer: Text("YD-Core, saf C ile sıfırdan geliştirilmiş bağımsız SEGA çekirdeğidir. Kararsızlık durumunda varsayılan motora dönebilirsiniz.")
            ) {
                Picker("Aktif Çekirdek", selection: $selectedCore) {
                    ForEach(EmulationCoreType.allCases) { core in
                        Text(core.displayName).tag(core)
                    }
                }
                .pickerStyle(.inline)
            }
            .disabled(!enableExperimentalCore)
            .opacity(enableExperimentalCore ? 1.0 : 0.45)

            // ── YD-CORE GELİŞMİŞ AYARLAR ──────────────────────────────────────
            Section(header: Text("YD-Core Gelişmiş Ayarlar")) {
                Toggle("Doğrudan Bellek Erişimi (DMA)", isOn: $fastMemory)
                    .tint(.blue)

                Toggle("Ses Enterpolasyonu (44.1 kHz)", isOn: $audioInterpolation)
                    .tint(.blue)

                Toggle("6-Buton Kontrolcü Zorla", isOn: $forceSixButton)
                    .tint(.blue)
            }
            .disabled(!enableExperimentalCore)
            .opacity(enableExperimentalCore ? 1.0 : 0.45)

            // ── MOTOR BİLGİSİ ─────────────────────────────────────────────────
            Section(footer: Text("YD-Core v1.2.0 • Gold Master Build")) {
                HStack {
                    Text("Motor Mimarisi")
                    Spacer()
                    Text("Pure C / Libretro")
                        .foregroundColor(.secondary)
                }

                HStack {
                    Text("İşlemci Çekirdekleri")
                    Spacer()
                    Text("Zilog Z80 & Motorola 68000")
                        .foregroundColor(.secondary)
                }

                HStack {
                    Text("Ses Sentezleyici")
                    Spacer()
                    Text("YM2612 FM + SN76489 PSG")
                        .foregroundColor(.secondary)
                }

                HStack {
                    Text("Durum Kaydı (Save State)")
                    Spacer()
                    Text("YDSS v2 (FNV-1a)")
                        .foregroundColor(.secondary)
                }
            }
            .disabled(!enableExperimentalCore)
            .opacity(enableExperimentalCore ? 1.0 : 0.45)
        }
        .navigationTitle("Deneysel Ayarlar")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Deneysel Ayarlar", isPresented: $showConfirmationAlert) {
            Button("Vazgeç", role: .cancel) {
                enableExperimentalCore = false
            }
            Button("Aç", role: .destructive) {
                enableExperimentalCore = true
                selectedCore = .ydCore
            }
        } message: {
            Text("Deneysel ayarlar henüz geliştirme aşamasındadır ve hatalar olabilir. Yine de deneysel ayarları açmak istiyor musunuz?")
        }
    }
}

#Preview {
    NavigationStack {
        ExperimentalSettingsView()
    }
}
