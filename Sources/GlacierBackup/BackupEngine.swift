import Foundation

enum BackupEngine {
    struct TooLargeError: LocalizedError {
        var errorDescription: String? { "L'archivio supera il numero massimo di parti consentito da S3." }
    }

    static let minimumPartSize = 16 * 1024 * 1024
    static let maximumParts = 10_000
    private static let concurrentUploads = 3
    private static let attemptsPerPart = 6

    /// Stima la dimensione dell'archivio tar non compresso di una cartella.
    static func estimateArchiveSize(of folder: URL) -> Int64 {
        let keys: [URLResourceKey] = [.isRegularFileKey, .fileSizeKey]
        guard let enumerator = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: keys) else {
            return 0
        }
        var total: Int64 = 1024
        for case let url as URL in enumerator {
            let values = try? url.resourceValues(forKeys: Set(keys))
            let size = values?.isRegularFile == true ? Int64(values?.fileSize ?? 0) : 0
            // Ogni voce ha un header da 512 byte e il contenuto è allineato a 512 byte.
            total += 512 + (size + 511) / 512 * 512
        }
        return total
    }

    static func partSize(forEstimatedSize estimate: Int64) -> Int {
        // Margine per header estesi e dati che non si comprimono.
        max(minimumPartSize, Int(estimate / 8_000) + 1)
    }

    /// Archivia `folder` con tar e lo carica su S3 in multipart. Restituisce i byte caricati.
    static func run(
        folder: URL,
        key: String,
        storageClass: String,
        compress: Bool,
        estimatedSize: Int64,
        client: S3Client,
        onProgress: @escaping @Sendable (Int64) -> Void
    ) async throws -> Int64 {
        let uploadID = try await client.createMultipartUpload(
            key: key,
            storageClass: storageClass,
            contentType: compress ? "application/gzip" : "application/x-tar"
        )
        let tar = TarStream(folder: folder, compress: compress)
        let tracker = ProgressTracker(onChange: onProgress)
        let partSize = partSize(forEstimatedSize: estimatedSize)

        do {
            try tar.start()
            let (parts, total) = try await withTaskCancellationHandler {
                try await withThrowingTaskGroup(of: (number: Int, etag: String).self) { group in
                    var parts: [(number: Int, etag: String)] = []
                    var total: Int64 = 0
                    var partNumber = 0
                    var inFlight = 0
                    while let chunk = try await tar.nextChunk(size: partSize) {
                        try Task.checkCancellation()
                        partNumber += 1
                        guard partNumber <= maximumParts else { throw TooLargeError() }
                        total += Int64(chunk.count)
                        if inFlight >= concurrentUploads, let finished = try await group.next() {
                            parts.append(finished)
                            inFlight -= 1
                        }
                        let number = partNumber
                        group.addTask {
                            let etag = try await uploadPart(
                                chunk, number: number, key: key, uploadID: uploadID, client: client, tracker: tracker
                            )
                            return (number, etag)
                        }
                        inFlight += 1
                    }
                    for try await finished in group {
                        parts.append(finished)
                    }
                    return (parts, total)
                }
            } onCancel: {
                tar.terminate()
            }
            try Task.checkCancellation()
            try tar.finish()
            try await client.completeMultipartUpload(key: key, uploadID: uploadID, parts: parts)
            return total
        } catch {
            tar.terminate()
            // Task separato: l'annullamento deve partire anche se questo task è stato cancellato.
            await Task.detached {
                try? await client.abortMultipartUpload(key: key, uploadID: uploadID)
            }.value
            throw Task.isCancelled ? CancellationError() : error
        }
    }

    private static func uploadPart(
        _ data: Data,
        number: Int,
        key: String,
        uploadID: String,
        client: S3Client,
        tracker: ProgressTracker
    ) async throws -> String {
        var attempt = 1
        while true {
            do {
                let etag = try await client.uploadPart(key: key, uploadID: uploadID, partNumber: number, data: data) {
                    tracker.update(part: number, sent: $0)
                }
                tracker.finish(part: number, size: Int64(data.count))
                return etag
            } catch {
                try Task.checkCancellation()
                let retryable = (error as? S3Error)?.isRetryable ?? (error is URLError)
                guard retryable, attempt < attemptsPerPart else { throw error }
                tracker.update(part: number, sent: 0)
                try await Task.sleep(for: .seconds(min(60, 1 << attempt)))
                attempt += 1
            }
        }
    }
}

/// Somma i byte inviati dalle parti in corso e completate, limitando la frequenza delle notifiche.
private final class ProgressTracker: @unchecked Sendable {
    private let lock = NSLock()
    private var completed: Int64 = 0
    private var inFlight: [Int: Int64] = [:]
    private var lastNotification = Date.distantPast
    private let onChange: @Sendable (Int64) -> Void

    init(onChange: @escaping @Sendable (Int64) -> Void) {
        self.onChange = onChange
    }

    func update(part: Int, sent: Int64) {
        notify(force: false) { inFlight[part] = sent }
    }

    func finish(part: Int, size: Int64) {
        notify(force: true) {
            inFlight[part] = nil
            completed += size
        }
    }

    private func notify(force: Bool, _ mutate: () -> Void) {
        lock.lock()
        mutate()
        let total = completed + inFlight.values.reduce(0, +)
        let now = Date()
        let shouldNotify = force || now.timeIntervalSince(lastNotification) > 0.2
        if shouldNotify { lastNotification = now }
        lock.unlock()
        if shouldNotify { onChange(total) }
    }
}
