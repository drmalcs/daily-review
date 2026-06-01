import SwiftUI

private enum DiscussPhase: Equatable {
    case off
    case inputting
    case loading
    case answered(String)
}

struct QuestionView: View {
    let question: Question
    @EnvironmentObject var store: AppStore
    @State private var isAddingToWiki = false
    @State private var discussPhase: DiscussPhase = .off
    @State private var followUpText: String = ""
    @FocusState private var followUpFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                typeBadge
                Text(question.text)
                    .font(.system(size: 13))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if question.isRevealed {
                Divider().opacity(0.3)

                if case .answered(let text) = discussPhase {
                    Text(text)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.answerColor)
                        .fixedSize(horizontal: false, vertical: true)
                    backButton
                } else if discussPhase == .loading {
                    HStack(spacing: 6) {
                        ProgressView().scaleEffect(0.65)
                        Text("Thinking…")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(Theme.muted)
                    }
                    .padding(.vertical, 6)
                } else {
                    Text(question.answer)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.answerColor)
                        .fixedSize(horizontal: false, vertical: true)

                    if let rating = question.srsRating {
                        ratedFooter(rating: rating)
                    } else {
                        ratingButtons
                        if discussPhase == .inputting {
                            discussInput
                        }
                    }
                }
            } else {
                Text("REVEAL")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Theme.muted)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.cardBg)
        .contentShape(Rectangle())
        .onTapGesture {
            guard !question.isRevealed else { return }
            store.revealAnswer(for: question.id)
        }
    }

    // MARK: - Rating buttons

    private var ratingButtons: some View {
        HStack(spacing: 8) {
            ratingButton("AGAIN",  rating: .miss,   color: Theme.danger)
            ratingButton("HARD",   rating: .hazy,   color: Theme.muted)
            ratingButton("GOT IT", rating: .solid,  color: Theme.answerColor)
            ratingButton("BORING", rating: .boring, color: Theme.boring)
            Spacer()
            Button("DISCUSS") { discussPhase = .inputting }
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(Theme.accent)
                .buttonStyle(.plain)
        }
    }

    private var discussInput: some View {
        HStack(spacing: 6) {
            TextField("Ask a follow-up…", text: $followUpText)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .padding(5)
                .background(Theme.background)
                .cornerRadius(4)
                .focused($followUpFocused)
                .onSubmit { submitFollowUp() }

            Button("Ask") { submitFollowUp() }
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(Theme.accent)
                .buttonStyle(.plain)
                .disabled(followUpText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

            Button("✕") {
                discussPhase = .off
                followUpText = ""
            }
            .font(.system(size: 11))
            .foregroundStyle(Theme.muted)
            .buttonStyle(.plain)
        }
        .padding(.top, 4)
        .onAppear {
            // MenuBarExtra panels dismiss when a text field claims keyboard focus
            // unless we explicitly make the window key first.
            NSApp.activate(ignoringOtherApps: true)
            NSApp.windows.first { $0.isVisible && $0.canBecomeKey }?.makeKey()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                followUpFocused = true
            }
        }
    }

    private var backButton: some View {
        Button("← BACK") {
            discussPhase = .off
            followUpText = ""
        }
        .font(.system(size: 11, weight: .semibold, design: .monospaced))
        .foregroundStyle(Theme.muted)
        .buttonStyle(.plain)
    }

    private func submitFollowUp() {
        let q = followUpText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return }
        discussPhase = .loading
        Task {
            let answer = await store.askFollowUp(question: question, followUp: q)
            discussPhase = .answered(answer)
        }
    }

    private func ratingButton(_ label: String, rating: SRSRating, color: Color) -> some View {
        Button(label) {
            Task { await store.rateQuestion(id: question.id, rating: rating) }
        }
        .font(.system(size: 11, weight: .semibold, design: .monospaced))
        .foregroundStyle(color)
        .buttonStyle(.plain)
    }

    // MARK: - Post-rating footer

    @ViewBuilder
    private func ratedFooter(rating: SRSRating) -> some View {
        HStack(spacing: 12) {
            // Show which rating was chosen
            Text(ratingLabel(rating))
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundStyle(ratingColor(rating).opacity(0.6))

            // Wiki actions for non-wiki questions only
            if question.type == .nonWiki {
                if question.isAddedToWiki {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill").font(.caption2)
                        Text("Added to wiki").font(.caption2)
                    }
                    .foregroundStyle(Theme.wikiBadge)
                } else if rating == .hazy {
                    // HARD: offer manual add
                    Button {
                        isAddingToWiki = true
                        Task {
                            await store.addToWiki(question: question)
                            isAddingToWiki = false
                        }
                    } label: {
                        HStack(spacing: 4) {
                            if isAddingToWiki {
                                ProgressView().scaleEffect(0.55)
                            } else {
                                Image(systemName: "plus.circle").font(.caption2)
                            }
                            Text("Add to wiki").font(.caption2)
                        }
                    }
                    .foregroundStyle(Theme.wikiBadge)
                    .buttonStyle(.plain)
                    .disabled(isAddingToWiki)
                }
                // AGAIN: no wiki button
            }
        }
    }

    // MARK: - Helpers

    private var typeBadge: some View {
        let isWiki = question.type == .wiki
        return Text(isWiki ? "WIKI" : "NEW")
            .font(.system(size: 9, weight: .bold, design: .monospaced))
            .foregroundStyle(isWiki ? Theme.wikiBadge : Theme.nonWikiBadge)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .overlay(
                RoundedRectangle(cornerRadius: 3)
                    .stroke(isWiki ? Theme.wikiBadge : Theme.nonWikiBadge, lineWidth: 1)
            )
    }

    private func ratingLabel(_ rating: SRSRating) -> String {
        switch rating {
        case .miss:   return "AGAIN"
        case .hazy:   return "HARD"
        case .solid:  return "GOT IT"
        case .boring: return "BORING"
        }
    }

    private func ratingColor(_ rating: SRSRating) -> Color {
        switch rating {
        case .miss:   return Theme.danger
        case .hazy:   return Theme.muted
        case .solid:  return Theme.answerColor
        case .boring: return Theme.boring
        }
    }
}
