import SwiftUI

public struct SettingsView: View {
    @StateObject private var settings = AppSettings.shared

    public init() {}

    public var body: some View {
        GeneralSettingsTab(settings: settings)
            .frame(width: 450, height: 520)
    }
}

struct GeneralSettingsTab: View {
    @ObservedObject var settings: AppSettings

    var body: some View {
        Form {
            Section {
                Stepper(value: $settings.recentToolCallsLimit, in: 5 ... 50, step: 5) {
                    HStack {
                        Text("Recent tool calls to display")
                        Spacer()
                        Text("\(settings.recentToolCallsLimit)")
                            .foregroundColor(.secondary)
                    }
                }

                Toggle("Show menu bar icon", isOn: $settings.showMenuBarItem)
            } header: {
                Text("Display")
            }

            Section {
                Toggle("Show token count in notch", isOn: $settings.showNotchTokenCount)
                Toggle("Show input/output tokens", isOn: $settings.showNotchTokenBreakdown)
            } header: {
                Text("Notch")
            }

            Section {
                Toggle("Battery saver mode", isOn: $settings.batterySaverEnabled)
                Text("15 FPS on battery, 25 FPS when charging")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            } header: {
                Text("Performance")
            }

            Section {
                Toggle("Enable JSONL session tracking", isOn: $settings.enableClaudeCodeJSONL)
                Toggle("Show session dots", isOn: $settings.showSessionDots)
                    .disabled(!settings.enableClaudeCodeJSONL)
                Toggle("Show permission indicator", isOn: $settings.showPermissionIndicator)
                    .disabled(!settings.enableClaudeCodeJSONL)
                Toggle("Show todo list", isOn: $settings.showTodoList)
                    .disabled(!settings.enableClaudeCodeJSONL)
                Toggle("Show thinking state", isOn: $settings.showThinkingState)
                    .disabled(!settings.enableClaudeCodeJSONL)

                Text("Reads from ~/.claude to track sessions")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            } header: {
                Text("Claude Code")
            }

            HookBridgeSection(settings: settings)

            Section {
                Toggle("Show context progress bar", isOn: $settings.showContextProgress)

                Stepper(value: $settings.contextTokenLimitOverride, in: 0 ... 1_000_000, step: 50000) {
                    HStack {
                        Text("Context limit")
                        Spacer()
                        Text(settings.contextTokenLimitOverride == 0
                            ? "Auto"
                            : "\(settings.contextTokenLimitOverride / 1000)k")
                            .foregroundColor(.secondary)
                    }
                }

                Text("Auto reads the window from the model Claude Code reports. Set a value only to override it.")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)

                Divider()

                Picker("Tool display mode", selection: $settings.toolDisplayMode) {
                    Text("Nothing").tag("off")
                    Text("Single detailed event").tag("singular")
                    Text("Recent events list").tag("list")
                }
                .pickerStyle(.segmented)
            } header: {
                Text("Context")
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

/// Registration of the hook relay in the user's Claude Code settings.
///
/// Kept a deliberate two-step: the toggle only decides whether the app listens,
/// while writing to `~/.claude/settings.json` takes a button press and a
/// confirmation naming the file. Editing another tool's configuration is not
/// something an app should do as a side effect of being launched.
struct HookBridgeSection: View {
    @ObservedObject var settings: AppSettings

    @State private var isInstalled = HookInstaller.isInstalled
    @State private var confirmingInstall = false
    @State private var confirmingUninstall = false
    @State private var failure: String?

    var body: some View {
        Section {
            Toggle("Listen for hook events", isOn: $settings.enableHookBridge)
                .onChange(of: settings.enableHookBridge) { _, _ in
                    ClaudeCodeManager.shared.updateHookBridge()
                }

            HStack {
                Text(isInstalled ? "Hooks are registered" : "Hooks are not registered")
                    .foregroundColor(isInstalled ? .green : .secondary)
                Spacer()
                if isInstalled {
                    Button("Remove…") { confirmingUninstall = true }
                } else {
                    Button("Register…") { confirmingInstall = true }
                }
            }

            Text("""
            Hooks report tool activity as it happens instead of inferring it from \
            transcripts. Registering adds \(HookInstaller.subscribedEvents.count) entries \
            to ~/.claude/settings.json; the previous file is copied alongside it first, \
            and Remove takes them out again.
            """)
            .font(.system(size: 11))
            .foregroundColor(.secondary)
        } header: {
            Text("Claude Code Hooks")
        }
        .onAppear { isInstalled = HookInstaller.isInstalled }
        .confirmationDialog(
            "Add hook entries to ~/.claude/settings.json?",
            isPresented: $confirmingInstall,
            titleVisibility: .visible
        ) {
            Button("Register Hooks") { perform(HookInstaller.install) }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog(
            "Remove hook entries from ~/.claude/settings.json?",
            isPresented: $confirmingUninstall,
            titleVisibility: .visible
        ) {
            Button("Remove Hooks", role: .destructive) { perform(HookInstaller.uninstall) }
            Button("Cancel", role: .cancel) {}
        }
        .alert("Could not update Claude Code settings", isPresented: .constant(failure != nil)) {
            Button("OK") { failure = nil }
        } message: {
            Text(failure ?? "")
        }
    }

    private func perform(_ action: () throws -> Void) {
        do {
            try action()
            isInstalled = HookInstaller.isInstalled
            // Listening without registration is pointless, and registration
            // without listening is worse: the hooks would run for nothing.
            settings.enableHookBridge = isInstalled
            ClaudeCodeManager.shared.updateHookBridge()
        } catch {
            failure = error.localizedDescription
        }
    }
}
