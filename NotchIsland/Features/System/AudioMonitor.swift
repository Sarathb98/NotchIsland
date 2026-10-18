import AppKit
import CoreAudio
import Combine

@MainActor
final class AudioMonitor: ObservableObject {
    @Published private(set) var volume: Double?
    @Published private(set) var outputName = String(localized: "No audio output")
    @Published private(set) var inputActive = false
    @Published private(set) var canSetVolume = false
    @Published private(set) var error: String?
    var onVolumeChange: ((Double) -> Void)?
    private var device = AudioObjectID(kAudioObjectUnknown)
    private var observer: AudioObjectPropertyListenerBlock?
    private var deviceObserver: AudioObjectPropertyListenerBlock?
    private var systemAddress = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
    private var volumeAddress = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyVolumeScalar, mScope: kAudioDevicePropertyScopeOutput, mElement: kAudioObjectPropertyElementMain)
    private var inputDevice = AudioObjectID(kAudioObjectUnknown)
    private var inputSystemObserver: AudioObjectPropertyListenerBlock?
    private var inputDeviceObserver: AudioObjectPropertyListenerBlock?
    private var inputSystemAddress = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultInputDevice, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
    private var inputRunningAddress = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
    private var stopped = false
    init() {
        observer = { [weak self] _, _ in Task { @MainActor in self?.connect() } }
        if let observer { AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &systemAddress, .main, observer) }
        connect()
    }
    private func connect() {
        guard !stopped else { return }
        if let deviceObserver, device != kAudioObjectUnknown {
            AudioObjectRemovePropertyListenerBlock(device, &volumeAddress, .main, deviceObserver)
        }
        deviceObserver = nil
        device = AudioObjectID(kAudioObjectUnknown)
        outputName = String(localized: "No audio output")
        canSetVolume = false
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &systemAddress, 0, nil, &size, &device) == noErr else { volume = nil; return }
        var nameAddress = AudioObjectPropertyAddress(mSelector: kAudioObjectPropertyName, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var name: Unmanaged<CFString>?
        size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        if AudioObjectGetPropertyData(device, &nameAddress, 0, nil, &size, &name) == noErr,
           let name { outputName = name.takeUnretainedValue() as String }
        var settable = DarwinBoolean(false)
        canSetVolume = AudioObjectIsPropertySettable(device, &volumeAddress, &settable) == noErr && settable.boolValue
        deviceObserver = { [weak self] _, _ in Task { @MainActor in self?.readVolume(announce: true) } }
        if let deviceObserver { AudioObjectAddPropertyListenerBlock(device, &volumeAddress, .main, deviceObserver) }
        readVolume(announce: false)
    }
    private func readVolume(announce: Bool) {
        guard !stopped else { return }
        var value: Float32 = 0
        var size = UInt32(MemoryLayout<Float32>.size)
        guard AudioObjectGetPropertyData(device, &volumeAddress, 0, nil, &size, &value) == noErr else { volume = nil; return }
        volume = Double(value)
        if announce { onVolumeChange?(Double(value)) }
    }
    func setVolume(_ value: Double) {
        guard !stopped, canSetVolume else { return }
        var scalar = Float32(min(1, max(0, value)))
        let result = AudioObjectSetPropertyData(device, &volumeAddress, 0, nil, UInt32(MemoryLayout<Float32>.size), &scalar)
        error = result == noErr ? nil : String(localized: "This audio device did not accept the volume change.")
        readVolume(announce: true)
    }
    func refreshInputActivity() {
        guard !stopped else { return }
        // The System pane starts observation on first presentation. These public
        // property listeners read driver state without opening an audio stream,
        // requesting microphone access, or polling while the island is idle.
        if inputSystemObserver == nil {
            let observer: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
                Task { @MainActor [weak self] in self?.connectInputDevice() }
            }
            if AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &inputSystemAddress, .main, observer) == noErr {
                inputSystemObserver = observer
            }
        }
        connectInputDevice()
    }
    private func connectInputDevice() {
        guard !stopped else { return }
        var nextDevice = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &inputSystemAddress, 0, nil, &size, &nextDevice) == noErr,
              nextDevice != kAudioObjectUnknown else {
            disconnectInputDevice()
            inputActive = false
            return
        }
        if nextDevice != inputDevice || inputDeviceObserver == nil {
            disconnectInputDevice()
            inputDevice = nextDevice
            let observer: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
                Task { @MainActor [weak self] in self?.readInputActivity() }
            }
            if AudioObjectAddPropertyListenerBlock(inputDevice, &inputRunningAddress, .main, observer) == noErr {
                inputDeviceObserver = observer
            }
        }
        readInputActivity()
    }
    private func readInputActivity() {
        guard !stopped else { return }
        var running: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        let result = AudioObjectGetPropertyData(inputDevice, &inputRunningAddress, 0, nil, &size, &running)
        inputActive = result == noErr && running != 0
    }
    private func disconnectInputDevice() {
        if let inputDeviceObserver, inputDevice != kAudioObjectUnknown {
            AudioObjectRemovePropertyListenerBlock(inputDevice, &inputRunningAddress, .main, inputDeviceObserver)
        }
        inputDeviceObserver = nil
        inputDevice = AudioObjectID(kAudioObjectUnknown)
    }
    func stop() {
        stopped = true
        if let observer { AudioObjectRemovePropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &systemAddress, .main, observer) }
        if let deviceObserver, device != kAudioObjectUnknown { AudioObjectRemovePropertyListenerBlock(device, &volumeAddress, .main, deviceObserver) }
        if let inputSystemObserver { AudioObjectRemovePropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &inputSystemAddress, .main, inputSystemObserver) }
        disconnectInputDevice()
        inputSystemObserver = nil
        inputActive = false
        observer = nil; deviceObserver = nil
    }
}
