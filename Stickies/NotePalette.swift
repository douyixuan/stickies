import AppKit

enum NotePalette {
    static let colors: [NSColor] = [
        NSColor(srgbRed: 1.0, green: 0.95, blue: 0.67, alpha: 1),
        NSColor(srgbRed: 0.79, green: 0.91, blue: 1.0, alpha: 1),
        NSColor(srgbRed: 0.88, green: 0.83, blue: 1.0, alpha: 1),
        NSColor(srgbRed: 0.83, green: 0.94, blue: 0.78, alpha: 1)
    ]

    static func color(_ index: Int) -> NSColor {
        colors[((index % colors.count) + colors.count) % colors.count]
    }
}
