import SwiftUI

struct TaskRowView: View {
    @Environment(AppState.self) private var appState
    let task: TaskItem

    private var tag: Tag? {
        appState.tagForId(task.tagId)
    }

    private var isActive: Bool {
        task.id == appState.activeTaskId
    }

    var body: some View {
        HStack(spacing: 8) {
            // Checkbox
            Button(action: { appState.toggleTaskComplete(id: task.id) }) {
                Image(systemName: task.completed ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(task.completed ? .green : .secondary)
                    .font(.title3)
            }
            .buttonStyle(.plain)

            // Tag dot
            if let tag = tag {
                Circle()
                    .fill(Color(hex: tag.color))
                    .frame(width: 10, height: 10)
            }

            // Name
            VStack(alignment: .leading, spacing: 2) {
                Text(task.name)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .strikethrough(task.completed)
                    .foregroundStyle(task.completed ? .secondary : .primary)
                    .lineLimit(appState.settings.wrapListNames ? 3 : 1)

                if isActive {
                    Text("Active")
                        .font(.caption2)
                        .foregroundStyle(.green)
                        .fontWeight(.medium)
                }

                if task.pausedElapsed > 0 && !task.completed {
                    Text("Paused \(DateTimeUtils.formatElapsed(task.pausedElapsed))")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
            }

            Spacer()

            // Duration badge
            Text(DateTimeUtils.formatElapsed(task.effectiveDuration))
                .font(.caption)
                .fontWeight(.medium)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Color.gray.opacity(0.18))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .foregroundStyle(.secondary)

            // Play/pause (incomplete tasks on today only)
            if !task.completed && appState.isToday {
                if isActive {
                    Button(action: { appState.pauseActiveTask() }) {
                        Image(systemName: "pause.fill")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                    .buttonStyle(.plain)
                } else {
                    Button(action: { appState.startSpecificTask(id: task.id) }) {
                        Image(systemName: "play.fill")
                            .font(.caption)
                            .foregroundStyle(.green)
                    }
                    .buttonStyle(.plain)
                }
            }

            // Duplicate
            if !task.completed {
                Button(action: { appState.duplicateTask(task) }) {
                    Image(systemName: "doc.on.doc")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            // Delete
            Button(action: { appState.deleteTask(id: task.id) }) {
                Image(systemName: "xmark")
                    .font(.caption)
                    .foregroundStyle(.red.opacity(0.7))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(.systemGray6))
        )
        .contentShape(RoundedRectangle(cornerRadius: 10))
        .onTapGesture {
            appState.editingTask = task
            appState.showTaskSheet = true
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 3)
    }
}
