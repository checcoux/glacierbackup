import Foundation

/// Esegue `tar` su una cartella e ne espone l'output a blocchi, senza passare da file temporanei.
final class TarStream: @unchecked Sendable {
    struct Failure: LocalizedError {
        let status: Int32
        let output: String

        var errorDescription: String? {
            let detail = output.trimmingCharacters(in: .whitespacesAndNewlines)
            return "Creazione dell'archivio fallita (tar \(status))" + (detail.isEmpty ? "." : ": \(detail)")
        }
    }

    private let process = Process()
    private let output = Pipe()
    private let errors = Pipe()
    private let readQueue = DispatchQueue(label: "com.suertestudio.glacierbackup.tar")
    private let lock = NSLock()
    private var errorOutput = Data()

    init(folder: URL, compress: Bool) {
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
        process.arguments = [
            compress ? "-czf" : "-cf", "-",
            "--exclude", ".DS_Store",
            "-C", folder.deletingLastPathComponent().path,
            folder.lastPathComponent,
        ]
        process.standardOutput = output
        process.standardError = errors
        errors.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard let self, !data.isEmpty else { return }
            self.lock.lock()
            if self.errorOutput.count < 4096 { self.errorOutput.append(data.prefix(4096)) }
            self.lock.unlock()
        }
    }

    func start() throws {
        try process.run()
    }

    /// Restituisce il prossimo blocco di `size` byte (l'ultimo può essere più corto), o nil a fine archivio.
    func nextChunk(size: Int) async throws -> Data? {
        try await withCheckedThrowingContinuation { continuation in
            readQueue.async {
                do {
                    var chunk = Data(capacity: size)
                    while chunk.count < size {
                        guard let data = try self.output.fileHandleForReading.read(upToCount: size - chunk.count),
                              !data.isEmpty
                        else { break }
                        chunk.append(data)
                    }
                    continuation.resume(returning: chunk.isEmpty ? nil : chunk)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    func terminate() {
        if process.isRunning { process.terminate() }
    }

    /// Da chiamare dopo aver letto tutto l'output: fallisce se tar non ha archiviato tutti i file.
    func finish() throws {
        process.waitUntilExit()
        errors.fileHandleForReading.readabilityHandler = nil
        guard process.terminationStatus == 0 else {
            lock.lock()
            defer { lock.unlock() }
            throw Failure(status: process.terminationStatus, output: String(decoding: errorOutput, as: UTF8.self))
        }
    }
}
