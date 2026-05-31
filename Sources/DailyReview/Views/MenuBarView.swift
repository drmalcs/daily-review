import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.openWindow) private var openWindow

    private var panelHeight: CGFloat {
        // 2/3 of the visible screen height (excludes menu bar and Dock)
        (NSScreen.main?.visibleFrame.height ?? 900) * 2 / 3
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            mainContent
        }
        .frame(width: 480, height: panelHeight)
        .background(Theme.background)
        .preferredColorScheme(.dark)
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack(spacing: 8) {
            Button { NSApp.terminate(nil) } label: {
                Image(systemName: "power")
            }
            .buttonStyle(.plain)
            .help("Quit")

            Text("DAILY REVIEW")
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundStyle(Theme.accent)

            Spacer()

            Button {
                Task { await store.runGenerateScript() }
            } label: {
                if store.isRefreshing {
                    ProgressView().scaleEffect(0.6)
                } else {
                    Image(systemName: "arrow.clockwise")
                }
            }
            .buttonStyle(.plain)
            .disabled(store.isRefreshing)
            .help("Generate fresh questions now (~30s)")

            Button {
                NSApp.activate()
                openWindow(id: "settings")
            } label: {
                Image(systemName: "gear")
            }
            .buttonStyle(.plain)
            .help("Settings")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: - Main content

    @ViewBuilder
    private var mainContent: some View {
        if store.wikiQuestions.isEmpty && store.nonWikiQuestions.isEmpty {
            emptyView
        } else {
            questionScrollView
        }
    }

    private var emptyView: some View {
        VStack(spacing: 10) {
            if let err = store.sessionError {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.title3)
                    .foregroundStyle(Theme.danger)
                Text(err)
                    .font(.caption)
                    .foregroundStyle(Theme.muted)
                    .multilineTextAlignment(.center)
            } else if store.awaitingAgent {
                Image(systemName: "moon.stars.fill")
                    .font(.title3)
                    .foregroundStyle(Theme.muted)
                Text("Tonight's questions haven't been generated yet.")
                    .font(.caption)
                    .foregroundStyle(Theme.muted)
                    .multilineTextAlignment(.center)
            } else {
                Text("No questions.")
                    .font(.caption)
                    .foregroundStyle(Theme.muted)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(24)
    }

    // MARK: - Question list

    private var questionScrollView: some View {
        ScrollView {
            VStack(spacing: 1) {
                notices

                // Wiki questions + topic input after the last one is revealed
                ForEach(Array(store.wikiQuestions.enumerated()), id: \.element.id) { idx, q in
                    QuestionView(question: q).environmentObject(store)

                    if idx == store.wikiQuestions.count - 1 && store.wikiQuestions.allSatisfy({ $0.srsRating != nil }) {
                        TopicInputView().environmentObject(store)
                    }
                }

                // Non-wiki questions
                ForEach(store.nonWikiQuestions) { q in
                    QuestionView(question: q).environmentObject(store)
                }

                if store.allRated {
                    completionBanner
                }
            }
            .padding(.vertical, 4)
        }
    }

    @ViewBuilder
    private var notices: some View {
        if let sessErr = store.sessionError {
            noticeRow(icon: "exclamationmark.triangle.fill", message: sessErr, color: Theme.danger)
        }
        if store.awaitingAgent && (!store.wikiQuestions.isEmpty || !store.nonWikiQuestions.isEmpty) {
            noticeRow(icon: "moon.stars.fill", message: "Showing carryovers — tonight's new questions haven't arrived yet.", color: Theme.muted)
        }
    }

    private func noticeRow(icon: String, message: String, color: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon).font(.caption2)
            Text(message).font(.caption).lineLimit(3)
        }
        .foregroundStyle(color)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Theme.cardBg)
    }

    private var completionBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.answerColor)
            Text("All done for today!")
                .font(.subheadline)
                .foregroundStyle(Theme.answerColor)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
    }
}
