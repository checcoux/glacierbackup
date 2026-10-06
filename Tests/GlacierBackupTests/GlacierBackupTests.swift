import XCTest
@testable import GlacierBackup

final class SigV4Tests: XCTestCase {
    // Esempi dalla documentazione AWS "Signature Calculations for the Authorization Header".
    private let credentials = AWSCredentials(
        accessKeyID: "AKIAIOSFODNN7EXAMPLE",
        secretAccessKey: "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY"
    )
    private let date = Date(timeIntervalSince1970: 1_369_353_600) // 20130524T000000Z

    private func signature(
        _ method: String,
        _ url: String,
        headers: [String: String] = [:],
        payloadHash: String = SigV4.emptyPayloadHash
    ) -> String {
        var allHeaders = headers
        allHeaders["x-amz-date"] = "20130524T000000Z"
        allHeaders["x-amz-content-sha256"] = payloadHash
        let authorization = SigV4.authorization(
            method: method,
            url: URL(string: url)!,
            headers: allHeaders,
            payloadHash: payloadHash,
            credentials: credentials,
            region: "us-east-1",
            date: date
        )
        return String(authorization.split(separator: "=").last!)
    }

    func testGetObject() {
        XCTAssertEqual(
            signature("GET", "https://examplebucket.s3.amazonaws.com/test.txt", headers: ["Range": "bytes=0-9"]),
            "f0e8bdb87c964420e857bd35b5d6ed310bd44f0170aba48dd91039c6036bdb41"
        )
    }

    func testPutObject() {
        XCTAssertEqual(
            signature(
                "PUT",
                "https://examplebucket.s3.amazonaws.com/test%24file.text",
                headers: ["Date": "Fri, 24 May 2013 00:00:00 GMT", "x-amz-storage-class": "REDUCED_REDUNDANCY"],
                payloadHash: "44ce7dd67c959e0d3524ffac1771dfbba87d2b6b4b4e99e42034a8b803f8b072"
            ),
            "98ad721746da40c64f1a55b78f14c238d841ea1380cd77a1b5971af0ece108bd"
        )
    }

    func testQueryWithoutValue() {
        XCTAssertEqual(
            signature("GET", "https://examplebucket.s3.amazonaws.com/?lifecycle"),
            "fea454ca298b7da1c68078a5d1bdbfbbe0d65c699e0f91ac7a200a0136783543"
        )
    }

    func testQueryParameters() {
        XCTAssertEqual(
            signature("GET", "https://examplebucket.s3.amazonaws.com/?max-keys=2&prefix=J"),
            "34b48302e7b5fa45bde8084f4b7868a86f0a534bc59db6670ed5711ef69dc6f7"
        )
    }

    func testTimestamp() {
        XCTAssertEqual(SigV4.timestamp(date), "20130524T000000Z")
    }
}

final class S3ClientTests: XCTestCase {
    private let credentials = AWSCredentials(accessKeyID: "id", secretAccessKey: "secret")

    func testURLKeepsAWSEncodingThroughURLComponents() throws {
        let client = S3Client(credentials: credentials, region: "eu-west-1", bucket: "my-bucket")
        let url = try client.makeURL(
            key: "backup/Foto città/Foto (1)+a_2026.tar",
            query: [("partNumber", "1"), ("uploadId", "a/b+c=")]
        )
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        XCTAssertEqual(components.host, "my-bucket.s3.eu-west-1.amazonaws.com")
        XCTAssertEqual(components.percentEncodedPath, "/backup/Foto%20citt%C3%A0/Foto%20%281%29%2Ba_2026.tar")
        XCTAssertEqual(components.percentEncodedQuery, "partNumber=1&uploadId=a%2Fb%2Bc%3D")
    }

    func testDottedBucketUsesPathStyle() throws {
        let client = S3Client(credentials: credentials, region: "eu-west-1", bucket: "my.bucket")
        let url = try client.makeURL(key: "a.tar", query: [])
        XCTAssertEqual(url.absoluteString, "https://s3.eu-west-1.amazonaws.com/my.bucket/a.tar")
    }

    func testXMLValue() {
        let xml = Data("<Error><Code>AccessDenied</Code><Message>No</Message></Error>".utf8)
        XCTAssertEqual(S3Client.xmlValue("Code", in: xml), "AccessDenied")
        XCTAssertNil(S3Client.xmlValue("UploadId", in: xml))
    }
}

final class ArchiveTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let folder = root.appendingPathComponent("Dati importanti/sotto")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data(repeating: 7, count: 100_000).write(to: folder.appendingPathComponent("grande.bin"))
        try Data("ciao".utf8).write(to: folder.deletingLastPathComponent().appendingPathComponent("nota.txt"))
        try Data().write(to: folder.deletingLastPathComponent().appendingPathComponent(".DS_Store"))
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: root)
    }

    func testTarStreamProducesReadableArchiveInChunks() async throws {
        let folder = root.appendingPathComponent("Dati importanti")
        let tar = TarStream(folder: folder, compress: false)
        try tar.start()
        var archive = Data()
        var chunkSizes: [Int] = []
        while let chunk = try await tar.nextChunk(size: 30_000) {
            chunkSizes.append(chunk.count)
            archive.append(chunk)
        }
        try tar.finish()
        XCTAssertTrue(chunkSizes.dropLast().allSatisfy { $0 == 30_000 })

        let file = root.appendingPathComponent("out.tar")
        try archive.write(to: file)
        let list = Process()
        let pipe = Pipe()
        list.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
        list.arguments = ["-tf", file.path]
        list.standardOutput = pipe
        try list.run()
        let names = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        list.waitUntilExit()
        XCTAssertTrue(names.contains("Dati importanti/sotto/grande.bin"))
        XCTAssertTrue(names.contains("Dati importanti/nota.txt"))
        XCTAssertFalse(names.contains(".DS_Store"))

        let estimate = BackupEngine.estimateArchiveSize(of: folder)
        XCTAssertEqual(Double(estimate), Double(archive.count), accuracy: Double(archive.count) * 0.2)
    }

    func testTarStreamReportsFailure() async throws {
        let tar = TarStream(folder: root.appendingPathComponent("inesistente"), compress: false)
        try tar.start()
        while try await tar.nextChunk(size: 30_000) != nil {}
        XCTAssertThrowsError(try tar.finish())
    }

    func testArchiveKeyAndPartSize() {
        var settings = AppSettings()
        settings.prefix = "/mac/backup/"
        settings.compress = true
        let key = settings.archiveKey(forFolderNamed: "Foto", date: Date())
        XCTAssertNotNil(key.range(of: #"^mac/backup/Foto/Foto_\d{4}-\d{2}-\d{2}_\d{6}\.tar\.gz$"#, options: .regularExpression))

        XCTAssertEqual(BackupEngine.partSize(forEstimatedSize: 1_000_000), BackupEngine.minimumPartSize)
        let terabyte: Int64 = 1 << 40
        XCTAssertGreaterThan(Int64(BackupEngine.partSize(forEstimatedSize: terabyte)) * 9_000, terabyte)
    }
}
