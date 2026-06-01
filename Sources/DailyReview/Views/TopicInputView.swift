import SwiftUI

struct TopicInputView: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button {
            NSApp.activate(ignoringOtherApps: true)
            openWindow(id: "settings")
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "list.bullet")
                    .font(.caption2)
                Text("Manage new-question topics →")
                    .font(.caption)
            }
            .foregroundStyle(Theme.nonWikiBadge)
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Theme.cardBg.opacity(0.7))
        .overlay(
            Rectangle()
                .frame(height: 1)
                .foregroundStyle(Theme.nonWikiBadge.opacity(0.35)),
            alignment: .top
        )
    }
}
