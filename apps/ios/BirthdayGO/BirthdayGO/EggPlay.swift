import SwiftUI

struct EggsInventorySection: View {
    @EnvironmentObject private var store: GameStore

    var body: some View {
        let eggs = store.playerEggs()
        VStack(alignment: .leading, spacing: 12) {
            Text("Cookies")
                .font(.system(.title2, design: .rounded, weight: .bold))
                .padding(.horizontal)
            Text("Incubate one cookie at a time. Steps count after you start, even when Birthday GO is closed.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(.horizontal)
            if eggs.isEmpty {
                Text("No cookies yet. A 1-mile, 10-mile, 26.2-mile, and 100-mile cookie will appear here.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)
            }
            ForEach(eggs, id: \.id) { egg in
                NavigationLink {
                    EggIncubatorView(eggId: egg.id)
                } label: {
                    EggInventoryRow(egg: egg)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

struct EggInventoryRow: View {
    let egg: PlayerEggRecord

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            EggIllustration(style: egg.artworkStyle, progress: egg.progress, compact: true)
                .frame(width: 72, height: 88)
            VStack(alignment: .leading, spacing: 4) {
                Text(egg.typeTitle)
                    .font(.system(.headline, design: .rounded, weight: .bold))
                Text(egg.rarityLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("\(EggDistance.formattedMiles(egg.requiredMeters)) miles to hatch")
                    .font(.subheadline)
                Text(egg.status.title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(egg.status == .ready ? Color.golden : Color.birthdayPurple)
                if egg.status == .incubating || egg.status == .ready {
                    ProgressView(value: egg.progress)
                        .tint(egg.artworkStyle == "gold" ? Color.golden : Color.skyBlue)
                    Text("\(EggDistance.formattedMiles(egg.metersWalked)) / \(EggDistance.formattedMiles(egg.requiredMeters)) miles walked")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                if egg.status == .hatched, let name = egg.rewardName {
                    Text("Hatched \(name)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding()
        .background(.white, in: RoundedRectangle(cornerRadius: 20))
        .padding(.horizontal)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(egg.typeTitle), \(egg.status.title), \(egg.rarityLabel)")
    }
}

struct EggIncubatorView: View {
    let eggId: UUID
    @EnvironmentObject private var store: GameStore
    @EnvironmentObject private var walk: WalkTracker
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showHatch = false

    var body: some View {
        let egg = store.egg(id: eggId)
        ScrollView {
            if let egg {
                VStack(spacing: 22) {
                    EggIllustration(style: egg.artworkStyle, progress: egg.progress, ready: egg.status == .ready)
                        .frame(height: 280)
                        .accessibilityLabel(egg.status == .ready ? "Cookie ready to hatch" : "\(egg.typeTitle) illustration")

                    Text(egg.typeTitle)
                        .font(.system(.largeTitle, design: .rounded, weight: .bold))
                    Text(statusCopy(for: egg))
                        .font(.headline)
                        .multilineTextAlignment(.center)

                    ProgressView(value: egg.progress)
                        .tint(egg.artworkStyle == "gold" ? Color.golden : Color.skyBlue)
                        .padding(.horizontal, 28)
                    Text("\(EggDistance.formattedMiles(egg.metersWalked)) / \(EggDistance.formattedMiles(egg.requiredMeters)) miles walked")
                        .font(.title3.weight(.semibold))
                    if egg.status != .hatched {
                        Text("\(EggDistance.formattedMiles(egg.remainingMeters)) miles until hatching!")
                            .foregroundStyle(.secondary)
                    }
                    Text("\(Int((egg.progress * 100).rounded()))% complete")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    trackingCard(for: egg)
                    actions(for: egg)
                }
                .padding(.vertical, 24)
            } else {
                Text("This cookie is no longer in your inventory.")
                    .foregroundStyle(.secondary)
                    .padding()
            }
        }
        .background(Color.warmWhite)
        .navigationTitle("Incubator")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { store.refreshEggs() }
        .fullScreenCover(isPresented: $showHatch) {
            if let egg = store.egg(id: eggId) {
                EggHatchView(egg: egg, reduceMotion: reduceMotion)
            }
        }
    }

    private func statusCopy(for egg: PlayerEggRecord) -> String {
        switch egg.status {
        case .available: "Select this cookie and start incubating to count your steps."
        case .incubating: walk.status == .paused
            ? (walk.pauseReason ?? "Walking is paused.")
            : "Steps count even when Birthday GO is closed."
        case .ready: "Your cookie is ready!"
        case .hatched: "Already hatched\(egg.rewardName.map { " into \($0)" } ?? "")."
        }
    }

    @ViewBuilder
    private func trackingCard(for egg: PlayerEggRecord) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(walk.status.title, systemImage: egg.status == .incubating ? "figure.walk" : "birthday.cake.fill")
                .font(.headline)
            Text(walk.activityLabel)
                .font(.subheadline)
            Text("Steps are recorded by your iPhone after you start incubating, including while Birthday GO is closed. Open the app to see the cookie catch up. Car and subway rides are not steps, so they do not count.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            if let reason = walk.pauseReason, egg.status == .incubating {
                Text(reason).font(.footnote).foregroundStyle(Color.birthdayPurple)
            }
            if walk.status == .denied {
                Text("Motion & Fitness is off. Birthday GO needs it to count steps toward this cookie.")
                    .font(.footnote)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white, in: RoundedRectangle(cornerRadius: 18))
        .padding(.horizontal)
    }

    @ViewBuilder
    private func actions(for egg: PlayerEggRecord) -> some View {
        VStack(spacing: 12) {
            if egg.status == .available {
                Button("Start Incubating") {
                    store.startIncubating(eggId: egg.id)
                }
                .buttonStyle(.borderedProminent)
                .disabled(store.activeIncubation() != nil)
                if store.activeIncubation() != nil {
                    Text("Only one cookie can incubate at a time.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            if egg.status == .incubating {
                if walk.status == .tracking {
                    Button("Pause walking") { store.pauseIncubation() }
                        .buttonStyle(.bordered)
                } else {
                    Button("Resume walking") { store.resumeIncubation() }
                        .buttonStyle(.borderedProminent)
                }
            }
            if egg.status == .ready {
                Button("Hatch your cookie") { showHatch = true }
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(.horizontal)
    }
}

struct EggHatchView: View {
    let egg: PlayerEggRecord
    var reduceMotion: Bool
    @EnvironmentObject private var store: GameStore
    @Environment(\.dismiss) private var dismiss
    @State private var phase = 0
    @State private var result: GameStore.HatchPresentation?
    @State private var skipped = false

    var body: some View {
        ZStack {
            LinearGradient(colors: egg.artworkStyle == "gold" ? [.birthdayPurple, .golden] : [.skyBlue, .birthdayPurple], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
            VStack(spacing: 24) {
                if result == nil && !reduceMotion && !skipped && phase < 3 {
                    EggIllustration(style: egg.artworkStyle, progress: 1, ready: true, shaking: phase > 0, cracked: phase > 1)
                        .frame(height: 280)
                    Text(phase == 0 ? "Something is stirring…" : phase == 1 ? "The cookie is cracking!" : "Almost there!")
                        .font(.system(.title2, design: .rounded, weight: .bold))
                        .foregroundStyle(.white)
                    Button("Skip animation") { skipped = true; reveal() }
                        .foregroundStyle(.white)
                } else if let result {
                    revealCard(result)
                } else {
                    ProgressView().tint(.white)
                }
            }
            .padding()
        }
        .onAppear {
            if reduceMotion || skipped {
                reveal()
            } else {
                animateThenReveal()
            }
        }
        .accessibilityAddTraits(.isModal)
    }

    private func animateThenReveal() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { phase = 1 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { phase = 2 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.6) { reveal() }
    }

    private func reveal() {
        guard result == nil else { return }
        result = store.hatch(eggId: egg.id)
        phase = 3
    }

    @ViewBuilder
    private func revealCard(_ presentation: GameStore.HatchPresentation) -> some View {
        VStack(spacing: 16) {
            if case .character(let character, _) = presentation {
                CreatureArtwork(character: character, pose: .caught)
                    .frame(height: 180)
                Text(character.name)
                    .font(.system(.largeTitle, design: .rounded, weight: .bold))
                Text(character.rarity.rawValue.capitalized)
                    .font(.headline)
                Text(character.description ?? "")
                    .multilineTextAlignment(.center)
            } else if case .duplicate(let xp) = presentation {
                Image(systemName: "sparkles")
                    .font(.system(size: 64))
                Text("Already in your FriendDex")
                    .font(.title2.bold())
                Text("This hatch granted \(xp) bonus XP instead of a duplicate character.")
                    .multilineTextAlignment(.center)
            }
            if presentation.xp > 0 {
                Text("+\(presentation.xp) XP")
                    .font(.title3.weight(.bold))
            }
            Button("Add to the adventure") { dismiss() }
                .buttonStyle(.borderedProminent)
                .tint(.white)
                .foregroundStyle(Color.birthdayPurple)
        }
        .padding(24)
        .background(.white, in: RoundedRectangle(cornerRadius: 28))
    }
}

struct EggReadyBanner: View {
    @EnvironmentObject private var store: GameStore

    var body: some View {
        if let banner = store.eggReadyBanner {
            Text(banner)
                .font(.system(.subheadline, design: .rounded, weight: .bold))
                .multilineTextAlignment(.center)
                .padding(14)
                .frame(maxWidth: .infinity)
                .background(Color.skyBlue, in: RoundedRectangle(cornerRadius: 18))
                .padding()
                .transition(.move(edge: .top).combined(with: .opacity))
                .onAppear {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
                        if store.eggReadyBanner == banner { store.eggReadyBanner = nil }
                    }
                }
                .accessibilityAddTraits(.isStaticText)
        }
    }
}

struct EggIllustration: View {
    var style: String
    var progress: Double = 0
    var ready = false
    var shaking = false
    var cracked = false
    var compact = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: reduceMotion ? 1 : 0.08, paused: reduceMotion || !shaking)) { timeline in
            let wiggle = reduceMotion || !shaking ? 0.0 : sin(timeline.date.timeIntervalSinceReferenceDate * 14) * 8
            ZStack {
                if style == "gold" || style == "marathon" || style == "century", !compact {
                    Circle()
                        .fill(Color.golden.opacity(ready ? 0.45 : 0.22))
                        .blur(radius: 18)
                        .scaleEffect(ready ? 1.15 : 1)
                }
                cookieShape
                    .rotationEffect(.degrees(wiggle))
                if cracked {
                    crackMarks.rotationEffect(.degrees(wiggle))
                }
            }
        }
        .accessibilityHidden(true)
    }

    private var cookieShape: some View {
        let chip: CGFloat = compact ? 7 : 16
        return ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: shellColors,
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    Circle().stroke(.white.opacity(0.35), lineWidth: compact ? 2 : 4)
                )
                .shadow(color: shellShadow.opacity(0.35), radius: ready ? 16 : 8, y: 6)
            ForEach(Array(chipOffsets.enumerated()), id: \.offset) { _, spot in
                Circle()
                    .fill(chipColor)
                    .frame(width: chip, height: chip)
                    .offset(x: spot.width, y: spot.height)
            }
        }
        .aspectRatio(1, contentMode: .fit)
    }

    private var chipOffsets: [CGSize] {
        let scale: CGFloat = compact ? 0.42 : 1
        return [
            CGSize(width: -28, height: -22),
            CGSize(width: 18, height: -30),
            CGSize(width: 30, height: 4),
            CGSize(width: -6, height: 6),
            CGSize(width: -30, height: 24),
            CGSize(width: 12, height: 32),
        ].map { CGSize(width: $0.width * scale, height: $0.height * scale) }
    }

    private var chipColor: Color {
        switch style {
        case "gold", "century": Color(red: 0.98, green: 0.86, blue: 0.45)
        default: Color(red: 0.28, green: 0.16, blue: 0.08)
        }
    }

    private var shellColors: [Color] {
        switch style {
        case "gold":
            [Color(red: 0.93, green: 0.72, blue: 0.32), Color.golden]
        case "marathon":
            [Color(red: 0.78, green: 0.46, blue: 0.24), Color(red: 0.95, green: 0.62, blue: 0.32)]
        case "century":
            [Color(red: 0.32, green: 0.18, blue: 0.10), Color(red: 0.62, green: 0.38, blue: 0.16)]
        default:
            [Color(red: 0.95, green: 0.76, blue: 0.46), Color(red: 0.76, green: 0.48, blue: 0.22)]
        }
    }

    private var shellShadow: Color {
        switch style {
        case "gold", "century": .birthdayPurple
        case "marathon": Color(red: 0.95, green: 0.55, blue: 0.25)
        default: .skyBlue
        }
    }

    private var crackMarks: some View {
        Path { path in
            path.move(to: CGPoint(x: 40, y: 8))
            path.addLine(to: CGPoint(x: 48, y: 36))
            path.addLine(to: CGPoint(x: 32, y: 58))
            path.addLine(to: CGPoint(x: 50, y: 90))
        }
        .stroke(.white, style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
        .frame(width: 80, height: 110)
    }
}
