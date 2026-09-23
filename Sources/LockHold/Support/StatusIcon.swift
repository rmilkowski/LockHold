import AppKit

@MainActor
enum StatusIcon {
    static func image(overrideIsActive: Bool, systemSleepDisabled: Bool = false) -> NSImage {
        // Draw both indicators in one status item so they stay together and share a menu.
        // Resolve the inactive colour while drawing to follow the menu bar's appearance.
        let image = NSImage(size: NSSize(width: 40, height: 18), flipped: false) { _ in
            drawSymbol(
                name: overrideIsActive ? "lock.slash.fill" : "lock.fill",
                isActive: overrideIsActive,
                in: NSRect(x: 0, y: 0, width: 18, height: 18)
            )
            drawSymbol(
                name: "laptopcomputer", isActive: systemSleepDisabled,
                in: NSRect(x: 22, y: 0, width: 18, height: 18)
            )
            return true
        }
        image.isTemplate = !overrideIsActive && !systemSleepDisabled
        return image
    }

    private static func drawSymbol(name: String, isActive: Bool, in frame: NSRect) {
        let colour: NSColor = isActive ? .systemRed : .labelColor
        let configuration = NSImage.SymbolConfiguration(pointSize: 15, weight: .semibold)
            .applying(NSImage.SymbolConfiguration(paletteColors: [colour]))
        if let symbol = NSImage(systemSymbolName: name, accessibilityDescription: nil),
            let configuredSymbol = symbol.withSymbolConfiguration(configuration)
        {
            configuredSymbol.isTemplate = false
            let scale = min(
                frame.width / configuredSymbol.size.width,
                frame.height / configuredSymbol.size.height
            )
            let size = NSSize(
                width: configuredSymbol.size.width * scale,
                height: configuredSymbol.size.height * scale
            )
            configuredSymbol.draw(
                in: NSRect(
                    x: frame.midX - size.width / 2, y: frame.midY - size.height / 2,
                    width: size.width, height: size.height
                )
            )
        } else {
            colour.setFill()
            NSBezierPath(ovalIn: frame.insetBy(dx: 4, dy: 4)).fill()
        }
    }
}
