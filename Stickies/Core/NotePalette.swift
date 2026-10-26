import Foundation

/// Colors live in the core as plain sRGB components so the model stays AppKit-free.
/// Persisted indices and component values are unchanged from earlier versions.
enum NotePalette {
    struct Swatch {
        let name: String
        let red: Double
        let green: Double
        let blue: Double
    }

    static let swatches: [Swatch] = [
        Swatch(name: "Pale Yellow", red: 1.0, green: 0.95, blue: 0.67),
        Swatch(name: "Light Blue", red: 0.79, green: 0.91, blue: 1.0),
        Swatch(name: "Lavender", red: 0.88, green: 0.83, blue: 1.0),
        Swatch(name: "Pale Green", red: 0.83, green: 0.94, blue: 0.78)
    ]

    static var indices: Range<Int> { swatches.indices.lowerBound..<swatches.indices.upperBound }

    static func normalizedIndex(_ index: Int) -> Int {
        ((index % swatches.count) + swatches.count) % swatches.count
    }

    static func swatch(_ index: Int) -> Swatch { swatches[normalizedIndex(index)] }

    static func name(_ index: Int) -> String { swatch(index).name }
}
