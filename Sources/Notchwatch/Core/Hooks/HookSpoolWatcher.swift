//
//  HookSpoolWatcher.swift
//  Notchwatch
//
//  Drains the hook spool into the app.
//

import Foundation

/// Watches the spool directory and hands each event to the app, then deletes it.
@MainActor
final class HookSpoolWatcher {
    static let shared = HookSpoolWatcher()

    /// Directory notifications coalesce, and a file created while we were already
    /// draining can leave no notification of its own. A slow poll bounds how long
    /// such an event can sit unread.
    private static let pollInterval: TimeInterval = 2.0

    private var source: DispatchSourceFileSystemObject?
    private var pollTimer: Timer?
    private var handler: ((HookEvent) -> Void)?

    private(set) var isRunning = false

    func start(handler: @escaping (HookEvent) -> Void) {
        stop()
        self.handler = handler

        guard (try? HookSpool.createDirectory()) != nil else {
            debugLog("[Hooks] Cannot create spool at \(HookSpool.directory.path)")
            return
        }

        discardStaleEvents()

        let descriptor = open(HookSpool.directory.path, O_EVTONLY)
        guard descriptor >= 0 else {
            debugLog("[Hooks] Cannot watch spool at \(HookSpool.directory.path)")
            return
        }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .extend],
            queue: .main
        )
        source.setEventHandler { [weak self] in
            self?.drain()
        }
        source.setCancelHandler {
            close(descriptor)
        }
        source.resume()
        self.source = source

        pollTimer = Timer.scheduledTimer(withTimeInterval: Self.pollInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.drain() }
        }

        isRunning = true
        debugLog("[Hooks] Watching spool at \(HookSpool.directory.path)")
        drain()
    }

    func stop() {
        source?.cancel()
        source = nil
        pollTimer?.invalidate()
        pollTimer = nil
        handler = nil
        isRunning = false
    }

    // MARK: - Draining

    private func drain() {
        guard let handler else { return }
        let fileManager = FileManager.default

        guard let files = try? fileManager.contentsOfDirectory(
            at: HookSpool.directory,
            includingPropertiesForKeys: nil
        ) else { return }

        // Names are timestamp-prefixed, so lexical order is arrival order.
        for file in files.filter({ $0.pathExtension == "json" }).sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            let data = fileManager.contents(atPath: file.path)
            // Removed before dispatch: an event that cannot be decoded is still
            // consumed, so one malformed payload cannot wedge the spool.
            try? fileManager.removeItem(at: file)

            guard let data, let event = HookEvent(data: data) else {
                debugLog("[Hooks] Discarded unreadable event \(file.lastPathComponent)")
                continue
            }
            handler(event)
        }
    }

    /// Events written while the app was not running describe sessions that have
    /// moved on; replaying them would show tools that finished long ago.
    private func discardStaleEvents() {
        let fileManager = FileManager.default
        guard let files = try? fileManager.contentsOfDirectory(
            at: HookSpool.directory,
            includingPropertiesForKeys: [.contentModificationDateKey]
        ) else { return }

        let cutoff = Date().addingTimeInterval(-HookSpool.maxEventAge)
        for file in files {
            let modified = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
            if (modified ?? .distantPast) < cutoff {
                try? fileManager.removeItem(at: file)
            }
        }
    }
}
