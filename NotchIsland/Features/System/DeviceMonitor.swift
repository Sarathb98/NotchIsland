import SwiftUI
import Combine
import CoreBluetooth
import IOBluetooth
import AVFoundation

struct ConnectedBluetoothDevice: Identifiable, Equatable {
    let id: String
    let name: String
    let batteryPercentage: Int?
}

/// A device integration can provide battery telemetry when it has a documented
/// API. IOBluetooth does not expose universal accessory battery percentages.
protocol AccessoryBatteryProviding {
    func batteryPercentage(for deviceIdentifier: String) -> Int?
}

struct UnavailableAccessoryBatteryProvider: AccessoryBatteryProviding {
    func batteryPercentage(for deviceIdentifier: String) -> Int? { nil }
}

@MainActor
final class DeviceMonitor: NSObject, ObservableObject, CBCentralManagerDelegate {
    @Published private(set) var bluetoothDevices: [ConnectedBluetoothDevice] = []
    @Published private(set) var bluetoothStatus = String(localized: "Device monitoring is off")
    @Published private(set) var cameraStatus = String(localized: "Camera awareness is off")
    @Published private(set) var activeCameraNames: [String] = []
    @Published private(set) var bluetoothEnabled = false
    @Published private(set) var cameraEnabled = false
    @Published private(set) var bluetoothDenied = false
    @Published private(set) var cameraDenied = false
    @Published private(set) var requestingCameraPermission = false
    private var bluetoothManager: CBCentralManager?
    private let batteryProvider: any AccessoryBatteryProviding
    private var poller: AnyCancellable?
    private var visible = false

    init(batteryProvider: any AccessoryBatteryProviding = UnavailableAccessoryBatteryProvider()) {
        self.batteryProvider = batteryProvider
        super.init()
    }

    /// This is called only after the user presses Enable. Constructing a central
    /// manager can ask for permission; no manager is created at app launch.
    func enableBluetooth() {
        bluetoothEnabled = true
        bluetoothDenied = false
        if CBManager.authorization == .notDetermined {
            bluetoothStatus = String(localized: "Waiting for Bluetooth permission…")
            bluetoothManager = CBCentralManager(delegate: self, queue: .main, options: [CBCentralManagerOptionShowPowerAlertKey: false])
        } else {
            refreshBluetooth()
        }
        updatePolling()
    }

    func disableBluetooth() {
        bluetoothEnabled = false
        bluetoothManager = nil
        bluetoothDevices = []
        bluetoothStatus = String(localized: "Device monitoring is off")
        updatePolling()
    }

    func enableCamera() async {
        guard !requestingCameraPermission else { return }
        cameraEnabled = true
        cameraDenied = false
        if AVCaptureDevice.authorizationStatus(for: .video) == .notDetermined {
            requestingCameraPermission = true
            _ = await AVCaptureDevice.requestAccess(for: .video)
            requestingCameraPermission = false
        }
        refreshCamera()
        updatePolling()
    }

    func disableCamera() {
        cameraEnabled = false
        activeCameraNames = []
        cameraStatus = String(localized: "Camera awareness is off")
        updatePolling()
    }

    func setVisible(_ isVisible: Bool) {
        visible = isVisible
        updatePolling()
    }

    nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
        Task { @MainActor [weak self] in self?.refreshBluetooth() }
    }

    private func updatePolling() {
        poller = nil
        guard visible, bluetoothEnabled || cameraEnabled else { return }
        refresh()
        poller = Timer.publish(every: 5, tolerance: 1, on: .main, in: .common).autoconnect()
            .sink { [weak self] _ in self?.refresh() }
    }

    private func refresh() {
        if bluetoothEnabled { refreshBluetooth() }
        if cameraEnabled { refreshCamera() }
    }

    private func refreshBluetooth() {
        guard bluetoothEnabled else { return }
        bluetoothDevices = []
        switch CBManager.authorization {
        case .allowedAlways:
            bluetoothDenied = false
        case .denied, .restricted:
            bluetoothDenied = true
            bluetoothStatus = String(localized: "Bluetooth access is unavailable. Check Privacy & Security in System Settings.")
            return
        case .notDetermined:
            bluetoothStatus = String(localized: "Waiting for Bluetooth permission…")
            return
        @unknown default:
            bluetoothStatus = String(localized: "Bluetooth authorization could not be determined")
            return
        }
        if let manager = bluetoothManager, manager.state != .poweredOn {
            bluetoothStatus = manager.state == .poweredOff ? String(localized: "Bluetooth is turned off") : String(localized: "Bluetooth is unavailable")
            return
        }
        let paired = (IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice]) ?? []
        bluetoothDevices = paired.filter { $0.isConnected() }.compactMap { device in
            guard let address = device.addressString else { return nil }
            return ConnectedBluetoothDevice(id: address, name: device.name ?? String(localized: "Bluetooth device"),
                                            batteryPercentage: batteryProvider.batteryPercentage(for: address))
        }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        bluetoothStatus = bluetoothDevices.isEmpty ? String(localized: "No connected paired devices reported") : String(localized: "Connected paired devices")
    }

    private func refreshCamera() {
        guard cameraEnabled else { return }
        activeCameraNames = []
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            cameraDenied = false
        case .denied, .restricted:
            cameraDenied = true
            cameraStatus = String(localized: "Camera access is unavailable. Check Privacy & Security in System Settings.")
            return
        case .notDetermined:
            cameraStatus = String(localized: "Camera permission has not been granted")
            return
        @unknown default:
            cameraStatus = String(localized: "Camera authorization could not be determined")
            return
        }
        // Discovery and the read-only usage flag do not create a capture session
        // or activate the camera. The driver supplies this limited status.
        let discovery = AVCaptureDevice.DiscoverySession(deviceTypes: [.builtInWideAngleCamera, .external], mediaType: .video, position: .unspecified)
        let cameras = discovery.devices
        activeCameraNames = cameras.filter(\.isInUseByAnotherApplication).map(\.localizedName)
        if cameras.isEmpty {
            cameraStatus = String(localized: "No supported camera found")
        } else if activeCameraNames.isEmpty {
            cameraStatus = String(localized: "No camera use reported")
        } else {
            cameraStatus = String(localized: "Camera in use by another app")
        }
    }
}

struct DeviceStatusWidget: View {
    @StateObject private var monitor = DeviceMonitor()

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Bluetooth devices", systemImage: "antenna.radiowaves.left.and.right")
                Spacer()
                Button(monitor.bluetoothEnabled ? String(localized: "Disable") : String(localized: "Enable")) {
                    monitor.bluetoothEnabled ? monitor.disableBluetooth() : monitor.enableBluetooth()
                }.controlSize(.small)
            }
            Text(monitor.bluetoothStatus).font(.caption).foregroundStyle(.secondary)
            ForEach(monitor.bluetoothDevices) { device in
                LabeledContent(device.name) {
                    if let battery = device.batteryPercentage {
                        Text("\(battery)%").monospacedDigit()
                    } else {
                        Text("Connected").foregroundStyle(.secondary)
                    }
                }.font(.caption)
            }
            if monitor.bluetoothEnabled, !monitor.bluetoothDevices.isEmpty {
                Text("Accessory battery levels are unavailable through this integration.")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            Divider()
            HStack {
                Label("Camera awareness", systemImage: "camera")
                Spacer()
                Button(monitor.cameraEnabled ? String(localized: "Disable") : String(localized: "Enable")) {
                    if monitor.cameraEnabled { monitor.disableCamera() }
                    else { Task { await monitor.enableCamera() } }
                }.disabled(monitor.requestingCameraPermission).controlSize(.small)
            }
            Text(monitor.cameraStatus).font(.caption).foregroundStyle(.secondary)
            ForEach(monitor.activeCameraNames, id: \.self) { name in
                Label(name, systemImage: "video.fill").font(.caption)
            }
            Text("Reports the camera driver’s usage flag after permission is granted. No video is captured. Use the macOS privacy indicator for system-wide awareness.")
                .font(.caption2).foregroundStyle(.secondary)
        }
        .onAppear { monitor.setVisible(true) }
        .onDisappear { monitor.setVisible(false) }
    }
}
