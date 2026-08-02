import SwiftUI

struct MenuBarContentView: View {
    @StateObject private var claudeCodeManager = ClaudeCodeManager.shared
    @State private var isAdvancedExpanded = false

    private var recentTools: [ClaudeToolExecution] {
        claudeCodeManager.state.activeTools + claudeCodeManager.state.recentTools
    }

    private var sessionCount: Int {
        claudeCodeManager.availableSessions.count
    }

    private var recentTokenTotal: Int {
        let usage = claudeCodeManager.state.tokenUsage
        return usage.inputTokens + usage.outputTokens
    }

    var body: some View {
        VStack(spacing: 12) {
            MenuSection {
                HStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(Color.accentColor.opacity(0.15))
                        Image(systemName: "waveform.path.ecg")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.accentColor)
                    }
                    .frame(width: 28, height: 28)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(AppIdentity.displayName)
                            .font(.system(size: 13, weight: .semibold))

                        Text(sessionCount == 0
                            ? "No Claude Code sessions"
                            : "\(sessionCount) session\(sessionCount == 1 ? "" : "s")")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                            .lineLimit(1)

                        // What is actually running, as opposed to what was last
                        // built: `open` reactivates an existing instance, so a
                        // rebuilt bundle can sit on disk while the old process
                        // keeps going. Compare with `--version`.
                        Text(BuildInfo.stamp.short)
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundColor(.secondary.opacity(0.7))
                            .lineLimit(1)
                            .textSelection(.enabled)
                    }

                    Spacer()
                }
            }

            MenuSection(title: "Recent Tool Calls") {
                ClaudeToolListView(tools: recentTools, maxItems: 5)
            }

            MenuSection {
                DisclosureGroup("Advanced", isExpanded: $isAdvancedExpanded) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Session Tokens")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                            Spacer()
                            Text(recentTokenTotal > 0 ? "\(recentTokenTotal)" : "-")
                                .font(.system(size: 11, weight: .medium, design: .monospaced))
                                .foregroundColor(.primary)
                        }
                    }
                    .padding(.top, 6)
                }
                .font(.system(size: 12, weight: .medium))
            }

            MenuSection {
                HStack {
                    Button {
                        openSettings()
                    } label: {
                        Label("Settings…", systemImage: "gearshape")
                            .font(.system(size: 12))
                    }
                    .buttonStyle(.plain)

                    Spacer()
                }
            }

            MenuSection {
                HStack {
                    Spacer()
                    Button {
                        NSApp.terminate(nil)
                    } label: {
                        Label("Quit", systemImage: "power")
                            .font(.system(size: 12))
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.red)
                }
            }
        }
        .padding(12)
        .frame(width: 300)
    }

    private func openSettings() {
        NSApp.sendAction(Selector(("showSettingsWindow")), to: NSApp.delegate, from: nil)
    }
}

private struct MenuSection<Content: View>: View {
    let title: String?
    let content: Content

    init(title: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title {
                Text(title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)
            }

            content
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.primary.opacity(0.08))
        )
    }
}

private struct MenuActionButton: View {
    let systemName: String
    var tint: Color?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 10, weight: .semibold))
        }
        .buttonStyle(.bordered)
        .controlSize(.mini)
        .tint(tint)
    }
}
