//
//  ClaudeCodeManager.swift
//  Notchwatch
//
//  Tracks what every live Claude Code session is doing.
//

import AppKit
import Combine
import Foundation

// MARK: - Debug Logging (disabled in Release builds)

/// Debug-only logging function - prints only in DEBUG builds to save CPU in production
@inline(__always)
func debugLog(_ message: @autoclosure () -> String) {
    #if DEBUG
        print(message())
    #endif
}

/// Session state for the notch, assembled from two sources.
///
/// **Hooks are the control plane.** `PreToolUse`, `PostToolUse`, `Stop` and the
/// rest are a documented, versioned contract: they say which tool started, in
/// which directory, under which session, at the moment it happens. Once a hook
/// has spoken for a session, the transcript stops being read for any of that.
///
/// **The transcript is the data plane.** Hooks carry no token counts and no model
/// id, and those are what the context bar is made of — so the transcript is still
/// read, but only for `usage` and `model`, and at the path the hook itself
/// supplied rather than one guessed from a directory name.
///
/// With no hooks installed the transcript drives everything, as before. That is a
/// degradation, not a failure mode.
@MainActor
final class ClaudeCodeManager: ObservableObject {
    static let shared = ClaudeCodeManager()

    /// Placeholder Claude Code puts in `message.model` for messages it generated
    /// itself rather than received from the API.
    private static let syntheticModel = "<synthetic>"

    /// Completed tools kept per session, and in the folded view across sessions.
    private static let recentToolsPerSession = 10
    private static let foldedToolLimit = 20

    /// Transcript entries replayed when a session is first attached.
    private static let historyLines = 200

    // MARK: - Cached Formatters

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    // MARK: - Published Properties

    @Published private(set) var availableSessions: [ClaudeSession] = []
    @Published private(set) var dailyStats: ClaudeDailyStats = .init()

    /// The only per-session truth. Everything the UI shows is folded from here.
    @Published private(set) var sessionStates: [String: ClaudeCodeState] = [:]

    /// Sessions currently waiting for user permission approval
    @Published private(set) var sessionsNeedingPermission: [ClaudeSession] = []

    // MARK: - Folded State

    /// Every watched session, folded into the one state the notch displays.
    ///
    /// This replaces a `selectedSession` that was only ever assigned when exactly
    /// one session existed. On any machine where an editor holds an IDE lock next
    /// to a terminal session — the normal case, not the exotic one — no session
    /// was ever selected, the published state stayed default-constructed, and the
    /// tool list was permanently empty while the per-session states filled up
    /// correctly behind it. There is no selection any more, so there is nothing
    /// left to fail to make.
    var state: ClaudeCodeState {
        guard var folded = focusedSessionKey.flatMap({ sessionStates[$0] }) else {
            return ClaudeCodeState()
        }

        folded.activeTools = foldTools(\.activeTools)
        folded.recentTools = foldTools(\.recentTools)

        // A prompt waiting anywhere is the one thing the user must not miss, so
        // it outranks the focused session.
        if let waiting = sessionStates.values.first(where: { $0.needsPermission }) {
            folded.needsPermission = true
            folded.pendingPermissionTool = waiting.pendingPermissionTool
        }

        return folded
    }

    /// The session whose single-valued readouts (model, tokens, branch, todos)
    /// are shown: the one doing something, most recently heard from.
    private var focusedSessionKey: String? {
        sessionStates.max { lhs, rhs in
            Self.focusRank(lhs.value) < Self.focusRank(rhs.value)
        }?.key
    }

    private static func focusRank(_ state: ClaudeCodeState) -> (Int, Date) {
        (state.isActive ? 1 : 0, state.lastUpdateTime ?? .distantPast)
    }

    /// Tools from every session, newest first, deduplicated by tool id.
    private func foldTools(_ keyPath: KeyPath<ClaudeCodeState, [ClaudeToolExecution]>) -> [ClaudeToolExecution] {
        var seen = Set<String>()
        return sessionStates.values
            .flatMap { $0[keyPath: keyPath] }
            .sorted { ($0.endTime ?? $0.startTime) > ($1.endTime ?? $1.startTime) }
            .filter { seen.insert($0.id).inserted }
            .prefix(Self.foldedToolLimit)
            .map { $0 }
    }

    /// Track when we last had activity (for grace period before notch collapses)
    private var lastActivityTime: Date = .distantPast
    /// Grace period to keep notch visible after activity stops (seconds)
    private let activityGracePeriod: TimeInterval = 1.0

    /// True if any session has activity (thinking, active tools, or needs permission)
    var hasAnySessionActivity: Bool {
        for sessionState in sessionStates.values {
            if sessionState.isActive || sessionState.needsPermission {
                lastActivityTime = Date()
                return true
            }
        }
        if !sessionsNeedingPermission.isEmpty {
            lastActivityTime = Date()
            return true
        }

        return Date().timeIntervalSince(lastActivityTime) < activityGracePeriod
    }

    // MARK: - Private Properties

    /// Home directory, read from the password database rather than `NSHomeDirectory`
    /// so that a future sandboxed build still finds the real one.
    private static let homeDir: URL = {
        if let pw = getpwuid(getuid()), let home = pw.pointee.pw_dir {
            return URL(fileURLWithPath: String(cString: home))
        }
        return FileManager.default.homeDirectoryForCurrentUser
    }()

    /// Every Claude Code configuration root on this machine, not just `~/.claude`.
    ///
    /// `CLAUDE_CONFIG_DIR` relocates the whole configuration directory, and running
    /// separate accounts out of `~/.claude-personal` and `~/.claude-work` is the
    /// documented way to keep them apart. A watcher that reads only `~/.claude`
    /// therefore misses every session of anyone who uses that mechanism — and
    /// silently, since the default root still exists and still holds whatever
    /// stale transcripts were written before the split.
    ///
    /// The app is launched from Finder and inherits no shell environment, so the
    /// variable itself is not available to read: the roots are discovered instead,
    /// by looking for the `projects` directory that makes a root a root.
    private let claudeRoots: [URL] = {
        let fm = FileManager.default
        // Deliberately without `.skipsHiddenFiles`: every root is a dot-directory,
        // so that option would hide exactly what is being looked for.
        let candidates = (try? fm.contentsOfDirectory(
            at: homeDir,
            includingPropertiesForKeys: nil,
            options: [.skipsSubdirectoryDescendants]
        )) ?? []

        let roots = ([homeDir.appendingPathComponent(".claude")] + candidates.sorted { $0.path < $1.path })
            .filter { $0.lastPathComponent == ".claude" || $0.lastPathComponent.hasPrefix(".claude-") }
            .filter { fm.fileExists(atPath: $0.appendingPathComponent("projects").path) }

        // The seed above keeps the default root first when it exists; the dedup
        // drops the copy the directory listing then yields.
        var seen = Set<String>()
        return roots.filter { seen.insert($0.standardizedFileURL.path).inserted }
    }()

    private var ideDirs: [URL] {
        claudeRoots.map { $0.appendingPathComponent("ide") }
    }

    private var projectsDirs: [URL] {
        claudeRoots.map { $0.appendingPathComponent("projects") }
    }

    /// One watched transcript, with everything needed to keep reading it.
    private struct WatchedSession {
        let session: ClaudeSession
        let transcript: URL
        let handle: FileHandle
        let source: DispatchSourceFileSystemObject
        var tail: TranscriptTail
        /// Set by the first hook event for this session, and never cleared while
        /// the session lives: the two planes must not both create tools.
        var isHookDriven = false
    }

    private var watched: [String: WatchedSession] = [:]

    /// Sessions a hook told us about. Kept across scans — the scan finds sessions
    /// by recently modified transcripts, which a session sitting on a permission
    /// prompt stops being.
    private var hookSessions: [String: ClaudeSession] = [:]

    private var sessionScanTimer: Timer?

    /// Sessions whose replayed history must not raise permission prompts.
    private var loadingHistory: Set<String> = []

    /// Tool ids awaiting completion, per session, with the time they started.
    private var pendingToolChecks: [String: [String: Date]] = [:]

    /// Context reading per session. Owns every decision about which usage entry
    /// counts; `ClaudeCodeState` only carries the result to the views.
    private var contextTrackers: [String: ClaudeContextTracker] = [:]

    /// Timer to detect when a tool is waiting for permission (no result after delay)
    private var permissionCheckTimer: Timer?
    /// Delay before assuming a tool needs permission (seconds)
    private let permissionCheckDelay: TimeInterval = 5.0
    /// Tools that typically require user permission or interaction
    private let permissionEligibleTools: Set<String> = [
        "Bash", "Write", "Edit", "Task", "NotebookEdit", // File/system operations
        "AskUserQuestion", // User interaction
        "WebSearch", "WebFetch", // Web operations (may need approval)
    ]
    /// Tools that are always auto-approved (never show permission indicator)
    private let autoApprovedTools: Set<String> = ["Read", "Glob", "Grep", "LS", "TodoWrite"]

    /// Timer to detect idle state (for thinking)
    private var idleCheckTimer: Timer?
    private let idleCheckDelay: TimeInterval = 3.0

    /// Timer to detect tool idle state (no new tool for 10 seconds = session done)
    private var toolIdleTimer: Timer?
    private let toolIdleDelay: TimeInterval = 10.0

    /// Sequence for tools reported by hooks that carry no `tool_use_id`.
    private var hookToolSequence: UInt64 = 0

    // MARK: - Initialization

    private init() {
        debugLog("[ClaudeCode] ClaudeCodeManager initializing (roots: \(claudeRoots.map(\.lastPathComponent)))")
        startSessionScanning()
        loadDailyStats()
        updateHookBridge()
    }

    // MARK: - Public Methods

    /// Manually refresh state
    func refresh() {
        scanForSessions()
    }

    /// Bring the IDE running Claude Code to the front
    func focusIDE(for session: ClaudeSession? = nil) {
        guard let targetSession = session ?? focusedSession else {
            debugLog("[ClaudeCode] No session to focus")
            return
        }

        let ideName = targetSession.ideName.lowercased()
        debugLog("[ClaudeCode] Attempting to focus IDE: \(targetSession.ideName)")

        let bundleIdentifiers: [String] = if ideName.contains("code") || ideName.contains("vscode") {
            ["com.microsoft.VSCode", "com.visualstudio.code.oss"]
        } else if ideName.contains("windsurf") {
            ["com.codeium.windsurf"]
        } else if ideName.contains("zed") {
            ["dev.zed.Zed"]
        } else {
            []
        }

        for bundleId in bundleIdentifiers {
            if let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleId).first {
                app.activate(options: [.activateIgnoringOtherApps])
                return
            }
        }

        let runningApps = NSWorkspace.shared.runningApplications
        if let app = runningApps.first(where: { $0.processIdentifier == Int32(targetSession.pid) }) {
            app.activate(options: [.activateIgnoringOtherApps])
            return
        }

        if let app = runningApps.first(where: {
            $0.localizedName?.lowercased().contains(ideName) == true
        }) {
            app.activate(options: [.activateIgnoringOtherApps])
        }
    }

    private var focusedSession: ClaudeSession? {
        guard let key = focusedSessionKey else { return nil }
        return watched[key]?.session ?? availableSessions.first { $0.id == key }
    }

    // MARK: - Session Discovery

    /// Scan for active Claude Code sessions
    func scanForSessions() {
        let fm = FileManager.default
        var sessions: [ClaudeSession] = []

        // IDE lock files, written by the editor extensions.
        for ideDir in ideDirs {
            guard fm.fileExists(atPath: ideDir.path),
                  let lockFiles = try? fm.contentsOfDirectory(at: ideDir, includingPropertiesForKeys: nil) else { continue }
            for lockFile in lockFiles where lockFile.pathExtension == "lock" {
                guard let data = fm.contents(atPath: lockFile.path),
                      let session = try? JSONDecoder().decode(ClaudeSession.self, from: data),
                      isProcessRunning(pid: session.pid) else { continue }
                sessions.append(session)
            }
        }

        // Terminal sessions leave no lock file; a recently written transcript is
        // the only trace they have.
        for projectsDir in projectsDirs {
            guard fm.fileExists(atPath: projectsDir.path),
                  let projectDirs = try? fm.contentsOfDirectory(at: projectsDir, includingPropertiesForKeys: nil) else { continue }
            let recentThreshold = Date().addingTimeInterval(-300) // 5 minutes

            for projectDir in projectDirs {
                var isDir: ObjCBool = false
                guard fm.fileExists(atPath: projectDir.path, isDirectory: &isDir), isDir.boolValue else { continue }

                for jsonlFile in findActiveSessionFiles(in: projectDir) {
                    let modDate = (try? fm.attributesOfItem(atPath: jsonlFile.path))?[.modificationDate] as? Date
                    guard (modDate ?? .distantPast) > recentThreshold else { continue }

                    // The project directory name is the workspace path with "/"
                    // replaced by "-", which is not reversible for a path that
                    // contains a dash. Good enough to key a session on; the real
                    // directory comes from the transcript in `workingDirectory`.
                    let workspacePath = projectDir.lastPathComponent.replacingOccurrences(of: "-", with: "/")
                    let sessionId = jsonlFile.deletingPathExtension().lastPathComponent

                    sessions.append(ClaudeSession(
                        pid: 0, // Terminal sessions don't have a single PID
                        workspaceFolders: ["\(workspacePath)#\(sessionId)"],
                        ideName: "Terminal",
                        transport: nil,
                        runningInWindows: nil
                    ))
                }
            }
        }

        for (key, session) in hookSessions where !sessions.contains(where: { $0.id == key }) {
            sessions.append(session)
        }

        for session in sessions where watched[session.id] == nil {
            startWatching(session)
        }

        // A session is only real once its transcript is attached. Discovery can
        // produce two entries for one transcript — an editor lock and a terminal
        // scan of the same project — and `attach` keeps the first; listing the
        // other would count one session twice.
        availableSessions = sessions.filter { watched[$0.id] != nil }

        let currentIds = Set(availableSessions.map(\.id))
        for watchedId in Array(watched.keys) where !currentIds.contains(watchedId) {
            detach(sessionKey: watchedId)
        }
    }

    private func startSessionScanning() {
        scanForSessions()
        sessionScanTimer = Timer.scheduledTimer(withTimeInterval: 10.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.scanForSessions()
                self?.loadDailyStats()
            }
        }
    }

    private func isProcessRunning(pid: Int) -> Bool {
        let runningApps = NSWorkspace.shared.runningApplications
        if runningApps.contains(where: { $0.processIdentifier == Int32(pid) }) {
            return true
        }

        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, Int32(pid)]
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.size
        let result = sysctl(&mib, UInt32(mib.count), &info, &size, nil, 0)
        return result == 0 && size > 0
    }

    private func findActiveSessionFiles(in projectDir: URL) -> [URL] {
        let fm = FileManager.default
        guard let allFiles = try? fm.contentsOfDirectory(
            at: projectDir,
            includingPropertiesForKeys: [.contentModificationDateKey]
        ) else { return [] }

        return allFiles
            .filter { $0.pathExtension == "jsonl" && !$0.lastPathComponent.hasPrefix("agent-") }
            .sorted { lhs, rhs in
                let lhsDate = (try? lhs.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
                let rhsDate = (try? rhs.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
                return lhsDate > rhsDate
            }
    }

    // MARK: - Transcript Watching

    private func startWatching(_ session: ClaudeSession) {
        guard let transcript = locateTranscript(for: session) else {
            debugLog("[ClaudeCode] No transcript for session \(session.displayName)")
            return
        }
        attach(session, transcript: transcript)
    }

    /// The transcript a discovered session reads from, searched across every
    /// configuration root: a lock written by an editor running one profile says
    /// nothing about which profile the session it describes belongs to.
    private func locateTranscript(for session: ClaudeSession) -> URL? {
        for projectsDir in projectsDirs {
            if let file = locateTranscript(for: session, under: projectsDir) {
                return file
            }
        }
        return nil
    }

    private func locateTranscript(for session: ClaudeSession, under projectsDir: URL) -> URL? {
        let fm = FileManager.default

        if let projectKey = session.projectKey {
            let directPath = projectsDir.appendingPathComponent(projectKey)
            if let terminalId = session.terminalSessionId {
                let file = directPath.appendingPathComponent("\(terminalId).jsonl")
                if fm.fileExists(atPath: file.path) {
                    return file
                }
            } else if let file = findActiveSessionFiles(in: directPath).first {
                return file
            }
        }

        // Fallback: the "/" -> "-" project key is lossy, so compare directories
        // by the path they decode to rather than by the key we built.
        guard let workspace = session.workspaceFolders.first,
              let projectDirs = try? fm.contentsOfDirectory(at: projectsDir, includingPropertiesForKeys: nil) else {
            return nil
        }
        let cleanWorkspace = (workspace.components(separatedBy: "#").first ?? workspace).lowercased()

        for dir in projectDirs {
            let decoded = dir.lastPathComponent.replacingOccurrences(of: "-", with: "/")
            let normalized = decoded.hasPrefix("/") ? decoded : "/" + decoded
            guard normalized.lowercased() == cleanWorkspace else { continue }

            if let terminalId = session.terminalSessionId {
                let file = dir.appendingPathComponent("\(terminalId).jsonl")
                if fm.fileExists(atPath: file.path) {
                    return file
                }
            } else if let file = findActiveSessionFiles(in: dir).first {
                return file
            }
        }
        return nil
    }

    private func attach(_ session: ClaudeSession, transcript rawTranscript: URL) {
        let transcript = rawTranscript.standardizedFileURL
        guard watched[session.id] == nil else { return }
        // A session discovered twice under two keys (a scan reconstructing the
        // workspace path one way, a hook reporting it another) is still one
        // transcript, and reading it twice would double every tool.
        guard !watched.values.contains(where: { $0.transcript == transcript }) else { return }
        guard let handle = try? FileHandle(forReadingFrom: transcript) else { return }

        let descriptor = open(transcript.path, O_EVTONLY)
        guard descriptor >= 0 else {
            try? handle.close()
            return
        }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .extend],
            queue: .main
        )
        source.setEventHandler { [weak self] in
            self?.readNewData(for: session.id)
        }
        source.setCancelHandler {
            close(descriptor)
        }

        var tail = TranscriptTail()
        tail.seekToEnd(handle)

        var sessionState = ClaudeCodeState()
        sessionState.sessionId = session.terminalSessionId ?? session.id
        sessionState.cwd = TranscriptTail.firstValue(forKey: "cwd", in: transcript) ?? ""
        sessionState.isConnected = true
        sessionState.lastUpdateTime = Date()
        sessionStates[session.id] = sessionState

        watched[session.id] = WatchedSession(
            session: session,
            transcript: transcript,
            handle: handle,
            source: source,
            tail: tail
        )

        debugLog("[ClaudeCode] Attached \(session.displayName) -> \(transcript.lastPathComponent)")
        loadHistory(for: session.id)

        // Last resort, and a poor one: the workspace path rebuilt from the
        // project directory name, which cannot survive a path containing a dash.
        if sessionStates[session.id]?.cwd.isEmpty == true,
           let workspace = session.workspaceFolders.first {
            sessionStates[session.id]?.cwd = workspace.components(separatedBy: "#").first ?? workspace
        }

        refreshGitBranch(for: session.id)
        source.resume()
    }

    private func detach(sessionKey: String) {
        watched[sessionKey]?.source.cancel()
        try? watched[sessionKey]?.handle.close()
        watched.removeValue(forKey: sessionKey)
        sessionStates.removeValue(forKey: sessionKey)
        pendingToolChecks.removeValue(forKey: sessionKey)
        contextTrackers.removeValue(forKey: sessionKey)
        loadingHistory.remove(sessionKey)
        sessionsNeedingPermission.removeAll { $0.id == sessionKey }
    }

    private func loadHistory(for sessionKey: String) {
        guard let entry = watched[sessionKey] else { return }

        loadingHistory.insert(sessionKey)
        for line in TranscriptTail.history(of: entry.transcript, maxLines: Self.historyLines) {
            parseTranscriptLine(line, sessionKey: sessionKey)
        }
        loadingHistory.remove(sessionKey)

        // History is what already happened: nothing replayed from it is running.
        if var sessionState = sessionStates[sessionKey] {
            sessionState.activeTools.removeAll()
            sessionState.isThinking = false
            sessionStates[sessionKey] = sessionState
        }
        pendingToolChecks[sessionKey] = nil
    }

    private func readNewData(for sessionKey: String) {
        guard var entry = watched[sessionKey] else { return }
        let lines = entry.tail.read(entry.handle)
        watched[sessionKey] = entry
        guard !lines.isEmpty else { return }

        objectWillChange.send()

        if var sessionState = sessionStates[sessionKey] {
            // Writing to the transcript at all means Claude is working. This is a
            // liveness signal rather than a claim about tools, so it stands even
            // for hook-driven sessions: it is what keeps the notch lit through
            // the stretches that raise no hook at all (compaction, a long
            // generation with no tool calls).
            sessionState.isThinking = true
            sessionState.lastUpdateTime = Date()
            sessionStates[sessionKey] = sessionState
        }

        for line in lines {
            parseTranscriptLine(line, sessionKey: sessionKey)
        }

        refreshGitBranch(for: sessionKey)
        resetIdleTimer()
    }

    // MARK: - Transcript Parsing

    private func parseTranscriptLine(_ line: String, sessionKey: String) {
        guard let data = line.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return
        }

        // The entry's own `gitBranch` is deliberately ignored — see
        // GitBranchResolver for why a field written by whoever wrote last cannot
        // answer which branch this session is on.

        if let sessionId = json["sessionId"] as? String, var sessionState = sessionStates[sessionKey] {
            sessionState.sessionId = sessionId
            sessionStates[sessionKey] = sessionState
        }

        // The working directory is adopted once and then left alone. A session's
        // directory is fixed when Claude Code starts, while the `cwd` of later
        // entries follows whichever sub-agent wrote them — tracking that is how
        // the branch badge ended up naming a nested checkout. Transcripts open
        // with metadata entries carrying no `cwd`, so the first one that does
        // wins; sidechain entries are a sub-agent's and never qualify.
        if sessionStates[sessionKey]?.cwd.isEmpty == true,
           json["isSidechain"] as? Bool != true,
           let cwd = json["cwd"] as? String, !cwd.isEmpty {
            sessionStates[sessionKey]?.cwd = cwd
            // The pin is per-project as well as per-user, so it can only be read
            // once the session's directory is known.
            if ClaudeModelPin.declaresLongWindow(projectDirectory: cwd) {
                contextTrackers[sessionKey, default: ClaudeContextTracker()].noteLongWindowOptIn()
            }
        }

        // Compaction replaces the conversation with a summary, so the prompt that
        // follows is legitimately far smaller than the one before. It is the only
        // routine reason for the context to shrink, and marking it here is what
        // lets the tracker reject every other shrink as an artefact.
        if json["type"] as? String == "system",
           json["subtype"] as? String == "compact_boundary" {
            contextTrackers[sessionKey, default: ClaudeContextTracker()].noteCompactBoundary()
        }

        // Interruptions are read in both modes: an interrupt clears state rather
        // than inventing any, and the transcript reports it sooner than `Stop`.
        if let toolUseResult = json["toolUseResult"] {
            // A `Task` result names the model the subagent resolved to, and that
            // is the one place in a transcript where the 1M opt-in survives with
            // its suffix intact.
            if let result = toolUseResult as? [String: Any],
               let resolved = result["resolvedModel"] as? String {
                contextTrackers[sessionKey, default: ClaudeContextTracker()].noteModelID(resolved)
            }

            let resultText = "\(toolUseResult)"
            if resultText.contains("interrupted by user") || resultText.contains("Request interrupted") {
                markInterrupted(sessionKey: sessionKey)
            }
        }

        if let message = json["message"] as? [String: Any] {
            applyMessage(message, sessionKey: sessionKey)
        }

        // Every branch above may have told the tracker something — a boundary, a
        // resolved model, a pin — and only some of them go through `applyMessage`.
        // Publishing here means the state never lags a signal by a whole entry.
        publishContextReading(sessionKey: sessionKey)
    }

    /// Copy the tracker's conclusions into the state the views read.
    private func publishContextReading(sessionKey: String) {
        guard let tracker = contextTrackers[sessionKey],
              var sessionState = sessionStates[sessionKey] else { return }
        guard sessionState.tokenUsage != tracker.usage
            || sessionState.observedPeakPromptTokens != tracker.peakPromptTokens
            || sessionState.declaresLongContextWindow != tracker.declaresLongWindow
        else { return }

        sessionState.tokenUsage = tracker.usage
        sessionState.observedPeakPromptTokens = tracker.peakPromptTokens
        sessionState.declaresLongContextWindow = tracker.declaresLongWindow
        sessionStates[sessionKey] = sessionState
        objectWillChange.send()
    }

    private func applyMessage(_ message: [String: Any], sessionKey: String) {
        guard var sessionState = sessionStates[sessionKey] else { return }

        // Claude Code writes `<synthetic>` messages for locally generated errors
        // and interrupts ("API Error: …", "Please run /login"). They carry no real
        // model and an all-zero usage block, so letting either through collapses
        // the context reading to 0 on a session that is still fully loaded.
        let isSynthetic = (message["model"] as? String) == Self.syntheticModel

        // --- data plane: read whether or not hooks are installed ---------------

        if let model = message["model"] as? String, !isSynthetic {
            sessionState.model = model
            // Empirically the suffix never reaches this field, but reading it
            // costs nothing and stops a future Claude Code from being missed.
            contextTrackers[sessionKey, default: ClaudeContextTracker()].noteModelID(model)
        }

        if let usage = message["usage"] as? [String: Any], !isSynthetic {
            contextTrackers[sessionKey, default: ClaudeContextTracker()].apply(
                ClaudeTokenUsage(transcriptUsage: usage),
                messageID: message["id"] as? String
            )
        }

        // The tracker's conclusions reach `sessionState` through
        // `publishContextReading`, which runs for every entry rather than only
        // for the ones carrying a `message`.

        // --- control plane: only while no hook has spoken for this session -----

        if watched[sessionKey]?.isHookDriven != true {
            applyTranscriptControlPlane(message, to: &sessionState, sessionKey: sessionKey)
        }

        sessionStates[sessionKey] = sessionState
        updateSessionsNeedingPermission()
        objectWillChange.send()
    }

    private func applyTranscriptControlPlane(
        _ message: [String: Any],
        to sessionState: inout ClaudeCodeState,
        sessionKey: String
    ) {
        if let stopReason = message["stop_reason"] as? String {
            sessionState.lastStopReason = stopReason
            if stopReason == "end_turn" {
                sessionState.isThinking = false
            }
        }

        let role = message["role"] as? String
        if role == "user" || role == "assistant" {
            sessionState.isThinking = true
            sessionState.lastStopReason = nil
        }

        guard let content = message["content"] as? [[String: Any]] else { return }

        for item in content {
            guard let type = item["type"] as? String else { continue }

            switch type {
            case "thinking":
                // Thinking after a tool has already run is the closing summary,
                // not the start of new work.
                sessionState.isThinking = !(sessionState.activeTools.isEmpty && !sessionState.recentTools.isEmpty)

            case "text":
                if sessionState.activeTools.isEmpty, !sessionState.recentTools.isEmpty {
                    sessionState.isThinking = false
                }
                if let text = item["text"] as? String, text.contains("[Request interrupted by user") {
                    sessionState.isThinking = false
                    sessionState.lastStopReason = "interrupted"
                    sessionState.activeTools.removeAll()
                    pendingToolChecks[sessionKey] = nil
                }

            case "tool_use":
                sessionState.isThinking = false
                resetToolIdleTimer()

                guard let toolId = item["id"] as? String,
                      let toolName = item["name"] as? String,
                      !sessionState.activeTools.contains(where: { $0.id == toolId }) else { continue }

                let input = item["input"] as? [String: Any]
                if toolName == "TodoWrite", let todos = input?["todos"] as? [[String: Any]] {
                    sessionState.todos = Self.parseTodos(todos)
                }

                sessionState.activeTools.append(makeTool(id: toolId, name: toolName, input: input))
                startPermissionCheck(sessionKey: sessionKey, toolId: toolId, toolName: toolName)

            case "tool_result":
                guard role == "user", let toolUseId = item["tool_use_id"] as? String else { continue }
                clearPermissionCheck(sessionKey: sessionKey, toolId: toolUseId, in: &sessionState)
                completeTool(id: toolUseId, in: &sessionState)
                sessionState.isThinking = true

            default:
                break
            }
        }
    }

    private func markInterrupted(sessionKey: String) {
        guard var sessionState = sessionStates[sessionKey] else { return }
        debugLog("[ClaudeCode] Session \(sessionKey) interrupted by user")
        sessionState.isThinking = false
        sessionState.lastStopReason = "interrupted"
        sessionState.activeTools.removeAll()
        sessionStates[sessionKey] = sessionState
        pendingToolChecks[sessionKey] = nil
        updateSessionsNeedingPermission()
    }

    // MARK: - Tool Bookkeeping

    private func makeTool(id: String, name: String, input: [String: Any]?) -> ClaudeToolExecution {
        var tool = ClaudeToolExecution(
            id: id,
            toolName: name,
            argument: Self.extractToolArgument(from: input),
            startTime: Date()
        )
        tool.description = input?["description"] as? String
        tool.timeout = input?["timeout"] as? Int
        return tool
    }

    /// Move a running tool to the recent list, stamping it with the usage read at
    /// the moment it finished.
    private func completeTool(id: String, in sessionState: inout ClaudeCodeState) {
        guard let index = sessionState.activeTools.firstIndex(where: { $0.id == id }) else { return }

        var tool = sessionState.activeTools.remove(at: index)
        tool.endTime = Date()
        tool.inputTokens = sessionState.tokenUsage.inputTokens
        tool.outputTokens = sessionState.tokenUsage.outputTokens
        tool.cacheReadTokens = sessionState.tokenUsage.cacheReadInputTokens
        tool.cacheWriteTokens = sessionState.tokenUsage.cacheCreationInputTokens

        sessionState.recentTools.insert(tool, at: 0)
        if sessionState.recentTools.count > Self.recentToolsPerSession {
            sessionState.recentTools.removeLast()
        }
    }

    private static func extractToolArgument(from input: [String: Any]?) -> String? {
        guard let input else { return nil }

        if let pattern = input["pattern"] as? String {
            return pattern
        }
        if let command = input["command"] as? String {
            return String(command.prefix(50))
        }
        if let filePath = input["file_path"] as? String {
            return URL(fileURLWithPath: filePath).lastPathComponent
        }
        if let query = input["query"] as? String {
            return String(query.prefix(50))
        }
        if let prompt = input["prompt"] as? String {
            return String(prompt.prefix(50))
        }

        return nil
    }

    private static func parseTodos(_ todosArray: [[String: Any]]) -> [ClaudeTodoItem] {
        todosArray.compactMap { todo in
            guard let content = todo["content"] as? String,
                  let statusText = todo["status"] as? String else { return nil }
            return ClaudeTodoItem(
                content: content,
                status: ClaudeTodoItem.TodoStatus(rawValue: statusText) ?? .pending
            )
        }
    }

    // MARK: - Hook Bridge

    /// Start or stop the spool watcher to match the current setting.
    func updateHookBridge() {
        if AppSettings.shared.enableHookBridge {
            guard !HookSpoolWatcher.shared.isRunning else { return }
            HookSpoolWatcher.shared.start { [weak self] event in
                self?.apply(event)
            }
        } else {
            HookSpoolWatcher.shared.stop()
        }
    }

    /// Fold one hook event into the session it belongs to.
    func apply(_ event: HookEvent) {
        guard let kind = event.kind,
              let sessionKey = resolveSession(for: event),
              var sessionState = sessionStates[sessionKey] else { return }

        objectWillChange.send()
        watched[sessionKey]?.isHookDriven = true

        switch kind {
        case .sessionStart, .userPromptSubmit:
            sessionState.isThinking = true
            sessionState.lastStopReason = nil

        case .preToolUse:
            guard let toolName = event.toolName else { break }
            hookToolSequence += 1
            // `tool_use_id` is not in every Claude Code version's payload; the
            // sequence keeps ids unique so a repeated tool name still pairs up.
            let toolId = event.toolUseID ?? "hook-\(event.sessionID)-\(hookToolSequence)"

            sessionState.isThinking = false
            if toolName == "TodoWrite", let todos = event.toolInput?["todos"] as? [[String: Any]] {
                sessionState.todos = Self.parseTodos(todos)
            }
            sessionState.activeTools.append(makeTool(id: toolId, name: toolName, input: event.toolInput))
            startPermissionCheck(sessionKey: sessionKey, toolId: toolId, toolName: toolName)
            resetToolIdleTimer()

        case .postToolUse:
            // Without an id, pair with the most recent running tool of that name:
            // PreToolUse and PostToolUse bracket one call, so the newest match is
            // the one that just returned.
            let toolId = event.toolUseID
                ?? sessionState.activeTools.last(where: { $0.toolName == event.toolName })?.id
            guard let toolId else { break }
            clearPermissionCheck(sessionKey: sessionKey, toolId: toolId, in: &sessionState)
            completeTool(id: toolId, in: &sessionState)
            sessionState.isThinking = true

        case .notification:
            // Claude Code notifies on both "needs your permission" and "waiting
            // for your input"; only the former is a blocked tool.
            if event.message?.range(of: "permission", options: .caseInsensitive) != nil {
                sessionState.needsPermission = true
                sessionState.pendingPermissionTool = sessionState.activeTools.last?.toolName
            }

        case .stop:
            sessionState.isThinking = false
            sessionState.lastStopReason = "end_turn"
            sessionState.activeTools.removeAll()
            pendingToolChecks[sessionKey] = nil

        case .sessionEnd:
            hookSessions.removeValue(forKey: sessionKey)
            availableSessions.removeAll { $0.id == sessionKey }
            detach(sessionKey: sessionKey)
            updateSessionsNeedingPermission()
            return
        }

        sessionState.isConnected = true
        sessionState.lastUpdateTime = Date()
        if let cwd = event.cwd, sessionState.cwd.isEmpty {
            sessionState.cwd = cwd
        }
        sessionStates[sessionKey] = sessionState

        refreshGitBranch(for: sessionKey)
        updateSessionsNeedingPermission()
        resetIdleTimer()
    }

    /// The session key this event belongs to, adopting the session if the scan
    /// has not found it yet.
    private func resolveSession(for event: HookEvent) -> String? {
        let transcript = event.transcriptPath.map { URL(fileURLWithPath: $0).standardizedFileURL }

        if let transcript, let key = watched.first(where: { $0.value.transcript == transcript })?.key {
            return key
        }
        if let key = watched.first(where: { $0.value.session.terminalSessionId == event.sessionID })?.key {
            return key
        }

        // A hook knows about a session before any scan can: it names the
        // transcript and the working directory outright, with none of the
        // guesswork the directory-name scan needs.
        guard let transcript, FileManager.default.fileExists(atPath: transcript.path) else { return nil }

        let cwd = event.cwd ?? transcript.deletingLastPathComponent().path
        let session = ClaudeSession(
            pid: 0,
            workspaceFolders: ["\(cwd)#\(event.sessionID)"],
            ideName: "Terminal",
            transport: nil,
            runningInWindows: nil
        )
        attach(session, transcript: transcript)
        guard watched[session.id] != nil else { return nil }

        hookSessions[session.id] = session
        if !availableSessions.contains(where: { $0.id == session.id }) {
            availableSessions.append(session)
        }
        return session.id
    }

    // MARK: - Git Branch

    private func refreshGitBranch(for sessionKey: String) {
        guard var sessionState = sessionStates[sessionKey], !sessionState.cwd.isEmpty else { return }
        let branch = GitBranchResolver.shared.branch(forWorkingDirectory: sessionState.cwd) ?? ""
        guard branch != sessionState.gitBranch else { return }
        sessionState.gitBranch = branch
        sessionStates[sessionKey] = sessionState
    }

    // MARK: - Permission Detection

    /// Check if a tool should be tracked for permission
    private func isPermissionEligible(_ toolName: String) -> Bool {
        if autoApprovedTools.contains(toolName) {
            return false
        }
        if permissionEligibleTools.contains(toolName) {
            return true
        }
        // MCP tools (external servers) may need permission
        if toolName.hasPrefix("mcp__") {
            return true
        }
        return false
    }

    private func startPermissionCheck(sessionKey: String, toolId: String, toolName: String) {
        guard !loadingHistory.contains(sessionKey), isPermissionEligible(toolName) else { return }

        pendingToolChecks[sessionKey, default: [:]][toolId] = Date()

        guard permissionCheckTimer == nil else { return }
        permissionCheckTimer = Timer.scheduledTimer(withTimeInterval: permissionCheckDelay, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.checkPendingPermissions()
            }
        }
    }

    private func clearPermissionCheck(sessionKey: String, toolId: String, in sessionState: inout ClaudeCodeState) {
        pendingToolChecks[sessionKey]?.removeValue(forKey: toolId)

        if sessionState.needsPermission, pendingToolChecks[sessionKey]?.isEmpty ?? true {
            sessionState.needsPermission = false
            sessionState.pendingPermissionTool = nil
        }
    }

    private func checkPendingPermissions() {
        let now = Date()
        var changed = false

        for (sessionKey, toolChecks) in pendingToolChecks {
            guard var sessionState = sessionStates[sessionKey] else { continue }
            for (toolId, startTime) in toolChecks where now.timeIntervalSince(startTime) >= permissionCheckDelay {
                guard let tool = sessionState.activeTools.first(where: { $0.id == toolId }) else { continue }
                sessionState.needsPermission = true
                sessionState.pendingPermissionTool = tool.toolName
                sessionStates[sessionKey] = sessionState
                changed = true
                break
            }
        }

        if changed {
            objectWillChange.send()
        }
        updateSessionsNeedingPermission()

        if !pendingToolChecks.values.contains(where: { !$0.isEmpty }) {
            permissionCheckTimer?.invalidate()
            permissionCheckTimer = nil
        }
    }

    private func updateSessionsNeedingPermission() {
        sessionsNeedingPermission = availableSessions.filter {
            sessionStates[$0.id]?.needsPermission == true
        }
    }

    // MARK: - Idle Timers

    private func resetIdleTimer() {
        idleCheckTimer?.invalidate()
        idleCheckTimer = Timer.scheduledTimer(withTimeInterval: idleCheckDelay, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.markAllSessionsIdle()
            }
        }
    }

    private func markAllSessionsIdle() {
        objectWillChange.send()
        for (sessionKey, sessionState) in Array(sessionStates) where !sessionState.needsPermission {
            var updated = sessionState
            updated.isThinking = false
            sessionStates[sessionKey] = updated
        }
    }

    /// Reset the tool idle timer - called when any tool activity is detected
    private func resetToolIdleTimer() {
        toolIdleTimer?.invalidate()
        toolIdleTimer = Timer.scheduledTimer(withTimeInterval: toolIdleDelay, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.markSessionsDoneAfterToolIdle()
            }
        }
    }

    /// Called after 10 seconds of no tool activity - mark sessions as done
    private func markSessionsDoneAfterToolIdle() {
        objectWillChange.send()

        for (sessionKey, sessionState) in Array(sessionStates)
            where sessionState.activeTools.isEmpty && !sessionState.needsPermission {
            var updated = sessionState
            updated.isThinking = false
            updated.lastStopReason = "idle_timeout"
            sessionStates[sessionKey] = updated
        }

        pendingToolChecks.removeAll()
        updateSessionsNeedingPermission()
    }

    // MARK: - Daily Stats

    func loadDailyStats() {
        // First root that has a cache wins. The file is per-account, and totals
        // from two accounts are not a total of anything — showing one profile's
        // figures beats inventing a sum nobody's usage page would agree with.
        guard let statsFile = claudeRoots
            .map({ $0.appendingPathComponent("stats-cache.json") })
            .first(where: { FileManager.default.fileExists(atPath: $0.path) }),
            let data = FileManager.default.contents(atPath: statsFile.path) else {
            return
        }

        do {
            let cache = try JSONDecoder().decode(ClaudeStatsCache.self, from: data)
            let today = Self.dateFormatter.string(from: Date())

            var stats = ClaudeDailyStats()

            let sortedActivity = cache.dailyActivity?.sorted { $0.date > $1.date }
            if let todayActivity = sortedActivity?.first(where: { $0.date == today }) {
                stats.date = today
                stats.messageCount = todayActivity.messageCount ?? 0
                stats.toolCallCount = todayActivity.toolCallCount ?? 0
                stats.sessionCount = todayActivity.sessionCount ?? 0
            } else if let latestActivity = sortedActivity?.first {
                stats.date = latestActivity.date
                stats.messageCount = latestActivity.messageCount ?? 0
                stats.toolCallCount = latestActivity.toolCallCount ?? 0
                stats.sessionCount = latestActivity.sessionCount ?? 0
            }

            let sortedTokens = cache.dailyModelTokens?.sorted { $0.date > $1.date }
            let targetDate = stats.date.isEmpty ? today : stats.date
            if let dayTokens = sortedTokens?.first(where: { $0.date == targetDate }),
               let tokensByModel = dayTokens.tokensByModel {
                stats.tokensUsed = tokensByModel.values.reduce(0, +)
            } else if let latestTokens = sortedTokens?.first,
                      let tokensByModel = latestTokens.tokensByModel {
                stats.tokensUsed = tokensByModel.values.reduce(0, +)
                if stats.date.isEmpty {
                    stats.date = latestTokens.date
                }
            }

            if stats != dailyStats {
                dailyStats = stats
            }
        } catch {
            debugLog("[ClaudeCode] Error parsing stats-cache.json: \(error)")
        }
    }
}
