import Foundation
import SwiftData
import SwiftUI

enum EggDistance {
    static let metersPerMile = 1_609.344

    static func miles(fromMeters meters: Double) -> Double { meters / metersPerMile }
    static func meters(fromMiles miles: Double) -> Double { miles * metersPerMile }

    static func formattedMiles(_ meters: Double, fraction: Int = 1) -> String {
        String(format: "%.\(fraction)f", miles(fromMeters: meters))
    }
}

enum WalkActivity: String, Sendable {
    case walking, running, cycling, automotive, stationary, unknown
}

struct WalkSample: Equatable, Sendable {
    var latitude: Double
    var longitude: Double
    var timestamp: Date
    var horizontalAccuracy: Double
    var reportedSpeed: Double?
}

enum WalkFilter {
    static let maxAccuracyMeters = 35.0
    static let minStepMeters = 3.5
    static let maxStepMeters = 40.0
    static let minDeltaSeconds = 0.8
    static let maxDeltaSeconds = 25.0
    static let maxWalkingSpeed = 3.2
    static let minWalkingSpeed = 0.45
    static let conservativeMaxSpeed = 2.2
    static let conservativeMinSpeed = 0.7
    static let maxReportedSpeed = 4.0

    static func acceptedMeters(from previous: WalkSample, to current: WalkSample, activity: WalkActivity?) -> Double? {
        guard current.horizontalAccuracy > 0, current.horizontalAccuracy <= maxAccuracyMeters else { return nil }
        guard previous.horizontalAccuracy > 0, previous.horizontalAccuracy <= maxAccuracyMeters else { return nil }
        if let activity, !isEligibleActivity(activity) { return nil }

        let elapsed = current.timestamp.timeIntervalSince(previous.timestamp)
        guard elapsed >= minDeltaSeconds, elapsed <= maxDeltaSeconds else { return nil }

        let meters = Proximity.distanceMeters(
            latitude: previous.latitude, longitude: previous.longitude,
            targetLatitude: current.latitude, targetLongitude: current.longitude
        )
        guard meters >= minStepMeters, meters <= maxStepMeters else { return nil }

        let impliedSpeed = meters / elapsed
        let (minSpeed, maxSpeed) = speedBounds(for: activity)
        guard impliedSpeed >= minSpeed, impliedSpeed <= maxSpeed else { return nil }

        if let reported = current.reportedSpeed, reported >= 0, reported > maxReportedSpeed {
            return nil
        }
        return meters
    }

    static func isEligibleActivity(_ activity: WalkActivity) -> Bool {
        switch activity {
        case .walking, .running: true
        case .cycling, .automotive, .stationary: false
        case .unknown: true
        }
    }

    static func speedBounds(for activity: WalkActivity?) -> (Double, Double) {
        switch activity {
        case .walking, .running:
            (minWalkingSpeed, maxWalkingSpeed)
        case .unknown, nil:
            (conservativeMinSpeed, conservativeMaxSpeed)
        case .cycling, .automotive, .stationary:
            (Double.greatestFiniteMagnitude, 0)
        }
    }
}

enum EggStatus: String, Codable, CaseIterable, Sendable {
    case available, incubating, ready, hatched

    var title: String {
        switch self {
        case .available: "Ready to incubate"
        case .incubating: "Incubating"
        case .ready: "Ready to hatch"
        case .hatched: "Hatched"
        }
    }
}

struct EggTypeConfig: Codable, Identifiable, Hashable, Sendable {
    var id: UUID
    var key: String
    var title: String
    var requiredMeters: Double
    var xpValue: Int
    var artworkStyle: String
    var rarityLabel: String
    var allowedRarities: [CharacterRarity]
    var rewardCharacterIds: [UUID]
    var rewardWeights: [String: Double]?
    var excludeDuplicates: Bool
    var duplicateXp: Int
    var artworkPath: String?

    var requiredMiles: Double { EggDistance.miles(fromMeters: requiredMeters) }

    func allows(_ character: Character) -> Bool {
        if !rewardCharacterIds.isEmpty {
            return rewardCharacterIds.contains(character.id) && allowedRarities.contains(character.rarity)
        }
        return allowedRarities.contains(character.rarity)
    }

    func weight(for character: Character) -> Double {
        if let value = rewardWeights?[character.id.uuidString] ?? rewardWeights?[character.id.uuidString.lowercased()] {
            return max(value, 0.01)
        }
        return 1
    }
}

struct RemotePlayerEgg: Codable, Identifiable, Hashable, Sendable {
    var id: UUID
    var eggTypeId: UUID
    var typeKey: String?
    var status: String
    var metersWalked: Double
    var requiredMeters: Double?
    var startedAt: Date?
    var readyAt: Date?
    var hatchedAt: Date?
    var rewardCharacterId: UUID?
    var isTest: Bool?
}

enum HatchDecision: Equatable {
    case character(UUID, xp: Int)
    case duplicate(xp: Int)
}

enum EggRewardPicker {
    static func decide(
        type: EggTypeConfig,
        characters: [Character],
        collectedIds: Set<UUID>,
        collectedNames: Set<String>,
        generator: inout some RandomNumberGenerator
    ) -> HatchDecision {
        var pool = characters.filter { type.allows($0) }
        if type.excludeDuplicates {
            pool = pool.filter { !collectedIds.contains($0.id) && !collectedNames.contains($0.name) }
        }
        guard let choice = weightedChoice(in: pool, type: type, generator: &generator) else {
            return .duplicate(xp: type.duplicateXp)
        }
        return .character(choice.id, xp: type.xpValue)
    }

    static func decide(
        type: EggTypeConfig,
        characters: [Character],
        collectedIds: Set<UUID>,
        collectedNames: Set<String>
    ) -> HatchDecision {
        var generator = SystemRandomNumberGenerator()
        return decide(
            type: type,
            characters: characters,
            collectedIds: collectedIds,
            collectedNames: collectedNames,
            generator: &generator
        )
    }

    private static func weightedChoice(
        in pool: [Character],
        type: EggTypeConfig,
        generator: inout some RandomNumberGenerator
    ) -> Character? {
        guard !pool.isEmpty else { return nil }
        let total = pool.reduce(0) { $0 + type.weight(for: $1) }
        guard total > 0 else { return pool.first }
        var ticket = Double.random(in: 0..<total, using: &generator)
        for character in pool {
            ticket -= type.weight(for: character)
            if ticket <= 0 { return character }
        }
        return pool.last
    }
}

@Model
final class PlayerEggRecord {
    @Attribute(.unique) var id: UUID
    var typeId: UUID
    var typeKey: String
    var typeTitle: String
    var requiredMeters: Double
    var xpValue: Int
    var artworkStyle: String
    var rarityLabel: String
    var statusRaw: String
    var metersWalked: Double
    var startedAt: Date?
    var pausedAt: Date?
    var readyAt: Date?
    var hatchedAt: Date?
    var rewardCharacterId: UUID?
    var rewardName: String?
    var hatchIdempotencyKey: UUID?
    var isTest: Bool
    var updatedAt: Date

    var status: EggStatus {
        get { EggStatus(rawValue: statusRaw) ?? .available }
        set { statusRaw = newValue.rawValue }
    }

    var remainingMeters: Double { max(requiredMeters - metersWalked, 0) }
    var progress: Double { min(max(metersWalked / max(requiredMeters, 1), 0), 1) }

    init(
        id: UUID = UUID(),
        typeId: UUID,
        typeKey: String,
        typeTitle: String,
        requiredMeters: Double,
        xpValue: Int,
        artworkStyle: String,
        rarityLabel: String,
        status: EggStatus = .available,
        metersWalked: Double = 0,
        isTest: Bool = false
    ) {
        self.id = id
        self.typeId = typeId
        self.typeKey = typeKey
        self.typeTitle = typeTitle
        self.requiredMeters = requiredMeters
        self.xpValue = xpValue
        self.artworkStyle = artworkStyle
        self.rarityLabel = rarityLabel
        self.statusRaw = status.rawValue
        self.metersWalked = metersWalked
        self.isTest = isTest
        self.updatedAt = .now
    }
}

enum EggCatalog {
    static let oneMileId = UUID(uuidString: "B1DAE600-0000-4000-8000-000000000001")!
    static let tenMileId = UUID(uuidString: "B1DAE600-0000-4000-8000-000000000002")!
    static let marathonId = UUID(uuidString: "B1DAE600-0000-4000-8000-000000000003")!
    static let hundredMileId = UUID(uuidString: "B1DAE600-0000-4000-8000-000000000004")!
    private static let remoteTypesKey = "eggTypesCache"

    static var defaults: [EggTypeConfig] {
        [
            EggTypeConfig(
                id: oneMileId,
                key: "one-mile",
                title: "1-Mile Cookie",
                requiredMeters: EggDistance.meters(fromMiles: 1),
                xpValue: 50,
                artworkStyle: "sky",
                rarityLabel: "Common or rare",
                allowedRarities: [.common, .rare],
                rewardCharacterIds: [],
                rewardWeights: nil,
                excludeDuplicates: true,
                duplicateXp: 15,
                artworkPath: nil
            ),
            EggTypeConfig(
                id: tenMileId,
                key: "ten-mile",
                title: "10-Mile Cookie",
                requiredMeters: EggDistance.meters(fromMiles: 10),
                xpValue: 200,
                artworkStyle: "gold",
                rarityLabel: "Rare or legendary",
                allowedRarities: [.rare, .legendary],
                rewardCharacterIds: [],
                rewardWeights: nil,
                excludeDuplicates: true,
                duplicateXp: 40,
                artworkPath: nil
            ),
            EggTypeConfig(
                id: marathonId,
                key: "marathon",
                title: "26.2-Mile Cookie",
                requiredMeters: EggDistance.meters(fromMiles: 26.2),
                xpValue: 500,
                artworkStyle: "marathon",
                rarityLabel: "Legendary",
                allowedRarities: [.legendary],
                rewardCharacterIds: [],
                rewardWeights: nil,
                excludeDuplicates: true,
                duplicateXp: 100,
                artworkPath: nil
            ),
            EggTypeConfig(
                id: hundredMileId,
                key: "hundred-mile",
                title: "100-Mile Cookie",
                requiredMeters: EggDistance.meters(fromMiles: 100),
                xpValue: 1_000,
                artworkStyle: "century",
                rarityLabel: "Legendary",
                allowedRarities: [.legendary],
                rewardCharacterIds: [],
                rewardWeights: nil,
                excludeDuplicates: true,
                duplicateXp: 200,
                artworkPath: nil
            ),
        ]
    }

    static var exclusiveCharacters: [Character] {
        [
            Character(
                id: UUID(uuidString: "B1DAE601-0000-4000-8000-000000000001")!,
                locationId: nil, name: "Balloon Buddy", category: "friend", rarity: .rare,
                required: false, xpValue: 80, sortOrder: 80, captured: false,
                description: "A helium-hearted friend who shows up for every birthday walk.",
                personality: "Buoyant and loyal", specialAbility: "Lifts the mood", artworkPath: nil
            ),
            Character(
                id: UUID(uuidString: "B1DAE601-0000-4000-8000-000000000002")!,
                locationId: nil, name: "Snack Sprite", category: "food", rarity: .common,
                required: false, xpValue: 40, sortOrder: 81, captured: false,
                description: "A crumb-sized celebration that smells like the good bakery.",
                personality: "Always hungry", specialAbility: "Shares the last bite", artworkPath: nil
            ),
            Character(
                id: UUID(uuidString: "B1DAE601-0000-4000-8000-000000000003")!,
                locationId: nil, name: "Joke Spark", category: "inside_joke", rarity: .rare,
                required: false, xpValue: 80, sortOrder: 82, captured: false,
                description: "Hatches only for people who already know the punchline.",
                personality: "Wry", specialAbility: "Callback humor", artworkPath: nil
            ),
            Character(
                id: UUID(uuidString: "B1DAE601-0000-4000-8000-000000000004")!,
                locationId: nil, name: "Confetti Spark", category: "legendary", rarity: .legendary,
                required: false, xpValue: 200, sortOrder: 83, captured: false,
                description: "A rare burst of birthday light earned one long walk at a time.",
                personality: "Dazzling", specialAbility: "Turns sidewalks into parades", artworkPath: nil
            ),
            Character(
                id: UUID(uuidString: "B1DAE601-0000-4000-8000-000000000005")!,
                locationId: nil, name: "Birthday Crown", category: "legendary", rarity: .legendary,
                required: false, xpValue: 220, sortOrder: 84, captured: false,
                description: "An exclusive hatch for the person the day is really about.",
                personality: "Regal and warm", specialAbility: "Makes any block feel like a procession", artworkPath: nil
            ),
            Character(
                id: UUID(uuidString: "B1DAE601-0000-4000-8000-000000000006")!,
                locationId: nil, name: "Golden Party Pal", category: "friend", rarity: .rare,
                required: false, xpValue: 120, sortOrder: 85, captured: false,
                description: "A 10-mile companion with a pocket full of surprises.",
                personality: "Generous", specialAbility: "Saves the best gift for last", artworkPath: nil
            ),
        ]
    }

    static func resolvedTypes() -> [EggTypeConfig] {
        if let cached = cachedRemoteTypes(), !cached.isEmpty {
            return mergeTypes(remote: cached, fallback: defaults)
        }
        return defaults
    }

    static func type(id: UUID) -> EggTypeConfig? {
        resolvedTypes().first { $0.id == id } ?? defaults.first { $0.id == id }
    }

    static func type(key: String) -> EggTypeConfig? {
        resolvedTypes().first { $0.key == key } ?? defaults.first { $0.key == key }
    }

    static func cacheRemoteTypes(_ types: [EggTypeConfig]) {
        guard let data = try? JSONEncoder.supabase.encode(types) else { return }
        UserDefaults.standard.set(data, forKey: remoteTypesKey)
    }

    static func merging(_ snapshot: PlayerSnapshot, capturedNames: Set<String>) -> PlayerSnapshot {
        var current = snapshot
        if let remote = snapshot.eggTypes, !remote.isEmpty {
            cacheRemoteTypes(remote)
        }
        for character in exclusiveCharacters {
            if let index = current.characters.firstIndex(where: { $0.id == character.id || $0.name == character.name }) {
                if capturedNames.contains(character.name) || capturedNames.contains(current.characters[index].name) {
                    current.characters[index] = current.characters[index].withCaptured(true)
                }
            } else {
                current.characters.append(character.withCaptured(capturedNames.contains(character.name)))
            }
        }
        return current
    }

    private static func cachedRemoteTypes() -> [EggTypeConfig]? {
        guard let data = UserDefaults.standard.data(forKey: remoteTypesKey) else { return nil }
        return try? JSONDecoder.supabase.decode([EggTypeConfig].self, from: data)
    }

    private static func mergeTypes(remote: [EggTypeConfig], fallback: [EggTypeConfig]) -> [EggTypeConfig] {
        var merged = remote
        for type in fallback where !merged.contains(where: { $0.key == type.key || $0.id == type.id }) {
            merged.append(type)
        }
        return merged
    }
}
