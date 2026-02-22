import SwiftUI

struct TagSelector: View {
    @Environment(AppState.self) private var appState
    @Binding var selectedTagId: Int?

    private let circleSize: CGFloat = 28

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .center, spacing: 10) {
                // No tag option
                Button(action: { selectedTagId = nil }) {
                    VStack(spacing: 4) {
                        ZStack {
                            Circle()
                                .stroke(Color.gray.opacity(0.4), lineWidth: selectedTagId == nil ? 2 : 1)
                                .frame(width: circleSize, height: circleSize)
                            Image(systemName: "xmark")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .scaleEffect(selectedTagId == nil ? 1.15 : 1.0)
                        .frame(width: circleSize + 8, height: circleSize + 8)
                        Text("None")
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .frame(width: 50)
                    }
                }
                .buttonStyle(.plain)
                .animation(.easeInOut(duration: 0.1), value: selectedTagId)

                // Tag circles
                ForEach(appState.tags) { tag in
                    Button(action: { selectedTagId = tag.id }) {
                        VStack(spacing: 4) {
                            Circle()
                                .fill(Color(hex: tag.color))
                                .frame(width: circleSize, height: circleSize)
                                .overlay {
                                    if selectedTagId == tag.id {
                                        Circle()
                                            .stroke(Color.primary, lineWidth: 2)
                                    }
                                }
                                .scaleEffect(selectedTagId == tag.id ? 1.15 : 1.0)
                                .frame(width: circleSize + 8, height: circleSize + 8)
                            Text(tag.name)
                                .font(.system(size: 9))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .frame(width: 50)
                        }
                    }
                    .buttonStyle(.plain)
                    .animation(.easeInOut(duration: 0.1), value: selectedTagId)
                }
            }
            .padding(.vertical, 4)
        }
    }
}
