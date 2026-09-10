import Foundation
import Testing
@testable import Inkling

@Suite("Text file service")
struct TextFileServiceTests {
    private let service = TextFileService()

    @Test("loads UTF-8")
    func loadsUTF8() throws {
        let text = "Hello, café\n"
        let loaded = try load(Data(text.utf8))

        #expect(loaded.text == text)
    }

    @Test("loads UTF-8 BOM without exposing the BOM")
    func loadsUTF8BOM() throws {
        let text = "Hello, café\n"
        var data = Data([0xEF, 0xBB, 0xBF])
        data.append(contentsOf: text.utf8)

        let loaded = try load(data)

        #expect(loaded.text == text)
    }

    @Test("loads UTF-16 little-endian BOM")
    func loadsUTF16LittleEndian() throws {
        let text = "Hello, café\n"
        let loaded = try load(utf16Fixture(text, littleEndian: true))

        #expect(loaded.text == text)
    }

    @Test("loads UTF-16 big-endian BOM")
    func loadsUTF16BigEndian() throws {
        let text = "Hello, café\n"
        let loaded = try load(utf16Fixture(text, littleEndian: false))

        #expect(loaded.text == text)
    }

    @Test("retains CRLF line endings")
    func retainsCRLF() throws {
        let text = "first\r\nsecond\r\n"
        let loaded = try load(Data(text.utf8))

        #expect(loaded.text == text)
    }

    @Test("rejects malformed unsupported bytes")
    func rejectsMalformedBytes() throws {
        let url = try fixtureURL(for: Data([0xC3, 0x28, 0x80]))
        defer { try? FileManager.default.removeItem(at: url) }

        do {
            _ = try service.load(url)
            Issue.record("Expected malformed bytes to be rejected")
        } catch InklingError.binary(let rejectedURL) {
            #expect(rejectedURL == url.standardizedFileURL.resolvingSymlinksInPath())
        } catch {
            Issue.record("Expected binary-data rejection, got \(error)")
        }
    }

    private func load(_ data: Data) throws -> LoadedTextFile {
        let url = try fixtureURL(for: data)
        defer { try? FileManager.default.removeItem(at: url) }
        return try service.load(url)
    }

    private func fixtureURL(for data: Data) throws -> URL {
        let url = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appending(path: ".build")
            .appending(path: "TextFileServiceTests-\(UUID().uuidString).txt")
        try data.write(to: url)
        return url
    }

    private func utf16Fixture(_ text: String, littleEndian: Bool) -> Data {
        var data = Data(littleEndian ? [0xFF, 0xFE] : [0xFE, 0xFF])
        for codeUnit in text.utf16 {
            let high = UInt8(truncatingIfNeeded: codeUnit >> 8)
            let low = UInt8(truncatingIfNeeded: codeUnit)
            data.append(contentsOf: littleEndian ? [low, high] : [high, low])
        }
        return data
    }
}
