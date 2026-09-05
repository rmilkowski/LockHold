import AppKit
import Testing

@testable import LockHold

@MainActor
struct StatusIconTests {
    @Test func inactiveIconAdaptsToMenuBarAppearance() {
        let image = StatusIcon.image(overrideIsActive: false)

        #expect(image.isTemplate)
        #expect(image.size.width > 0)
        #expect(image.size.height > 0)
    }

    @Test func activeIconPreservesItsWarningColour() {
        let image = StatusIcon.image(overrideIsActive: true)

        #expect(!image.isTemplate)
        #expect(image.size.width > 0)
        #expect(image.size.height > 0)
    }

    @Test(arguments: [false, true])
    func activeIconRendersRed(inDarkAppearance: Bool) throws {
        let appearance = try #require(
            NSAppearance(named: inDarkAppearance ? .darkAqua : .aqua)
        )
        var renderedImage: Data?
        appearance.performAsCurrentDrawingAppearance {
            renderedImage = StatusIcon.image(overrideIsActive: true).tiffRepresentation
        }

        let data = try #require(renderedImage)
        let bitmap = try #require(NSBitmapImageRep(data: data))
        let containsRed = (0..<bitmap.pixelsWide).contains { x in
            (0..<bitmap.pixelsHigh).contains { y in
                guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else {
                    return false
                }
                return color.alphaComponent > 0.5
                    && color.redComponent > 0.7
                    && color.greenComponent < color.redComponent * 0.7
                    && color.blueComponent < color.redComponent * 0.7
            }
        }

        #expect(containsRed)
    }
}
