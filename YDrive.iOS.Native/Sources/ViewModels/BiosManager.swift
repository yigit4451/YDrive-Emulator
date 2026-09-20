import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class BiosManager: ObservableObject {
    static let shared = BiosManager()
    
    @Published var isUSABiosInstalled = false
    @Published var isEuropeBiosInstalled = false
    @Published var isJapanBiosInstalled = false
    
    private let biosDir: URL
    
    private init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        biosDir = docs.appendingPathComponent("BIOS")
        
        if !FileManager.default.fileExists(atPath: biosDir.path) {
            try? FileManager.default.createDirectory(at: biosDir, withIntermediateDirectories: true)
        }
        
        refreshStatus()
    }
    
    func refreshStatus() {
        isUSABiosInstalled = FileManager.default.fileExists(atPath: biosDir.appendingPathComponent("bios_CD_U.bin").path)
        isEuropeBiosInstalled = FileManager.default.fileExists(atPath: biosDir.appendingPathComponent("bios_CD_E.bin").path)
        isJapanBiosInstalled = FileManager.default.fileExists(atPath: biosDir.appendingPathComponent("bios_CD_J.bin").path)
    }
    
    func hasAnySegaCDBios() -> Bool {
        return isUSABiosInstalled || isEuropeBiosInstalled || isJapanBiosInstalled
    }
    
    func importBios(url: URL) -> Bool {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        
        guard let data = try? Data(contentsOf: url) else { return false }
        
        // Simple heuristic validation: Sega CD BIOS is typically 128KB (131072 bytes)
        if data.count < 65536 || data.count > 524288 {
            return false // Invalid size for a Sega CD BIOS
        }
        
        let name = url.lastPathComponent.lowercased()
        let destName: String
        
        if name.contains("u") || name.contains("usa") {
            destName = "bios_CD_U.bin"
        } else if name.contains("e") || name.contains("eu") || name.contains("pal") {
            destName = "bios_CD_E.bin"
        } else if name.contains("j") || name.contains("jp") || name.contains("japan") {
            destName = "bios_CD_J.bin"
        } else {
            // Default to US if indeterminate
            destName = "bios_CD_U.bin"
        }
        
        let dest = biosDir.appendingPathComponent(destName)
        do {
            if FileManager.default.fileExists(atPath: dest.path) {
                try FileManager.default.removeItem(at: dest)
            }
            try data.write(to: dest)
            refreshStatus()
            return true
        } catch {
            return false
        }
    }
    
    func deleteBios(region: String) {
        let name: String
        switch region {
        case "USA": name = "bios_CD_U.bin"
        case "Europe": name = "bios_CD_E.bin"
        case "Japan": name = "bios_CD_J.bin"
        default: return
        }
        
        let dest = biosDir.appendingPathComponent(name)
        try? FileManager.default.removeItem(at: dest)
        refreshStatus()
    }
}
