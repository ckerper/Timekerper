import SwiftUI

struct ActiveTaskBar: View {
    @Environment(AppState.self) private var appState

    private var activeTask: TaskItem? {
        guard let id = appState.activeTaskId else { return nil }
        return appState.tasks.first(where: { $0.id == id })
    }

    private var firstIncomplete: TaskItem? {
        appState.firstIncompleteTask
    }

    var body: some View {
        if appState.isToday {
            VStack(spacing: 0) {
                if let active = activeTask {
                    activeView(task: active)
                } else if let next = firstIncomplete {
                    idleView(task: next)
                } else if !appState.tasks.isEmpty {
                    allDoneView
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 4)
            .padding(.bottom, 6)
        }
    }

    // MARK: - Active Task Running

    private func activeView(task: TaskItem) -> some View {
        VStack(spacing: 8) {
            // Task name and timer
            HStack {
                if let tag = appState.tagForId(task.tagId) {
                    Circle()
                        .fill(Color(hex: tag.color))
                        .frame(width: 10, height: 10)
                }
                Text(task.name)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .lineLimit(1)
                    .foregroundStyle(.white)

                Spacer()

                // Timer display
                let elapsed = appState.elapsedMinutes
                let estimate = task.effectiveDuration
                let isOver = elapsed > estimate
                Text("\(DateTimeUtils.formatElapsed(elapsed)) / \(DateTimeUtils.formatElapsed(estimate))")
                    .font(.subheadline.monospacedDigit())
                    .fontWeight(.medium)
                    .foregroundStyle(isOver ? Color.red : .white)
            }

            // Adjust and action buttons
            HStack(spacing: 8) {
                // Duration adjustments
                Group {
                    Button("-15") { appState.adjustTaskTime(-15) }
                    Button("-5") { appState.adjustTaskTime(-5) }
                    Button("+5") { appState.adjustTaskTime(5) }
                    Button("+15") { appState.adjustTaskTime(15) }
                }
                .font(.caption)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.white.opacity(0.15))
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 4))

                Spacer()

                Button(action: { appState.completeActiveTask() }) {
                    Image(systemName: "checkmark")
                        .font(.caption.weight(.semibold))
                }
                .padding(8)
                .background(Color.green)
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 4))

                Button(action: { appState.pauseActiveTask() }) {
                    Image(systemName: "pause.fill")
                        .font(.caption.weight(.semibold))
                }
                .padding(8)
                .background(Color.orange)
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 4))

                Button(action: { appState.cancelActiveTask() }) {
                    Image(systemName: "xmark")
                        .font(.caption.weight(.semibold))
                }
                .padding(8)
                .background(Color.red.opacity(0.8))
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 4))
            }
        }
        .padding(12)
        .background(
            LinearGradient(
                colors: [Color(hex: "#7c3aed"), Color(hex: "#6d28d9")],
                startPoint: .leading,
                endPoint: .trailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .shadow(color: .black.opacity(0.15), radius: 4, y: 2)
    }

    // MARK: - Idle (Next Task)

    private func idleView(task: TaskItem) -> some View {
        HStack {
            if let tag = appState.tagForId(task.tagId) {
                Circle()
                    .fill(Color(hex: tag.color))
                    .frame(width: 10, height: 10)
            }

            let isPaused = task.pausedElapsed > 0
            Text(isPaused ? "Resume:" : "Next:")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.8))

            Text(task.name)
                .font(.subheadline)
                .fontWeight(.medium)
                .lineLimit(1)
                .foregroundStyle(.white)

            Text(DateTimeUtils.formatElapsed(task.effectiveDuration))
                .font(.caption)
                .foregroundStyle(.white.opacity(0.7))

            Spacer()

            Button(isPaused ? "Resume" : "Start") {
                appState.startTask()
            }
            .font(.subheadline.weight(.semibold))
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .background(Color.white.opacity(0.2))
            .foregroundStyle(.white)
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .padding(12)
        .background(
            LinearGradient(
                colors: [Color(hex: "#7c3aed"), Color(hex: "#6d28d9")],
                startPoint: .leading,
                endPoint: .trailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .shadow(color: .black.opacity(0.15), radius: 4, y: 2)
    }

    // MARK: - All Done

    private var allDoneView: some View {
        HStack {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
            Text("All tasks completed!")
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundStyle(.white)
            Spacer()
        }
        .padding(12)
        .background(
            LinearGradient(
                colors: [Color(hex: "#7c3aed"), Color(hex: "#6d28d9")],
                startPoint: .leading,
                endPoint: .trailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .shadow(color: .black.opacity(0.15), radius: 4, y: 2)
    }
}
