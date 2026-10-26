import Darwin
import Foundation

/// Which directory this build's notes live in. A delivery copy and a developer
/// preview never implicitly adopt the production profile.
enum NoteDataLocation {
    static func directory(environment: [String: String], bundleID: String?, bundleURL: URL,
                          applicationSupport: URL) -> URL {
        if let path = environment["STICKIES_DATA_DIR"] {
            return URL(fileURLWithPath: path, isDirectory: true)
        }
        if bundleID == "dev.douyixuan.stickies.local-preview" {
            return bundleURL.deletingLastPathComponent().appendingPathComponent("preview-data", isDirectory: true)
        }
        let name = bundleID == "dev.douyixuan.stickies.delivery" ? "Stickies Delivery" : "Stickies"
        return applicationSupport.appendingPathComponent(name, isDirectory: true)
    }

    static var current: URL {
        directory(environment: ProcessInfo.processInfo.environment,
                  bundleID: Bundle.main.bundleIdentifier,
                  bundleURL: Bundle.main.bundleURL,
                  applicationSupport: FileManager.default.urls(for: .applicationSupportDirectory,
                                                               in: .userDomainMask)[0])
    }
}

/// One writer per data directory. A second instance reads but never writes,
/// so two copies of the app cannot overwrite each other's notes.
final class DirectoryLock {
    private let descriptor: Int32

    /// Returns nil when another process already holds the directory.
    init?(directory: URL) {
        let url = directory.appendingPathComponent("notes.lock")
        descriptor = open(url.path, O_CREAT | O_RDWR, 0o644)
        guard descriptor >= 0 else { return nil }
        guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
            close(descriptor)
            return nil
        }
    }

    deinit {
        flock(descriptor, LOCK_UN)
        close(descriptor)
    }
}
