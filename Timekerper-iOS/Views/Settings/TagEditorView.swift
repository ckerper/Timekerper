import SwiftUI

struct TagEditorView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        ForEach(appState.tags) { tag in
            HStack(spacing: 8) {
                ColorPicker("", selection: Binding(
                    get: { Color(hex: tag.color) },
                    set: { appState.updateTag(id: tag.id, color: $0.toHex()) }
                ))
                .labelsHidden()
                .frame(width: 30)

                TextField("Tag name", text: Binding(
                    get: { tag.name },
                    set: { appState.updateTag(id: tag.id, name: $0) }
                ))
                .font(.subheadline)
            }
        }
        .onDelete { offsets in
            for idx in offsets {
                appState.deleteTag(id: appState.tags[idx].id)
            }
        }
        .onMove { source, destination in
            appState.moveTags(from: source, to: destination)
        }

        Button(action: { appState.addTag() }) {
            Label("Add Tag", systemImage: "plus")
                .font(.subheadline)
        }
    }
}
