import Foundation

public struct SystemStatsSnapshot: Equatable, Sendable {
    public var cpuPercent: Double
    public var memoryUsedBytes: UInt64
    public var memoryTotalBytes: UInt64
    public var downloadBytesPerSec: Double
    public var uploadBytesPerSec: Double

    public init(
        cpuPercent: Double,
        memoryUsedBytes: UInt64,
        memoryTotalBytes: UInt64,
        downloadBytesPerSec: Double = 0,
        uploadBytesPerSec: Double = 0
    ) {
        self.cpuPercent = min(100, max(0, cpuPercent))
        self.memoryUsedBytes = memoryUsedBytes
        self.memoryTotalBytes = memoryTotalBytes
        self.downloadBytesPerSec = max(0, downloadBytesPerSec)
        self.uploadBytesPerSec = max(0, uploadBytesPerSec)
    }

    public var memoryFraction: Double {
        guard memoryTotalBytes > 0 else { return 0 }
        return min(1, max(0, Double(memoryUsedBytes) / Double(memoryTotalBytes)))
    }

    public var memoryPercent: Int {
        Int((memoryFraction * 100).rounded())
    }

    public var formattedCPU: String {
        "\(Int(cpuPercent.rounded()))%"
    }

    public var formattedMemory: String {
        SystemStatsFormat.formatMemory(used: memoryUsedBytes, total: memoryTotalBytes)
    }

    public var formattedDownRate: String {
        SystemStatsFormat.formatRate(downloadBytesPerSec)
    }

    public var formattedUpRate: String {
        SystemStatsFormat.formatRate(uploadBytesPerSec)
    }
}

public struct NetworkRateTracker: Sendable {
    private var previousRX: UInt64?
    private var previousTX: UInt64?
    private var previousDate: Date?

    public init() {}

    public mutating func sample(rxBytes: UInt64, txBytes: UInt64, at now: Date) -> (download: Double, upload: Double) {
        defer {
            previousRX = rxBytes
            previousTX = txBytes
            previousDate = now
        }
        guard let lastRX = previousRX,
              let lastTX = previousTX,
              let lastDate = previousDate else {
            return (0, 0)
        }
        let dt = now.timeIntervalSince(lastDate)
        guard dt > 0 else { return (0, 0) }

        let dRX = rxBytes >= lastRX ? Double(rxBytes - lastRX) : 0
        let dTX = txBytes >= lastTX ? Double(txBytes - lastTX) : 0
        return (dRX / dt, dTX / dt)
    }
}

public enum SystemStatsFormat {
    public static func formatRate(_ bytesPerSec: Double) -> String {
        let rate = max(0, bytesPerSec)
        if rate < 1024 {
            return "\(Int(rate.rounded())) B/s"
        }
        let kb = rate / 1024
        if kb < 1024 {
            return "\(Int(kb.rounded())) KB/s"
        }
        let mb = kb / 1024
        if mb < 1024 {
            return String(format: "%.1f MB/s", mb)
        }
        let gb = mb / 1024
        return String(format: "%.2f GB/s", gb)
    }

    public static func formatMemory(used: UInt64, total: UInt64) -> String {
        let gb: Double = 1024 * 1024 * 1024
        let usedGB = Double(used) / gb
        let totalGB = Double(total) / gb
        if totalGB >= 1 {
            return String(format: "%.1f/%.0fG", usedGB, totalGB)
        }
        let mb: Double = 1024 * 1024
        return String(format: "%.0f/%.0fM", Double(used) / mb, Double(total) / mb)
    }
}
