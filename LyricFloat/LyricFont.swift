import UIKit

enum LyricFont: String, CaseIterable, Identifiable {
    case system, rounded, serif, monospaced

    var id: String { rawValue }

    var name: String {
        switch self {
        case .system: "System"
        case .rounded: "Rounded"
        case .serif: "Serif"
        case .monospaced: "Monospaced"
        }
    }

    private var design: UIFontDescriptor.SystemDesign? {
        switch self {
        case .system: nil
        case .rounded: .rounded
        case .serif: .serif
        case .monospaced: .monospaced
        }
    }

    func uiFont(size: CGFloat, weight: UIFont.Weight) -> UIFont {
        let system = UIFont.systemFont(ofSize: size, weight: weight)
        guard let design, let descriptor = system.fontDescriptor.withDesign(design) else {
            return system
        }
        return UIFont(descriptor: descriptor, size: size)
    }
}
