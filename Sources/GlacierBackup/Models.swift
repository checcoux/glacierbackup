import Foundation

enum StorageClass: String, Codable, CaseIterable, Identifiable {
    case deepArchive = "DEEP_ARCHIVE"
    case glacier = "GLACIER"
    case glacierInstant = "GLACIER_IR"
    case standard = "STANDARD"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .deepArchive: "Glacier Deep Archive (il più economico)"
        case .glacier: "Glacier Flexible Retrieval"
        case .glacierInstant: "Glacier Instant Retrieval"
        case .standard: "Standard (solo per prove)"
        }
    }
}

struct AppSettings: Codable, Equatable {
    var region = "eu-west-1"
    var bucket = ""
    var prefix = "backup"
    var storageClass = StorageClass.deepArchive
    var compress = false

    var isValid: Bool {
        bucket.range(of: "^[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$", options: .regularExpression) != nil
            && region.range(of: "^[a-z0-9-]+$", options: .regularExpression) != nil
    }

    /// Chiave S3 dell'archivio: prefisso/Cartella/Cartella_data.tar[.gz]
    func archiveKey(forFolderNamed name: String, date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd_HHmmss"
        let file = "\(name)_\(formatter.string(from: date)).tar" + (compress ? ".gz" : "")
        let parts = prefix.split(separator: "/").map(String.init) + [name, file]
        return parts.joined(separator: "/")
    }
}

struct BackupFolder: Codable, Identifiable, Equatable {
    var id = UUID()
    var path: String
    var isSelected = true
    var lastBackupDate: Date?
    var lastBackupKey: String?
    var lastBackupSize: Int64?

    var url: URL { URL(fileURLWithPath: path) }
    var name: String { url.lastPathComponent }
}

enum FolderStatus: Equatable {
    case queued
    case measuring
    case uploading(sent: Int64, estimated: Int64)
    case done
    case cancelled
    case failed(String)
}
