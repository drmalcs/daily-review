import SwiftUI
import AppKit
import CoreText

@main
struct DailyReviewApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var store = AppStore()

    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
                .environmentObject(store)
        } label: {
            Image(nsImage: store.allRated ? DailyReviewApp.whiteIcon : DailyReviewApp.redIcon)
        }
        .menuBarExtraStyle(.window)

        Window("Settings", id: "settings") {
            SettingsView()
                .environmentObject(store)
        }
        .windowResizability(.contentSize)
        .defaultPosition(.center)
    }

    // Two explicit-colour icons drawn as vector paths (not template rendering).
    static let redIcon:   NSImage = makeQuestionIcon(color: .systemRed)
    static let whiteIcon: NSImage = makeQuestionIcon(color: .white)

    // Draws a "?" glyph by extracting its CGPath from Core Text and filling it
    // with the requested colour — produces a proper vector image, not a text render.
    private static func makeQuestionIcon(color: NSColor) -> NSImage {
        let size = CGSize(width: 22, height: 22)
        return NSImage(size: size, flipped: false) { rect in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }

            let fontSize: CGFloat = 19
            let ctFont = CTFontCreateWithName("Helvetica-Bold" as CFString, fontSize, nil)

            // Convert "?" to a glyph index
            let chars: [UniChar] = Array("?".utf16)
            var glyphs = [CGGlyph](repeating: 0, count: chars.count)
            CTFontGetGlyphsForCharacters(ctFont, chars, &glyphs, chars.count)

            guard glyphs[0] != 0,
                  let glyphPath = CTFontCreatePathForGlyph(ctFont, glyphs[0], nil) else {
                // Fallback: plain text draw
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: NSFont.boldSystemFont(ofSize: fontSize),
                    .foregroundColor: color
                ]
                let s = "?" as NSString
                let sz = s.size(withAttributes: attrs)
                s.draw(at: CGPoint(x: (rect.width - sz.width) / 2,
                                   y: (rect.height - sz.height) / 2),
                       withAttributes: attrs)
                return true
            }

            // Centre the glyph path within the icon canvas
            var glyph = glyphs[0]
            let bounds = CTFontGetBoundingRectsForGlyphs(ctFont, .default, &glyph, nil, 1)
            let xOffset = (rect.width  - bounds.width)  / 2 - bounds.minX
            let yOffset = (rect.height - bounds.height) / 2 - bounds.minY

            ctx.saveGState()
            ctx.translateBy(x: xOffset, y: yOffset)
            ctx.addPath(glyphPath)
            ctx.setFillColor(color.cgColor)
            ctx.fillPath()
            ctx.restoreGState()
            return true
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        Config.loadDotEnv()
    }
}
