import SwiftUI

struct TaskListView: View {
    @Environment(AppState.self) private var appState

    private var visibleTasks: [TaskItem] {
        if appState.hideCompleted {
            return appState.tasks.filter { !$0.completed }
        }
        return appState.tasks
    }

    var body: some View {
        VStack(spacing: 0) {
            // Summary bar
            HStack {
                Text("\(appState.incompleteTaskCount) tasks, \(DateTimeUtils.formatElapsed(appState.totalIncompleteDuration))")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                Button(appState.hideCompleted ? "Show completed" : "Hide completed") {
                    appState.hideCompleted.toggle()
                }
                .font(.caption)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)

            if appState.tasks.isEmpty {
                ContentUnavailableView {
                    Label("No Tasks", systemImage: "checklist")
                } description: {
                    Text("Add tasks to start planning your day.")
                }
            } else {
                List {
                    ForEach(visibleTasks) { task in
                        TaskRowView(task: task)
                    }
                    .onMove { source, destination in
                        // Map filtered indices back to actual indices if needed
                        if appState.hideCompleted {
                            // Need to map between filtered and original indices
                            let taskIds = visibleTasks.map(\.id)
                            var allTasks = appState.tasks
                            appState.pushUndo()
                            // Simple approach: reorder within the filtered view
                            var filtered = visibleTasks
                            filtered.move(fromOffsets: source, toOffset: destination)
                            // Rebuild: keep completed in place, insert incomplete in new order
                            var result: [TaskItem] = []
                            var incompleteIter = filtered.makeIterator()
                            for t in allTasks {
                                if t.completed {
                                    result.append(t)
                                } else {
                                    if let next = incompleteIter.next() {
                                        result.append(next)
                                    }
                                }
                            }
                            appState.tasks = result
                        } else {
                            appState.moveTasks(from: source, to: destination)
                        }
                    }
                }
                .listStyle(.plain)
                .environment(\.editMode, .constant(.active))
            }

            // Action buttons
            HStack(spacing: 12) {
                if appState.tasks.contains(where: { $0.completed }) {
                    Button("Clear Completed") {
                        appState.clearCompletedTasks()
                    }
                    .font(.caption)
                    .foregroundStyle(.red)
                }

                Spacer()

                if !appState.tasks.isEmpty {
                    Button("Clear All") {
                        appState.clearAllTasks()
                    }
                    .font(.caption)
                    .foregroundStyle(.red)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
    }
}
