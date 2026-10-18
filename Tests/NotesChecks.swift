import AppKit

@main
struct NotesChecks {
    @MainActor static func main() {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("NotchNotes-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let storage = directory.appendingPathComponent("notes.json")
        let model = NotesModel(storage: storage)
        model.create()
        model.update("A local note\nDetails")
        model.save()
        let restored = NotesModel(storage: storage)
        precondition(restored.notes.count == 1 && restored.notes[0].title == "A local note")
        restored.update(String(repeating: "a", count: 25_000))
        precondition(restored.selectedText.count == 20_000)
        restored.removeSelected()
        precondition(NotesModel(storage: storage).notes.isEmpty)
        print("PASS: note persistence, title, size limit, deletion")
    }
}
