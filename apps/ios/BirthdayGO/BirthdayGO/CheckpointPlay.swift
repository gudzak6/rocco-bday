import SwiftUI
import CoreLocation
import UIKit

struct MemoryStopView: View {
    @EnvironmentObject private var store: GameStore
    @EnvironmentObject private var location: LocationService
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let checkpoint: CheckpointCatalog.Entry
    let currentLocation: CLLocation?
    let dwellStartedAt: Date
    let fallbackCode: String?
    var onClose: (() -> Void)? = nil

    @State private var angle = 0.0
    @State private var dragging = false
    @State private var dragOriginAngle = 0.0
    @State private var coastStartAngle = 0.0
    @State private var coastVelocity = 0.0
    @State private var coastFriction = MemoryStopSpin.friction
    @State private var coastStartedAt: Date?
    @State private var coastGeneration = 0
    @State private var awardInFlight = false
    @State private var showBurst = false
    @State private var showXP = false
    @State private var confirmed = false
    @State private var previousGPS: MemoryStopBand?
    @State private var spinGlow = false

    var body: some View {
        ZStack(alignment: .top) {
            LinearGradient(colors: [.warmWhite, Color.skyBlue.opacity(0.28), .warmWhite], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
            if showBurst && !reduceMotion {
                ConfettiBurst().ignoresSafeArea()
            }
            GeometryReader { screen in
                let diameter = min(screen.size.width * 0.70, max(180, screen.size.height * 0.46))
                ScrollView {
                    VStack(spacing: 18) {
                        Text(checkpoint.title)
                            .font(.system(.largeTitle, design: .rounded, weight: .bold))
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.primary)
                            .minimumScaleFactor(0.7)
                        TimelineView(.animation(minimumInterval: reduceMotion ? 1 : 1.0 / 60.0, paused: coastStartedAt == nil || reduceMotion)) { timeline in
                            disc(diameter: diameter, at: timeline.date)
                        }
                        Text(checkpoint.message.body)
                            .font(.body)
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.primary)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(instruction)
                            .font(.subheadline.weight(.semibold))
                            .multilineTextAlignment(.center)
                            .foregroundStyle(Color.birthdayPurple)
                        if confirmed {
                            Text("Memory Collected")
                                .font(.system(.title2, design: .rounded, weight: .bold))
                                .foregroundStyle(Color.birthdayPurple)
                            Text(rewardCopy)
                                .font(.subheadline)
                                .multilineTextAlignment(.center)
                                .foregroundStyle(.secondary)
                            Button("Back to map") { close() }
                                .buttonStyle(.borderedProminent)
                                .controlSize(.large)
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 64)
                    .padding(.bottom, 24)
                    .frame(maxWidth: .infinity)
                    .overlay(alignment: .center) {
                        if showXP {
                            Text("+\(checkpoint.checkpointXP) XP")
                                .font(.system(.title, design: .rounded, weight: .black))
                                .foregroundStyle(Color.golden)
                                .shadow(color: .black.opacity(0.15), radius: 4, y: 2)
                                .offset(y: showXP ? -diameter * 0.15 : 12)
                                .transition(.move(edge: .bottom).combined(with: .opacity))
                        }
                    }
                }
            }
            HStack {
                Spacer()
                Button {
                    close()
                } label: {
                    Image(systemName: "xmark")
                        .font(.headline.weight(.bold))
                        .foregroundStyle(Color.birthdayPurple)
                        .padding(10)
                        .background(.white.opacity(0.9), in: Circle())
                }
                .accessibilityLabel("Close")
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
        }
        .interactiveDismissDisabled()
        .onAppear {
            if let snapshot = store.snapshot, checkpoint.isComplete(snapshot) {
                confirmed = true
            }
            updateGPSBand()
        }
        .onChange(of: location.location?.timestamp) { _, _ in
            updateGPSBand()
        }
    }

    private func disc(diameter: CGFloat, at date: Date) -> some View {
        let rotation = displayedAngle(at: date)
        let coasting = coastStartedAt != nil
        return ZStack {
            Circle()
                .fill(Color.skyBlue.opacity(spinGlow ? 0.45 : 0.22))
                .frame(width: diameter * 1.08, height: diameter * 1.08)
                .blur(radius: coasting && !reduceMotion ? 16 : 8)
            ZStack {
                Circle()
                    .strokeBorder(
                        AngularGradient(
                            colors: [Color.skyBlue, .white, Color.birthdayPurple.opacity(0.8), Color.skyBlue],
                            center: .center
                        ),
                        lineWidth: max(10, diameter * 0.045)
                    )
                Circle()
                    .stroke(.white.opacity(0.85), lineWidth: 3)
                    .padding(max(12, diameter * 0.05))
                discImage
                    .frame(width: diameter * 0.78, height: diameter * 0.78)
                    .clipped()
                    .clipShape(Circle())
            }
            .frame(width: diameter, height: diameter)
            .rotationEffect(.degrees(rotation))
            .shadow(color: Color.skyBlue.opacity(0.55), radius: coasting ? 22 : 10, y: 6)
        }
        .frame(width: diameter, height: diameter)
        .contentShape(Circle())
        .highPriorityGesture(spinGesture)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(checkpoint.title) photo disc")
        .accessibilityHint("Swipe horizontally to spin. A tap will not collect this memory.")
        .accessibilityAddTraits(.isImage)
    }

    @ViewBuilder
    private var discImage: some View {
        if let name = MemoryStopArtwork.assetName(for: checkpoint.title) {
            Image(name)
                .resizable()
                .scaledToFill()
        } else {
            Circle().fill(Color.skyBlue.opacity(0.35))
            Image(systemName: checkpoint.markerSymbol)
                .font(.system(size: 48, weight: .bold))
                .foregroundStyle(.white)
        }
    }

    private var spinGesture: some Gesture {
        DragGesture(minimumDistance: 8)
            .onChanged { value in
                let horizontal = abs(value.translation.width) >= abs(value.translation.height)
                guard horizontal || dragging else { return }
                if !dragging {
                    dragging = true
                    coastGeneration += 1
                    dragOriginAngle = displayedAngle(at: .now)
                    coastStartedAt = nil
                    coastVelocity = 0
                }
                angle = dragOriginAngle + Double(value.translation.width) * MemoryStopSpin.degreesPerPoint
            }
            .onEnded { value in
                let releasedAngle = dragging ? angle : displayedAngle(at: .now)
                dragging = false
                guard MemoryStopSpin.qualifies(translationWidth: value.translation.width, translationHeight: value.translation.height) else { return }
                coastFriction = reduceMotion ? 8 : MemoryStopSpin.friction
                coastVelocity = MemoryStopSpin.releaseVelocity(
                    pointsPerSecond: value.velocity.width,
                    translationWidth: value.translation.width
                )
                let duration = MemoryStopSpin.settleDuration(velocity: coastVelocity, friction: coastFriction)
                let settled = MemoryStopSpin.angle(
                    startAngle: releasedAngle,
                    velocity: coastVelocity,
                    friction: coastFriction,
                    elapsed: duration
                )
                spinGlow = true
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                coastGeneration += 1
                let generation = coastGeneration
                if reduceMotion {
                    withAnimation(.linear(duration: 0.2)) { angle = settled }
                    coastStartedAt = nil
                } else {
                    coastStartAngle = releasedAngle
                    coastStartedAt = .now
                    angle = releasedAngle
                    Task { @MainActor in
                        try? await Task.sleep(for: .seconds(duration))
                        guard generation == coastGeneration, !dragging else { return }
                        angle = settled
                        coastStartedAt = nil
                        coastVelocity = 0
                        spinGlow = false
                    }
                }
                if MemoryStopAward.shouldAward(
                    gestureQualified: true,
                    gpsInRange: gpsBand == .inRange,
                    alreadyComplete: alreadyComplete,
                    awardInFlight: awardInFlight
                ) {
                    beginAward()
                }
            }
    }

    private func displayedAngle(at date: Date) -> Double {
        if dragging { return angle }
        guard let coastStartedAt else { return angle }
        return MemoryStopSpin.angle(
            startAngle: coastStartAngle,
            velocity: coastVelocity,
            friction: coastFriction,
            elapsed: date.timeIntervalSince(coastStartedAt)
        )
    }

    private var alreadyComplete: Bool {
        if confirmed { return true }
        guard let snapshot = store.snapshot else { return false }
        return checkpoint.isComplete(snapshot)
    }

    private var gpsBand: MemoryStopBand {
        let reading = gpsReading
        return MemoryStopProximity.band(
            collected: alreadyComplete,
            distance: reading.distance,
            accuracy: reading.accuracy,
            maximumAccuracy: reading.maximum,
            previous: previousGPS
        )
    }

    private var instruction: String {
        if alreadyComplete {
            return "Already collected. Swipe the disc to spin it again."
        }
        if location.location == nil && currentLocation == nil {
            return "Location is unavailable, so this memory cannot be collected yet."
        }
        switch gpsBand {
        case .inRange:
            return "Swipe across the disc to collect this memory."
        case .nearby:
            return "Walk within 50 meters, then swipe the disc."
        case .distant, .collected:
            return "This memory is still out of range."
        }
    }

    private var rewardCopy: String {
        var parts = ["Saved to your adventure."]
        if let souvenir = checkpoint.souvenir {
            parts.append("You collected \(souvenir.name).")
        }
        if checkpoint.unlocksCharacterOnVisit, let name = checkpoint.characters.first?.name {
            parts.append("\(name) joined FriendDex.")
        }
        return parts.joined(separator: " ")
    }

    private var gpsReading: (distance: Double?, accuracy: Double?, maximum: Double) {
        let place = store.snapshot?.locations.first { $0.id == checkpoint.locationId }
        let maximum = Double(place?.maxAccuracyMeters ?? 250)
        let current = location.location ?? currentLocation
        guard let current else { return (nil, nil, maximum) }
        let distance = Proximity.distanceMeters(
            latitude: current.coordinate.latitude,
            longitude: current.coordinate.longitude,
            targetLatitude: place?.latitude ?? checkpoint.latitude,
            targetLongitude: place?.longitude ?? checkpoint.longitude
        )
        let accuracy = current.horizontalAccuracy > 0 ? current.horizontalAccuracy : nil
        return (distance, accuracy, maximum)
    }

    private func updateGPSBand() {
        let reading = gpsReading
        previousGPS = MemoryStopProximity.band(
            collected: alreadyComplete,
            distance: reading.distance,
            accuracy: reading.accuracy,
            maximumAccuracy: reading.maximum,
            previous: previousGPS
        )
    }

    private func close() {
        if let onClose {
            onClose()
        } else {
            dismiss()
        }
    }

    private func beginAward() {
        guard MemoryStopAward.shouldAward(
            gestureQualified: true,
            gpsInRange: gpsBand == .inRange,
            alreadyComplete: alreadyComplete,
            awardInFlight: awardInFlight
        ) else { return }
        awardInFlight = true
        showBurst = true
        withAnimation(reduceMotion ? .linear(duration: 0.01) : .spring(duration: 0.45)) {
            showXP = true
            confirmed = true
        }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        let playerLocation = location.location ?? currentLocation
        Task { @MainActor in
            let saved = await store.completeCheckpoint(
                checkpoint,
                currentLocation: playerLocation,
                dwellStartedAt: dwellStartedAt,
                fallbackCode: fallbackCode
            )
            let complete = store.snapshot.map { checkpoint.isComplete($0) } == true
            if !saved && !complete {
                awardInFlight = false
                showBurst = false
                showXP = false
                confirmed = false
            }
        }
    }
}

struct StandardMemoryStopMarker: View {
    let band: MemoryStopBand
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var onScreen = false

    var body: some View {
        TimelineView(.animation(minimumInterval: reduceMotion ? 1 : 1.0 / 30.0, paused: reduceMotion || !onScreen)) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate
            let spin = reduceMotion ? 32.0 : time.truncatingRemainder(dividingBy: 10) / 10 * 360
            let floatY = reduceMotion ? 0.0 : sin(time * 1.7) * 4
            let glow = reduceMotion ? 0.5 : 0.35 + 0.4 * (0.5 + 0.5 * sin(time * 2.3))
            marker(spin: spin, floatY: floatY, glow: glow)
        }
        .onAppear { onScreen = true }
        .onDisappear { onScreen = false }
        .accessibilityHidden(true)
        .animation(.easeInOut(duration: reduceMotion ? 0.01 : 0.45), value: band)
    }

    private func marker(spin: Double, floatY: CGFloat, glow: Double) -> some View {
        ZStack(alignment: .bottom) {
            Capsule()
                .fill(
                    LinearGradient(
                        colors: [tint.opacity(0.02), tint.opacity(band == .distant ? 0.28 : 0.55)],
                        startPoint: .bottom,
                        endPoint: .top
                    )
                )
                .frame(width: band == .inRange ? 8 : 5, height: crystal * 1.35)
                .blur(radius: 0.4)
                .padding(.bottom, 10)
            Ellipse()
                .fill(tint.opacity(0.28 + glow * 0.35))
                .frame(width: crystal * 1.35, height: 16)
                .blur(radius: 1.5)
                .overlay {
                    Ellipse()
                        .stroke(tint.opacity(0.75), lineWidth: 2)
                }
            if showsRing {
                Circle()
                    .stroke(tint.opacity(0.9), lineWidth: band == .inRange ? 3 : 2)
                    .frame(width: crystal * 1.85, height: crystal * 1.85)
                    .padding(.bottom, crystal * 0.55)
            }
            MemoryStopCrystal(spin: spin, size: crystal, tint: tint)
                .frame(width: crystal * 1.9, height: crystal * 1.9)
                .offset(y: floatY - crystal * 0.85)
            if band == .inRange && !reduceMotion && onScreen {
                MemoryStopParticles(color: tint)
                    .frame(width: crystal * 2.1, height: crystal * 2.1)
                    .offset(y: -crystal * 0.7)
                    .allowsHitTesting(false)
            }
        }
        .frame(width: 88, height: 108, alignment: .bottom)
    }

    private var crystal: CGFloat {
        switch band {
        case .distant: 26
        case .nearby: 34
        case .inRange: 44
        case .collected: 34
        }
    }

    private var tint: Color {
        band == .collected ? .birthdayPurple : .skyBlue
    }

    private var showsRing: Bool {
        band == .nearby || band == .inRange
    }
}

private struct MemoryStopCrystal: View {
    var spin: Double
    var size: CGFloat
    var tint: Color

    var body: some View {
        Canvas { context, canvas in
            let yaw = CGFloat(spin) * .pi / 180
            let pitch: CGFloat = 0.46
            let half = size * 0.5
            let origin = CGPoint(x: canvas.width / 2, y: canvas.height * 0.58)
            func project(_ x: CGFloat, _ y: CGFloat, _ z: CGFloat) -> (CGPoint, CGFloat) {
                let xr = x * cos(yaw) + z * sin(yaw)
                let zr = -x * sin(yaw) + z * cos(yaw)
                let yr = y * cos(pitch) - zr * sin(pitch)
                let depth = y * sin(pitch) + zr * cos(pitch)
                let perspective = 2.6 / (2.6 + depth / max(half, 1))
                return (CGPoint(x: origin.x + xr * perspective, y: origin.y - yr * perspective), depth)
            }
            let corners: [(CGFloat, CGFloat, CGFloat)] = [
                (-half, -half, -half), (half, -half, -half), (half, half, -half), (-half, half, -half),
                (-half, -half, half), (half, -half, half), (half, half, half), (-half, half, half),
            ]
            let projected = corners.map { project($0.0, $0.1, $0.2) }
            let faces = [
                [4, 5, 6, 7], [1, 0, 3, 2], [0, 4, 7, 3], [5, 1, 2, 6], [3, 2, 6, 7], [0, 1, 5, 4],
            ]
            let normals: [(CGFloat, CGFloat, CGFloat)] = [
                (0, 0, 1), (0, 0, -1), (-1, 0, 0), (1, 0, 0), (0, 1, 0), (0, -1, 0),
            ]
            let light = (CGFloat(0.25), CGFloat(0.82), CGFloat(0.4))
            var draw: [(path: Path, depth: CGFloat, shade: CGFloat)] = []
            for index in faces.indices {
                let indices = faces[index]
                var path = Path()
                path.move(to: projected[indices[0]].0)
                for point in indices.dropFirst() {
                    path.addLine(to: projected[point].0)
                }
                path.closeSubpath()
                let depth = indices.reduce(CGFloat(0)) { $0 + projected[$1].1 } / CGFloat(indices.count)
                let normal = normals[index]
                let nx = normal.0 * cos(yaw) + normal.2 * sin(yaw)
                let nz = -normal.0 * sin(yaw) + normal.2 * cos(yaw)
                let ny = normal.1 * cos(pitch) - nz * sin(pitch)
                let nz2 = normal.1 * sin(pitch) + nz * cos(pitch)
                let shade = max(0.22, nx * light.0 + ny * light.1 + nz2 * light.2)
                draw.append((path, depth, shade))
            }
            for face in draw.sorted(by: { $0.depth > $1.depth }) {
                context.fill(face.path, with: .color(tint.opacity(0.28 + 0.62 * face.shade)))
                context.stroke(face.path, with: .color(.white.opacity(0.55)), lineWidth: 1)
            }
        }
        .allowsHitTesting(false)
    }
}

private struct MemoryStopParticles: View {
    var color: Color

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
            Canvas { context, size in
                let time = timeline.date.timeIntervalSinceReferenceDate
                for index in 0..<7 {
                    let seed = Double(index)
                    let angle = seed / 7 * .pi * 2 + time * 0.9
                    let radius = size.width * (0.28 + 0.08 * sin(time * 1.5 + seed))
                    let point = CGPoint(
                        x: size.width / 2 + CGFloat(cos(angle) * radius),
                        y: size.height / 2 + CGFloat(sin(angle) * radius * 0.72)
                    )
                    let rect = CGRect(x: point.x, y: point.y, width: 3.5, height: 3.5)
                    context.fill(Path(ellipseIn: rect), with: .color(color.opacity(0.85)))
                }
            }
        }
        .accessibilityHidden(true)
    }
}

struct MultiCatchView: View {
    @EnvironmentObject private var store: GameStore
    @Environment(\.dismiss) private var dismiss
    let checkpoint: CheckpointCatalog.Entry
    let currentLocation: CLLocation?
    let dwellStartedAt: Date
    let fallbackCode: String?
    @State private var selected: Character?

    private var characters: [Character] {
        (store.snapshot?.characters ?? []).filter { character in
            checkpoint.characters.contains { $0.id == character.id || $0.name == character.name }
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Text(checkpoint.title)
                    .font(.system(.title, design: .rounded, weight: .bold))
                Text("Special encounter · catch everyone here")
                    .foregroundStyle(.secondary)
                ForEach(characters) { character in
                    Button {
                        selected = character
                    } label: {
                        HStack {
                            CreatureArtwork(character: character, silhouette: !character.captured)
                                .frame(width: 54, height: 54)
                            VStack(alignment: .leading) {
                                Text(character.name).font(.headline)
                                Text(character.captured ? "Caught" : "+\(character.xpValue) XP")
                                    .font(.caption)
                                    .foregroundStyle(character.captured ? Color.mint : .secondary)
                            }
                            Spacer()
                            Image(systemName: character.captured ? "checkmark.seal.fill" : "camera.viewfinder")
                                .foregroundStyle(character.captured ? Color.mint : Color.birthdayPurple)
                        }
                        .padding()
                        .background(.white, in: RoundedRectangle(cornerRadius: 18))
                    }
                    .buttonStyle(.plain)
                    .disabled(character.captured)
                }
                Spacer()
                Button("Done") { dismiss() }.buttonStyle(.borderedProminent)
            }
            .padding()
            .background(Color.warmWhite.ignoresSafeArea())
            .navigationTitle("Special encounter")
            .navigationBarTitleDisplayMode(.inline)
            .fullScreenCover(item: $selected) { character in
                EncounterView(
                    item: MapContentItem(
                        id: character.id, locationId: character.locationId, title: character.name,
                        kind: .character, completed: character.captured, immediate: false, category: character.category
                    ),
                    character: character,
                    currentLocation: currentLocation,
                    dwellStartedAt: dwellStartedAt,
                    fallbackCode: fallbackCode
                )
            }
        }
    }
}

struct CheckpointMarker: View {
    let checkpoint: CheckpointCatalog.Entry
    var status: MarkerStatus = .locked

    var body: some View {
        ZStack {
            if !checkpointComplete && (status == .available || status == .nearby) {
                PulseRing(color: color)
                    .frame(width: 54, height: 54)
            }
            Image(systemName: status == .completed ? "checkmark.circle.fill" : checkpoint.markerSymbol)
                .font(.title2.bold())
                .foregroundStyle(status == .completed ? Color.mint : color)
                .padding(10)
                .background(.white, in: Circle())
                .shadow(color: color.opacity(0.35), radius: 6, y: 2)
                .opacity(status == .locked ? 0.55 : 1)
        }
        .accessibilityHidden(true)
    }

    private var checkpointComplete: Bool {
        status == .completed
    }

    private var color: Color {
        switch checkpoint.kind {
        case .memoryStop: .golden
        case .wildEncounter: .birthdayPurple
        case .specialEncounter: .skyBlue
        case .travelStop: .skyBlue
        }
    }
}

struct TravelStopView: View {
    @EnvironmentObject private var store: GameStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let checkpoint: CheckpointCatalog.Entry
    let currentLocation: CLLocation?
    let dwellStartedAt: Date
    let fallbackCode: String?

    @State private var saving = false
    @State private var celebrated = false

    var body: some View {
        ZStack {
            LinearGradient(colors: [.warmWhite, .skyBlue.opacity(0.35), .birthdayPurple.opacity(0.15)], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
            if celebrated { ConfettiBurst().ignoresSafeArea() }
            VStack(spacing: 20) {
                Image(systemName: celebrated ? "checkmark.seal.fill" : "airplane.departure")
                    .font(.system(size: 64, weight: .bold))
                    .foregroundStyle(celebrated ? Color.mint : Color.skyBlue)
                    .scaleEffect(celebrated && !reduceMotion ? 1.12 : 1)
                Text(checkpoint.title)
                    .font(.system(.title, design: .rounded, weight: .bold))
                    .multilineTextAlignment(.center)
                if let code = checkpoint.airportCode {
                    Text(code)
                        .font(.system(.title2, design: .rounded, weight: .heavy))
                        .foregroundStyle(Color.skyBlue)
                }
                Text("Travel Stop · +100 XP")
                    .font(.headline)
                    .foregroundStyle(Color.birthdayPurple)
                if let souvenir = checkpoint.souvenir {
                    Label(souvenir.name, systemImage: souvenir.symbol)
                        .font(.title3.weight(.semibold))
                }
                Text(celebrated
                     ? "Checked in. \(checkpoint.souvenir?.name ?? "This collectible") is in your Travel Collection."
                     : checkpoint.hint)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)
                if celebrated {
                    Button("Done") { dismiss() }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                } else {
                    Button(saving ? "Saving…" : "Check in") {
                        Task { await checkIn() }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(saving)
                }
            }
            .padding(28)
        }
        .onAppear {
            if store.snapshot.map(checkpoint.isComplete) == true {
                celebrated = true
            }
        }
    }

    private func checkIn() async {
        saving = true
        let saved = await store.completeCheckpoint(
            checkpoint,
            currentLocation: currentLocation,
            dwellStartedAt: dwellStartedAt,
            fallbackCode: fallbackCode
        )
        saving = false
        if saved || store.snapshot.map(checkpoint.isComplete) == true {
            withAnimation(reduceMotion ? .none : .spring) { celebrated = true }
        }
    }
}
