import Foundation

/// All preferences remain in this dictionary. These checks never write to the
/// user's defaults database, show panels, launch applications, or start transfers.
private final class MemoryDefaults: UserDefaults, @unchecked Sendable {
    private var values: [String: Any] = [:]
    override func data(forKey key: String) -> Data? { values[key] as? Data }
    override func set(_ value: Any?, forKey key: String) { values[key] = value }
}

@main
struct ActionDownloadChecks {
    @MainActor static func main() async {
        checkActions()
        await checkDownloadValidation()
        checkEmptyLauncher()
        print("PASS: action persistence, ordering, removal and callbacks; HTTPS validation; empty launcher navigation (no launches, dialogs, downloads or saved preferences)")
    }

    @MainActor private static func checkActions() {
        let defaults = MemoryDefaults()
        let model = QuickActionsModel(defaults: defaults)
        let defaultCount = model.actions.count
        expect(defaultCount > 0, "New users receive default quick actions")
        model.addTimer(minutes: 0)
        expect(model.actions.last?.seconds == 60, "Timer durations have a one-minute minimum")
        model.addTimer(minutes: 999)
        let custom = model.actions.last!
        expect(custom.seconds == 10_800, "Timer durations have a three-hour maximum")
        model.rename(custom, to: "Review timer")
        var duration: TimeInterval?
        model.onStartTimer = { duration = $0 }
        model.run(custom)
        expect(duration == 10_800, "A timer action invokes the shared timer callback")
        var startedFocus = false
        model.onStartFocus = { startedFocus = true }
        model.run(model.actions.first { $0.kind == .focus }!)
        expect(startedFocus, "A focus action invokes the shared focus callback")
        model.move(custom, by: -100)
        expect(model.actions.first?.id == custom.id, "Moving upward stops at the first position")
        let restored = QuickActionsModel(defaults: defaults)
        expect(restored.actions.first?.title == "Review timer", "Names and order survive model recreation")
        restored.move(restored.actions.first!, by: 100)
        expect(restored.actions.last?.id == custom.id, "Moving downward stops at the final position")
        restored.remove(custom)
        expect(restored.actions.count == defaultCount + 1, "Removal preserves unrelated actions")
        expect(QuickActionsModel(defaults: defaults).actions.allSatisfy { $0.id != custom.id }, "Removal persists")
        restored.restoreDefaults()
        expect(restored.actions.count == defaultCount, "Restoring defaults replaces customized actions")
        restored.run(restored.actions.first { $0.kind == .lockGuidance }!)
        expect(restored.message?.contains("Control–Command–Q") == true, "Lock fallback gives the system keyboard shortcut")
    }

    @MainActor private static func checkDownloadValidation() async {
        expect(DownloadModel.validatedURL(" https://example.com/file.zip ")?.scheme == "https", "Whitespace around an HTTPS URL is accepted")
        expect(DownloadModel.validatedURL("HTTPS://example.com/file") != nil, "Scheme validation is case insensitive")
        for address in ["http://example.com/file", "file:///tmp/test", "ftp://example.com/a", "data:text/plain,test",
                        "https://user:password@example.com/file", "https://user@example.com/file", "not a URL", "https://"] {
            expect(DownloadModel.validatedURL(address) == nil, "Reject unsupported or malformed URL: \(address)")
        }
        let model = DownloadModel()
        model.address = "http://example.com/file"
        await model.start()
        expect(model.state == .failed && model.error != nil, "An invalid address fails before opening a save panel")
        expect(!model.isBusy && model.savedURL == nil && model.receivedBytes == 0, "Validation cannot create a transfer or output file")
        model.cancel()
        expect(model.state == .failed, "Cancelling without a transfer is harmless")
    }

    @MainActor private static func checkEmptyLauncher() {
        let model = AppLauncherModel()
        model.query = "No application scan is performed by this test"
        model.moveSelection(by: 1)
        model.moveSelection(by: -1)
        expect(model.filtered.isEmpty && model.selectedID == nil, "Arrow navigation handles an empty application list")
        model.query = ""
        expect(model.selectedID == nil && !model.isLoading, "Clearing an empty search does not start discovery")
    }

    private static func expect(_ value: @autoclosure () -> Bool, _ message: String,
                               file: StaticString = #file, line: UInt = #line) {
        precondition(value(), message, file: file, line: line)
    }
}
