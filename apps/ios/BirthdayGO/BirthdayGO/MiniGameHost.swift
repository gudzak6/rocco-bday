import SpriteKit
import SwiftUI

struct QuestSpriteView: UIViewRepresentable {
    let scene: SKScene

    func makeUIView(context: Context) -> SKView {
        let view = SKView()
        view.ignoresSiblingOrder = true
        scene.isPaused = false
        view.presentScene(scene)
        view.isPaused = false
        return view
    }

    func updateUIView(_ view: SKView, context: Context) {
        if view.scene !== scene {
            scene.isPaused = false
            view.presentScene(scene)
        }
        view.isPaused = false
        scene.isPaused = false
    }
}

struct ArcadeScreen<S: SKScene>: View {
    @ObservedObject var session: QuestSession
    let scene: S
    let primary: (S) -> String
    let secondary: (S) -> String
    let lives: (S) -> Int?
    let outcome: (S) -> Int
    let setRunning: (S, Bool) -> Void

    var body: some View {
        QuestSpriteView(scene: scene)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onAppear { setRunning(scene, session.phase == .playing) }
            .onChange(of: session.phase) { _, phase in
                setRunning(scene, phase == .playing)
            }
            .onReceive(Timer.publish(every: 0.12, on: .main, in: .common).autoconnect()) { _ in
                guard session.phase == .playing else { return }
                session.primary = primary(scene)
                session.secondary = secondary(scene)
                session.lives = lives(scene)
                switch outcome(scene) {
                case 1: session.succeed()
                case 2: session.fail()
                default: break
                }
            }
    }
}

struct QuestPlayView: View {
    let level: QuestLevel
    var onVictory: () -> Void
    var onClose: () -> Void
    @StateObject private var session = QuestSession()
    @State private var savedWin = false

    var body: some View {
        ZStack {
            if session.phase == .won {
                LevelCompleteView(level: level, onContinue: onClose)
            } else if session.phase == .ready {
                readyCard
            } else {
                stage
                    .id(session.runID)
                    .overlay(alignment: .top) {
                        if session.phase == .playing || session.phase == .paused {
                            hud
                        }
                    }
                if session.phase == .countdown { countdownCard }
                if session.phase == .paused { pauseCard }
                if session.phase == .lost { lostCard }
            }
        }
        .background(Color.warmWhite.ignoresSafeArea())
        .onChange(of: session.phase) { _, phase in
            if phase == .won, !savedWin {
                savedWin = true
                onVictory()
            }
        }
    }

    @ViewBuilder
    private var stage: some View {
        switch level.number {
        case 1: MarathonHost(session: session)
        case 2: CookieHost(session: session)
        case 3: ClimbingGame(session: session)
        case 4: BoyfriendHost(session: session)
        case 5: MazeHost(session: session)
        case 6: LoyaltyGame(session: session)
        case 7: TrainHost(session: session)
        case 8: MemoryMatchGame(session: session)
        case 9: BakeOffGame(session: session)
        default: LegendaryGame(session: session)
        }
    }

    private var hud: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(session.primary).font(.system(.headline, design: .rounded, weight: .black))
                Text(session.secondary).font(.caption.weight(.bold))
            }
            .padding(10)
            .background(.white.opacity(0.92), in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(.black, lineWidth: 3))
            Spacer()
            if let lives = session.lives {
                Text(String(repeating: "♥", count: max(lives, 0)))
                    .font(.headline)
                    .foregroundStyle(.pink)
                    .padding(10)
                    .background(.white.opacity(0.92), in: Capsule())
            }
            Button { session.pause() } label: {
                Image(systemName: "pause.fill")
                    .padding(12)
                    .background(.white, in: Circle())
                    .overlay(Circle().stroke(.black, lineWidth: 3))
            }
            .accessibilityLabel("Pause")
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    private var readyCard: some View {
        card {
            Text(level.title).font(.system(.title, design: .rounded, weight: .black))
            Text(level.theme).font(.headline).foregroundStyle(level.accent)
            Text(level.instructions).multilineTextAlignment(.center)
            Button("Start") { session.startCountdown() }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            Button("Back to quest", action: onClose)
        }
    }

    private var countdownCard: some View {
        Text("\(session.countdown)")
            .font(.system(size: 96, weight: .black, design: .rounded))
            .foregroundStyle(.white)
            .shadow(color: .black, radius: 0, y: 4)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(level.accent.opacity(0.35).ignoresSafeArea())
    }

    private var pauseCard: some View {
        card {
            Text("Paused").font(.system(.title, design: .rounded, weight: .black))
            Button("Resume") { session.resume() }.buttonStyle(.borderedProminent)
            Button("Retry") { session.retry() }
            Button("Back to quest", action: onClose)
        }
    }

    private var lostCard: some View {
        card {
            Text("Not this time").font(.system(.title, design: .rounded, weight: .black))
            Text("The level is still here. Give it another run.")
                .multilineTextAlignment(.center)
            Button("Retry") { session.retry() }.buttonStyle(.borderedProminent)
            Button("Back to quest", action: onClose)
        }
    }

    private func card<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 14) { content() }
            .padding(22)
            .background(.white, in: RoundedRectangle(cornerRadius: 22))
            .overlay(RoundedRectangle(cornerRadius: 22).stroke(.black, lineWidth: 4))
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.black.opacity(0.25).ignoresSafeArea())
    }
}

struct MarathonHost: View {
    @ObservedObject var session: QuestSession
    @State private var scene = MarathonScene()
    var body: some View {
        ArcadeScreen(session: session, scene: scene, primary: { "\($0.meters) m" }, secondary: { "Gels \($0.gels)/5" }, lives: { 3 - $0.hits }, outcome: { $0.outcome }, setRunning: { $0.setRunning($1) })
            .ignoresSafeArea()
    }
}

struct CookieHost: View {
    @ObservedObject var session: QuestSession
    @State private var scene = CookieChaosScene()
    var body: some View {
        ArcadeScreen(session: session, scene: scene, primary: { "Cookies \($0.cookies)/20" }, secondary: { "Combo \($0.combo)" }, lives: { 3 - $0.bad }, outcome: { $0.outcome }, setRunning: { $0.setRunning($1) })
            .ignoresSafeArea()
    }
}

struct BoyfriendHost: View {
    @ObservedObject var session: QuestSession
    @State private var scene = BoyfriendScene()
    var body: some View {
        ArcadeScreen(session: session, scene: scene, primary: { "Hearts \($0.hearts)/10" }, secondary: { $0.hint }, lives: { 3 - $0.hits }, outcome: { $0.outcome }, setRunning: { $0.setRunning($1) })
            .ignoresSafeArea()
            .overlay(alignment: .bottom) {
                if session.phase == .playing {
                    HStack(spacing: 12) {
                        holdButton("arrow.left") { scene.inputX = $0 ? -1 : 0 }
                        Button { scene.jumpQueued = true } label: {
                            Text("Jump").font(.system(.headline, design: .rounded, weight: .black))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(Color.pink, in: RoundedRectangle(cornerRadius: 12))
                                .overlay(RoundedRectangle(cornerRadius: 12).stroke(.black, lineWidth: 3))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Jump")
                        holdButton("arrow.right") { scene.inputX = $0 ? 1 : 0 }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)
                }
            }
    }

    private func holdButton(_ symbol: String, set: @escaping (Bool) -> Void) -> some View {
        Image(systemName: symbol)
            .font(.title2.weight(.black))
            .frame(width: 64, height: 52)
            .background(.white, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(.black, lineWidth: 3))
            .gesture(DragGesture(minimumDistance: 0).onChanged { _ in set(true) }.onEnded { _ in set(false) })
            .accessibilityLabel(symbol == "arrow.left" ? "Move left" : "Move right")
    }
}

struct MazeHost: View {
    @ObservedObject var session: QuestSession
    @State private var scene = GamerMazeScene()
    var body: some View {
        ArcadeScreen(session: session, scene: scene, primary: { "Controllers \($0.found)/5" }, secondary: { _ in "Find the exit" }, lives: { 3 - $0.hits }, outcome: { $0.outcome }, setRunning: { $0.setRunning($1) })
            .ignoresSafeArea()
            .overlay(alignment: .bottom) {
                if session.phase == .playing {
                    VStack(spacing: 6) {
                        padButton("arrow.up") { scene.move(dx: 0, dy: -1) }
                        HStack(spacing: 28) {
                            padButton("arrow.left") { scene.move(dx: -1, dy: 0) }
                            padButton("arrow.right") { scene.move(dx: 1, dy: 0) }
                        }
                        padButton("arrow.down") { scene.move(dx: 0, dy: 1) }
                    }
                    .padding(.bottom, 16)
                }
            }
    }

    private func padButton(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.title3.weight(.black))
                .frame(width: 54, height: 44)
                .background(.white, in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(.black, lineWidth: 3))
        }
        .buttonStyle(.plain)
    }
}

struct TrainHost: View {
    @ObservedObject var session: QuestSession
    @State private var scene = TrainScene()
    var body: some View {
        ArcadeScreen(session: session, scene: scene, primary: { "\($0.meters) m" }, secondary: { "Tickets \($0.tickets)/8" }, lives: { 3 - $0.hits }, outcome: { $0.outcome }, setRunning: { $0.setRunning($1) })
            .ignoresSafeArea()
    }
}
