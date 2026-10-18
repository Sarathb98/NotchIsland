import AppKit
import Combine

struct QuickNote: Identifiable, Codable, Equatable {
    var id = UUID()
    var text: String
    var modified = Date()
    var title: String {
        guard let firstLine = text.split(separator: "\n").first else { return String(localized: "New note") }
        return String(firstLine.prefix(60))
    }
}

@MainActor
final class NotesModel: ObservableObject {
    @Published private(set) var notes: [QuickNote] = []
    @Published var selectedID: UUID?
    @Published private(set) var error: String?
    private let storage: URL
    private var saveTask: Task<Void, Never>?
    init(storage: URL? = nil) {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        self.storage = storage ?? support.appendingPathComponent("NotchIsland/notes.json")
        do {
            if FileManager.default.fileExists(atPath: self.storage.path) {
                notes = try JSONDecoder().decode([QuickNote].self, from: Data(contentsOf: self.storage))
            }
        } catch { self.error = String(localized: "Could not read saved notes: \(error.localizedDescription)") }
        selectedID = notes.first?.id
    }
    var selectedText: String { notes.first(where: { $0.id == selectedID })?.text ?? "" }
    func create() {
        guard notes.count < 100 else { error = String(localized: "You can keep up to 100 quick notes."); return }
        let note = QuickNote(text: "")
        notes.insert(note, at: 0); selectedID = note.id; save()
    }
    func update(_ text: String) {
        guard let index = notes.firstIndex(where: { $0.id == selectedID }) else { return }
        notes[index].text = String(text.prefix(20_000)); notes[index].modified = .now
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            self?.save()
        }
    }
    func removeSelected() {
        notes.removeAll { $0.id == selectedID }
        selectedID = notes.first?.id; save()
    }
    func copySelected() { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(selectedText, forType: .string) }
    func save() {
        saveTask?.cancel()
        do {
            try FileManager.default.createDirectory(at: storage.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(notes).write(to: storage, options: .atomic)
            error = nil
        } catch { self.error = String(localized: "Could not save notes: \(error.localizedDescription)") }
    }
}
