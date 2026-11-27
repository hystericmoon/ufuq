import Foundation
import UfuqCore

enum DownloadsMonitor {
    static func scan(directory: URL? = nil) -> [ActiveDownload] {
        let dir = directory ?? FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
        guard let dir else { return [] }

        let keys: [URLResourceKey] = [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey]
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            return []
        }

        var items: [ActiveDownload] = []
        for url in urls {
            guard let values = try? url.resourceValues(forKeys: Set(keys)),
                  values.isRegularFile == true else { continue }
            let name = url.lastPathComponent
            let partial = DownloadsModule.isPartialFile(name)
            items.append(ActiveDownload(
                path: url.path,
                fileName: partial ? DownloadsModule.displayName(for: name) : name,
                byteCount: Int64(values.fileSize ?? 0),
                modifiedAt: values.contentModificationDate ?? Date(),
                isInProgress: partial
            ))
        }
        return items
    }
}
