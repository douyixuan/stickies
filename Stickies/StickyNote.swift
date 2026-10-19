import Foundation
import CoreGraphics

struct StickyNote: Codable, Identifiable {
    var id: UUID = UUID()
    var text: String = ""
    var color: Int = 0
    var frame: CGRect = CGRect(x: 120, y: 180, width: 260, height: 220)
    var visible: Bool = true
}

