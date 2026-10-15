import SwiftUI
import CoreLocation
import UIKit

enum CatchState: Equatable {
    case aiming, throwing, authorizing, success, missed
}

struct CatchGameView: View {
    @EnvironmentObject private var store: GameStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let item: MapContentItem
    var character: Character?
    let currentLocation: CLLocation?
    let dwellStartedAt: Date
    let fallbackCode: String?
    var showsAROffFallback = false

    @State private var creatureBounce = false
    @State private var state: CatchState = .aiming
    @State private var struck = false
    @State private var ballAnchor: CGPoint = .zero
    @State private var ballReset = 0
    @State private var targetFrame: CGRect = .zero
    @State private var code: String = ""
    @State private var tappedBounce = false

    private var resolvedCharacter: Character? {
        character ?? store.snapshot?.characters.first { $0.id == item.id }
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                if state == .success { ConfettiBurst().ignoresSafeArea() }
                VStack(spacing: 16) {
                    if showsAROffFallback {
                        Text("AR Off — catch \(item.title) here instead.")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color.birthdayPurple)
                            .multilineTextAlignment(.center)
                    }
                    Text(item.title).font(.system(.largeTitle, design: .rounded, weight: .bold))
                    if let resolvedCharacter {
                        HStack(spacing: 8) {
                            Text("\(resolvedCharacter.combatPower) CP")
                            Text("·")
                            Text(resolvedCharacter.rarity.rawValue.capitalized)
                            Text("·")
                            Text(resolvedCharacter.displayType)
                        }
                        .font(.system(.headline, design: .rounded, weight: .bold))
                        .foregroundStyle(Color.birthdayPurple)
                    }
                    Text("Drag the ball, then swipe up to throw")
                        .foregroundStyle(.secondary).multilineTextAlignment(.center)
                    Spacer()
                    ZStack {
                        if resolvedCharacter?.rarity == .rare || resolvedCharacter?.rarity == .legendary {
                            SparkleField().frame(width: 240, height: 220)
                        }
                        encounterArt
                            .scaleEffect(struck ? 0.08 : (tappedBounce ? 1.08 : 1))
                            .opacity(struck ? 0 : 1)
                            .offset(y: struck || reduceMotion ? 0 : (creatureBounce ? -10 : 5))
                            .animation(reduceMotion ? .linear(duration: 0.12) : .spring(response: 0.28, dampingFraction: 0.72), value: struck)
                            .animation(reduceMotion ? nil : .easeInOut(duration: 1.15).repeatForever(autoreverses: true), value: creatureBounce)
                            .onTapGesture {
                                withAnimation(.spring(duration: 0.28)) { tappedBounce = true }
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.28) {
                                    withAnimation(.spring) { tappedBounce = false }
                                }
                            }
                    }
                    .background {
                        GeometryReader { creature in
                            Color.clear.preference(key: TargetFrameKey.self, value: creature.frame(in: .named("playfield")))
                        }
                    }
                    .accessibilityLabel("\(item.title), capture target")
                    Spacer()
                    if state == .success {
                        Label("Caught!", systemImage: "party.popper.fill")
                            .font(.system(.title, design: .rounded, weight: .bold)).foregroundStyle(Color.mint)
                        Button("Continue") { dismiss() }.buttonStyle(.borderedProminent)
                    } else {
                        BallRestSlot()
                        Button(state == .authorizing ? "Saving…" : "Tap to catch instead") { tapCatch() }
                            .disabled(state == .authorizing || state == .throwing)
                            .accessibilityHint("Accessible alternative to the swipe gesture")
                        TextField("Fallback code if GPS fails", text: $code)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .padding(10)
                            .background(.white, in: RoundedRectangle(cornerRadius: 12))
                        if state == .missed { Text("Almost! Try again, or enter a fallback code.").foregroundStyle(.secondary) }
                    }
                }
                .padding(28)
                if state != .success {
                    ThrowableBall(
                        rest: ballAnchor,
                        playfield: CGRect(origin: .zero, size: proxy.size),
                        target: targetFrame,
                        reduceMotion: reduceMotion,
                        canThrow: state == .aiming || state == .missed,
                        resetToken: ballReset,
                        onLaunch: { state = .throwing },
                        onHit: {
                            struck = true
                            finishThrow(hit: true)
                        },
                        onMiss: {
                            state = .missed
                            UINotificationFeedbackGenerator().notificationOccurred(.warning)
                        }
                    )
                }
            }
            .onAppear {
                creatureBounce = true
                if code.isEmpty { code = fallbackCode ?? resolvedCharacter?.catalog?.fallbackCode ?? "" }
            }
            .onPreferenceChange(TargetFrameKey.self) { targetFrame = $0 }
            .onPreferenceChange(BallAnchorKey.self) { ballAnchor = $0 }
            .coordinateSpace(name: "playfield")
        }
        .background(LinearGradient(colors: [.warmWhite, .skyBlue.opacity(0.25)], startPoint: .top, endPoint: .bottom).ignoresSafeArea())
    }

    @ViewBuilder
    private var encounterArt: some View {
        if let resolvedCharacter, resolvedCharacter.catalog != nil {
            CreaturePoseArt(
                character: resolvedCharacter,
                celebrating: state == .success,
                alert: tappedBounce
            )
            .frame(width: 240, height: 220)
        } else {
            CreaturePlaceholder(name: item.title)
        }
    }

    private func tapCatch() {
        finishThrow(hit: true)
    }

    private func finishThrow(hit: Bool) {
        guard hit else { return }
        guard state != .authorizing else { return }
        state = .authorizing
        Task {
            let saved = await store.complete(
                type: "character", id: item.id, location: currentLocation,
                dwellStartedAt: dwellStartedAt,
                fallbackCode: {
                    let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines)
                    return trimmed.isEmpty ? nil : trimmed
                }()
            )
            withAnimation {
                state = saved ? .success : .missed
                if !saved {
                    struck = false
                    ballReset += 1
                }
            }
            if saved { UINotificationFeedbackGenerator().notificationOccurred(.success) }
        }
    }
}

struct BallAnchorKey: PreferenceKey {
    static let defaultValue: CGPoint = .zero
    static func reduce(value: inout CGPoint, nextValue: () -> CGPoint) { value = nextValue() }
}

struct BallRestSlot: View {
    var body: some View {
        Color.clear
            .frame(width: 92, height: 92)
            .background {
                GeometryReader { slot in
                    let frame = slot.frame(in: .named("playfield"))
                    Color.clear.preference(
                        key: BallAnchorKey.self,
                        value: CGPoint(x: frame.midX, y: frame.midY)
                    )
                }
            }
            .accessibilityHidden(true)
            .allowsHitTesting(false)
    }
}

struct ThrowableBall: View {
    var rest: CGPoint
    var playfield: CGRect
    var target: CGRect
    var reduceMotion: Bool
    var canThrow: Bool
    var resetToken: Int
    var onLaunch: () -> Void
    var onHit: () -> Void
    var onMiss: () -> Void

    private enum Phase {
        case ready, flying, dropping, falling
    }

    @State private var drag: CGSize = .zero
    @State private var phase: Phase = .ready
    @State private var progress: CGFloat = 0
    @State private var arc: CatchPhysics.Arc?
    @State private var impactT: CGFloat?
    @State private var drop: CGFloat = 0
    @State private var fall: CGFloat = 0
    @State private var spin: Double = 0
    @State private var ballScale: CGFloat = 1
    @State private var ballOpacity: Double = 1
    @State private var showImpact = false
    @State private var impactPoint: CGPoint = .zero
    @State private var flightID = 0
    @State private var dragActive = false
    @State private var aimVelocity: CGSize = .zero

    var body: some View {
        ZStack(alignment: .topLeading) {
            flightEffects
            if rest != .zero {
                CaptureOrb()
                    .frame(width: 92, height: 92)
                    .scaleEffect(ballScale)
                    .rotationEffect(.degrees(spin))
                    .opacity(ballOpacity)
                    .offset(x: displayed.x - 46, y: displayed.y - 46)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
            BallTouchCatcher(
                ballCenter: displayed,
                enabled: canThrow && phase == .ready && rest != .zero,
                phaseValue: phase == .ready ? "Ready" : "In flight",
                onChanged: { translation, velocity in
                    guard canThrow, phase == .ready else { return }
                    if !dragActive {
                        dragActive = true
                        flightID += 1
                        ballOpacity = 1
                        ballScale = 1
                    }
                    drag = translation
                    aimVelocity = velocity
                    spin = Double(translation.width) * 0.18
                },
                onEnded: { translation, velocity in
                    dragActive = false
                    aimVelocity = velocity
                    guard canThrow, phase == .ready else { return }
                    release(translation, velocity: velocity)
                }
            )
            .frame(width: max(playfield.width, 1), height: max(playfield.height, 1))
        }
        .onChange(of: resetToken) { _, _ in
            resetToReady()
        }
    }

    private var displayed: CGPoint {
        switch phase {
        case .ready:
            return CGPoint(x: rest.x + drag.width, y: rest.y + drag.height)
        case .flying:
            guard let arc else { return rest }
            return CatchPhysics.point(start: arc.start, control: arc.control, end: arc.end, t: progress)
        case .dropping:
            guard let arc else { return rest }
            let point = CatchPhysics.point(start: arc.start, control: arc.control, end: arc.end, t: impactT ?? progress)
            return CGPoint(x: point.x, y: point.y + drop)
        case .falling:
            guard let arc else { return rest }
            return CGPoint(x: arc.end.x, y: arc.end.y + fall)
        }
    }

    private var flightEffects: some View {
        ZStack(alignment: .topLeading) {
            if let preview = previewArc {
                Path { path in
                    path.move(to: preview.start)
                    for step in 1...16 {
                        let t = CGFloat(step) / 16
                        path.addLine(to: CatchPhysics.point(start: preview.start, control: preview.control, end: preview.end, t: t))
                    }
                }
                .stroke(
                    Color.white.opacity(previewQualifies ? 0.9 : 0.4),
                    style: StrokeStyle(lineWidth: 3, lineCap: .round, dash: [6, 7])
                )
                .shadow(color: .birthdayPurple.opacity(0.8), radius: 2)
            }
            if showImpact {
                ImpactSparks(reduceMotion: reduceMotion)
                    .position(impactPoint)
            }
        }
        .frame(width: max(playfield.width, 1), height: max(playfield.height, 1))
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var previewQualifies: Bool {
        CatchPhysics.qualifies(translation: drag, velocity: aimVelocity)
    }

    private var previewArc: CatchPhysics.Arc? {
        guard phase == .ready, drag.height < -28, rest != .zero, playfield.width > 1 else { return nil }
        let start = CGPoint(x: rest.x + drag.width, y: rest.y + drag.height)
        return CatchPhysics.arc(from: start, translation: drag, velocity: aimVelocity, in: playfield)
    }

    private func release(_ translation: CGSize, velocity: CGSize) {
        guard rest != .zero, playfield.width > 1, CatchPhysics.qualifies(translation: translation, velocity: velocity) else {
            springBack()
            return
        }
        let start = CGPoint(x: rest.x + translation.width, y: rest.y + translation.height)
        let thrown = CatchPhysics.arc(from: start, translation: translation, velocity: velocity, in: playfield)
        let hitT = CatchPhysics.impactProgress(arc: thrown, target: target, ballRadius: 36)
        flightID += 1
        let token = flightID
        arc = thrown
        impactT = hitT
        drag = .zero
        progress = 0
        drop = 0
        fall = 0
        ballScale = 1
        ballOpacity = 1
        phase = .flying
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        onLaunch()
        let travel = hitT ?? 1
        let duration = max((reduceMotion ? 0.16 : thrown.duration) * Double(travel), 0.12)
        let spinStart = spin
        animate(duration: duration, easing: .easeOut, token: token) { amount in
            progress = travel * amount
            spin = spinStart + (reduceMotion ? 0 : 480 * Double(progress))
        } done: {
            guard token == flightID, phase == .flying else { return }
            progress = travel
            if hitT != nil {
                resolveHit(token: token, arc: thrown, t: travel)
            } else {
                resolveMiss(token: token, arc: thrown)
            }
        }
    }

    private func resolveHit(token: Int, arc thrown: CatchPhysics.Arc, t: CGFloat) {
        let point = CatchPhysics.point(start: thrown.start, control: thrown.control, end: thrown.end, t: t)
        impactPoint = point
        showImpact = !reduceMotion
        phase = .dropping
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        onHit()
        let ground = max(48, playfield.maxY + 36 - point.y)
        let spinStart = spin
        animate(duration: reduceMotion ? 0.12 : 0.4, easing: .easeIn, token: token) { amount in
            drop = ground * amount
            ballScale = 1 - 0.38 * amount
            spin = spinStart + (reduceMotion ? 0 : 90 * Double(amount))
        } done: {}
    }

    private func resolveMiss(token: Int, arc thrown: CatchPhysics.Arc) {
        let end = thrown.end
        let alreadyGone = end.y < playfield.minY - 12
            || end.x < playfield.minX - 12
            || end.x > playfield.maxX + 12
        phase = .falling
        let distance = alreadyGone ? 0 : max(90, playfield.maxY + 80 - end.y)
        let spinStart = spin
        animate(duration: reduceMotion ? 0.12 : (alreadyGone ? 0.2 : 0.42), easing: .easeIn, token: token) { amount in
            fall = distance * amount
            ballOpacity = Double(1 - amount)
            spin = spinStart + (reduceMotion ? 0 : 160 * Double(amount))
        } done: {
            guard token == flightID else { return }
            resetToReady()
            ballOpacity = 0
            onMiss()
            animate(duration: reduceMotion ? 0.05 : 0.26, easing: .easeOut, token: flightID) { amount in
                ballOpacity = Double(amount)
            } done: {}
        }
    }

    private func springBack() {
        let token = flightID
        let start = drag
        let startSpin = spin
        animate(duration: reduceMotion ? 0.12 : 0.34, easing: .easeOut, token: token) { amount in
            guard phase == .ready else { return }
            drag = CGSize(width: start.width * (1 - amount), height: start.height * (1 - amount))
            spin = startSpin * (1 - Double(amount))
        } done: {
            guard token == flightID, phase == .ready else { return }
            drag = .zero
            spin = 0
        }
    }

    private func resetToReady() {
        flightID += 1
        phase = .ready
        progress = 0
        drop = 0
        fall = 0
        drag = .zero
        dragActive = false
        aimVelocity = .zero
        arc = nil
        impactT = nil
        showImpact = false
        ballScale = 1
        spin = 0
    }

    private enum FlightEasing {
        case easeOut, easeIn
    }

    private func animate(
        duration: TimeInterval,
        easing: FlightEasing,
        token: Int,
        step: @escaping (CGFloat) -> Void,
        done: @escaping () -> Void
    ) {
        let started = Date()
        Task { @MainActor in
            while true {
                let raw = min(CGFloat(Date().timeIntervalSince(started) / max(duration, 0.01)), 1)
                guard token == flightID else { return }
                let amount: CGFloat
                switch easing {
                case .easeOut:
                    amount = 1 - (1 - raw) * (1 - raw)
                case .easeIn:
                    amount = raw * raw
                }
                step(amount)
                if raw >= 1 { break }
                try? await Task.sleep(nanoseconds: 16_000_000)
            }
            guard token == flightID else { return }
            done()
        }
    }
}

private struct BallTouchCatcher: UIViewRepresentable {
    var ballCenter: CGPoint
    var enabled: Bool
    var phaseValue: String
    var onChanged: (CGSize, CGSize) -> Void
    var onEnded: (CGSize, CGSize) -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> CatcherView {
        let view = CatcherView()
        view.backgroundColor = .clear
        view.isAccessibilityElement = true
        view.accessibilityLabel = "Capture orb"
        view.accessibilityIdentifier = "capture-orb"
        view.accessibilityHint = "Drag to aim, then swipe up to throw. A tap will not throw."
        let pan = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.pan(_:)))
        pan.maximumNumberOfTouches = 1
        view.addGestureRecognizer(pan)
        return view
    }

    func updateUIView(_ uiView: CatcherView, context: Context) {
        uiView.ballCenter = ballCenter
        uiView.touchEnabled = enabled
        uiView.accessibilityValue = phaseValue
        context.coordinator.onChanged = onChanged
        context.coordinator.onEnded = onEnded
    }

    final class Coordinator: NSObject {
        var onChanged: (CGSize, CGSize) -> Void = { _, _ in }
        var onEnded: (CGSize, CGSize) -> Void = { _, _ in }

        @objc func pan(_ gesture: UIPanGestureRecognizer) {
            guard let view = gesture.view else { return }
            let translation = gesture.translation(in: view)
            let velocity = gesture.velocity(in: view)
            let drag = CGSize(width: translation.x, height: translation.y)
            let speed = CGSize(width: velocity.x, height: velocity.y)
            switch gesture.state {
            case .began, .changed:
                onChanged(drag, speed)
            case .ended, .cancelled, .failed:
                onEnded(drag, speed)
            default:
                break
            }
        }
    }

    final class CatcherView: UIView {
        var ballCenter: CGPoint = .zero
        var touchEnabled = true

        override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
            guard touchEnabled else { return false }
            return ballContains(point)
        }

        override var accessibilityFrame: CGRect {
            get {
                convert(CGRect(x: ballCenter.x - 46, y: ballCenter.y - 46, width: 92, height: 92), to: nil)
            }
            set {}
        }

        private func ballContains(_ point: CGPoint) -> Bool {
            let dx = point.x - ballCenter.x
            let dy = point.y - ballCenter.y
            return dx * dx + dy * dy <= 52 * 52
        }
    }
}

private struct ImpactSparks: View {
    var reduceMotion: Bool
    @State private var burst = false

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.golden, lineWidth: 3)
                .frame(width: burst ? 78 : 16, height: burst ? 78 : 16)
                .opacity(burst ? 0 : 0.95)
            ForEach(0..<7, id: \.self) { index in
                Circle()
                    .fill(index.isMultiple(of: 2) ? Color.golden : Color.white)
                    .frame(width: 8, height: 8)
                    .offset(burst ? sparkOffset(index) : .zero)
                    .opacity(burst ? 0 : 1)
            }
        }
        .allowsHitTesting(false)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeOut(duration: 0.4)) { burst = true }
        }
    }

    private func sparkOffset(_ index: Int) -> CGSize {
        let angle = Double(index) / 7 * Double.pi * 2
        return CGSize(width: cos(angle) * 44, height: sin(angle) * 44)
    }
}

private struct TargetFrameKey: PreferenceKey {
    static let defaultValue: CGRect = .zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) { value = nextValue() }
}

private struct CreaturePlaceholder: View {
    let name: String
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 44)
                .fill(LinearGradient(colors: [.golden, .mint], startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: 190, height: 180)
            VStack(spacing: 8) {
                HStack(spacing: 30) {
                    Circle().fill(.black).frame(width: 16, height: 22)
                    Circle().fill(.black).frame(width: 16, height: 22)
                }
                Capsule().fill(.white).frame(width: 50, height: 18)
                Text(name.prefix(1)).font(.system(size: 48, weight: .black, design: .rounded)).foregroundStyle(.white)
            }
        }
        .shadow(color: .birthdayPurple.opacity(0.18), radius: 18, y: 10)
    }
}
