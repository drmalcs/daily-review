import SwiftUI

struct TopicInputView: View {
    @EnvironmentObject var store: AppStore
    @State private var inputText: String = ""
    @State private var isSaved = false
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "lightbulb.fill")
                    .font(.caption2)
                    .foregroundStyle(Theme.nonWikiBadge)
                Text("Tomorrow's new-knowledge topic")
                    .font(.caption)
                    .foregroundStyle(Theme.nonWikiBadge)
            }

            Text("What should tomorrow's \(store.nonWikiQuestionCount) new question\(store.nonWikiQuestionCount == 1 ? "" : "s") be about?")
                .font(.caption2)
                .foregroundStyle(Theme.muted)

            HStack(spacing: 8) {
                TextField("e.g. transformer attention mechanisms", text: $inputText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .padding(6)
                    .background(Theme.background)
                    .cornerRadius(5)
                    .focused($isFocused)
                    .onSubmit { saveTopic() }
                    .onChange(of: inputText) { _, _ in isSaved = false }

                Button(isSaved ? "Saved ✓" : "Set") {
                    saveTopic()
                }
                .font(.caption)
                .disabled(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.cardBg.opacity(0.7))
        .overlay(
            Rectangle()
                .frame(height: 1)
                .foregroundStyle(Theme.nonWikiBadge.opacity(0.35)),
            alignment: .top
        )
        .onAppear { inputText = store.topicForTomorrow }
    }

    private func saveTopic() {
        let trimmed = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        store.updateTopicForTomorrow(inputText)
        isSaved = true
        isFocused = false
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            isSaved = false
        }
    }
}
