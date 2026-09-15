import Foundation
import Testing
@testable import InstaDictCore

private func responsePack() -> DictionaryPack {
    DictionaryPack(id: .englishEnglish, version: "test", schemaVersion: 3,
                   entryCount: 1, byteCount: 100, sha256: String(repeating: "a", count: 64),
                   url: URL(string: "https://example.com/pack.sqlite")!)
}

@Test(arguments: [200, 206])
func completedDownloadAcceptsNormalAndResumedResponses(_ status: Int) throws {
    try responsePack().validateDownload(statusCode: status, fileByteCount: 100)
}

@Test(arguments: [200, 206])
func partialFileIsNotMistakenForACompletedDownload(_ status: Int) {
    for size: Int64 in [0, 40, 99, 101] {
        do {
            try responsePack().validateDownload(statusCode: status, fileByteCount: size)
            Issue.record("Incomplete or oversized file was accepted")
        } catch PackError.sizeMismatch {} catch { Issue.record("Unexpected error: \(error)") }
    }
}

@Test(arguments: [0, 204, 301, 404, 416, 500])
func failedHTTPResponsesRemainErrors(_ status: Int) {
    do {
        try responsePack().validateDownload(statusCode: status, fileByteCount: 100)
        Issue.record("HTTP error was accepted")
    } catch PackError.http(let code) { #expect(code == status) }
    catch { Issue.record("Unexpected error: \(error)") }
}
