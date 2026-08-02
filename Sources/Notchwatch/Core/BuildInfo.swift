//
//  BuildInfo.swift
//  Notchwatch
//
//  What this process was built from — so a running instance can be asked.
//

import Foundation

/// Identity of the binary the current process is executing.
///
/// `scripts/build-app.sh` deletes the bundle before assembling the new one, so a
/// running instance goes on executing an unlinked inode while a freshly built
/// binary sits at the same path — and `open` reactivates that old process rather
/// than starting the new one. The two are indistinguishable from the outside,
/// which is how an afternoon goes into debugging a fix that was never running.
///
/// So both sides are made to speak: `--version` reports the file on disk, and the
/// running app reports this stamp in its menu bar popover. If the two disagree,
/// what is on screen is not what was just built.
enum BuildInfo {
    struct Stamp {
        /// `CFBundleShortVersionString`, or "dev" for a bare `swift run` binary
        /// that has no bundle at all.
        let version: String
        /// `CFBundleVersion` — the monotonic build number CI injects.
        let build: String
        /// Modification time of the executable, read at launch. The nearest thing
        /// to a build timestamp available without Xcode, and the one field that
        /// actually distinguishes two builds of the same version.
        let builtAt: Date?
        let executablePath: String

        init() {
            let info = Bundle.main.infoDictionary
            version = info?["CFBundleShortVersionString"] as? String ?? "dev"
            build = info?["CFBundleVersion"] as? String ?? "0"
            executablePath = Bundle.main.executablePath
                ?? CommandLine.arguments.first
                ?? "unknown"
            builtAt = (try? FileManager.default.attributesOfItem(atPath: executablePath))?[.modificationDate] as? Date
        }

        /// Date and time, to the second: two builds a minute apart have to read
        /// as different, and a build number does not move between them locally.
        var builtAtDescription: String {
            guard let builtAt else { return "unknown" }
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
            return formatter.string(from: builtAt)
        }

        /// What the menu bar shows, and the second half of every `--version`.
        var short: String {
            "\(version) (build \(build)) · built \(builtAtDescription)"
        }

        var full: String {
            "\(AppIdentity.displayName) \(short)\n\(executablePath)"
        }
    }

    /// Resolved once, at launch, and never again. A later read would describe
    /// whatever file now sits at that path — which is precisely the binary this
    /// process is *not* running.
    static let stamp = Stamp()

    /// Take the reading while the file on disk is still the one being executed.
    static func capture() {
        _ = stamp
    }

    static let versionFlag = "--version"

    static func isVersionInvocation(_ arguments: [String]) -> Bool {
        arguments.dropFirst().contains(versionFlag)
    }
}
