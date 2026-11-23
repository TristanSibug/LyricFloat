import SwiftUI
import UIKit

struct LyricTheme: Identifiable, Equatable, Sendable {
    let id: String
    let name: String
    let background: UInt32
    let card: UInt32
    let text: UInt32
    let muted: UInt32
    let accent: UInt32
    let accent2: UInt32
    var isLight = false

    var backdrop: Color { Color(uiColor: UIColor(lyricHex: background)) }
    var surface: Color { Color(uiColor: panelColor) }
    var foreground: Color { Color(uiColor: UIColor(lyricHex: text)) }
    var secondary: Color { Color(uiColor: UIColor(lyricHex: muted)) }
    var highlight: Color { Color(uiColor: UIColor(lyricHex: accent)) }
    var highlight2: Color { Color(uiColor: UIColor(lyricHex: accent2)) }
    var onAccent: Color { Color(uiColor: UIColor(lyricHex: isLight ? 0xffffff : 0x160f12)) }
    var panelColor: UIColor { UIColor(lyricHex: card) }
    var colorScheme: ColorScheme { isLight ? .light : .dark }
    var alternateIconName: String? { id == Self.defaultID ? nil : "AppIcon-\(id)" }

    static let defaultID = "sunrise"
    static var defaultTheme: LyricTheme { all[0] }

    static func find(_ id: String) -> LyricTheme {
        all.first { $0.id == id } ?? defaultTheme
    }

    // LunkAlarm's current mobile palettes and the VS Code Blue desktop palette.
    static let all: [LyricTheme] = [
        LyricTheme(id: "sunrise", name: "Sunrise", background: 0x0a0c16, card: 0x171923,
                   text: 0xf4f2ff, muted: 0x9a9bb8, accent: 0xffa94d, accent2: 0xff6b7a),
        LyricTheme(id: "light", name: "Light", background: 0xf3f2fa, card: 0xffffff,
                   text: 0x1c1b2e, muted: 0x5b5c76, accent: 0xc4520a, accent2: 0xd6336c, isLight: true),
        LyricTheme(id: "eggshell-white", name: "Eggshell White", background: 0xf7f3e8, card: 0xfffefa,
                   text: 0x28343c, muted: 0x636b70, accent: 0x566a78, accent2: 0x6d6252, isLight: true),
        LyricTheme(id: "linen", name: "Linen", background: 0xf5efe5, card: 0xfffcf6,
                   text: 0x302921, muted: 0x766858, accent: 0x986020, accent2: 0xb34938, isLight: true),
        LyricTheme(id: "sea-glass", name: "Sea Glass", background: 0xeaf3ef, card: 0xf9fffc,
                   text: 0x173c37, muted: 0x526d67, accent: 0x237268, accent2: 0x346d8e, isLight: true),
        LyricTheme(id: "heritage", name: "Heritage", background: 0xf9efd4, card: 0xfffdf5,
                   text: 0x032d3f, muted: 0x52626b, accent: 0x7d0500, accent2: 0x032d3f, isLight: true),
        LyricTheme(id: "oled", name: "OLED Black", background: 0x000000, card: 0x0c0c0e,
                   text: 0xf2f2f5, muted: 0x9a9aa3, accent: 0xffa94d, accent2: 0xff6b7a),
        LyricTheme(id: "dark", name: "Dark", background: 0x17181c, card: 0x212329,
                   text: 0xececf1, muted: 0x9a9ba6, accent: 0xffa94d, accent2: 0xff6b7a),
        LyricTheme(id: "ember", name: "Ember", background: 0x1b1110, card: 0x2b1d1a,
                   text: 0xffeee3, muted: 0xc3a49a, accent: 0xffbb74, accent2: 0xef876d),
        LyricTheme(id: "midnight-cherry", name: "Midnight Cherry", background: 0x260f19, card: 0x3d1c2a,
                   text: 0xfff2f6, muted: 0xcaa6b5, accent: 0x9ecbf5, accent2: 0xff8d87),
        LyricTheme(id: "forest", name: "Forest", background: 0x0b1714, card: 0x142720,
                   text: 0xe4f2e9, muted: 0x9bb5a4, accent: 0x9dcc88, accent2: 0x59c7a5),
        LyricTheme(id: "nord", name: "Nord", background: 0x2e3440, card: 0x3b4252,
                   text: 0xeceff4, muted: 0xa4b1c4, accent: 0x88c0d0, accent2: 0x81a1c1),
        LyricTheme(id: "deep-ocean", name: "Deep Ocean", background: 0x081a24, card: 0x102b38,
                   text: 0xe1f5fb, muted: 0x99b9c6, accent: 0x79d2de, accent2: 0x82b0f7),
        LyricTheme(id: "vscode-blue", name: "VS Code Blue", background: 0x002451, card: 0x003370,
                   text: 0xe8f0ff, muted: 0xa9c0e6, accent: 0x5db0ff, accent2: 0x3a86ff),
        LyricTheme(id: "cobalt-coral", name: "Cobalt & Coral", background: 0x101c3d, card: 0x1d3057,
                   text: 0xf2f6ff, muted: 0xa8b8d6, accent: 0x92bdff, accent2: 0xff8a85),
        LyricTheme(id: "signal-blue", name: "Signal Blue", background: 0x032d3f, card: 0xbe0d1f,
                   text: 0xf1f7fa, muted: 0xe8d7e1, accent: 0xd2e7f2, accent2: 0x699db8),
        LyricTheme(id: "tokyo-night", name: "Tokyo Night", background: 0x1a1b26, card: 0x24283b,
                   text: 0xc0caf5, muted: 0x8c93bf, accent: 0x7aa2f7, accent2: 0xbb9af7),
        LyricTheme(id: "amethyst", name: "Amethyst", background: 0x171123, card: 0x251d36,
                   text: 0xf1eaff, muted: 0xb3a3cb, accent: 0xc5a2ff, accent2: 0xf0a4ce),
        LyricTheme(id: "dracula", name: "Dracula", background: 0x282a36, card: 0x303241,
                   text: 0xf8f8f2, muted: 0xa7a5bd, accent: 0xbd93f9, accent2: 0xff79c6),
    ]
}

extension UIColor {
    convenience init(lyricHex rgb: UInt32) {
        self.init(red: CGFloat((rgb >> 16) & 255) / 255,
                  green: CGFloat((rgb >> 8) & 255) / 255,
                  blue: CGFloat(rgb & 255) / 255,
                  alpha: 1)
    }
}
