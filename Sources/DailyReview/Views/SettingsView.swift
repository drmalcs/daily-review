import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var store: AppStore
    @State private var wikiPath: String = Config.wikiPath
    @State private var wikiPathSaved = false

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
                }
                .padding()
            }
        }
        .frame(width: 400, height: 280)
        .preferredColorScheme(.dark)
    }

    private var questionCountSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Questions per day").font(.subheadline).bold()

            HStack {
                Text("Wiki-based")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Stepper(value: $store.wikiQuestionCount, in: 1...20) {
                    Text("\(store.wikiQuestionCount)")
                        .font(.caption.monospacedDigit())
                        .frame(width: 24)
                }
            }

            HStack {
                Text("New-knowledge")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Stepper(value: $store.nonWikiQuestionCount, in: 1...10) {
                    Text("\(store.nonWikiQuestionCount)")
                        .font(.caption.monospacedDigit())
                        .frame(width: 24)
                }
            }

            Text("Takes effect when questions are next generated (tonight).")
                .font(.caption2).foregroundStyle(.tertiary)
        }
    }

    private var wikiPathSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Wiki folder").font(.subheadline).bold()
            Text("Path to the folder containing your wiki .md files.")
                .font(.caption).foregroundStyle(.secondary)

            TextField("", text: $wikiPath)
                .textFieldStyle(.roundedBorder)
                .font(.system(.caption, design: .monospaced))
                .onChange(of: wikiPath) { _, _ in wikiPathSaved = false }

            HStack(spacing: 8) {
                Button(wikiPathSaved ? "Saved" : "Save path") {
                    Config.setWikiPath(wikiPath.trimmingCharacters(in: .whitespacesAndNewlines))
                    wikiPathSaved = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { wikiPathSaved = false }
                }
                .disabled(wikiPath.trimmingCharacters(in: .whitespacesAndNewlines) == Config.wikiPath)

                let accessible = FileManager.default.fileExists(atPath: Config.wikiPath)
                HStack(spacing: 4) {
                    Image(systemName: accessible ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .font(.caption2)
                    Text(accessible ? "Accessible" : "Not found")
                        .font(.caption2)
                }
                .foregroundStyle(accessible ? Theme.answerColor : Theme.danger)
            }
        }
    }
}
