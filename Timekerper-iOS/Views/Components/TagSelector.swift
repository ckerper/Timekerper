import SwiftUI

struct TagSelector: View {
    @Environment(AppState.self) private var appState
    @Binding var selectedTagId: Int?

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 10) {
                // No tag option — wrapped in VStack with hidden label for alignment
                Button(action: { selectedTagId = nil }) {
                    VStack(spacing: 2) {
                        ZStack {
                            Circle()
                                .stroke(Color.gray.opacity(0.4), lineWidth: selectedTagId == nil ? 2 : 1)
                                .frame(width: 28, height: 28)
                            Image(systemName: "xmark")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Text("None")
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .frame(maxWidth: 50)
                    }
                }
                .buttonStyle(.plain)
                .scaleEffect(selectedTagId == nil ? 1.15 : 1.0)
                .animation(.easeInOut(duration: 0.1), value: selectedTagId)

                // Tag circles
                ForEach(appState.tags) { tag in
                    Button(action: { selectedTagId = tag.id }) {
                        VStack(spacing: 2) {
                            Circle()
                                .fill(Color(hex: tag.color))
                                .frame(width: 28, height: 28)
                                .overlay {
                                    if selectedTagId == tag.id {
                                        Circle()
                                            .stroke(Color.primary, lineWidth: 2)
                                    }
                                }
                            Text(tag.name)
                                .font(.system(size: 9))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .frame(maxWidth: 50)
                        }
                    }
                    .buttonStyle(.plain)
                    .scaleEffect(selectedTagId == tag.id ? 1.15 : 1.0)
                    .animation(.easeInOut(duration: 0.1), value: selectedTagId)
                }
            }
            .padding(.vertical, 4)
        }
    }
}
