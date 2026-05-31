import SwiftUI

struct QuestionView: View {
    let question: Question
    @EnvironmentObject var store: AppStore
    @State private var isAddingToWiki = false

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
                Text(question.answer)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.answerColor)
                    .fixedSize(horizontal: false, vertical: true)

                if let rating = question.srsRating {
                    ratedFooter(rating: rating)
                } else {
                    ratingButtons
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
            ratingButton("AGAIN", rating: .miss,  color: Theme.danger)
            ratingButton("HARD",  rating: .hazy,  color: Theme.muted)
            ratingButton("GOT IT", rating: .solid, color: Theme.answerColor)
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
        case .miss:  return "AGAIN"
        case .hazy:  return "HARD"
        case .solid: return "GOT IT"
        }
    }

    private func ratingColor(_ rating: SRSRating) -> Color {
        switch rating {
        case .miss:  return Theme.danger
        case .hazy:  return Theme.muted
        case .solid: return Theme.answerColor
        }
    }
}
