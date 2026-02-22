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
        VStack(spacing: 0) {
            if let active = activeTask {
                activeView(task: active)
            } else if appState.isToday {
                if let next = firstIncomplete {
                    idleView(task: next)
                } else if !appState.tasks.isEmpty {
                    allDoneView
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 4)
        .padding(.bottom, 10)
    }

    // MARK: - Gradient helper

    private func barGradient(for task: TaskItem?) -> LinearGradient {
        let hex = taskBarColor(for: task)
        return LinearGradient(
            colors: [Color(hex: hex), Color(hex: hex).opacity(0.85)],
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    private func taskBarColor(for task: TaskItem?) -> String {
        guard let task = task else { return appState.settings.defaultTaskColor }
        return appState.colorForTag(task.tagId, defaultColor: appState.settings.defaultTaskColor)
    }

    // MARK: - Active Task Running

    private func activeView(task: TaskItem) -> some View {
        VStack(spacing: 6) {
            // Row 1: Name + Action buttons
            HStack {
                Text(task.name)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .lineLimit(1)
                    .foregroundStyle(.white)

                Spacer()

                // Action buttons
                HStack(spacing: 6) {
                    Button(action: { appState.completeActiveTask() }) {
                        Image(systemName: "checkmark")
                            .font(.caption.weight(.semibold))
                    }
                    .padding(6)
                    .background(Color.green)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 4))

                    Button(action: { appState.pauseActiveTask() }) {
                        Image(systemName: "pause.fill")
                            .font(.caption.weight(.semibold))
                    }
                    .padding(6)
                    .background(Color.orange)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 4))

                    Button(action: { appState.cancelActiveTask() }) {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.caption.weight(.semibold))
                    }
                    .padding(6)
                    .background(Color.red.opacity(0.8))
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                }
            }

            // Row 2: [-] [1m|5m|15m] [+]  Timer
            HStack(spacing: 6) {
                // Minus button
                Button(action: { appState.adjustTaskTime(-appState.adjustIncrement) }) {
                    Image(systemName: "minus")
                        .font(.caption2.weight(.semibold))
                }
                .frame(width: 26, height: 26)
                .background(Color.white.opacity(0.15))
                .foregroundStyle(.white)
                .clipShape(Circle())

                // Increment picker
                Picker("", selection: Binding(
                    get: { appState.adjustIncrement },
                    set: { appState.adjustIncrement = $0 }
                )) {
                    Text("1m").tag(1)
                    Text("5m").tag(5)
                    Text("15m").tag(15)
                }
                .pickerStyle(.segmented)
                .frame(width: 120)
                .scaleEffect(0.8)

                // Plus button
                Button(action: { appState.adjustTaskTime(appState.adjustIncrement) }) {
                    Image(systemName: "plus")
                        .font(.caption2.weight(.semibold))
                }
                .frame(width: 26, height: 26)
                .background(Color.white.opacity(0.15))
                .foregroundStyle(.white)
                .clipShape(Circle())

                Spacer()

                let elapsed = appState.elapsedMinutes
                let estimate = task.effectiveDuration
                let isOver = elapsed > estimate
                Text("\(DateTimeUtils.formatElapsed(elapsed)) / \(DateTimeUtils.formatElapsed(estimate))")
                    .font(.caption.monospacedDigit())
                    .fontWeight(.medium)
                    .foregroundStyle(isOver ? Color.red : .white)
            }
        }
        .padding(10)
        .background(barGradient(for: task))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .shadow(color: .black.opacity(0.15), radius: 4, y: 2)
    }

    // MARK: - Idle (Next Task)

    private func idleView(task: TaskItem) -> some View {
        HStack {
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
        .background(barGradient(for: task))
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
        .background(barGradient(for: nil))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .shadow(color: .black.opacity(0.15), radius: 4, y: 2)
    }
}
