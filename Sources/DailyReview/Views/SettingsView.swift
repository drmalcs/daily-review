import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var store: AppStore
    @State private var wikiPath: String = Config.wikiPath
    @State private var wikiPathSaved = false
    @State private var newTopicText: String = ""

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Settings").font(.headline)
                Spacer()
                Button("Done") { NSApp.keyWindow?.close() }
            }
            .padding()

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    questionCountSection
                    Divider()
                    wikiPathSection
                    Divider()
                    topicsSection
                }
                .padding()
            }
        }
        .frame(width: 400)
        .preferredColorScheme(.dark)
    }

    // MARK: - Question counts

    private var questionCountSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Questions per day").font(.system(size: 17, weight: .bold))

            HStack {
                Text("Wiki-based")
                    .font(.system(size: 14)).foregroundStyle(.secondary)
                Spacer()
                Stepper(value: $store.wikiQuestionCount, in: 1...20) {
                    Text("\(store.wikiQuestionCount)")
                        .font(.system(size: 14).monospacedDigit())
                        .frame(width: 24)
                }
            }

            HStack {
                Text("New-knowledge")
                    .font(.system(size: 14)).foregroundStyle(.secondary)
                Spacer()
                Stepper(value: $store.nonWikiQuestionCount, in: 1...10) {
                    Text("\(store.nonWikiQuestionCount)")
                        .font(.system(size: 14).monospacedDigit())
                        .frame(width: 24)
                }
            }

            Text("Takes effect when questions are next generated (tonight).")
                .font(.system(size: 13)).foregroundStyle(.tertiary)
        }
    }

    // MARK: - Wiki path

    private var wikiPathSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Wiki folder").font(.system(size: 17, weight: .bold))
            Text("Path to the folder containing your wiki .md files.")
                .font(.system(size: 14)).foregroundStyle(.secondary)

            TextField("", text: $wikiPath)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 14, design: .monospaced))
                .onChange(of: wikiPath) { _, _ in wikiPathSaved = false }

            HStack(spacing: 8) {
                Button(wikiPathSaved ? "Saved" : "Save path") {
                    Config.setWikiPath(wikiPath.trimmingCharacters(in: .whitespacesAndNewlines))
                    wikiPathSaved = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { wikiPathSaved = false }
                }
                .font(.system(size: 14))
                .disabled(wikiPath.trimmingCharacters(in: .whitespacesAndNewlines) == Config.wikiPath)

                let accessible = FileManager.default.fileExists(atPath: Config.wikiPath)
                HStack(spacing: 4) {
                    Image(systemName: accessible ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .font(.system(size: 13))
                    Text(accessible ? "Accessible" : "Not found")
                        .font(.system(size: 13))
                }
                .foregroundStyle(accessible ? Theme.answerColor : Theme.danger)
            }
        }
    }

    // MARK: - Topics

    private var topicsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("New-knowledge topics").font(.system(size: 17, weight: .bold))
            Text("Each new-knowledge question independently picks one active topic at random. Paused topics are excluded.")
                .font(.system(size: 14)).foregroundStyle(.secondary)

            HStack(spacing: 6) {
                TextField("Add a topic…", text: $newTopicText)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 14))
                    .onSubmit { submitTopic() }

                Button("Add") { submitTopic() }
                    .font(.system(size: 14))
                    .disabled(newTopicText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            if store.topics.isEmpty {
                Text("No topics yet. Questions will extend the wiki content.")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.muted)
                    .padding(.top, 2)
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(store.topics) { topic in
                            topicRow(topic)
                            if topic.id != store.topics.last?.id {
                                Divider().opacity(0.3)
                            }
                        }
                    }
                }
                .frame(maxHeight: 200)
                .background(Theme.cardBg)
                .cornerRadius(6)
            }
        }
    }

    private func topicRow(_ topic: Topic) -> some View {
        HStack(spacing: 8) {
            Text(topic.text)
                .font(.system(size: 14))
                .foregroundStyle(topic.isPaused ? Theme.muted : .primary)
                .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                store.togglePause(id: topic.id)
            } label: {
                Image(systemName: topic.isPaused ? "pause.circle.fill" : "pause.circle")
                    .font(.system(size: 18))
                    .foregroundStyle(topic.isPaused ? Theme.accent : Theme.muted)
                    .shadow(color: topic.isPaused ? Theme.accent.opacity(0.8) : .clear, radius: 4)
            }
            .buttonStyle(.plain)
            .help(topic.isPaused ? "Un-pause topic" : "Pause topic")

            Button {
                store.deleteTopic(id: topic.id)
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 18))
                    .foregroundStyle(Theme.danger)
            }
            .buttonStyle(.plain)
            .help("Delete topic")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
    }

    private func submitTopic() {
        let trimmed = newTopicText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        store.addTopic(trimmed)
        newTopicText = ""
    }
}
