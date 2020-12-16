import Foundation

public extension FileManager {
    func pathsWithinDirectory(_ directory: URL) throws -> [URL] {
        let contents = try contentsOfDirectory(atPath: directory.path)
        return contents.map {
            URL(fileURLWithPath: $0, relativeTo: directory)
        }
    }

    func filesUnderDirectory(_ directory: URL) throws -> [URL] {
        return try pathsWithinDirectory(directory).flatMap { path -> [URL] in
            if path.hasDirectoryPath {
                return try filesUnderDirectory(path)
            } else {
                return [path]
            }
        }
    }

    func calculateDirectorySize(_ directory: URL) throws -> UInt64 {
        let files = try filesUnderDirectory(directory)
        return files.compactMap {
            do {
                let attributes = try FileManager.default.attributesOfItem(atPath: $0.path)
                guard let fileSize = attributes[.size] as? UInt64 else { return nil }
                return fileSize
            } catch {
                return 0
            }
        }.reduce(0, +)
    }
}
