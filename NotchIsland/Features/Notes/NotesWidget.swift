import SwiftUI

struct NotesWidget: View {
    @ObservedObject var model: NotesModel
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Picker("Note", selection: $model.selectedID) {
                    ForEach(model.notes) { note in Text(note.title).tag(Optional(note.id)) }
                }.labelsHidden().frame(maxWidth: .infinity).accessibilityLabel("Select note")
                Button { model.create() } label: { Image(systemName: "plus") }.help("New note").accessibilityLabel("New note")
                Menu {
                    Button("Copy Note", action: model.copySelected)
                    Button("Delete Note", role: .destructive, action: model.removeSelected)
                } label: { Image(systemName: "ellipsis.circle") }.menuStyle(.borderlessButton).frame(width: 24).disabled(model.selectedID == nil)
            }
            if model.selectedID != nil {
                TextEditor(text: Binding(get: { model.selectedText }, set: model.update))
                    .font(.body).scrollContentBackground(.hidden).accessibilityLabel("Note text")
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(.quaternary))
            } else {
                ContentUnavailableView("Quick Notes", systemImage: "note.text", description: Text("Create a note to keep a thought close by."))
            }
            if let error = model.error { Text(error).font(.caption).foregroundStyle(.red) }
        }
    }
}
