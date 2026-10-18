import SwiftUI

struct ClipboardWidget: View {
    @ObservedObject var model: ClipboardModel
    @EnvironmentObject private var coordinator: IslandCoordinator
    @State private var showPrivacy = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Toggle("Clipboard history", isOn: Binding(get: { model.enabled }, set: model.setEnabled))
                    .toggleStyle(.switch).controlSize(.small).accessibilityIdentifier("clipboard.history")
                Spacer()
                Button { showPrivacy.toggle() } label: { Image(systemName: "hand.raised") }
                    .buttonStyle(.borderless).help("Privacy exclusions").accessibilityLabel("Privacy exclusions")
                Button("Clear") { model.clear() }.disabled(model.items.isEmpty).controlSize(.small)
            }
            if model.enabled || !model.items.isEmpty {
                HStack {
                    TextField("Search clipboard", text: $model.searchQuery).textFieldStyle(.roundedBorder)
                    Toggle(isOn: $model.favoritesOnly) { Image(systemName: model.favoritesOnly ? "star.fill" : "star") }
                        .toggleStyle(.button).help("Show favorites").accessibilityLabel("Show favorites")
                }
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 6) {
                        ForEach(model.filteredItems) { entry in
                            HStack(spacing: 8) {
                                if case .image(let data) = entry.payload, let image = NSImage(data: data) {
                                    Image(nsImage: image).resizable().scaledToFit().frame(width: 28, height: 28)
                                } else { Image(systemName: entry.payload.symbol).frame(width: 22) }
                                Button { model.restore(entry) } label: {
                                    Text(entry.payload.title).lineLimit(2).frame(maxWidth: .infinity, alignment: .leading)
                                }.buttonStyle(.plain).help("Copy to clipboard")
                                Button { model.toggleFavorite(entry.id) } label: {
                                    Image(systemName: entry.isFavorite ? "star.fill" : "star")
                                }.buttonStyle(.borderless).accessibilityLabel(entry.isFavorite ? String(localized: "Remove favorite") : String(localized: "Favorite"))
                            }
                            .font(.caption).padding(.vertical, 3)
                            .contextMenu {
                                Button("Copy") { model.restore(entry) }
                                Button(entry.isFavorite ? String(localized: "Remove favorite") : String(localized: "Favorite")) { model.toggleFavorite(entry.id) }
                                Button("Remove", role: .destructive) { model.remove(entry.id) }
                            }
                        }
                        if model.filteredItems.isEmpty {
                            Text("New copies appear here after history is enabled.").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }.frame(maxHeight: 125)
            } else {
                Text("Enable to save new text, links, images, and file references. History and favorites stay in memory and are cleared when you quit.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Text(model.status).font(.caption2).foregroundStyle(.secondary)
        }
        .onChange(of: showPrivacy) { _, shown in coordinator.setPresentationHeld(shown, reason: "clipboard.privacy") }
        .onDisappear { coordinator.setPresentationHeld(false, reason: "clipboard.privacy") }
        .popover(isPresented: $showPrivacy) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Clipboard Privacy").font(.headline)
                Text("Copies from known password managers and items marked confidential or transient are skipped. Source detection follows the foreground app and cannot identify every sensitive copy.")
                    .font(.callout).foregroundStyle(.secondary)
                TextField("Excluded app bundle IDs, separated by commas", text: $model.excludedBundleIDs, axis: .vertical)
                    .textFieldStyle(.roundedBorder).lineLimit(3...6)
                Text("Example: com.apple.Terminal").font(.caption).foregroundStyle(.secondary)
                Text("Up to 100 items, 5 MB each, and 32 MB total. Clearing history also removes favorites.")
                    .font(.caption).foregroundStyle(.secondary)
                Button("Done") { showPrivacy = false }.keyboardShortcut(.defaultAction)
            }.padding(16).frame(width: 330)
        }
    }
}
