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
                    .frame(width: 8, height: 8)
            }

            // Name
            VStack(alignment: .leading, spacing: 2) {
                Text(task.name)
                    .font(.subheadline)
                    .fontWeight(isActive ? .semibold : .regular)
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
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.gray.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .foregroundStyle(.secondary)

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
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture {
            appState.editingTask = task
            appState.showTaskSheet = true
        }
    }
}
