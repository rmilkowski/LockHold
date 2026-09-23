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

    @Test(arguments: [false, true], [(false, false), (true, false), (false, true), (true, true)])
    func indicatorsRenderIndependently(inDarkAppearance: Bool, overrides: (Bool, Bool)) throws {
        let appearance = try #require(
            NSAppearance(named: inDarkAppearance ? .darkAqua : .aqua)
        )
        var renderedImage: Data?
        appearance.performAsCurrentDrawingAppearance {
            renderedImage =
                StatusIcon.image(
                    overrideIsActive: overrides.0, systemSleepDisabled: overrides.1
                ).tiffRepresentation
        }

        let data = try #require(renderedImage)
        let bitmap = try #require(NSBitmapImageRep(data: data))
        let midpoint = bitmap.pixelsWide / 2
        for (columns, isActive) in [
            (0..<midpoint, overrides.0), (midpoint..<bitmap.pixelsWide, overrides.1),
        ] {
            var containsRed = false
            var containsContrastingInk = false
            for x in columns {
                for y in 0..<bitmap.pixelsHigh {
                    guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB),
                        color.alphaComponent > 0.5
                    else { continue }
                    containsRed =
                        containsRed
                        || (color.redComponent > 0.7
                            && color.greenComponent < color.redComponent * 0.7
                            && color.blueComponent < color.redComponent * 0.7)
                    let brightness =
                        (color.redComponent + color.greenComponent + color.blueComponent) / 3
                    containsContrastingInk =
                        containsContrastingInk
                        || (inDarkAppearance ? brightness > 0.6 : brightness < 0.4)
                }
            }
            #expect(containsRed == isActive)
            if !isActive { #expect(containsContrastingInk) }
        }
    }
}
