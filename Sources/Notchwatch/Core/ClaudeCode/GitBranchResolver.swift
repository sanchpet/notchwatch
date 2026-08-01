//
//  GitBranchResolver.swift
//  Notchwatch
//
//  Resolves the branch a session's working directory is on.
//

import Foundation

/// Answers "which branch is this directory on?" from the repository itself.
///
/// The badge used to mirror the transcript's `gitBranch` field. That field is a
/// snapshot taken by whichever entry was written last, so a sub-agent working in
/// a nested checkout moved the badge to *that* repository's branch, and a
/// detached head arrived as the literal string `HEAD` — a word that names no
/// branch and tells the reader nothing.
///
/// Reading `.git/HEAD` answers the same question from the working directory the
/// session actually belongs to. It is also why no `git` process is spawned:
/// `git rev-parse --abbrev-ref HEAD` prints exactly the useless `HEAD` on a
/// detached head, so it would have to be paired with a second invocation, and
/// the answer is one short file that has to be stat'd for cache invalidation
/// anyway.
@MainActor
final class GitBranchResolver {
    static let shared = GitBranchResolver()

    private struct CacheEntry {
        let head: URL?
        let headModified: Date?
        let resolvedAt: Date
        let branch: String?
    }

    /// How long a "not a repository" answer is trusted. Positive answers are
    /// invalidated by the modification date of `HEAD` instead, which is exact.
    private static let negativeCacheLifetime: TimeInterval = 30

    private var cache: [String: CacheEntry] = [:]

    /// Branch name for `path`, or a short commit id when the head is detached.
    /// `nil` when the directory is not inside a work tree.
    func branch(forWorkingDirectory path: String) -> String? {
        guard !path.isEmpty else { return nil }

        if let cached = cache[path], isFresh(cached) {
            return cached.branch
        }

        guard let head = Self.headFile(startingAt: path) else {
            cache[path] = CacheEntry(head: nil, headModified: nil, resolvedAt: Date(), branch: nil)
            return nil
        }

        let branch = Self.branch(fromHeadAt: head)
        cache[path] = CacheEntry(
            head: head,
            headModified: Self.modificationDate(of: head),
            resolvedAt: Date(),
            branch: branch
        )
        return branch
    }

    private func isFresh(_ entry: CacheEntry) -> Bool {
        guard let head = entry.head else {
            return Date().timeIntervalSince(entry.resolvedAt) < Self.negativeCacheLifetime
        }
        // A checkout rewrites HEAD, so its modification date is the whole
        // invalidation rule — one stat per query instead of a process.
        return Self.modificationDate(of: head) == entry.headModified
    }

    // MARK: - Repository discovery

    /// Walk up from `path` to the `HEAD` of the enclosing work tree.
    private static func headFile(startingAt path: String) -> URL? {
        var directory = URL(fileURLWithPath: path).standardizedFileURL
        let fileManager = FileManager.default

        while true {
            let dotGit = directory.appendingPathComponent(".git")
            var isDirectory: ObjCBool = false
            if fileManager.fileExists(atPath: dotGit.path, isDirectory: &isDirectory) {
                if isDirectory.boolValue {
                    return dotGit.appendingPathComponent("HEAD")
                }
                // A linked worktree or a submodule stores a pointer instead of a
                // directory: "gitdir: <path>", absolute or relative to this one.
                if let gitDir = gitDirectory(fromPointerAt: dotGit, relativeTo: directory) {
                    return gitDir.appendingPathComponent("HEAD")
                }
                return nil
            }

            let parent = directory.deletingLastPathComponent().standardizedFileURL
            guard parent != directory else { return nil }
            directory = parent
        }
    }

    private static func gitDirectory(fromPointerAt pointer: URL, relativeTo base: URL) -> URL? {
        guard let contents = try? String(contentsOf: pointer, encoding: .utf8) else { return nil }
        guard let line = contents
            .split(separator: "\n")
            .first(where: { $0.hasPrefix("gitdir:") }) else { return nil }

        let target = line.dropFirst("gitdir:".count).trimmingCharacters(in: .whitespaces)
        guard !target.isEmpty else { return nil }
        return target.hasPrefix("/")
            ? URL(fileURLWithPath: target)
            : base.appendingPathComponent(target).standardizedFileURL
    }

    // MARK: - HEAD parsing

    private static func branch(fromHeadAt head: URL) -> String? {
        guard let contents = try? String(contentsOf: head, encoding: .utf8) else { return nil }
        let value = contents.trimmingCharacters(in: .whitespacesAndNewlines)

        if value.hasPrefix("ref:") {
            let ref = value.dropFirst("ref:".count).trimmingCharacters(in: .whitespaces)
            let branchPrefix = "refs/heads/"
            return ref.hasPrefix(branchPrefix) ? String(ref.dropFirst(branchPrefix.count)) : ref
        }

        // Detached head: HEAD holds the commit id. Show it — an abbreviated id
        // locates the reader, the word "HEAD" does not.
        guard value.count >= 7, value.allSatisfy(\.isHexDigit) else { return nil }
        return String(value.prefix(8))
    }

    private static func modificationDate(of url: URL) -> Date? {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
    }
}
