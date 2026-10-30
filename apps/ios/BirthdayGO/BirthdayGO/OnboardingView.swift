import SwiftUI

struct OnboardingPage: Identifiable, Hashable {
    let id: Int
    let headline: String
    let subtitle: String
    let body: String
    let buttonTitle: String
    let symbol: String

    static let all: [OnboardingPage] = [
        OnboardingPage(
            id: 0,
            headline: "Rocco's Quest",
            subtitle: "A birthday adventure made just for you.",
            body: "Seven levels wait on the Quest map. Win them in order. Every win unlocks a set of photos in that level’s Birthday Dex album, plus a birthday message on the Messages tab.",
            buttonTitle: "Let's Go",
            symbol: "flag.fill"
        ),
        OnboardingPage(
            id: 1,
            headline: "Play the Quest",
            subtitle: "One flag at a time.",
            body: "Tap the lit flag, then tap Start. The game stays still through the 3-2-1 countdown. Clear the level and the next flag lights up.",
            buttonTitle: "Next",
            symbol: "flag.fill"
        ),
        OnboardingPage(
            id: 2,
            headline: "Win the Mini-Games",
            subtitle: "Run, catch, climb, and bake.",
            body: "Each flag is a short game about you: a marathon, cookies, a climbing wall, a race to the door, a matching game, a bake-off, and a last castle. Lose a round and you can try that level again.",
            buttonTitle: "Next",
            symbol: "sparkles"
        ),
        OnboardingPage(
            id: 3,
            headline: "Photos & Memories",
            subtitle: "Each level unlocks a set of both.",
            body: "Clear a level and two things open. A set of photos fills that level’s album on Birthday Dex. That friend’s birthday message unlocks on the Messages tab, and you can reread the win memory from the quest book.",
            buttonTitle: "Next",
            symbol: "photo.on.rectangle.angled"
        ),
        OnboardingPage(
            id: 4,
            headline: "A Little Birthday Love",
            subtitle: "Messages from your people.",
            body: "Sharon, Joey, Derek, Sheba, and Mary each left a note. Win their level to unlock it on the Messages tab. Locked notes stay visible so you can see who is still waiting.",
            buttonTitle: "Next",
            symbol: "envelope.fill"
        ),
        OnboardingPage(
            id: 5,
            headline: "Ready for Rocco's Quest?",
            subtitle: "Your birthday. Your quest.",
            body: "Start on the Quest tab and win the levels in order. Each win unlocks that level’s photo album and a birthday message. Open Birthday Dex to browse the albums, and Messages to read the notes you’ve unlocked.",
            buttonTitle: "Start Rocco's Quest",
            symbol: "flag.fill"
        ),
    ]
}

struct OnboardingView: View {
    var isReplay = false
    @EnvironmentObject private var store: GameStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("onboardingPage") private var savedPage = 0
    @State private var page = 0

    private var pages: [OnboardingPage] { OnboardingPage.all }
    private var current: OnboardingPage { pages[page] }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [.warmWhite, Color.skyBlue.opacity(0.18), Color.birthdayPurple.opacity(0.12)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            if !reduceMotion && page == 0 { ConfettiBurst().opacity(0.35).ignoresSafeArea() }

            VStack(spacing: 16) {
                if isReplay { topBar }
                progressDots
                    .padding(.top, isReplay ? 0 : 8)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Page \(page + 1) of \(pages.count)")

                TabView(selection: $page) {
                    ForEach(pages) { item in
                        pageContent(item)
                            .tag(item.id)
                            .accessibilityElement(children: .combine)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.28), value: page)

                controls
                    .padding(.horizontal, 24)
                    .padding(.bottom, 16)
            }
        }
        .onAppear {
            page = isReplay ? 0 : min(max(savedPage, 0), pages.count - 1)
        }
        .onChange(of: page) { _, value in
            if !isReplay {
                savedPage = value
            }
        }
    }

    private var topBar: some View {
        HStack {
            if isReplay {
                Text("How to Play")
                    .font(.system(.headline, design: .rounded, weight: .bold))
                    .foregroundStyle(Color.birthdayPurple)
            }
            Spacer()
            if isReplay {
                Button("Exit") { finish() }
                    .font(.system(.headline, design: .rounded, weight: .semibold))
                    .accessibilityLabel("Exit how to play")
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 12)
        .frame(minHeight: 44)
    }

    private var progressDots: some View {
        HStack(spacing: 8) {
            ForEach(pages) { item in
                Capsule()
                    .fill(item.id == page ? Color.birthdayPurple : Color.birthdayPurple.opacity(0.22))
                    .frame(width: item.id == page ? 22 : 8, height: 8)
                    .accessibilityHidden(true)
            }
        }
        .animation(reduceMotion ? nil : .spring(duration: 0.35), value: page)
    }

    private func pageContent(_ item: OnboardingPage) -> some View {
        ScrollView {
            VStack(spacing: 20) {
                OnboardingArt(symbol: item.symbol)
                    .frame(height: 168)
                    .accessibilityHidden(true)
                Text(item.headline)
                    .font(.system(.largeTitle, design: .rounded, weight: .bold))
                    .foregroundStyle(Color.birthdayPurple)
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.7)
                Text(item.subtitle)
                    .font(.system(.title3, design: .rounded, weight: .semibold))
                    .foregroundStyle(Color.skyBlue)
                    .multilineTextAlignment(.center)
                Text(item.body)
                    .font(.system(.body, design: .rounded))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 8)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 12)
        }
    }

    private var controls: some View {
        HStack(spacing: 12) {
            if page > 0 {
                Button("Back") {
                    page -= 1
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .accessibilityLabel("Back")
            }
            Button(primaryButtonTitle) {
                advance()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .frame(maxWidth: .infinity)
            .accessibilityLabel(primaryButtonTitle)
        }
    }

    private var primaryButtonTitle: String {
        if isReplay, page == pages.count - 1 { return "Done" }
        if isReplay, page == 0 { return "Next" }
        return current.buttonTitle
    }

    private func advance() {
        if page < pages.count - 1 {
            page += 1
            return
        }
        finish()
    }

    private func finish() {
        if isReplay {
            store.showHowToPlay = false
            return
        }
        savedPage = 0
        store.acknowledgeWelcome()
    }
}

private struct OnboardingArt: View {
    let symbol: String

    var body: some View {
        ZStack {
            Circle()
                .fill(LinearGradient(colors: [.golden.opacity(0.55), .skyBlue.opacity(0.45), .mint.opacity(0.4)], startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: 150, height: 150)
                .shadow(color: .birthdayPurple.opacity(0.2), radius: 16, y: 8)
            if symbol == "gift.fill" {
                CaptureOrb().frame(width: 92, height: 92)
                Image(systemName: "sparkle")
                    .font(.title2.bold())
                    .foregroundStyle(Color.golden)
                    .offset(x: 58, y: -48)
                Image(systemName: "sparkle")
                    .font(.headline)
                    .foregroundStyle(Color.mint)
                    .offset(x: -56, y: -36)
            } else {
                Image(systemName: symbol)
                    .font(.system(size: 54, weight: .bold))
                    .foregroundStyle(Color.birthdayPurple)
            }
        }
    }
}
