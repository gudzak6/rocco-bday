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
            headline: "A Birthday Adventure Awaits!",
            subtitle: "Someone made an entire game just for you.",
            body: "Your favorite people, places, and ridiculous memories have been turned into a real-world NYC adventure. Explore the city, discover surprises, and collect the memories that make you, you.",
            buttonTitle: "Open Your Gift",
            symbol: "gift.fill"
        ),
        OnboardingPage(
            id: 1,
            headline: "Explore Your City",
            subtitle: "Your memories are hiding around NYC.",
            body: "Open the map to find special locations across New York City. Visit the places marked on your map to discover characters, collectibles, and birthday surprises. You need to be physically nearby to activate certain encounters.",
            buttonTitle: "Next",
            symbol: "map.fill"
        ),
        OnboardingPage(
            id: 2,
            headline: "Catch Your Characters",
            subtitle: "Some familiar faces are out there.",
            body: "Find cartoon characters inspired by your friends, favorite foods, and inside jokes. Tap a nearby character, throw your capture ball, and add it to your FriendDex.",
            buttonTitle: "Next",
            symbol: "sparkles"
        ),
        OnboardingPage(
            id: 3,
            headline: "Collect Passport Stamps",
            subtitle: "Seven locations. Seven memories.",
            body: "Visit Memory Stops and complete special encounters to earn stamps in your NYC Memory Passport. Collect all seven stamps to unlock your final birthday surprise.",
            buttonTitle: "Next",
            symbol: "seal.fill"
        ),
        OnboardingPage(
            id: 4,
            headline: "A Little Birthday Love",
            subtitle: "Messages from your people.",
            body: "Your friends left you a few birthday notes. Visit the Memories tab to read messages from Sharon, Shelby, Mary, Joey, Derek, and Anya. They're available whenever you want.",
            buttonTitle: "Next",
            symbol: "envelope.fill"
        ),
        OnboardingPage(
            id: 5,
            headline: "Ready to Explore?",
            subtitle: "Your birthday. Your city. Your adventure.",
            body: "Enable location access to discover nearby surprises, follow your Memory Passport, and explore the city at your own pace. Remember to stay aware of your surroundings.",
            buttonTitle: "Start My Adventure",
            symbol: "figure.walk"
        ),
    ]
}

struct OnboardingView: View {
    var isReplay = false
    @EnvironmentObject private var store: GameStore
    @EnvironmentObject private var location: LocationService
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
                progressDots
                    .padding(.top, 8)
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
            Button(current.buttonTitle) {
                advance()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .frame(maxWidth: .infinity)
            .accessibilityLabel(current.buttonTitle)
        }
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
        if location.authorizationStatus == .notDetermined {
            location.requestAccess()
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
