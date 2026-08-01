//
//  CurrentActivityView.swift
//  Notchwatch
//
//  What the agent is doing right now, with a clock on it.
//

import SwiftUI

/// One line answering "is it alive, or is it stuck?".
///
/// A list of finished tool calls answers neither: it says what happened, which
/// stops being interesting the moment you trust the agent. What stays
/// interesting is the operation that has not finished — and how long it has been
/// going. `Bash · 47s` carries more than ten completed calls, because the number
/// is what separates a long test run from a wedged one.
///
/// The clock ticks only while something is running, and at half rate on battery:
/// a redraw a second for a notch that mostly says the same thing is not worth
/// the wake-ups.
struct CurrentActivityView: View {
    let activeTool: ClaudeToolExecution?
    let lastTool: ClaudeToolExecution?
    let isThinking: Bool
    let model: String
    @ObservedObject var settings: AppSettings
    @ObservedObject var powerMonitor: PowerStateMonitor

    private let activityColor = Color(red: 1.0, green: 0.55, blue: 0.2)

    private var tickInterval: TimeInterval {
        (settings.batterySaverEnabled && !powerMonitor.isCharging) ? 2 : 1
    }

    var body: some View {
        if let tool = activeTool {
            TimelineView(.periodic(from: .now, by: tickInterval)) { _ in
                row(
                    color: activityColor,
                    pulsing: true,
                    title: tool.toolName,
                    detail: tool.argument,
                    trailing: tool.formattedDuration
                )
            }
        } else if isThinking {
            row(
                color: activityColor.opacity(0.7),
                pulsing: true,
                title: "Thinking",
                detail: model.isEmpty ? nil : model,
                trailing: nil
            )
        } else if let tool = lastTool {
            row(
                color: .white.opacity(0.25),
                pulsing: false,
                title: tool.toolName,
                detail: tool.argument,
                trailing: tool.formattedDuration
            )
        } else {
            row(color: .white.opacity(0.2), pulsing: false, title: "Idle", detail: nil, trailing: nil)
        }
    }

    private func row(color: Color, pulsing: Bool, title: String, detail: String?, trailing: String?) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
                .shadow(color: color.opacity(pulsing ? 0.6 : 0), radius: pulsing ? 4 : 0)

            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.white.opacity(0.9))

            if let detail, !detail.isEmpty {
                Text(detail)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.white.opacity(0.5))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 4)

            if let trailing {
                Text(trailing)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundColor(.white.opacity(0.7))
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
    }
}

/// Agents finished against agents started, for a live workflow run.
struct WorkflowProgressRow: View {
    let progress: WorkflowProgress

    private let workflowColor = Color(red: 0.55, green: 0.8, blue: 0.9)

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "point.3.filled.connected.trianglepath.dotted")
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(workflowColor.opacity(0.9))

            Text("Workflow")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.white.opacity(0.85))

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.08))
                    Capsule()
                        .fill(workflowColor.opacity(0.8))
                        .frame(width: geo.size.width * min(max(progress.fraction, 0), 1))
                }
            }
            .frame(height: 3)

            Text("\(progress.finished)/\(progress.started)")
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundColor(.white.opacity(0.7))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
    }
}
