import AppKit
import SwiftUI
import UniformTypeIdentifiers
import QuickLook
import QuickLookThumbnailing

struct FileShelfWidget: View {
    @ObservedObject var model: DropZoneModel
    @State private var previewURL: URL?
    @State private var dropTargeted = false

    var body: some View {
        VStack(spacing: 5) {
            HStack(spacing: 6) {
                if model.items.isEmpty {
                    emptyTray
                } else {
                    ScrollView(.horizontal) {
                        LazyHStack(alignment: .top, spacing: 5) {
                            ForEach(model.items) { item in
                                ShelfFileTile(item: item, isBusy: model.busyItems.contains(item.id)) {
                                    previewURL = item.url
                                }
                                .onDrag { NSItemProvider(object: item.url as NSURL) }
                                .contextMenu {
                                    Button("Quick Look") { previewURL = item.url }
                                    Button("Reveal in Finder") { model.reveal(item.url) }
                                    Button("Copy") { model.copyToPasteboard(item.url) }
                                    Button(item.isPinned ? String(localized: "Unpin") : String(localized: "Pin")) {
                                        model.togglePin(item.url)
                                    }
                                    Divider()
                                    Button("Remove", role: .destructive) { model.remove(item.url) }
                                }
                                .disabled(model.busyItems.contains(item.id))
                            }
                        }
                        .padding(.horizontal, 5)
                    }
                    .scrollIndicators(.hidden)
                    .accessibilityLabel("Files in tray")
                }

                if !model.items.isEmpty || model.isImporting {
                    VStack(spacing: 10) {
                        if !model.items.isEmpty {
                            Button { model.clear() } label: {
                                Image(systemName: "trash")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(.white.opacity(0.55))
                                    .frame(width: 28, height: 28)
                                    .background(.white.opacity(0.06), in: Circle())
                            }
                            .buttonStyle(.plain)
                            .disabled(!model.items.contains { !$0.isPinned })
                            .help("Clear unpinned files")
                            .accessibilityLabel("Clear unpinned files")
                        }
                        if model.isImporting {
                            ProgressView().controlSize(.small)
                                .accessibilityLabel("Copying files to tray")
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.top, 4)
                    .frame(width: 28)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(dropTargeted ? Color.accentColor.opacity(0.10) : Color.black,
                        in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(dropTargeted ? Color.accentColor : Color.white.opacity(0.14),
                                  style: StrokeStyle(lineWidth: 1.5, dash: [5, 6]))
                    .allowsHitTesting(false)
            }
            .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .onDrop(of: [UTType.fileURL], isTargeted: $dropTargeted, perform: model.accept)

            if let error = model.error {
                Text(error)
                    .font(.system(size: 10))
                    .foregroundStyle(.red)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .help(error)
            }
        }
        .quickLookPreview($previewURL)
    }

    private var emptyTray: some View {
        HStack(spacing: 12) {
            Image(systemName: "tray.and.arrow.down")
                .font(.system(size: 25, weight: .light))
                .foregroundStyle(dropTargeted ? Color.accentColor : .white.opacity(0.45))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(dropTargeted ? "Release to add files" : "Drop files here")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.9))
                Text("Temporary copies. Pin a file to keep it.")
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.42))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct ShelfFileTile: View {
    let item: ShelfFile
    let isBusy: Bool
    let preview: () -> Void
    @State private var isHovered = false
    @State private var thumbnail: NSImage?

    var body: some View {
        Button(action: preview) {
            VStack(spacing: 6) {
                ZStack {
                    Image(nsImage: thumbnail ?? NSWorkspace.shared.icon(forFile: item.url.path))
                        .resizable()
                        .scaledToFit()
                        .frame(width: 45, height: 45)
                        .shadow(color: .black.opacity(0.3), radius: 3, y: 2)

                    if isHovered && !isBusy {
                        Image(systemName: "eye.fill")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.white)
                            .frame(width: 28, height: 24)
                            .background(.black.opacity(0.8), in: RoundedRectangle(cornerRadius: 7))
                    }
                    if isBusy {
                        ProgressView().controlSize(.small)
                            .frame(width: 45, height: 45)
                            .background(.black.opacity(0.65), in: RoundedRectangle(cornerRadius: 7))
                    }
                }
                .frame(width: 54, height: 47)
                .overlay(alignment: .bottomTrailing) {
                    if item.isPinned {
                        Image(systemName: "pin.fill")
                            .font(.system(size: 8, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 16, height: 16)
                            .background(.black, in: Circle())
                    }
                }

                Text(item.url.lastPathComponent)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white.opacity(0.9))
                    .lineLimit(2)
                    .truncationMode(.middle)
                    .multilineTextAlignment(.center)
                    .frame(width: 76, height: 27, alignment: .top)
            }
            .padding(.top, 4)
            .padding(.bottom, 3)
            .frame(width: 80)
            .background(isHovered ? .white.opacity(0.07) : .clear,
                        in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help(item.url.lastPathComponent)
        .accessibilityLabel("Preview \(item.url.lastPathComponent)")
        .accessibilityValue(item.isPinned ? String(localized: "Pinned") : String(localized: "Temporary copy"))
        .accessibilityHint("Opens Quick Look. Drag to copy this file to another app.")
        .task(id: item.url) {
            thumbnail = nil
            let request = QLThumbnailGenerator.Request(fileAt: item.url,
                                                      size: CGSize(width: 48, height: 48),
                                                      scale: NSScreen.main?.backingScaleFactor ?? 2,
                                                      representationTypes: .all)
            let representation = try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request)
            guard !Task.isCancelled else { return }
            thumbnail = representation?.nsImage
        }
    }
}
