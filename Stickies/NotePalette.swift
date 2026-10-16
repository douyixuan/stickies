import AppKit

enum NotePalette {
    static let colors: [NSColor] = [
        NSColor(srgbRed: 1.0, green: 0.95, blue: 0.67, alpha: 1),
        NSColor(srgbRed: 0.79, green: 0.91, blue: 1.0, alpha: 1),
        NSColor(srgbRed: 0.88, green: 0.83, blue: 1.0, alpha: 1),
        NSColor(srgbRed: 0.83, green: 0.94, blue: 0.78, alpha: 1)
    ]

    // Names describe the existing sRGB colors; persisted indices and values stay unchanged.
    static let names = ["Pale Yellow", "Light Blue", "Lavender", "Pale Green"]

    static func normalizedIndex(_ index: Int) -> Int {
        ((index % colors.count) + colors.count) % colors.count
    }

    static func name(_ index: Int) -> String { names[normalizedIndex(index)] }

    static func color(_ index: Int) -> NSColor { colors[normalizedIndex(index)] }
}
