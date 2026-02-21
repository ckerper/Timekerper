import Foundation

enum PersistenceService {

    private static var directory: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("Timekerper", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private static func fileURL(for key: String) -> URL {
        directory.appendingPathComponent("\(key).json")
    }

    static func save<T: Encodable>(_ value: T, key: String) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        guard let data = try? encoder.encode(value) else { return }
        try? data.write(to: fileURL(for: key))
    }

    static func load<T: Decodable>(key: String, as type: T.Type) -> T? {
        let url = fileURL(for: key)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    static func delete(key: String) {
        try? FileManager.default.removeItem(at: fileURL(for: key))
    }
}
