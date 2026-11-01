import AppKit

/// What the menu bar shows. Equatable so it is only redrawn when it changes.
struct MenuBarLabel: Equatable {
    private static let minNameCharacters = 3
    private static let nameFont = NSFont.systemFont(ofSize: NSFont.menuBarFont(ofSize: 0).pointSize)
    private static let timeFont = NSFont.monospacedDigitSystemFont(ofSize: NSFont.menuBarFont(ofSize: 0).pointSize, weight: .medium)
    private static let dotSize: CGFloat = 8
    private static let dotGap: CGFloat = 5
    private static let nameGap: CGFloat = 6
    private static let capsulePadding: CGFloat = 9

    let name: String?
    let time: String
    let isRunning: Bool
    let fullName: String

    /// The name takes whatever of `availableWidth` the timer leaves, shortening as needed.
    /// With no room for at least a few characters, only the timer shows.
    init(task: TaskItem, seconds: TimeInterval, isRunning: Bool, availableWidth: CGFloat) {
        self.time = Formatting.clock(seconds, showSeconds: true)
        self.name = Self.fittedName(task.name, time: time, availableWidth: availableWidth)
        self.isRunning = isRunning
        self.fullName = task.name
    }

    static func fittedName(_ name: String, time: String, availableWidth: CGFloat) -> String? {
        var length = name.count
        while length >= minNameCharacters {
            let prefix = name.prefix(length).trimmingCharacters(in: .whitespaces)
            let candidate = length < name.count ? prefix + "…" : prefix
            if width(name: candidate, time: time) <= availableWidth {
                return candidate
            }
            length -= 1
        }
        return nil
    }

    var width: CGFloat {
        Self.width(name: name, time: time)
    }

    /// Decided from the timer alone, since the name adapts to whatever room there is. A hidden
    /// item returns with a little to spare, so it doesn't flicker at the edge.
    func shouldShow(availableWidth: CGFloat, isVisible: Bool) -> Bool {
        availableWidth >= Self.width(name: nil, time: time) + (isVisible ? 0 : 4)
    }

    private static func width(name: String?, time: String) -> CGFloat {
        var width = dotSize + dotGap + attributed(time, font: timeFont).size().width
        if let name {
            width += attributed(name, font: nameFont).size().width + nameGap
        }
        return ceil(width + capsulePadding * 2)
    }

    private static func attributed(_ string: String, font: NSFont) -> NSAttributedString {
        NSAttributedString(string: string, attributes: [.font: font, .foregroundColor: NSColor.labelColor])
    }

    /// A glass-like capsule holding a green or grey dot, the name and the timer.
    func draw(in bounds: NSRect, isHighlighted: Bool, isDark: Bool) {
        drawCapsule(in: bounds, isHighlighted: isHighlighted, isDark: isDark)

        var x = (bounds.width - width) / 2 + Self.capsulePadding
        drawDot(at: x, midY: bounds.midY)
        x += Self.dotSize + Self.dotGap

        if let name {
            let text = Self.attributed(name, font: Self.nameFont)
            text.draw(at: NSPoint(x: x, y: bounds.midY - text.size().height / 2))
            x += text.size().width + Self.nameGap
        }
        let text = Self.attributed(time, font: Self.timeFont)
        text.draw(at: NSPoint(x: x, y: bounds.midY - text.size().height / 2))
    }

    /// Hand-drawn rather than a system material, so it looks the same on every macOS version.
    private func drawCapsule(in bounds: NSRect, isHighlighted: Bool, isDark: Bool) {
        let rect = bounds.insetBy(dx: 1, dy: 1)
        let radius = rect.height / 2
        let capsule = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
        let boost: CGFloat = isHighlighted ? 0.1 : 0

        // Soft contact shadow, so the capsule lifts off the bar.
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(isDark ? 0.3 : 0.14)
        shadow.shadowOffset = NSSize(width: 0, height: -0.5)
        shadow.shadowBlurRadius = 1.5
        shadow.set()
        NSColor.white.withAlphaComponent(isDark ? 0.08 : 0.3).setFill()
        capsule.fill()
        NSGraphicsContext.restoreGraphicsState()

        // Body: brighter at the top, as if lit from above.
        let top = (isDark ? 0.2 : 0.62) + boost
        let bottom = (isDark ? 0.09 : 0.36) + boost
        NSGradient(
            starting: NSColor.white.withAlphaComponent(top),
            ending: NSColor.white.withAlphaComponent(bottom)
        )?.draw(in: capsule, angle: -90)

        // Rim: a bright hairline along the top edge that fades towards the bottom.
        NSGraphicsContext.saveGraphicsState()
        let edge = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
        edge.append(NSBezierPath(roundedRect: rect.insetBy(dx: 0.75, dy: 0.75), xRadius: radius - 0.75, yRadius: radius - 0.75).reversed)
        edge.setClip()
        NSGradient(
            starting: NSColor.white.withAlphaComponent(isDark ? 0.5 : 0.95),
            ending: NSColor.white.withAlphaComponent(isDark ? 0.1 : 0.35)
        )?.draw(in: rect, angle: -90)
        NSGraphicsContext.restoreGraphicsState()

        // Outer line, so the capsule holds its shape on a bright wallpaper.
        NSColor.black.withAlphaComponent(isDark ? 0.18 : 0.1).setStroke()
        let outline = NSBezierPath(roundedRect: rect.insetBy(dx: -0.25, dy: -0.25), xRadius: radius, yRadius: radius)
        outline.lineWidth = 0.5
        outline.stroke()
    }

    private func drawDot(at x: CGFloat, midY: CGFloat) {
        let dot = NSBezierPath(ovalIn: NSRect(x: x, y: midY - Self.dotSize / 2, width: Self.dotSize, height: Self.dotSize))
        NSGraphicsContext.saveGraphicsState()
        if isRunning {
            let glow = NSShadow()
            glow.shadowColor = NSColor.systemGreen.withAlphaComponent(0.7)
            glow.shadowBlurRadius = 4
            glow.set()
            NSColor.systemGreen.setFill()
        } else {
            NSColor.systemGray.setFill()
        }
        dot.fill()
        NSGraphicsContext.restoreGraphicsState()
    }
}

/// Draws the label on top of the status button, whose own title can't show the capsule.
final class MenuBarLabelView: NSView {
    var label: MenuBarLabel? {
        didSet { needsDisplay = true }
    }

    /// Brightens the capsule while the dropdown is open.
    var isHighlighted = false {
        didSet { needsDisplay = true }
    }

    /// The capsule is drawn by hand, so it has to be redrawn for light and dark.
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    /// Clicks go through to the status button underneath.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
        let isDark = effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        label?.draw(in: bounds, isHighlighted: isHighlighted, isDark: isDark)
    }
}
