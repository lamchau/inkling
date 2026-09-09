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
        guard !data.contains(0) else {
            throw InklingError.binary(canonicalURL)
        }

        let text = String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .utf16)
            ?? String(decoding: data, as: UTF8.self)
        return LoadedTextFile(url: canonicalURL, text: text)
    }

    func save(_ text: String, to url: URL) throws {
        do {
            try text.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            throw InklingError.unwritable(url, error)
        }
    }
}
