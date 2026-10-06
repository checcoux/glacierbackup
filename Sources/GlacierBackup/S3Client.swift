import Foundation

struct S3Error: LocalizedError {
    let status: Int
    let code: String?
    let message: String?
    let bucketRegion: String?

    var isRetryable: Bool {
        status >= 500 || code == "RequestTimeout" || code == "SlowDown"
    }

    var errorDescription: String? {
        if let bucketRegion, status == 301 || status == 400 || code == "AuthorizationHeaderMalformed" {
            return "Regione errata: il bucket si trova in \(bucketRegion)."
        }
        switch code {
        case "InvalidAccessKeyId": return "Access Key ID non valida."
        case "SignatureDoesNotMatch": return "Secret Access Key non valida."
        case "AccessDenied": return "Accesso negato: la chiave non ha i permessi necessari sul bucket."
        case "NoSuchBucket": return "Il bucket non esiste."
        case "RequestTimeTooSkewed": return "L'orologio del Mac non è sincronizzato con AWS."
        default: break
        }
        if let code {
            return "Errore S3 \(code): \(message ?? "HTTP \(status)")"
        }
        switch status {
        case 403: return "Accesso negato (HTTP 403): controlla credenziali e permessi."
        case 404: return "Bucket non trovato (HTTP 404)."
        default: return "Errore S3 (HTTP \(status))."
        }
    }
}

struct S3Client {
    enum ConfigurationError: LocalizedError {
        case invalidEndpoint

        var errorDescription: String? { "Nome del bucket o regione non validi." }
    }

    let credentials: AWSCredentials
    let region: String
    let bucket: String

    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 120
        configuration.waitsForConnectivity = true
        return URLSession(configuration: configuration)
    }()

    // MARK: - Operazioni

    /// Verifica che il bucket sia raggiungibile con le credenziali configurate.
    func headBucket() async throws {
        _ = try await send("HEAD")
    }

    func createMultipartUpload(key: String, storageClass: String, contentType: String) async throws -> String {
        let (data, _) = try await send(
            "POST",
            key: key,
            query: [("uploads", "")],
            headers: ["x-amz-storage-class": storageClass, "Content-Type": contentType]
        )
        guard let uploadID = Self.xmlValue("UploadId", in: data) else {
            throw S3Error(status: 200, code: "InvalidResponse", message: "UploadId mancante", bucketRegion: nil)
        }
        return uploadID
    }

    /// Carica una parte e ne restituisce l'ETag.
    func uploadPart(
        key: String,
        uploadID: String,
        partNumber: Int,
        data: Data,
        onProgress: @escaping (Int64) -> Void
    ) async throws -> String {
        let (_, response) = try await send(
            "PUT",
            key: key,
            query: [("partNumber", String(partNumber)), ("uploadId", uploadID)],
            body: data,
            onProgress: onProgress
        )
        guard let etag = response.value(forHTTPHeaderField: "ETag") else {
            throw S3Error(status: 200, code: "InvalidResponse", message: "ETag mancante", bucketRegion: nil)
        }
        return etag
    }

    func completeMultipartUpload(key: String, uploadID: String, parts: [(number: Int, etag: String)]) async throws {
        let body = "<CompleteMultipartUpload>"
            + parts.sorted { $0.number < $1.number }
                .map { "<Part><PartNumber>\($0.number)</PartNumber><ETag>\($0.etag)</ETag></Part>" }
                .joined()
            + "</CompleteMultipartUpload>"
        let (data, _) = try await send(
            "POST",
            key: key,
            query: [("uploadId", uploadID)],
            headers: ["Content-Type": "application/xml"],
            body: Data(body.utf8)
        )
        // S3 può rispondere 200 con un errore nel corpo.
        if let code = Self.xmlValue("Code", in: data) {
            throw S3Error(status: 200, code: code, message: Self.xmlValue("Message", in: data), bucketRegion: nil)
        }
    }

    func abortMultipartUpload(key: String, uploadID: String) async throws {
        _ = try await send("DELETE", key: key, query: [("uploadId", uploadID)])
    }

    // MARK: - Richieste

    func makeURL(key: String?, query: [(String, String)]) throws -> URL {
        // I bucket con un punto nel nome non sono compatibili con il certificato wildcard.
        let pathStyle = bucket.contains(".")
        let host = pathStyle ? "s3.\(region).amazonaws.com" : "\(bucket).s3.\(region).amazonaws.com"
        var path = pathStyle ? "/\(bucket)" : ""
        if let key {
            path += "/" + key.split(separator: "/", omittingEmptySubsequences: false)
                .map { SigV4.awsEncode(String($0)) }
                .joined(separator: "/")
        }
        if path.isEmpty { path = "/" }
        var string = "https://\(host)\(path)"
        if !query.isEmpty {
            string += "?" + query.map { "\(SigV4.awsEncode($0.0))=\(SigV4.awsEncode($0.1))" }.joined(separator: "&")
        }
        guard let url = URL(string: string) else { throw ConfigurationError.invalidEndpoint }
        return url
    }

    private func send(
        _ method: String,
        key: String? = nil,
        query: [(String, String)] = [],
        headers: [String: String] = [:],
        body: Data? = nil,
        onProgress: ((Int64) -> Void)? = nil
    ) async throws -> (Data, HTTPURLResponse) {
        var request = URLRequest(url: try makeURL(key: key, query: query))
        request.httpMethod = method
        for (name, value) in headers {
            request.setValue(value, forHTTPHeaderField: name)
        }
        let payloadHash = body.map(SigV4.sha256Hex) ?? SigV4.emptyPayloadHash
        SigV4.sign(&request, payloadHash: payloadHash, credentials: credentials, region: region)

        let (data, response): (Data, URLResponse)
        if let body {
            let delegate = onProgress.map(UploadProgressDelegate.init)
            (data, response) = try await Self.session.upload(for: request, from: body, delegate: delegate)
        } else {
            (data, response) = try await Self.session.data(for: request)
        }
        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        guard (200..<300).contains(http.statusCode) else {
            throw S3Error(
                status: http.statusCode,
                code: Self.xmlValue("Code", in: data),
                message: Self.xmlValue("Message", in: data),
                bucketRegion: http.value(forHTTPHeaderField: "x-amz-bucket-region")
                    ?? Self.xmlValue("Region", in: data)
            )
        }
        return (data, http)
    }

    static func xmlValue(_ tag: String, in data: Data) -> String? {
        guard let text = String(data: data, encoding: .utf8),
              let start = text.range(of: "<\(tag)>"),
              let end = text.range(of: "</\(tag)>", range: start.upperBound..<text.endIndex)
        else { return nil }
        return String(text[start.upperBound..<end.lowerBound])
    }
}

private final class UploadProgressDelegate: NSObject, URLSessionTaskDelegate {
    private let onProgress: (Int64) -> Void

    init(onProgress: @escaping (Int64) -> Void) {
        self.onProgress = onProgress
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didSendBodyData bytesSent: Int64,
        totalBytesSent: Int64,
        totalBytesExpectedToSend: Int64
    ) {
        onProgress(totalBytesSent)
    }
}
