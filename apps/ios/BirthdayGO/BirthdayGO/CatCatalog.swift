import Foundation
import SwiftData
import SwiftUI
import UIKit
import CoreLocation

enum DeveloperMode {
    static let defaultsKey = "developerMode"

    static var isEnabled: Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("-developer-mode")
            || UserDefaults.standard.bool(forKey: defaultsKey)
        #else
        false
        #endif
    }
}

@Model
final class CapturedCreature {
    @Attribute(.unique) var characterId: UUID
    var name: String
    var capturedAt: Date

    init(characterId: UUID, name: String, capturedAt: Date = .now) {
        self.characterId = characterId
        self.name = name
        self.capturedAt = capturedAt
    }
}

enum CatCatalog {
    struct Entry: Identifiable, Sendable {
        let id: UUID
        let locationId: UUID
        let name: String
        let rarity: CharacterRarity
        let combatPower: Int
        let type: String
        let ability: String
        let description: String
        let personality: String
        let category: String
        let locationTitle: String
        let hint: String
        let fallbackCode: String
        let idleAsset: String
        let iconAsset: String
        let mapAsset: String
        let caughtAsset: String
        let lookAsset: String
        let blinkAsset: String?
        let alertAsset: String?
        let playfulAsset: String?
        let rollAsset: String?
        /// Edit these to move the encounter on the map.
        var latitude: Double
        var longitude: Double
        let radiusMeters: Int
        let sortOrder: Int
    }

    enum Pose: String, Sendable {
        case idle, icon, map, caught, look, blink, alert, playful, roll
    }

    /// Mock player coordinate used in developer mode / Simulator.
    static let mockPlayerLocation = CLLocationCoordinate2D(latitude: 40.7720308, longitude: -73.9543142)

    static var entries: [Entry] {
        [
            Entry(
                id: UUID(uuidString: "8F1A2C10-0001-4000-8000-000000000001")!,
                locationId: UUID(uuidString: "8F1A2C10-1001-4000-8000-000000000001")!,
                name: "Chair Cat",
                rarity: .common,
                combatPower: 324,
                type: "Cozy",
                ability: "Perfect Loaf",
                description: "A professional napper who has mastered the art of occupying office chairs. Rarely moves, but always watches.",
                personality: "Still, loyal, and quietly in charge of the chair.",
                category: "friend",
                locationTitle: "The office chair",
                hint: "Look for the loaf who claimed the best seat.",
                fallbackCode: "chaircat",
                idleAsset: "ChairCatIdle",
                iconAsset: "ChairCatIcon",
                mapAsset: "ChairCatMap",
                caughtAsset: "ChairCatCaught",
                lookAsset: "ChairCatLook",
                blinkAsset: "ChairCatBlink",
                alertAsset: "ChairCatAlert",
                playfulAsset: nil,
                rollAsset: nil,
                latitude: 40.7710274,
                longitude: -73.9539757,
                radiusMeters: 50,
                sortOrder: 10
            ),
            Entry(
                id: UUID(uuidString: "8F1A2C10-0002-4000-8000-000000000002")!,
                locationId: UUID(uuidString: "8F1A2C10-1002-4000-8000-000000000002")!,
                name: "Rug Cat",
                rarity: .rare,
                combatPower: 512,
                type: "Playful",
                ability: "Treat Magnet",
                description: "A mischievous rug guardian who loves attention and has perfected the dramatic over-the-shoulder stare.",
                personality: "Dramatic, social, and always angling for one more treat.",
                category: "inside_joke",
                locationTitle: "The living-room rug",
                hint: "Follow the stare from the rug.",
                fallbackCode: "rugcat",
                idleAsset: "RugCatIdle",
                iconAsset: "RugCatIcon",
                mapAsset: "RugCatMap",
                caughtAsset: "RugCatCaught",
                lookAsset: "RugCatLook",
                blinkAsset: nil,
                alertAsset: nil,
                playfulAsset: "RugCatPlayful",
                rollAsset: "RugCatRoll",
                latitude: 40.7720308,
                longitude: -73.9543142,
                radiusMeters: 50,
                sortOrder: 11
            ),
        ]
    }

    static func entry(named name: String) -> Entry? {
        entries.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }
    }

    static func entry(id: UUID) -> Entry? {
        entries.first { $0.id == id }
    }

    static func contains(id: UUID) -> Bool {
        entries.contains { $0.id == id }
    }

    static func merging(_ snapshot: PlayerSnapshot, capturedNames: Set<String>) -> PlayerSnapshot {
        var locations = snapshot.locations
        var characters = snapshot.characters
        for entry in entries {
            if let index = locations.firstIndex(where: { $0.title == entry.locationTitle || $0.id == entry.locationId }) {
                let existing = locations[index]
                locations[index] = GameLocation(
                    id: existing.id, title: existing.title, latitude: entry.latitude, longitude: entry.longitude,
                    radiusMeters: entry.radiusMeters, maxAccuracyMeters: existing.maxAccuracyMeters ?? 250,
                    dwellSeconds: 0, hint: existing.hint ?? entry.hint, sortOrder: existing.sortOrder,
                    hasFallback: existing.hasFallback ?? true
                )
            } else {
                locations.append(entry.asLocation)
            }
            if let index = characters.firstIndex(where: { $0.name.caseInsensitiveCompare(entry.name) == .orderedSame }) {
                if capturedNames.contains(entry.name), !characters[index].captured {
                    characters[index] = characters[index].withCaptured(true)
                }
            } else {
                characters.append(entry.asCharacter(captured: capturedNames.contains(entry.name)))
            }
        }
        var updated = snapshot
        updated.locations = locations
        updated.characters = characters
        return updated
    }
}

extension CatCatalog.Entry {
    var idleCycle: [CatCatalog.Pose] {
        if blinkAsset != nil {
            return [.idle, .idle, .blink, .idle, .look]
        }
        return [.idle, .look, .idle, .playful, .roll]
    }

    var tapPose: CatCatalog.Pose {
        alertAsset != nil ? .alert : .playful
    }

    func assetName(for pose: CatCatalog.Pose) -> String {
        switch pose {
        case .idle: idleAsset
        case .icon: iconAsset
        case .map: mapAsset
        case .caught: caughtAsset
        case .look: lookAsset
        case .blink: blinkAsset ?? idleAsset
        case .alert: alertAsset ?? idleAsset
        case .playful: playfulAsset ?? idleAsset
        case .roll: rollAsset ?? idleAsset
        }
    }

    var asLocation: GameLocation {
        GameLocation(
            id: locationId, title: locationTitle, latitude: latitude, longitude: longitude,
            radiusMeters: radiusMeters, maxAccuracyMeters: 250, dwellSeconds: 0, hint: hint,
            sortOrder: sortOrder, hasFallback: true
        )
    }

    func asCharacter(captured: Bool) -> Character {
        Character(
            id: id, locationId: locationId, name: name, category: category, rarity: rarity,
            required: false, xpValue: combatPower, sortOrder: sortOrder, captured: captured,
            description: description, personality: personality, specialAbility: ability,
            artworkPath: idleAsset
        )
    }
}

extension Character {
    var catalog: CatCatalog.Entry? { CatCatalog.entry(named: name) ?? CatCatalog.entry(id: id) }
    var combatPower: Int { catalog?.combatPower ?? xpValue }
    var displayType: String { catalog?.type ?? category.replacingOccurrences(of: "_", with: " ").capitalized }

    func withCaptured(_ captured: Bool) -> Character {
        Character(
            id: id, locationId: locationId, name: name, category: category, rarity: rarity,
            required: required, xpValue: xpValue, sortOrder: sortOrder, captured: captured,
            description: description, personality: personality, specialAbility: specialAbility,
            artworkPath: artworkPath
        )
    }
}

struct CreatureArtwork: View {
    let character: Character
    var pose: CatCatalog.Pose = .idle
    var useIcon = false
    var silhouette = false

    var body: some View {
        let resolvedPose: CatCatalog.Pose = useIcon ? .icon : pose
        let name = character.catalog?.assetName(for: resolvedPose) ?? character.artworkPath
        Group {
            if let name, UIImage(named: name) != nil {
                Image(name).resizable().scaledToFit()
            } else if let path = character.artworkPath, let url = URL(string: path), url.scheme?.hasPrefix("http") == true {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image): image.resizable().scaledToFit()
                    default: placeholder
                    }
                }
            } else {
                placeholder
            }
        }
        .grayscale(silhouette ? 1 : 0)
        .opacity(silhouette ? 0.35 : 1)
        .accessibilityHidden(true)
    }

    private var placeholder: some View {
        Image(systemName: silhouette ? "questionmark" : "cat.fill")
            .font(.system(size: 58, weight: .bold))
            .foregroundStyle(silhouette ? Color.gray : Color.birthdayPurple)
    }
}

struct CreaturePoseArt: View {
    let character: Character
    var celebrating = false
    var alert = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if celebrating || alert || reduceMotion || character.catalog == nil {
            CreatureArtwork(character: character, pose: staticPose)
        } else {
            TimelineView(.animation(minimumInterval: 1.35, paused: false)) { timeline in
                let cycle = character.catalog?.idleCycle ?? [.idle]
                let index = Int(timeline.date.timeIntervalSinceReferenceDate / 1.35) % max(cycle.count, 1)
                CreatureArtwork(character: character, pose: cycle[index])
            }
        }
    }

    private var staticPose: CatCatalog.Pose {
        if celebrating { return .caught }
        if alert { return character.catalog?.tapPose ?? .idle }
        return .idle
    }
}

struct PulseRing: View {
    var color: Color = .birthdayPurple
    @State private var pulse = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Circle()
            .stroke(color.opacity(pulse ? 0.05 : 0.45), lineWidth: 3)
            .scaleEffect(pulse ? 1.55 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 1.4).repeatForever(autoreverses: false), value: pulse)
            .onAppear { pulse = true }
            .accessibilityHidden(true)
    }
}

struct SparkleField: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        TimelineView(.animation(minimumInterval: reduceMotion ? 1 : 0.12, paused: reduceMotion)) { timeline in
            Canvas { context, size in
                let t = timeline.date.timeIntervalSinceReferenceDate
                for index in 0..<12 {
                    let seed = Double(index) * 1.7
                    let x = (sin(seed + t * 0.6) * 0.5 + 0.5) * size.width
                    let y = (cos(seed * 0.8 + t * 0.5) * 0.5 + 0.5) * size.height
                    let glow = 0.45 + 0.45 * sin(t * 3 + seed)
                    context.opacity = glow
                    context.fill(
                        Path(ellipseIn: CGRect(x: x, y: y, width: 7, height: 7)),
                        with: .color(index.isMultiple(of: 2) ? Color.golden : Color.mint)
                    )
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
