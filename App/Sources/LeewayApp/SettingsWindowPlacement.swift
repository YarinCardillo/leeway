import CoreGraphics

/// Selects the active display and keeps the entire Settings frame inside its usable area.
enum SettingsWindowPlacement {
    struct Display {
        let frame: CGRect
        let visible: CGRect
    }

    static func frame(size: CGSize, saved: CGRect?, pointer: CGPoint, displays: [Display]) -> CGRect? {
        guard let active = displays.first(where: { $0.frame.contains(pointer) }) ?? displays.first else { return nil }
        let previousDisplay = saved.flatMap { previous in
            displays.filter { previous.intersects($0.visible) }.max {
                area(previous.intersection($0.visible)) < area(previous.intersection($1.visible))
            }
        }
        let visible = (previousDisplay ?? active).visible
        let requestedSize = saved?.size ?? size
        let fitted = CGSize(width: min(requestedSize.width, visible.width), height: min(requestedSize.height, visible.height))
        let origin: CGPoint
        if previousDisplay != nil, let saved {
            origin = saved.origin
        } else {
            origin = CGPoint(x: visible.midX - fitted.width / 2, y: visible.midY - fitted.height / 2)
        }
        return CGRect(x: min(max(origin.x, visible.minX), visible.maxX - fitted.width),
                      y: min(max(origin.y, visible.minY), visible.maxY - fitted.height),
                      width: fitted.width, height: fitted.height)
    }

    private static func area(_ rect: CGRect) -> CGFloat { rect.width * rect.height }
}
