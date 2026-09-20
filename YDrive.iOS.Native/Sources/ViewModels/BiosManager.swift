import SwiftUI
import UniformTypeIdentifiers
import CryptoKit

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
        // Re-validate existing files to migrate wrong states from previous bug
        let names = ["bios_CD_U.bin", "bios_CD_E.bin", "bios_CD_J.bin"]
        
        for name in names {
            let fileURL = biosDir.appendingPathComponent(name)
            if FileManager.default.fileExists(atPath: fileURL.path) {
                if let data = try? Data(contentsOf: fileURL) {
                    let region = detectRegion(data: data)
                    
                    let expectedName: String?
                    switch region {
                    case .us: expectedName = "bios_CD_U.bin"
                    case .eu: expectedName = "bios_CD_E.bin"
                    case .jp: expectedName = "bios_CD_J.bin"
                    case .unknown: expectedName = nil
                    }
                    
                    if expectedName != name {
                        try? FileManager.default.removeItem(at: fileURL)
                        // Rescue misnamed valid BIOS
                        if let correctName = expectedName {
                            let correctURL = biosDir.appendingPathComponent(correctName)
                            if !FileManager.default.fileExists(atPath: correctURL.path) {
                                try? data.write(to: correctURL)
                            }
                        }
                    }
                }
            }
        }
        
        isUSABiosInstalled = FileManager.default.fileExists(atPath: biosDir.appendingPathComponent("bios_CD_U.bin").path)
        isEuropeBiosInstalled = FileManager.default.fileExists(atPath: biosDir.appendingPathComponent("bios_CD_E.bin").path)
        isJapanBiosInstalled = FileManager.default.fileExists(atPath: biosDir.appendingPathComponent("bios_CD_J.bin").path)
    }
    
    func hasAnySegaCDBios() -> Bool {
        return isUSABiosInstalled || isEuropeBiosInstalled || isJapanBiosInstalled
    }
    
    enum BiosRegion {
        case unknown, us, eu, jp
    }
    
    private let knownHashes: [String: BiosRegion] = [
        "2efd74e3232ff264e3042e5339597c29": .us,
        "854b9150240a198074c5716bb2b45880": .us,
        "e66fa1dc5820d254611fd9e107da504e": .us,
        "e2298711e6804f5e7178c18c1b268573": .eu,
        "2e49d2c03eb73e653d35d110ac1fdd14": .eu,
        "278a9397e1421490f0aa7d94943f2f0a": .jp,
        "9d2da8f219b1b706f9d2a6a5d4e16d3f": .jp,
        "bdeb4c47da613315afbab03b14b977b0": .jp
    ]
    
    private func detectRegion(data: Data) -> BiosRegion {
        if data.count != 131072 && data.count != 262144 {
            return .unknown
        }
        
        if data.count >= 0x200 {
            let magicData = data.subdata(in: 0x100..<0x110)
            if let magicStr = String(data: magicData, encoding: .ascii), magicStr.uppercased().contains("SEGA") {
                
                let regionByte = data[0x01F0]
                let regionChar = Character(UnicodeScalar(regionByte))
                switch regionChar.uppercased() {
                case "U", "A": return .us
                case "E": return .eu
                case "J": return .jp
                default: break
                }
                
                let headerData = data.subdata(in: 0x100..<0x200)
                if let headerStr = String(data: headerData, encoding: .ascii)?.uppercased() {
                    if headerStr.contains("USA") || headerStr.contains("AMERICA") || headerStr.contains("NTSC-U") {
                        return .us
                    }
                    if headerStr.contains("EUROPE") || headerStr.contains("PAL") {
                        return .eu
                    }
                    if headerStr.contains("JAPAN") || headerStr.contains("NTSC-J") {
                        return .jp
                    }
                }
            }
        }
        
        let hash = Insecure.MD5.hash(data: data)
        let hashString = hash.map { String(format: "%02x", $0) }.joined()
        return knownHashes[hashString] ?? .unknown
    }
    
    func importBios(url: URL) -> Bool {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        
        guard let data = try? Data(contentsOf: url) else { return false }
        
        let region = detectRegion(data: data)
        guard region != .unknown else { return false }
        
        let destName: String
        switch region {
        case .us: destName = "bios_CD_U.bin"
        case .eu: destName = "bios_CD_E.bin"
        case .jp: destName = "bios_CD_J.bin"
        case .unknown: return false
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
