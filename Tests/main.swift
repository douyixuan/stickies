import Foundation

let screen = CGRect(x: -1440, y: 80, width: 1440, height: 820)
for strategy in [Arrangement.grid, .list] {
    for count in [0, 1, 4, 50] {
        let frames = LayoutEngine.arrange(count: count, in: screen, strategy: strategy)
        precondition(frames.count == count)
        precondition(frames.allSatisfy { screen.contains($0) })
        precondition(frames == LayoutEngine.arrange(count: count, in: screen, strategy: strategy))
    }
}
let small = CGRect(x: 0, y: 0, width: 150, height: 100)
precondition(LayoutEngine.arrange(count: 10, in: small, strategy: .grid).allSatisfy { small.contains($0) })
let missing = CGRect(x: 5000, y: -2000, width: 900, height: 1200)
precondition(screen.contains(LayoutEngine.restore(missing, screens: [screen])))
let second = CGRect(x: 0, y: 0, width: 1920, height: 1080)
let frame = CGRect(x: -1000, y: 100, width: 260, height: 220)
precondition(LayoutEngine.restore(frame, screens: [second, screen]) == frame)
precondition(LayoutEngine.restore(frame, screens: []) == frame)
print("PASS: layout boundaries, overflow, deterministic arrangements, small screens, negative coordinates, display recovery")
