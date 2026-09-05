import AppKit

@MainActor
enum StatusIcon {
    static func image(overrideIsActive: Bool) -> NSImage {
        let symbolName = overrideIsActive ? "lock.slash.fill" : "lock.fill"
        var configuration = NSImage.SymbolConfiguration(pointSize: 15, weight: .semibold)
        if overrideIsActive {
            configuration = configuration.applying(
                NSImage.SymbolConfiguration(paletteColors: [.systemRed])
            )
        }

        if let symbol = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil),
            let configuredSymbol = symbol.withSymbolConfiguration(configuration)
        {
            configuredSymbol.isTemplate = !overrideIsActive
            return configuredSymbol
        }

        return fallbackImage(overrideIsActive: overrideIsActive)
    }

    private static func fallbackImage(overrideIsActive: Bool) -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { _ in
            let color: NSColor = overrideIsActive ? .systemRed : .labelColor
            color.setFill()
            NSBezierPath(ovalIn: NSRect(x: 4, y: 4, width: 10, height: 10)).fill()
            return true
        }
        image.isTemplate = !overrideIsActive
        return image
    }
}
