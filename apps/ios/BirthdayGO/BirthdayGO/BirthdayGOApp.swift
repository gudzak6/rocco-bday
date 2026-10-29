import SwiftUI
import SwiftData

@main
struct BirthdayGOApp: App {
    @StateObject private var store = GameStore()
    @StateObject private var location = LocationService()
    @StateObject private var walk = WalkTracker()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .environmentObject(location)
                .environmentObject(walk)
                .modelContainer(for: [CachedSnapshot.self, CapturedCreature.self, CollectedSouvenir.self, AwardedCheckpoint.self, NotePreference.self, LocalPassportStamp.self, PlayerEggRecord.self])
                .tint(.birthdayPurple)
        }
    }
}

extension Color {
    static let birthdayPurple = Color(red: 117 / 255, green: 85 / 255, blue: 232 / 255)
    static let skyBlue = Color(red: 102 / 255, green: 201 / 255, blue: 242 / 255)
    static let golden = Color(red: 255 / 255, green: 200 / 255, blue: 87 / 255)
    static let mint = Color(red: 80 / 255, green: 201 / 255, blue: 154 / 255)
    static let warmWhite = Color(red: 248 / 255, green: 247 / 255, blue: 252 / 255)

    static func avatar(_ token: String) -> Color {
        switch token {
        case "sky": .skyBlue
        case "gold": .golden
        case "mint": .mint
        default: .birthdayPurple
        }
    }
}

struct RootView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var store: GameStore
    @EnvironmentObject private var walk: WalkTracker

    var body: some View {
        Group {
            switch store.phase {
            case .loading:
                ProgressView("Preparing your adventure…")
            case .needsInvitation:
                InvitationView()
            case .ready:
                if store.hasSeenWelcome {
                    MainTabView()
                } else {
                    OnboardingView()
                }
            }
        }
        .background(Color.warmWhite.ignoresSafeArea())
        .task {
            store.configure(modelContext: modelContext)
            store.attachWalkTracker(walk)
            await store.launch()
        }
        .onChange(of: scenePhase) { _, phase in
            walk.handleScene(active: phase == .active)
            if phase == .active { Task { await store.synchronize() } }
        }
        .alert("Birthday GO", isPresented: Binding(
            get: { store.errorMessage != nil },
            set: { if !$0 { store.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(store.errorMessage ?? "")
        }
    }
}

struct InvitationView: View {
    @EnvironmentObject private var store: GameStore
    @State private var code = ""
    @State private var recovering = false
    @State private var showCode = false

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                CaptureOrb().frame(width: 150, height: 150)
                Text("Birthday GO")
                    .font(.system(.largeTitle, design: .rounded, weight: .bold))
                    .foregroundStyle(Color.birthdayPurple)
                Text("A birthday adventure is waiting for you.")
                    .font(.title3).multilineTextAlignment(.center)
                Button {
                    Task { await store.joinOpenAdventure() }
                } label: {
                    if store.isWorking { ProgressView().tint(.white) }
                    else { Text("Start the adventure").frame(maxWidth: .infinity) }
                }
                .buttonStyle(.borderedProminent).controlSize(.large)
                .disabled(store.isWorking)
                Button("I have a private code") { showCode.toggle() }
                    .font(.footnote)
                if showCode {
                    TextField("Private invitation code", text: $code)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .textContentType(.oneTimeCode)
                        .padding().background(.white, in: RoundedRectangle(cornerRadius: 16))
                        .accessibilityLabel("Private invitation code")
                    Button {
                        Task {
                            if recovering { await store.recover(code: code) }
                            else { await store.redeem(code: code) }
                        }
                    } label: {
                        Text(recovering ? "Recover adventure" : "Use invite code").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .disabled(code.trimmingCharacters(in: .whitespacesAndNewlines).count < 6 || store.isWorking)
                    Button(recovering ? "Use a new invitation instead" : "Reinstalled? Use an organizer recovery code") {
                        recovering.toggle()
                        code = ""
                    }
                    .font(.footnote)
                }
                Text("A birthday quest is waiting on the first tab.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            .padding(28)
        }
        .task {
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("-ui-testing-invite") { return }
            #endif
            await store.joinOpenAdventure()
        }
        .onOpenURL { url in
            guard url.host == "invite",
                  let value = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                    .queryItems?.first(where: { $0.name == "code" })?.value else { return }
            showCode = true
            code = value
        }
    }
}

struct MainTabView: View {
    @EnvironmentObject private var store: GameStore
    @StateObject private var questProgress = QuestProgress()
    @State private var tab = 0

    var body: some View {
        TabView(selection: $tab) {
            QuestMapView()
                .environmentObject(questProgress)
                .tag(0)
                .tabItem { Label("Quest", systemImage: "flag.fill") }
            BirthdayDexView()
                .environmentObject(questProgress)
                .tag(1)
                .tabItem { Label("Birthday Dex", systemImage: "photo.on.rectangle.angled") }
            MemoryBookView().tag(2).tabItem { Label("Messages", systemImage: "envelope.fill") }
            ProfileView().tag(3).tabItem { Label("Me", systemImage: "person.crop.circle.fill") }
        }
        .overlay(alignment: .top) {
            VStack(spacing: 8) {
                if let banner = store.noteUnlockBanner {
                    Text(banner)
                        .font(.system(.subheadline, design: .rounded, weight: .bold))
                        .multilineTextAlignment(.center)
                        .padding(14)
                        .frame(maxWidth: .infinity)
                        .background(Color.golden, in: RoundedRectangle(cornerRadius: 18))
                        .padding(.horizontal)
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .onAppear {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 3.4) {
                                if store.noteUnlockBanner == banner { store.noteUnlockBanner = nil }
                            }
                        }
                        .accessibilityAddTraits(.isStaticText)
                }
            }
            .padding(.top)
        }
        .animation(.spring, value: store.noteUnlockBanner)
        .fullScreenCover(isPresented: $store.showHowToPlay) {
            OnboardingView(isReplay: true)
                .environmentObject(store)
        }
    }
}

struct CaptureOrb: View {
    var body: some View {
        ZStack {
            Circle().fill(LinearGradient(colors: [.skyBlue, .birthdayPurple], startPoint: .top, endPoint: .bottom))
            Rectangle().fill(Color.golden).frame(height: 18).clipShape(.capsule)
            Image(systemName: "star.fill")
                .font(.title).foregroundStyle(Color.mint)
                .padding(8).background(Color.golden, in: Circle())
        }
        .shadow(color: .birthdayPurple.opacity(0.25), radius: 12, y: 7)
        .accessibilityHidden(true)
    }
}

struct AvatarMarker: View {
    let initial: String
    let color: String
    var body: some View {
        Text(initial)
            .font(.system(.headline, design: .rounded, weight: .black))
            .foregroundStyle(.white)
            .frame(width: 36, height: 36)
            .background(Color.avatar(color), in: Circle())
            .overlay(Circle().stroke(.white, lineWidth: 3))
            .shadow(radius: 4, y: 2)
            .accessibilityLabel("You")
    }
}

struct ConfettiBurst: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        TimelineView(.animation(minimumInterval: reduceMotion ? 1 : 0.05, paused: reduceMotion)) { timeline in
            Canvas { context, size in
                let colors: [Color] = [.birthdayPurple, .skyBlue, .golden, .mint]
                for index in 0..<24 {
                    var copy = context
                    let seed = Double(index)
                    let x = (sin(seed * 1.7) * 0.5 + 0.5) * size.width
                    let y = (timeline.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 2.4) / 2.4
                             + seed * 0.04).truncatingRemainder(dividingBy: 1) * size.height
                    copy.fill(
                        Path(ellipseIn: CGRect(x: x, y: y, width: 8, height: 12)),
                        with: .color(colors[index % colors.count].opacity(0.85))
                    )
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
