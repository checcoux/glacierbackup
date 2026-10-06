import CryptoKit
import Foundation

struct AWSCredentials: Codable, Equatable {
    var accessKeyID: String
    var secretAccessKey: String
}

/// AWS Signature Version 4 per le richieste S3 (payload firmato, header Authorization).
enum SigV4 {
    static let emptyPayloadHash = "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"

    /// Percent-encoding secondo le regole AWS: restano in chiaro solo A-Z a-z 0-9 - . _ ~
    static func awsEncode(_ string: String) -> String {
        var result = ""
        for byte in string.utf8 {
            switch byte {
            case UInt8(ascii: "A")...UInt8(ascii: "Z"), UInt8(ascii: "a")...UInt8(ascii: "z"),
                 UInt8(ascii: "0")...UInt8(ascii: "9"), UInt8(ascii: "-"), UInt8(ascii: "."),
                 UInt8(ascii: "_"), UInt8(ascii: "~"):
                result.unicodeScalars.append(UnicodeScalar(byte))
            default:
                result += String(format: "%%%02X", byte)
            }
        }
        return result
    }

    static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    /// Aggiunge a `request` gli header x-amz-date, x-amz-content-sha256 e Authorization.
    /// L'URL deve essere già percent-encoded con `awsEncode`.
    static func sign(
        _ request: inout URLRequest,
        payloadHash: String,
        credentials: AWSCredentials,
        region: String,
        date: Date = Date()
    ) {
        request.setValue(timestamp(date), forHTTPHeaderField: "x-amz-date")
        request.setValue(payloadHash, forHTTPHeaderField: "x-amz-content-sha256")
        let value = authorization(
            method: request.httpMethod ?? "GET",
            url: request.url!,
            headers: request.allHTTPHeaderFields ?? [:],
            payloadHash: payloadHash,
            credentials: credentials,
            region: region,
            date: date
        )
        request.setValue(value, forHTTPHeaderField: "Authorization")
    }

    /// Calcola il valore dell'header Authorization. `headers` contiene tutti gli header
    /// da firmare tranne `host`, che viene ricavato dall'URL.
    static func authorization(
        method: String,
        url: URL,
        headers: [String: String],
        payloadHash: String,
        credentials: AWSCredentials,
        region: String,
        date: Date
    ) -> String {
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        var host = components.host ?? ""
        if let port = components.port { host += ":\(port)" }

        var canonicalHeaders = ["host": host]
        for (name, value) in headers {
            canonicalHeaders[name.lowercased()] = value.trimmingCharacters(in: .whitespaces)
        }
        let headerNames = canonicalHeaders.keys.sorted()
        let signedHeaders = headerNames.joined(separator: ";")

        let path = components.percentEncodedPath.isEmpty ? "/" : components.percentEncodedPath
        let queryItems: [(name: String, value: String)] = (components.percentEncodedQuery ?? "")
            .split(separator: "&")
            .map { item in
                let pair = item.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
                return (String(pair[0]), pair.count > 1 ? String(pair[1]) : "")
            }
        let query = queryItems
            .sorted { ($0.name, $0.value) < ($1.name, $1.value) }
            .map { $0.name + "=" + $0.value }
            .joined(separator: "&")

        let canonicalRequest = [
            method,
            path,
            query,
            headerNames.map { "\($0):\(canonicalHeaders[$0]!)\n" }.joined(),
            signedHeaders,
            payloadHash,
        ].joined(separator: "\n")

        let stamp = timestamp(date)
        let day = String(stamp.prefix(8))
        let scope = "\(day)/\(region)/s3/aws4_request"
        let stringToSign = [
            "AWS4-HMAC-SHA256",
            stamp,
            scope,
            sha256Hex(Data(canonicalRequest.utf8)),
        ].joined(separator: "\n")

        var key = SymmetricKey(data: Data("AWS4\(credentials.secretAccessKey)".utf8))
        for part in [day, region, "s3", "aws4_request"] {
            key = SymmetricKey(data: Data(HMAC<SHA256>.authenticationCode(for: Data(part.utf8), using: key)))
        }
        let signature = HMAC<SHA256>.authenticationCode(for: Data(stringToSign.utf8), using: key)
            .map { String(format: "%02x", $0) }.joined()

        return "AWS4-HMAC-SHA256 Credential=\(credentials.accessKeyID)/\(scope), "
            + "SignedHeaders=\(signedHeaders), Signature=\(signature)"
    }

    static func timestamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        return formatter.string(from: date)
    }
}
