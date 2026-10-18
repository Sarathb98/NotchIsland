import AppKit

struct NotchGeometry: Equatable {
    let screenFrame: CGRect
    let collapsedSize: CGSize
    let centerX: CGFloat
    let hasNotch: Bool

    static func resolve(frame: CGRect, safeTop: CGFloat, left: CGRect?, right: CGRect?) -> NotchGeometry {
        // NSScreen geometry is in points and global screen coordinates. Do not multiply
        // it by backingScaleFactor: AppKit scales the panel's backing store itself.
        // Auxiliary areas must be positive, unobscured rectangles in the top safe-area
        // band. Reject inconsistent snapshots during display reconfiguration.
        if isValid(frame), safeTop.isFinite, safeTop > 0, safeTop < frame.height,
           let left, let right, isValid(left), isValid(right),
           CGRect(x: frame.minX, y: frame.maxY - safeTop,
                  width: frame.width, height: safeTop).contains(left),
           CGRect(x: frame.minX, y: frame.maxY - safeTop,
                  width: frame.width, height: safeTop).contains(right),
           left.maxY == frame.maxY, right.maxY == frame.maxY,
           right.minX > left.maxX {
            return NotchGeometry(screenFrame: frame,
                                 collapsedSize: CGSize(width: right.minX - left.maxX, height: safeTop),
                                 centerX: (left.maxX + right.minX) / 2, hasNotch: true)
        }
        // Product size for the optional island on displays without camera housing.
        return NotchGeometry(screenFrame: frame, collapsedSize: CGSize(width: 112, height: 24),
                             centerX: frame.midX, hasNotch: false)
    }

    private static func isValid(_ rect: CGRect) -> Bool {
        rect.origin.x.isFinite && rect.origin.y.isFinite &&
        rect.size.width.isFinite && rect.size.height.isFinite && rect.size.width > 0 && rect.size.height > 0
    }
}

enum NotchDetector {
    static func geometry(for screen: NSScreen) -> NotchGeometry {
        .resolve(frame: screen.frame, safeTop: screen.safeAreaInsets.top,
                 left: screen.auxiliaryTopLeftArea, right: screen.auxiliaryTopRightArea)
    }
}
