import SwiftUI
import Combine

enum IslandPage: Equatable { case dashboard, tray, module }

/// A single outline for SwiftUI clipping and AppKit's transparent hit testing.
/// Shoulder radii describe the expanded interface, never the physical notch.
struct IslandSilhouette: Shape {
    var shoulderRadius: CGFloat
    var bottomRadius: CGFloat

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(shoulderRadius, bottomRadius) }
        set { shoulderRadius = newValue.first; bottomRadius = newValue.second }
    }

    func path(in rect: CGRect) -> Path {
        guard rect.width > 0, rect.height > 0 else { return Path() }
        let shoulder = min(max(0, shoulderRadius), min(rect.width / 2, rect.height))
        let radius = min(max(0, bottomRadius), min((rect.width - shoulder * 2) / 2, rect.height - shoulder))
        let left = rect.minX + shoulder
        let right = rect.maxX - shoulder
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addQuadCurve(to: CGPoint(x: right, y: rect.minY + shoulder),
                          control: CGPoint(x: right, y: rect.minY))
        path.addLine(to: CGPoint(x: right, y: rect.maxY - radius))
        path.addQuadCurve(to: CGPoint(x: right - radius, y: rect.maxY),
                          control: CGPoint(x: right, y: rect.maxY))
        path.addLine(to: CGPoint(x: left + radius, y: rect.maxY))
        path.addQuadCurve(to: CGPoint(x: left, y: rect.maxY - radius),
                          control: CGPoint(x: left, y: rect.maxY))
        path.addLine(to: CGPoint(x: left, y: rect.minY + shoulder))
        path.addQuadCurve(to: CGPoint(x: rect.minX, y: rect.minY),
                          control: CGPoint(x: left, y: rect.minY))
        path.closeSubpath()
        return path
    }
}

enum IslandWidget: String, CaseIterable, Identifiable {
    case timer = "Timer", calendar = "Calendar", files = "Files", system = "System"
    case clipboard = "Clipboard", notes = "Notes", actions = "Actions", apps = "Apps", downloads = "Downloads", media = "Media"
    case mirror = "Mirror", tasks = "Tasks"
    var id: String { rawValue }
    var title: String {
        switch self {
        case .timer: String(localized: "Timer")
        case .calendar: String(localized: "Calendar")
        case .files: String(localized: "Files")
        case .system: String(localized: "System")
        case .clipboard: String(localized: "Clipboard")
        case .notes: String(localized: "Notes")
        case .actions: String(localized: "Actions")
        case .apps: String(localized: "Apps")
        case .downloads: String(localized: "Downloads")
        case .media: String(localized: "Media")
        case .mirror: String(localized: "Mirror")
        case .tasks: String(localized: "Tasks")
        }
    }
}

@MainActor
final class IslandModel: ObservableObject {
    typealias State = IslandCoordinator.State
    let geometry: NotchGeometry
    let coordinator: IslandCoordinator
    private var subscriptions = Set<AnyCancellable>()
    init(geometry: NotchGeometry, coordinator: IslandCoordinator? = nil) {
        self.geometry = geometry
        self.coordinator = coordinator ?? IslandCoordinator(settings: IslandSettings())
        self.coordinator.objectWillChange.sink { [weak self] in self?.objectWillChange.send() }.store(in: &subscriptions)
        self.coordinator.settings.objectWillChange.sink { [weak self] in self?.objectWillChange.send() }.store(in: &subscriptions)
    }
    var state: State {
        get { coordinator.state }
        set { coordinator.transition(to: newValue) }
    }
    var selectedWidget: IslandWidget {
        get { coordinator.selectedWidget }
        set { coordinator.selectedWidget = newValue }
    }
    var contentHeight: CGFloat {
        switch state {
        case .collapsed: return 0
        case .hovered: return 48
        case .expanded:
            switch coordinator.page {
            case .dashboard: return 220
            case .tray: return 160
            case .module: return 280
            }
        case .liveActivity, .alert: return 72
        case .dragTarget: return 160
        }
    }
    var expandedWidth: CGFloat {
        let preferred = coordinator.page == .module ? min(coordinator.settings.islandWidth, 640) : coordinator.settings.islandWidth
        return fittingWidth(preferred)
    }
    var size: CGSize {
        let width: CGFloat
        switch state {
        case .collapsed: width = geometry.collapsedSize.width
        case .hovered: width = max(geometry.collapsedSize.width + 48, 280)
        case .expanded: width = expandedWidth
        case .dragTarget: width = fittingWidth(coordinator.settings.islandWidth)
        case .liveActivity, .alert: width = fittingWidth(min(coordinator.settings.islandWidth, 640))
        }
        return CGSize(width: min(width, geometry.screenFrame.width), height: geometry.collapsedSize.height + contentHeight)
    }
    var canvasSize: CGSize {
        CGSize(width: min(geometry.screenFrame.width, max(geometry.collapsedSize.width + 48, IslandSettings.widthRange.upperBound)),
               height: geometry.collapsedSize.height + 280)
    }
    var silhouette: IslandSilhouette {
        IslandSilhouette(shoulderRadius: state == .collapsed ? 0 : 12,
                         bottomRadius: state == .collapsed ? 8 : 28)
    }
    private func fittingWidth(_ preferred: CGFloat) -> CGFloat {
        min(geometry.screenFrame.width, max(geometry.collapsedSize.width, preferred))
    }
}
