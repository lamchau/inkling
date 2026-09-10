import Foundation

struct TextFileService: Sendable {
    static let maximumSize = 5 * 1024 * 1024

    func load(_ url: URL) throws -> LoadedTextFile {
        let canonicalURL = url.standardizedFileURL.resolvingSymlinksInPath()
        let data: Data
        do {
            data = try Data(contentsOf: canonicalURL, options: [.mappedIfSafe])
        } catch {
            throw InklingError.unreadable(canonicalURL, error)
        }

        guard data.count <= Self.maximumSize else {
            throw InklingError.tooLarge(canonicalURL)
        }

        guard let text = decode(data), !text.contains("\0") else {
            throw InklingError.binary(canonicalURL)
        }

        return LoadedTextFile(url: canonicalURL, text: text)
    }

    func save(_ text: String, to url: URL) throws {
        do {
            try text.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            throw InklingError.unwritable(url, error)
        }
    }

    private func decode(_ data: Data) -> String? {
        if data.starts(with: [0xEF, 0xBB, 0xBF]) {
            return String(data: data.dropFirst(3), encoding: .utf8)
        }
        if data.starts(with: [0xFF, 0xFE]) {
            return decodeUTF16(data.dropFirst(2), encoding: .utf16LittleEndian)
        }
        if data.starts(with: [0xFE, 0xFF]) {
            return decodeUTF16(data.dropFirst(2), encoding: .utf16BigEndian)
        }

        guard !data.contains(0) else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    private func decodeUTF16(
        _ data: Data.SubSequence,
        encoding: String.Encoding
    ) -> String? {
        guard data.count.isMultiple(of: 2) else {
            return nil
        }
        return String(data: data, encoding: encoding)
    }
}
