import Foundation

@MainActor
final class AppState: ObservableObject {
    @Published var settings: AppSettings {
        didSet { Self.store(settings, forKey: "settings") }
    }
    @Published var folders: [BackupFolder] {
        didSet { Self.store(folders, forKey: "folders") }
    }
    @Published private(set) var credentials: AWSCredentials?
    @Published private(set) var statuses: [UUID: FolderStatus] = [:]
    @Published private(set) var isRunning = false

    private var runTask: Task<Void, Never>?

    init() {
        settings = Self.restore(AppSettings.self, forKey: "settings") ?? AppSettings()
        folders = Self.restore([BackupFolder].self, forKey: "folders") ?? []
        credentials = Keychain.load()
    }

    var isConfigured: Bool { credentials != nil && settings.isValid }

    var canStart: Bool { isConfigured && !isRunning && folders.contains(where: \.isSelected) }

    func saveCredentials(_ credentials: AWSCredentials) throws {
        try Keychain.save(credentials)
        self.credentials = credentials
    }

    func addFolders(_ urls: [URL]) {
        for url in urls where !folders.contains(where: { $0.path == url.path }) {
            folders.append(BackupFolder(path: url.path))
        }
    }

    func removeFolder(_ id: UUID) {
        folders.removeAll { $0.id == id }
        statuses[id] = nil
    }

    func startBackup() {
        guard canStart, let credentials else { return }
        let client = S3Client(credentials: credentials, region: settings.region, bucket: settings.bucket)
        let queue = folders.filter(\.isSelected)
        statuses = Dictionary(uniqueKeysWithValues: queue.map { ($0.id, .queued) })
        isRunning = true
        runTask = Task {
            // Evita che il Mac vada in stop durante un caricamento lungo.
            let activity = ProcessInfo.processInfo.beginActivity(
                options: [.userInitiated, .idleSystemSleepDisabled],
                reason: "Backup su S3 in corso"
            )
            for folder in queue {
                if Task.isCancelled {
                    statuses[folder.id] = .cancelled
                    continue
                }
                await backUp(folder, client: client)
            }
            ProcessInfo.processInfo.endActivity(activity)
            isRunning = false
        }
    }

    func cancelBackup() {
        runTask?.cancel()
    }

    private func backUp(_ folder: BackupFolder, client: S3Client) async {
        let id = folder.id
        let url = folder.url
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            statuses[id] = .failed("La cartella non esiste più.")
            return
        }

        statuses[id] = .measuring
        let estimate = await Task.detached { BackupEngine.estimateArchiveSize(of: url) }.value
        let date = Date()
        let key = settings.archiveKey(forFolderNamed: folder.name, date: date)
        statuses[id] = .uploading(sent: 0, estimated: estimate)

        do {
            let size = try await BackupEngine.run(
                folder: url,
                key: key,
                storageClass: settings.storageClass.rawValue,
                compress: settings.compress,
                estimatedSize: estimate,
                client: client
            ) { [weak self] sent in
                Task { @MainActor in
                    guard let self, case .uploading = self.statuses[id] else { return }
                    self.statuses[id] = .uploading(sent: sent, estimated: estimate)
                }
            }
            statuses[id] = .done
            if let index = folders.firstIndex(where: { $0.id == id }) {
                folders[index].lastBackupDate = date
                folders[index].lastBackupKey = key
                folders[index].lastBackupSize = size
            }
        } catch is CancellationError {
            statuses[id] = .cancelled
        } catch {
            statuses[id] = .failed(error.localizedDescription)
        }
    }

    // MARK: - Persistenza

    private static func store<Value: Encodable>(_ value: Value, forKey key: String) {
        UserDefaults.standard.set(try? JSONEncoder().encode(value), forKey: key)
    }

    private static func restore<Value: Decodable>(_ type: Value.Type, forKey key: String) -> Value? {
        UserDefaults.standard.data(forKey: key).flatMap { try? JSONDecoder().decode(type, from: $0) }
    }
}
