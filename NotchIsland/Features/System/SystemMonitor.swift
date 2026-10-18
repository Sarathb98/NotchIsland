import AppKit
import Combine
import Network
import Darwin

struct IntegrationCapability {
    let title: String
    let explanation: String
    let isAvailable: Bool
}

protocol BrightnessProviding {
    var capability: IntegrationCapability { get }
    var brightness: Double? { get }
}
struct PublicBrightnessProvider: BrightnessProviding {
    let capability = IntegrationCapability(title: String(localized: "Brightness"), explanation: String(localized: "Use macOS Display settings or the brightness keys. A universal brightness observer is not available through the APIs used by this app."), isAvailable: false)
    let brightness: Double? = nil
}

/// This reports only sessions owned by Notch Island, never other apps' recordings.
@MainActor
final class AppRecordingState: ObservableObject {
    @Published private(set) var isRecording = false
    private var session: UUID?
    func didStartOwnedSession(_ id: UUID) { session = id; isRecording = true }
    func didStopOwnedSession(_ id: UUID) { if session == id { session = nil; isRecording = false } }
}

@MainActor
final class SystemMonitor: ObservableObject {
    @Published private(set) var network = String(localized: "Checking connection")
    @Published private(set) var cpuUsage: Double = 0
    @Published private(set) var memoryUsed: UInt64 = 0
    @Published private(set) var diskFree: Int64 = 0
    @Published private(set) var diskTotal: Int64 = 0
    let memoryTotal = ProcessInfo.processInfo.physicalMemory
    let brightness: any BrightnessProviding = PublicBrightnessProvider()
    let recording = AppRecordingState()
    private let pathMonitor = NWPathMonitor()
    private var poller: AnyCancellable?
    private var previousTicks: (UInt64, UInt64)?
    init() {
        pathMonitor.pathUpdateHandler = { [weak self] path in
            let text = path.status == .satisfied ? (path.usesInterfaceType(.wifi) ? String(localized: "Wi-Fi connected") : path.usesInterfaceType(.wiredEthernet) ? String(localized: "Ethernet connected") : String(localized: "Connected")) : String(localized: "Offline")
            Task { @MainActor [weak self] in self?.network = text }
        }
        pathMonitor.start(queue: DispatchQueue(label: "com.notchisland.network", qos: .utility))
    }
    // Sampling is scoped to the visible System pane, rather than running while idle.
    func startSampling() {
        guard poller == nil else { return }
        sample()
        poller = Timer.publish(every: 3, tolerance: 0.5, on: .main, in: .common).autoconnect()
            .sink { [weak self] _ in self?.sample() }
    }
    func stopSampling() { poller = nil; previousTicks = nil }
    private func sample() {
        var cpu = host_cpu_load_info()
        var cpuCount = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.stride / MemoryLayout<integer_t>.stride)
        let cpuResult = withUnsafeMutablePointer(to: &cpu) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(cpuCount)) { host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &cpuCount) }
        }
        if cpuResult == KERN_SUCCESS {
            let ticks = cpu.cpu_ticks
            let idle = UInt64(ticks.2)
            let total = UInt64(ticks.0) + UInt64(ticks.1) + UInt64(ticks.3) + idle
            if let previousTicks, total > previousTicks.0, idle >= previousTicks.1 {
                cpuUsage = min(1, max(0, 1 - Double(idle - previousTicks.1) / Double(total - previousTicks.0)))
            }
            previousTicks = (total, idle)
        }
        var vm = vm_statistics64()
        var vmCount = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.stride / MemoryLayout<integer_t>.stride)
        let vmResult = withUnsafeMutablePointer(to: &vm) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(vmCount)) { host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &vmCount) }
        }
        if vmResult == KERN_SUCCESS {
            memoryUsed = min(memoryTotal, (UInt64(vm.active_count) + UInt64(vm.wire_count) + UInt64(vm.compressor_page_count)) * UInt64(vm_kernel_page_size))
        }
        if let values = try? URL(fileURLWithPath: NSHomeDirectory()).resourceValues(forKeys: [.volumeAvailableCapacityKey, .volumeTotalCapacityKey]) {
            diskFree = Int64(values.volumeAvailableCapacity ?? 0)
            diskTotal = Int64(values.volumeTotalCapacity ?? 0)
        }
    }
    deinit { pathMonitor.cancel() }
}
