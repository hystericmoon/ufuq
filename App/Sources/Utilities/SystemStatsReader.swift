import Darwin
import Foundation
import UfuqCore

final class SystemStatsReader: @unchecked Sendable {
    static let shared = SystemStatsReader()

    private struct CPUTicks {
        var user: UInt64
        var system: UInt64
        var idle: UInt64
        var nice: UInt64
    }

    private let lock = NSLock()
    private var previousCPU: CPUTicks?
    private var networkTracker = NetworkRateTracker()

    private init() {}

    func read(at now: Date = Date()) -> SystemStatsSnapshot {
        lock.lock()
        defer { lock.unlock() }

        let cpu = readCPUPercent()
        let (memUsed, memTotal) = readMemory()
        let (rx, tx) = readNetworkBytes()
        let rates = networkTracker.sample(rxBytes: rx, txBytes: tx, at: now)

        return SystemStatsSnapshot(
            cpuPercent: cpu,
            memoryUsedBytes: memUsed,
            memoryTotalBytes: memTotal,
            downloadBytesPerSec: rates.download,
            uploadBytesPerSec: rates.upload
        )
    }

    private func readCPUPercent() -> Double {
        var loadInfo = host_cpu_load_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info_data_t>.stride / MemoryLayout<integer_t>.stride)
        let result = withUnsafeMutablePointer(to: &loadInfo) { ptr in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { intPtr in
                host_statistics64(mach_host_self(), HOST_CPU_LOAD_INFO, intPtr, &count)
            }
        }
        guard result == KERN_SUCCESS else { return 0 }

        let current = CPUTicks(
            user: UInt64(loadInfo.cpu_ticks.0),
            system: UInt64(loadInfo.cpu_ticks.1),
            idle: UInt64(loadInfo.cpu_ticks.2),
            nice: UInt64(loadInfo.cpu_ticks.3)
        )
        defer { previousCPU = current }
        guard let prev = previousCPU else { return 0 }

        let dUser = current.user >= prev.user ? current.user - prev.user : 0
        let dSys = current.system >= prev.system ? current.system - prev.system : 0
        let dIdle = current.idle >= prev.idle ? current.idle - prev.idle : 0
        let dNice = current.nice >= prev.nice ? current.nice - prev.nice : 0
        let total = dUser + dSys + dIdle + dNice
        guard total > 0 else { return 0 }
        return Double(dUser + dSys + dNice) / Double(total) * 100.0
    }

    private func readMemory() -> (used: UInt64, total: UInt64) {
        let total = ProcessInfo.processInfo.physicalMemory
        var vmStats = vm_statistics64_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.stride / MemoryLayout<integer_t>.stride)
        let result = withUnsafeMutablePointer(to: &vmStats) { ptr in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { intPtr in
                host_statistics64(mach_host_self(), HOST_VM_INFO64, intPtr, &count)
            }
        }
        guard result == KERN_SUCCESS else { return (0, total) }
        let pageSize = UInt64(vm_kernel_page_size)
        let usedPages = UInt64(vmStats.active_count)
            + UInt64(vmStats.wire_count)
            + UInt64(vmStats.compressor_page_count)
        return (min(total, usedPages * pageSize), total)
    }

    private func readNetworkBytes() -> (rx: UInt64, tx: UInt64) {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let first = ifaddr else { return (0, 0) }
        defer { freeifaddrs(ifaddr) }

        var rx: UInt64 = 0
        var tx: UInt64 = 0
        var ptr: UnsafeMutablePointer<ifaddrs>? = first
        while let current = ptr {
            defer { ptr = current.pointee.ifa_next }
            guard let addr = current.pointee.ifa_addr,
                  addr.pointee.sa_family == UInt8(AF_LINK),
                  let namePtr = current.pointee.ifa_name else { continue }
            let name = String(cString: namePtr)
            guard name.hasPrefix("en"),
                  let data = current.pointee.ifa_data?.assumingMemoryBound(to: if_data.self) else {
                continue
            }
            rx &+= UInt64(data.pointee.ifi_ibytes)
            tx &+= UInt64(data.pointee.ifi_obytes)
        }
        return (rx, tx)
    }
}
