import Foundation

/// A tiny assertion harness: no XCTest, so the whole core suite is one swiftc
/// invocation that runs in a second and needs no window server.
enum Check {
    static var failures: [String] = []
    static var passed = 0

    static func that(_ condition: Bool, _ what: String) {
        if condition { passed += 1 } else { failures.append(what) }
    }

    static func equal<T: Equatable>(_ actual: T, _ expected: T, _ what: String) {
        that(actual == expected, "\(what): expected \(expected), got \(actual)")
    }

    static func summary() -> Never {
        for failure in failures { print("FAIL \(failure)") }
        print("\(passed) checks passed, \(failures.count) failed")
        exit(failures.isEmpty ? 0 : 1)
    }
}

/// A fresh empty directory per test, removed when the run ends.
enum Scratch {
    private static var created: [URL] = []

    static func directory(_ name: String) -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("stickies-tests-\(name)-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        created.append(url)
        return url
    }

    static func cleanUp() {
        for url in created {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
            try? FileManager.default.removeItem(at: url)
        }
        created = []
    }
}
