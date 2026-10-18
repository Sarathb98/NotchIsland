import SwiftUI
import UniformTypeIdentifiers

struct IslandView: View {
    @ObservedObject var model: IslandModel
    let widgets: WidgetStore
    @State private var dropTargeted = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        VStack(spacing: 0) {
            surface
                .frame(width: model.size.width, height: model.size.height, alignment: .top)
                .background(.black)
                .clipShape(model.silhouette)
                .overlay {
                    if contrast == .increased && model.state != .collapsed {
                        model.silhouette.stroke(.white.opacity(0.65), lineWidth: 1)
                            .allowsHitTesting(false).accessibilityHidden(true)
                    }
                }
                .contentShape(model.silhouette)
                .onTapGesture { if model.state != .expanded { model.coordinator.expand() } }
                .contextMenu {
                    Button("Open Island") { model.coordinator.showDashboard() }
                    if model.coordinator.settings.orderedModules.contains(.files) {
                        Button("Open Tray") { model.coordinator.showTray() }
                    }
                    Button("Collapse Island") { model.coordinator.collapse() }
                }
                .onDrop(of: [UTType.fileURL], isTargeted: $dropTargeted) { providers in
                    let accepted = widgets.dropZone.accept(providers)
                    model.coordinator.endDrag(accepted: accepted)
                    return accepted
                }
                .onChange(of: dropTargeted) { _, targeted in
                    if targeted { model.coordinator.beginDrag() }
                    else if model.state == .dragTarget { model.coordinator.endDrag(accepted: false) }
                }
                .animation(animation, value: model.state)
                .animation(animation, value: model.coordinator.page)
                .animation(animation, value: model.size)
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("island.surface")
                .accessibilityLabel("Notch Island")
                .accessibilityValue(model.state.rawValue)
                .accessibilityAction(named: "Expand") { model.coordinator.expand() }
                .accessibilityAction(named: "Collapse") { model.coordinator.collapse() }
            Spacer(minLength: 0)
        }
        .frame(width: model.canvasSize.width, height: model.canvasSize.height, alignment: .top)
        .environment(\.colorScheme, .dark)
        .preferredColorScheme(.dark)
        .tint(.blue)
        .environmentObject(model.coordinator)
    }

    private var animation: Animation? { model.coordinator.settings.animation(reduceMotion: reduceMotion) }

    @ViewBuilder private var surface: some View {
        if model.state == .expanded {
            ExpandedIsland(widgets: widgets, settings: model.coordinator.settings,
                           topInset: model.geometry.collapsedSize.height,
                           notchWidth: model.geometry.collapsedSize.width,
                           collapse: { model.coordinator.collapse() }, selection: $model.selectedWidget)
                .transition(.opacity)
        } else {
            VStack(spacing: 0) {
                Color.black.frame(height: model.geometry.collapsedSize.height)
                compactContent.frame(height: model.contentHeight)
            }
        }
    }

    @ViewBuilder private var compactContent: some View {
        switch model.state {
        case .collapsed, .expanded: EmptyView()
        case .hovered:
            CollapsedIsland(media: widgets.media, timer: widgets.timer, battery: widgets.battery)
        case .dragTarget:
            VStack(spacing: 8) {
                Image(systemName: "tray.and.arrow.down.fill").font(.system(size: 27, weight: .light)).foregroundStyle(.blue)
                Text("Drop into your tray").font(.system(size: 15, weight: .semibold))
                Text("Keep files close. Drag them out whenever you need them.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(.blue.opacity(0.08), in: RoundedRectangle(cornerRadius: 18))
            .overlay { RoundedRectangle(cornerRadius: 18).strokeBorder(.blue.opacity(0.6), style: StrokeStyle(lineWidth: 1.5, dash: [6, 5])) }
            .padding(.horizontal, 24).padding(.bottom, 16).padding(.top, 6)
        case .liveActivity, .alert:
            HStack(spacing: 12) {
                Image(systemName: model.coordinator.activity?.symbol ?? "bell")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(model.state == .alert ? Color.orange : Color.blue)
                    .frame(width: 38, height: 38)
                    .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 11))
                VStack(alignment: .leading, spacing: 4) {
                    Text(model.coordinator.activity?.title ?? "Notch Island").font(.system(size: 13, weight: .semibold))
                    Text(model.coordinator.activity?.detail ?? "").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    if let progress = model.coordinator.activity?.progress { ProgressView(value: progress).tint(.white) }
                }
                Spacer()
                Button { model.coordinator.collapse() } label: { Image(systemName: "xmark") }
                    .buttonStyle(IslandIconButtonStyle()).accessibilityLabel("Dismiss activity")
            }.padding(.horizontal, 24).padding(.bottom, 12)
        }
    }
}
