import SwiftUI

struct TaskFormSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    @State private var name: String = ""
    @State private var duration: Int = 30
    @State private var tagId: Int?

    private var isEditing: Bool { appState.editingTask != nil }

    var body: some View {
        NavigationStack {
            Form {
                // Name
                Section {
                    if isEditing {
                        TextField("Task name", text: $name)
                            .textInputAutocapitalization(.sentences)
                    } else {
                        ZStack(alignment: .topLeading) {
                            if name.isEmpty {
                                Text("One task per line. Append a number for duration (e.g. \"Review doc 45\")")
                                    .font(.body)
                                    .foregroundStyle(.tertiary)
                                    .padding(.top, 8)
                                    .padding(.leading, 5)
                                    .allowsHitTesting(false)
                            }
                            TextEditor(text: $name)
                                .frame(minHeight: 80)
                                .textInputAutocapitalization(.sentences)
                        }
                    }
                } header: {
                    Text(isEditing ? "Task Name" : "Tasks (one per line)")
                }

                // Duration
                Section("Duration") {
                    Stepper("\(duration) min", value: $duration, in: 5...480, step: 5)

                    // Quick duration buttons
                    HStack(spacing: 8) {
                        ForEach([15, 30, 45, 60, 90, 120], id: \.self) { mins in
                            Button(DateTimeUtils.formatElapsed(mins)) {
                                duration = mins
                            }
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(duration == mins ? Color.accentColor.opacity(0.15) : Color.gray.opacity(0.1))
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                        }
                    }
                }

                // Tag
                Section("Tag") {
                    TagSelector(selectedTagId: $tagId)
                }

                if isEditing {
                    Section {
                        Button(role: .destructive) {
                            if let task = appState.editingTask {
                                appState.deleteTask(id: task.id)
                            }
                            appState.editingTask = nil
                            dismiss()
                        } label: {
                            HStack {
                                Spacer()
                                Text("Delete Task")
                                Spacer()
                            }
                        }
                    }
                }

                // Add to Top button (add mode only)
                if !isEditing {
                    Section {
                        Button(action: {
                            saveAndDismiss(addToTop: true)
                        }) {
                            HStack {
                                Image(systemName: "arrow.up.to.line")
                                Text("Add to Top")
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
            }
            .navigationTitle(isEditing ? "Edit Task" : "Add Tasks")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveAndDismiss(addToTop: false)
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear {
                if let task = appState.editingTask {
                    name = task.name
                    duration = task.effectiveDuration
                    tagId = task.tagId
                } else {
                    name = ""
                    duration = appState.settings.defaultTaskDuration
                    tagId = nil
                }
            }
        }
        .presentationDetents([.large])
    }

    private func saveAndDismiss(addToTop: Bool) {
        appState.saveTask(
            name: name,
            duration: duration,
            tagId: tagId,
            editing: appState.editingTask,
            addToTop: addToTop,
            smartParse: !isEditing && appState.settings.smartDuration
        )
        appState.editingTask = nil
        dismiss()
    }
}
