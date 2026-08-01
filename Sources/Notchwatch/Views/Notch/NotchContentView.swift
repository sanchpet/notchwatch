import SwiftUI

struct NotchContentView: View {
    @StateObject private var notchVM = NotchViewModel()
    @StateObject private var settings = AppSettings.shared
    @StateObject private var claudeCodeManager = ClaudeCodeManager.shared
    @State private var isHovering = false
    @State private var hoverTask: Task<Void, Never>?
    @State private var sessionStart = Date()
    @State private var showStartupGlow = false
    @State private var startupGlowTask: Task<Void, Never>?
    /// What the peek is currently saying. One value rather than a pair of
    /// booleans with a fallback: the fallback was reachable — clearing a flag
    /// because the underlying condition ended, while the peek it belongs to was
    /// still on screen, swapped the notice for a stray token count mid-display.
    /// A notice now lives exactly as long as the peek that carries it.
    private enum PeekNotice: Equatable {
        case permission
        case turnDone
    }

    @State private var peekNotice: PeekNotice?
    @State private var permissionToolName: String?
    @State private var panelControlObserver: NSObjectProtocol?
    @State private var turnDoneProject: String?
    @State private var turnDoneSummary: String?

    private let animationSpring = Animation.interactiveSpring(response: 0.38, dampingFraction: 0.8, blendDuration: 0)
    private let startupGlowColor = Color(red: 0.55, green: 0.8, blue: 0.9)
    private let startupBrightColor = Color(red: 0.75, green: 0.9, blue: 1.0)
    private let activityGlowColor = Color(red: 0.9, green: 0.4, blue: 0.1)
    private let activityBrightColor = Color(red: 1.0, green: 0.55, blue: 0.2)
    // Green rather than another shade of the activity orange: "your move" is a
    // different kind of event from "busy", and a hue apart is legible from the
    // corner of an eye where a brightness apart is not.
    private let awaitingGlowColor = Color(red: 0.2, green: 0.75, blue: 0.45)
    private let awaitingBrightColor = Color(red: 0.4, green: 0.95, blue: 0.6)

    private var isExpanded: Bool {
        notchVM.notchState == .open || notchVM.notchState == .peeking
    }

    /// Uncached input plus output of the last request — not a session total, and
    /// not context occupancy (see `ClaudeTokenUsage.promptTokens` for that).
    private var recentTokenTotal: Int {
        let usage = claudeCodeManager.state.tokenUsage
        return usage.inputTokens + usage.outputTokens
    }

    private var topCornerRadius: CGFloat {
        isExpanded ? cornerRadiusInsets.opened.top : cornerRadiusInsets.closed.top
    }

    private var bottomCornerRadius: CGFloat {
        isExpanded ? cornerRadiusInsets.opened.bottom : cornerRadiusInsets.closed.bottom
    }

    var body: some View {
        VStack(spacing: 0) {
            notchBody
                // Closed, the shape is exactly the cut-out and gets no padding:
                // a padded shape is a wider shape, and every point of it lands
                // on the menu bar. Expanded, the panel is invited on screen and
                // may use its corner insets.
                .padding(.horizontal, isExpanded ? cornerRadiusInsets.opened.top : 0)
                .padding([.horizontal, .bottom], isExpanded ? 12 : 0)
                .background(Color.black)
                .mask(
                    NotchShape(
                        topCornerRadius: topCornerRadius,
                        bottomCornerRadius: bottomCornerRadius
                    )
                )
                .contentShape(
                    NotchShape(
                        topCornerRadius: topCornerRadius,
                        bottomCornerRadius: bottomCornerRadius
                    )
                )
                .onHover { hovering in
                    handleHover(hovering)
                }
                .onTapGesture {
                    notchVM.toggle()
                }
                .overlay {
                    if showStartupGlow, notchVM.notchState == .closed {
                        NotchGlowBorder(
                            topCornerRadius: topCornerRadius,
                            bottomCornerRadius: bottomCornerRadius,
                            glowColor: startupGlowColor,
                            brightColor: startupBrightColor
                        )
                    } else if !claudeCodeManager.sessionsAwaitingUser.isEmpty, notchVM.notchState == .closed {
                        // Ahead of the activity glow, not behind it. Busy is the
                        // background state — with several sessions open one of
                        // them almost always is — so ranking it first meant the
                        // orange permanently masked the one signal the user has
                        // to see. Needing the user is the exception, and the
                        // exception wins.
                        //
                        // Persistent rather than a flash: a signal that has to
                        // be caught in the second it fires is a signal that gets
                        // missed. It clears when the session picks work back up.
                        NotchGlowBorder(
                            topCornerRadius: topCornerRadius,
                            bottomCornerRadius: bottomCornerRadius,
                            glowColor: awaitingGlowColor,
                            brightColor: awaitingBrightColor,
                            lineWidth: 7,
                            glowStrength: 2.2,
                            isSteady: true
                        )
                    } else if claudeCodeManager.hasAnySessionActivity, notchVM.notchState == .closed {
                        NotchGlowBorder(
                            topCornerRadius: topCornerRadius,
                            bottomCornerRadius: bottomCornerRadius,
                            glowColor: activityGlowColor,
                            brightColor: activityBrightColor
                        )
                    }
                }
                .onChange(of: claudeCodeManager.sessionsAwaitingUser.count) { oldCount, newCount in
                    // Only on the way up. Sessions finishing one after another
                    // each deserve a notice; the count falling is a session
                    // resuming, which is not news — and must not disturb a
                    // notice already being shown.
                    if newCount > oldCount {
                        triggerTurnDoneNotice()
                    }
                }
                .onChange(of: notchVM.notchState) { _, newState in
                    // The notice belongs to the peek. When the peek is over —
                    // by timeout or because the user opened the panel — it goes.
                    if newState != .peeking {
                        peekNotice = nil
                    }
                }
                .onChange(of: claudeCodeManager.sessionsNeedingPermission.count) { oldCount, newCount in
                    if newCount > oldCount {
                        triggerPermissionNotice()
                    }
                }
                .shadow(
                    color: (isExpanded || isHovering) ? .black.opacity(0.6) : .clear,
                    radius: 8
                )
                .animation(animationSpring, value: notchVM.notchState)
                .animation(animationSpring, value: notchVM.notchSize)

            // Closed-state readout hangs below the menu bar, where the pixels
            // are the app's own, instead of beside the cut-out where they are
            // the system's.
            if notchVM.notchState == .closed {
                closedTray
                    .animation(animationSpring, value: notchVM.notchState)
            }
        }
        .padding(.bottom, isExpanded ? 8 : closedNotchGlowPadding)
        .frame(maxWidth: notchVM.windowSize.width, maxHeight: notchVM.windowSize.height, alignment: .top)
        .compositingGroup()
        .preferredColorScheme(.dark)
        .onAppear {
            triggerStartupGlow()
            panelControlObserver = PanelControl.observe { command in
                switch command {
                case .open: notchVM.open()
                case .close: notchVM.close()
                case .toggle: notchVM.toggle()
                case .peek: notchVM.peek(duration: settings.noticeDurationSeconds)
                }
            }
        }
        .onDisappear {
            startupGlowTask?.cancel()
            if let panelControlObserver {
                DistributedNotificationCenter.default().removeObserver(panelControlObserver)
            }
        }
    }

    private var notchBody: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header - always visible.
            //
            // Constrained to the cut-out's height only while closed, where the
            // header is an empty spacer holding the silhouette. Expanded it
            // draws a title, a session count and two buttons, none of which fit
            // in the height of a camera housing — so the frame was clipping its
            // own content and the first row below it.
            notchHeader
                .frame(height: notchVM.notchState == .closed ? notchVM.closedNotchSize.height : nil)
                .padding(.bottom, notchVM.notchState == .closed ? 0 : 8)

            // Expanded content
            if notchVM.notchState == .open {
                expandedContent
                    .frame(height: notchVM.notchSize.height - notchVM.closedNotchSize.height)
                    .transition(.opacity.combined(with: .scale(scale: 0.95, anchor: .top)))
            } else if notchVM.notchState == .peeking {
                peekContent
                    .frame(height: notchVM.notchSize.height - notchVM.closedNotchSize.height)
                    .transition(.opacity.combined(with: .scale(scale: 0.95, anchor: .top)))
            }
        }
    }

    @ViewBuilder
    private var notchHeader: some View {
        if notchVM.notchState == .closed {
            closedHeader
        } else if notchVM.notchState == .peeking {
            peekHeader
        } else {
            openHeader
        }
    }

    /// Closed, the shape is the cut-out and nothing else, so there is nothing to
    /// draw into it — it exists to give the panel a silhouette to grow out of and
    /// the activity glow an edge to trace.
    private var closedHeader: some View {
        Spacer()
            .frame(width: notchVM.closedNotchSize.width)
    }

    /// The closed-state readout: one row hanging just below the cut-out.
    ///
    /// This used to be two "wings" flanking the cut-out with hard-coded widths,
    /// which put black over the menu bar — over the frontmost app's menus on the
    /// left and over the status items on the right, the further the longer the
    /// tool name got. The menu bar is not the app's to draw on and macOS will not
    /// say how much of it is already spoken for, so the readout moved below it,
    /// where the only limit is how much room the panel has.
    @ViewBuilder
    private var closedTray: some View {
        // The manager's state already folds every session together, so there is
        // no per-session fallback left to write here.
        let claudeActiveTool = claudeCodeManager.state.activeTools.first
        // Recent completed Claude tool (within last 5 seconds)
        let recentClaudeTool: ClaudeToolExecution? = {
            if let recent = claudeCodeManager.state.recentTools.first,
               let endTime = recent.endTime,
               Date().timeIntervalSince(endTime) < 5.0 {
                return recent
            }
            return nil
        }()
        let isClaudeActive = claudeCodeManager.hasAnySessionActivity
        let isSessionIdle = claudeCodeManager.state.isSessionComplete && !isClaudeActive

        // Check if we have sessions (for context indicator)
        let hasSessions = settings.showSessionDots
            && settings.enableClaudeCodeJSONL
            && !claudeCodeManager.availableSessions.isEmpty
        let hasActiveSessionDots = hasSessions
            && claudeCodeManager.sessionStates.values.contains { $0.isActive || $0.needsPermission }
        let hasPermissionNeeded = settings.showPermissionIndicator && !claudeCodeManager.sessionsNeedingPermission.isEmpty

        // Determine what tool to show (prefer active, then recent)
        let currentClaudeTool: ClaudeToolExecution? = claudeActiveTool ?? recentClaudeTool
        let isThinking = isClaudeActive && currentClaudeTool == nil
        let hasCurrentTool = currentClaudeTool != nil

        if hasCurrentTool || isThinking || isSessionIdle || hasSessions || hasPermissionNeeded {
            HStack(spacing: 6) {
                if hasCurrentTool || isThinking {
                    Circle()
                        .fill(activityGlowColor)
                        .frame(width: 8, height: 8)
                        .shadow(color: activityGlowColor.opacity(isClaudeActive ? 0.6 : 0.3), radius: isClaudeActive ? 3 : 1)

                    if let toolName = currentClaudeTool?.toolName {
                        Text(toolName)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.white.opacity(0.85))
                            .lineLimit(1)
                            .truncationMode(.tail)
                    } else {
                        Text("Thinking...")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.white.opacity(0.7))
                            .lineLimit(1)
                    }
                } else if isSessionIdle {
                    // Session complete indicator
                    Circle()
                        .fill(Color.green)
                        .frame(width: 8, height: 8)
                        .shadow(color: Color.green.opacity(0.5), radius: 2)
                    Text("Done")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.green.opacity(0.9))
                } else if hasSessions {
                    // Idle with sessions around - session count for context
                    let sessionCount = claudeCodeManager.availableSessions.count
                    Circle()
                        .fill(hasActiveSessionDots ? activityGlowColor : Color.gray)
                        .frame(width: 6, height: 6)
                        .opacity(hasActiveSessionDots ? 1.0 : 0.5)
                    Text("\(sessionCount) session\(sessionCount == 1 ? "" : "s")")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(hasActiveSessionDots ? .white.opacity(0.8) : .gray)
                        .lineLimit(1)
                }

                if let claudeTool = currentClaudeTool {
                    if claudeTool.isRunning {
                        ProgressView()
                            .scaleEffect(0.3)
                            .frame(width: 8, height: 8)
                        if let desc = claudeTool.description {
                            Text(desc)
                                .font(.system(size: 9))
                                .foregroundColor(.white.opacity(0.5))
                                .lineLimit(1)
                                .truncationMode(.tail)
                        }
                    } else {
                        if let input = claudeTool.inputTokens, input > 0 {
                            trayTokenCount(input, systemName: "arrow.up", tint: .green)
                        }
                        if let output = claudeTool.outputTokens, output > 0 {
                            trayTokenCount(output, systemName: "arrow.down", tint: .blue)
                        }
                        Text(claudeTool.formattedDuration)
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundColor(.white.opacity(0.6))
                    }
                } else if isThinking, let modelName = extractModelName(claudeCodeManager.state.model) {
                    ProgressView()
                        .scaleEffect(0.3)
                        .frame(width: 8, height: 8)
                    Text(modelName)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(.white.opacity(0.5))
                } else if hasPermissionNeeded {
                    PermissionNeededIndicatorCompact()
                    Text("Needs OK")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(.orange)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            // `maxWidth` alone is a budget, not a limit: a flexible frame takes
            // the whole width it is offered, so the capsule painted 532 pt of
            // black across whatever window sat beneath it to say "1 session".
            // Fixing the horizontal axis proposes the content's ideal width to
            // the frame instead, which the frame still clamps to the budget — so
            // a long tool name truncates at the cap rather than escaping it.
            .frame(maxWidth: notchVM.geometry.maxTrayWidth)
            .fixedSize(horizontal: true, vertical: true)
            .background(Color.black, in: Capsule())
            // The waiting signal lands here as much as on the cut-out. The
            // cut-out has almost no visible perimeter — its top is behind the
            // camera housing and the mask trims the rest — so an outline there
            // shows as two lit corners however heavy it is drawn. The tray is
            // wide, fully on screen, and already where the eye goes.
            .overlay {
                if !claudeCodeManager.sessionsAwaitingUser.isEmpty {
                    Capsule()
                        .stroke(awaitingBrightColor, lineWidth: 2)
                        .shadow(color: awaitingGlowColor.opacity(0.9), radius: 6)
                        .shadow(color: awaitingGlowColor.opacity(0.6), radius: 14)
                        .shadow(color: awaitingGlowColor.opacity(0.3), radius: 24)
                }
            }
            .padding(.top, 4)
            .onHover { hovering in
                // The tray vanishes into the panel it opens, so its own
                // hover-exit must not be read as "the pointer left the panel" —
                // by then the panel is sitting under the pointer.
                if hovering {
                    handleHover(true)
                } else {
                    cancelHoverOpen()
                }
            }
            .onTapGesture {
                notchVM.toggle()
            }
            .transition(.opacity.combined(with: .move(edge: .top)))
        }
    }

    private func trayTokenCount(_ count: Int, systemName: String, tint: Color) -> some View {
        HStack(spacing: 1) {
            Image(systemName: systemName)
                .font(.system(size: 6, weight: .bold))
                .foregroundColor(tint.opacity(0.8))
            Text(formatTokenCount(count))
                .font(.system(size: 9, design: .monospaced))
                .foregroundColor(.white.opacity(0.7))
        }
    }

    private func formatTokenCount(_ count: Int) -> String {
        if count >= 1000 {
            return String(format: "%.1fk", Double(count) / 1000.0)
        }
        return "\(count)"
    }

    /// Extract model name from full model ID (e.g., "opus" from "claude-opus-4-5-20251101")
    private func extractModelName(_ modelId: String) -> String? {
        let parts = modelId.lowercased().split(separator: "-")
        // Look for known model names
        if parts.contains("opus") {
            return "Opus"
        }
        if parts.contains("sonnet") {
            return "Sonnet"
        }
        if parts.contains("haiku") {
            return "Haiku"
        }
        // Fallback: return second part if available (usually the model name)
        if parts.count > 1 {
            return String(parts[1]).capitalized
        }
        return nil
    }

    private var openHeader: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(AppIdentity.displayName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white)

                Text(claudeCodeManager.availableSessions.isEmpty
                    ? "No Claude Code sessions"
                    : "\(claudeCodeManager.availableSessions.count) session\(claudeCodeManager.availableSessions.count == 1 ? "" : "s")")
                    .font(.system(size: 10))
                    .foregroundColor(.white.opacity(0.6))
                    .lineLimit(1)
            }

            Spacer()

            HStack(spacing: 6) {
                NotchControlButton(systemName: "gearshape") {
                    openSettings()
                }

                NotchControlButton(systemName: "power", tint: .red) {
                    NSApp.terminate(nil)
                }
            }
            .padding(4)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(
                Capsule()
                    .stroke(Color.white.opacity(0.12))
            )
        }
        .padding(.horizontal, 16)
    }

    private var expandedContent: some View {
        VStack(spacing: 6) {
            // The rows above the footer vary with the session count, the display
            // mode and whether a workflow is running, while the panel's height
            // does not: a fixed frame met by taller content clips it, and what
            // it clipped was the top row, under the header. Scrolling is the
            // honest resolution — the footer stays pinned because it is the part
            // that must never move.
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 6) {
                    scrollingContent
                }
            }

            Spacer(minLength: 0)

            // Permission badge above footer
            if settings.showPermissionIndicator, !claudeCodeManager.sessionsNeedingPermission.isEmpty {
                PermissionNeededBadge(toolName: claudeCodeManager.state.pendingPermissionTool)
                    .onTapGesture {
                        claudeCodeManager.focusIDE()
                    }
            }

            footerBlock
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 12)
    }

    @ViewBuilder
    private var scrollingContent: some View {
        if settings.showTodoList, !claudeCodeManager.state.todos.isEmpty {
            NotchSection(title: "Current Tasks") {
                TodoListView(todos: claudeCodeManager.state.todos, maxItems: 4)
            }
        }

        let claudeTools = claudeCodeManager.state.activeTools + claudeCodeManager.state.recentTools

        // Always first, whatever the tool-display mode: it is the only line
        // that answers "is it alive" rather than "what has it done".
        CurrentActivityView(
            activeTool: claudeCodeManager.state.activeTools.first,
            lastTool: claudeCodeManager.state.recentTools.first,
            isThinking: claudeCodeManager.state.isThinking,
            model: extractModelName(claudeCodeManager.state.model) ?? "",
            settings: settings,
            powerMonitor: PowerStateMonitor.shared
        )

        // A fan-out of subagents is the one case where the session looks
        // idle for an hour while a great deal happens. Its own journal is
        // the only place that says how far along it is.
        if let workflow = claudeCodeManager.workflowProgress {
            WorkflowProgressRow(progress: workflow)
        }

        // One row per session, so that "which session is this?" has an answer,
        // and above the tool blocks rather than below them: with several
        // sessions running this is what the panel is opened for, and burying it
        // under a variable-height block meant scrolling to reach it. Only worth
        // the room when there is something to tell apart — with a single session
        // the footer and the bar already describe it.
        if claudeCodeManager.availableSessions.count > 1 {
            NotchSection(title: "Sessions") {
                SessionListView(manager: claudeCodeManager, settings: settings)
            }
        }

        if settings.toolDisplayMode == "singular" {
            // Singular mode: show one detailed event
            if let currentTool = claudeTools.first {
                NotchSection(title: currentTool.isRunning ? "Active Tool" : "Last Tool") {
                    SingularToolDetailView(tool: currentTool, tokenUsage: claudeCodeManager.state.tokenUsage)
                }
            }
        } else if settings.toolDisplayMode == "list" {
            // List mode: show recent events list
            NotchSection(title: "Recent Tools") {
                ClaudeToolListView(tools: claudeTools, maxItems: 4)
            }
        }
    }

    /// Context bar and footer: the readouts pinned below the scrolling rows.
    ///
    /// Both describe the *focused* session, which is only unambiguous while
    /// there is one. With several live, the Sessions list carries branch and
    /// context per row, so repeating either here would be a reading whose
    /// subject the panel never names — and the tokens become a sum across
    /// sessions, which is a figure that means the same thing however many there
    /// are.
    @ViewBuilder
    private var footerBlock: some View {
        let single = claudeCodeManager.availableSessions.count <= 1

        if settings.showContextProgress, single {
            ContextProgressBar(
                tokenUsage: claudeCodeManager.state.tokenUsage,
                contextLimit: settings.effectiveContextLimit(for: claudeCodeManager.state)
            )
        }

        let tokens = single
            ? claudeCodeManager.state.tokenUsage
            : claudeCodeManager.sessionStates.values.reduce(into: ClaudeTokenUsage()) { sum, state in
                sum.inputTokens += state.tokenUsage.inputTokens
                sum.outputTokens += state.tokenUsage.outputTokens
                sum.cacheReadInputTokens += state.tokenUsage.cacheReadInputTokens
                sum.cacheCreationInputTokens += state.tokenUsage.cacheCreationInputTokens
            }

        NotchFooterView(
            // Time since the focused session last did anything, not the panel's
            // own age: the clock used to start when the view appeared, so it
            // measured how long Notchwatch had been open while sitting beside a
            // branch badge that made it read as the session's.
            sessionDuration: claudeCodeManager.state.lastUpdateTime.map { Date().timeIntervalSince($0) } ?? 0,
            tokenTotal: tokens.inputTokens + tokens.outputTokens,
            cacheReadTokens: tokens.cacheReadInputTokens,
            cacheWriteTokens: tokens.cacheCreationInputTokens,
            showTokenCount: settings.showNotchTokenCount,
            gitBranch: single ? claudeCodeManager.state.gitBranch : nil
        )
    }

    private var turnDoneContent: some View {
        TurnDoneNotice(project: turnDoneProject, summary: turnDoneSummary)
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .onTapGesture {
                notchVM.open()
            }
    }

    private var peekHeader: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(activityGlowColor)
                .frame(width: 8, height: 8)
            Text("Claude Code")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.white)

            Spacer()
        }
        .padding(.horizontal, 16)
    }

    @ViewBuilder
    private var peekContent: some View {
        switch peekNotice {
        case .permission:
            permissionContent
        case .turnDone:
            turnDoneContent
        case nil:
            // A peek is only ever raised to carry a notice, so there is nothing
            // to fall back to. What used to be here — a token count — was never
            // requested by anything and only appeared when a notice was cleared
            // out from under its own peek.
            EmptyView()
        }
    }

    private var permissionContent: some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                // Pulsing orange indicator
                Circle()
                    .fill(Color.orange)
                    .frame(width: 12, height: 12)
                    .shadow(color: .orange.opacity(0.6), radius: 4)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Permission Required")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white)

                    if let toolName = permissionToolName {
                        Text("Claude wants to run: \(toolName)")
                            .font(.system(size: 11))
                            .foregroundColor(.white.opacity(0.7))
                    }
                }

                Spacer()

                // Named after the host the session actually reports. It used to
                // read "Check Terminal" unconditionally while the tap activated
                // whatever the editor lock claimed — so a session running in a
                // terminal sent you to VS Code, which is worse than no button.
                if let host = claudeCodeManager.sessionsNeedingPermission.first?.ideName,
                   host != ClaudeSession.unknownHost {
                    Text("Open \(host)")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.orange)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.orange.opacity(0.2), in: Capsule())
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .onTapGesture {
            claudeCodeManager.focusIDE()
        }
    }

    private struct NotchSection<Content: View>: View {
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
                        .foregroundColor(.white.opacity(0.55))
                }

                content
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color.white.opacity(0.08))
            )
        }
    }

    private struct NotchControlButton: View {
        let systemName: String
        var tint: Color?
        let action: () -> Void

        var body: some View {
            Button(action: action) {
                Image(systemName: systemName)
                    .font(.system(size: 10, weight: .semibold))
            }
            .buttonStyle(.plain)
            .foregroundColor(tint ?? .white.opacity(0.75))
            .padding(6)
            .background(
                Circle()
                    .fill(Color.white.opacity(0.08))
            )
        }
    }

    private struct NotchPill: View {
        let text: String
        var mono: Bool = false

        var body: some View {
            Text(text)
                .font(.system(size: 9, weight: .medium, design: mono ? .monospaced : .default))
                .foregroundColor(.white.opacity(0.7))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.white.opacity(0.08), in: Capsule())
        }
    }

    private struct NotchFooterView: View {
        let sessionDuration: TimeInterval
        let tokenTotal: Int
        let cacheReadTokens: Int
        let cacheWriteTokens: Int
        let showTokenCount: Bool
        let gitBranch: String?

        var body: some View {
            TimelineView(.periodic(from: .now, by: 5)) { _ in
                HStack(spacing: 8) {
                    Image(systemName: "clock")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.white.opacity(0.6))

                    Text(formatDuration(sessionDuration))
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundColor(.white.opacity(0.8))

                    // Git branch badge
                    if let branch = gitBranch, !branch.isEmpty {
                        HStack(spacing: 3) {
                            Image(systemName: "arrow.triangle.branch")
                                .font(.system(size: 8, weight: .semibold))
                                .foregroundColor(.purple.opacity(0.8))
                            Text(branch)
                                .font(.system(size: 9, weight: .medium))
                                .foregroundColor(.purple.opacity(0.9))
                                .lineLimit(1)
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.purple.opacity(0.15), in: Capsule())
                    }

                    Spacer()

                    if showTokenCount {
                        // Regular tokens (input + output)
                        Image(systemName: "sparkles")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(.white.opacity(0.6))

                        Text(tokenTotal > 0 ? formatTokens(tokenTotal) : "-")
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundColor(.white.opacity(0.8))

                        // Cache read tokens (green - savings)
                        if cacheReadTokens > 0 {
                            HStack(spacing: 2) {
                                Image(systemName: "arrow.down.circle")
                                    .font(.system(size: 8, weight: .semibold))
                                    .foregroundColor(.green.opacity(0.8))
                                Text(formatTokens(cacheReadTokens))
                                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                                    .foregroundColor(.green.opacity(0.9))
                            }
                        }

                        // Cache write tokens (yellow - creation)
                        if cacheWriteTokens > 0 {
                            HStack(spacing: 2) {
                                Image(systemName: "arrow.up.circle")
                                    .font(.system(size: 8, weight: .semibold))
                                    .foregroundColor(.yellow.opacity(0.8))
                                Text(formatTokens(cacheWriteTokens))
                                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                                    .foregroundColor(.yellow.opacity(0.9))
                            }
                        }
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.white.opacity(0.06), in: Capsule())
            }
        }

        private func formatDuration(_ duration: TimeInterval) -> String {
            let totalSeconds = Int(duration)
            if totalSeconds < 60 {
                return "\(totalSeconds)s"
            } else if totalSeconds < 3600 {
                let minutes = totalSeconds / 60
                let seconds = totalSeconds % 60
                return String(format: "%dm %02ds", minutes, seconds)
            } else {
                let hours = totalSeconds / 3600
                let minutes = (totalSeconds % 3600) / 60
                return String(format: "%dh %02dm", hours, minutes)
            }
        }
    }

    // MARK: - Context Progress Bar

    private struct ContextProgressBar: View {
        let tokenUsage: ClaudeTokenUsage
        let contextLimit: Int

        private var progress: Double {
            tokenUsage.contextFraction(window: contextLimit)
        }

        private var progressColor: Color {
            if progress > 0.9 {
                return .red
            }
            if progress > 0.7 {
                return .orange
            }
            if progress > 0.5 {
                return .yellow
            }
            return .green
        }

        var body: some View {
            VStack(spacing: 4) {
                HStack {
                    Text("Context")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(.white.opacity(0.6))

                    Text("\(formatTokens(tokenUsage.promptTokens)) / \(formatTokens(contextLimit))")
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundColor(.white.opacity(0.7))

                    Spacer()
                }

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        // Background
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color.white.opacity(0.1))

                        // Progress fill
                        RoundedRectangle(cornerRadius: 3)
                            .fill(progressColor.opacity(0.8))
                            .frame(width: geo.size.width * progress)
                    }
                }
                .frame(height: 6)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
        }

        private func formatTokens(_ count: Int) -> String {
            // Both operands can now reach seven digits, where "1000.0k" is unreadable.
            if count >= 1_000_000 {
                return String(format: "%.1fM", Double(count) / 1_000_000.0)
            }
            if count >= 1000 {
                return String(format: "%.1fk", Double(count) / 1000.0)
            }
            return "\(count)"
        }
    }

    // MARK: - Singular Tool Detail View (for Claude Code tools)

    private struct SingularToolDetailView: View {
        let tool: ClaudeToolExecution
        let tokenUsage: ClaudeTokenUsage

        private let claudeColor = Color(red: 1.0, green: 0.55, blue: 0.2)

        var body: some View {
            VStack(alignment: .leading, spacing: 8) {
                // Tool name and status
                HStack(spacing: 8) {
                    Circle()
                        .fill(claudeColor)
                        .frame(width: 10, height: 10)
                        .shadow(color: claudeColor.opacity(tool.isRunning ? 0.6 : 0.3), radius: tool.isRunning ? 4 : 2)

                    Text(tool.toolName)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.primary)

                    Spacer()

                    if tool.isRunning {
                        ProgressView()
                            .scaleEffect(0.5)
                            .frame(width: 16, height: 16)
                    } else {
                        Text(tool.formattedDuration)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                }

                // Description
                if let desc = tool.description, !desc.isEmpty {
                    Text(desc)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }

                // Argument/filename
                if let arg = tool.argument, !arg.isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: "doc.text")
                            .font(.system(size: 9))
                            .foregroundColor(.secondary)
                        Text(arg)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(.secondary.opacity(0.8))
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }

                Divider()
                    .background(Color.white.opacity(0.1))

                // Token details
                HStack(spacing: 12) {
                    // Input tokens
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Input")
                            .font(.system(size: 8, weight: .medium))
                            .foregroundColor(.secondary)
                        HStack(spacing: 2) {
                            Image(systemName: "arrow.up")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundColor(.green.opacity(0.8))
                            Text(formatTokens(tool.inputTokens ?? tokenUsage.inputTokens))
                                .font(.system(size: 11, weight: .medium, design: .monospaced))
                                .foregroundColor(.primary)
                        }
                    }

                    // Output tokens
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Output")
                            .font(.system(size: 8, weight: .medium))
                            .foregroundColor(.secondary)
                        HStack(spacing: 2) {
                            Image(systemName: "arrow.down")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundColor(.blue.opacity(0.8))
                            Text(formatTokens(tool.outputTokens ?? tokenUsage.outputTokens))
                                .font(.system(size: 11, weight: .medium, design: .monospaced))
                                .foregroundColor(.primary)
                        }
                    }

                    // Cache read
                    if (tool.cacheReadTokens ?? tokenUsage.cacheReadInputTokens) > 0 {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Cache")
                                .font(.system(size: 8, weight: .medium))
                                .foregroundColor(.secondary)
                            HStack(spacing: 2) {
                                Image(systemName: "arrow.triangle.2.circlepath")
                                    .font(.system(size: 8, weight: .bold))
                                    .foregroundColor(.green.opacity(0.8))
                                Text(formatTokens(tool.cacheReadTokens ?? tokenUsage.cacheReadInputTokens))
                                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                                    .foregroundColor(.green)
                            }
                        }
                    }

                    Spacer()

                    // Timeout if present
                    if let timeout = tool.timeout {
                        VStack(alignment: .trailing, spacing: 2) {
                            Text("Timeout")
                                .font(.system(size: 8, weight: .medium))
                                .foregroundColor(.secondary)
                            Text("\(timeout / 1000)s")
                                .font(.system(size: 11, weight: .medium, design: .monospaced))
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
        }

        private func formatTokens(_ count: Int) -> String {
            if count >= 1000 {
                return String(format: "%.1fk", Double(count) / 1000.0)
            }
            return "\(count)"
        }
    }

    /// Drops a pending hover-open without arming the hover-close.
    private func cancelHoverOpen() {
        hoverTask?.cancel()
        withAnimation(animationSpring) {
            isHovering = false
        }
    }

    private func handleHover(_ hovering: Bool) {
        hoverTask?.cancel()

        if hovering {
            withAnimation(animationSpring) {
                isHovering = true
            }

            guard notchVM.notchState == .closed else { return }

            hoverTask = Task {
                try? await Task.sleep(for: .milliseconds(300))
                guard !Task.isCancelled else { return }

                await MainActor.run {
                    guard notchVM.notchState == .closed, isHovering else { return }
                    notchVM.open()
                }
            }
        } else {
            hoverTask = Task {
                try? await Task.sleep(for: .milliseconds(150))
                guard !Task.isCancelled else { return }

                await MainActor.run {
                    withAnimation(animationSpring) {
                        isHovering = false
                    }

                    if notchVM.notchState == .open {
                        notchVM.close()
                    }
                }
            }
        }
    }

    /// Announce that a session handed control back, and say what it was doing.
    ///
    /// The glow alone answers "something wants you" but not "which, and about
    /// what" — and with several sessions open that is most of the question. The
    /// notice is deliberately brief: it names the project and the agent's own
    /// closing line, then gets out of the way. Anything longer belongs in the
    /// panel, which is one click below it.
    private func triggerTurnDoneNotice() {
        let session = claudeCodeManager.sessionsAwaitingUser.first
        let state = session.flatMap { claudeCodeManager.sessionStates[$0.id] }
        turnDoneProject = session?.displayName
        turnDoneSummary = state?.lastAssistantSummary

        peekNotice = .turnDone
        notchVM.peek(duration: settings.noticeDurationSeconds)
    }

    private func triggerPermissionNotice() {
        // Get the tool name from the first session needing permission
        if let session = claudeCodeManager.sessionsNeedingPermission.first,
           let state = claudeCodeManager.sessionStates[session.id] {
            permissionToolName = state.pendingPermissionTool
        } else {
            permissionToolName = claudeCodeManager.state.pendingPermissionTool
        }

        peekNotice = .permission
        // No separate hide timer: the peek owns the lifetime and clears the
        // notice when it ends. A second timer on a different duration was how
        // the notice could vanish while its own peek was still on screen.
        notchVM.peek(duration: settings.noticeDurationSeconds)
    }

    private func triggerStartupGlow() {
        startupGlowTask?.cancel()
        showStartupGlow = true
        startupGlowTask = Task {
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                withAnimation(.easeOut(duration: 0.3)) {
                    showStartupGlow = false
                }
            }
        }
    }

    private func openSettings() {
        NSApp.sendAction(Selector(("showSettingsWindow")), to: NSApp.delegate, from: nil)
    }
}
