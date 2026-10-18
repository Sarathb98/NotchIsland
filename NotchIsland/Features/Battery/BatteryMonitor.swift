import Foundation
import Combine
import IOKit.ps

@MainActor
final class BatteryMonitor: ObservableObject {
    enum PowerState: Equatable {
        case unavailable, charging, externalPower, battery

        var title: String {
            switch self {
            case .unavailable: String(localized: "No battery")
            case .charging: String(localized: "Charging")
            case .externalPower: String(localized: "Power adapter")
            case .battery: String(localized: "On battery")
            }
        }
    }

    @Published private(set) var percentage: Int?
    @Published private(set) var powerState: PowerState = .unavailable
    var status: String { powerState.title }
    private var subscription: AnyCancellable?
    init() {
        refresh()
        subscription = Timer.publish(every: 30, tolerance: 5, on: .main, in: .common).autoconnect()
            .sink { [weak self] _ in self?.refresh() }
    }
    func refresh() {
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [CFTypeRef] else { return }
        var newPercentage: Int?
        var newPowerState: PowerState = .unavailable
        for source in sources {
            guard let info = IOPSGetPowerSourceDescription(snapshot, source)?.takeUnretainedValue() as? [String: Any],
                  info[kIOPSTypeKey] as? String == kIOPSInternalBatteryType,
                  let current = info[kIOPSCurrentCapacityKey] as? Int,
                  let maximum = info[kIOPSMaxCapacityKey] as? Int, maximum > 0 else { continue }
            newPercentage = min(100, max(0, Int(Double(current) / Double(maximum) * 100)))
            let charging = info[kIOPSIsChargingKey] as? Bool == true
            let pluggedIn = info[kIOPSPowerSourceStateKey] as? String == kIOPSACPowerValue
            newPowerState = charging ? .charging : pluggedIn ? .externalPower : .battery
            break
        }
        if powerState != newPowerState { powerState = newPowerState }
        if percentage != newPercentage { percentage = newPercentage }
    }
}
