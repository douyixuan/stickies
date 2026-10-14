# Stickies

Native macOS spatial sticky notes, built with SwiftUI and AppKit. Local-first, with iCloud sync planned.

## Development

The prototype uses [XcodeGen](https://github.com/yonaskolb/XcodeGen) to generate an Xcode project:

```sh
brew install xcodegen
xcodegen generate
open Stickies.xcodeproj
```

Requires a Mac with Xcode. Current milestone: independent note windows, drag/resize, local persistence and grid/list arrangement. iCloud sync and desktop-level attachment are subsequent milestones.

## Roadmap

- [x] Repository bootstrap
- [ ] M1: Native note windows
- [ ] M2: Grid/list layout
- [ ] M3: Persistence and crash recovery
- [ ] M4: Desktop/Spaces compatibility validation
- [ ] M5: CloudKit sync
