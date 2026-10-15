import Foundation
import SwiftData
import CoreGraphics

struct PlayerSnapshot: Codable, Sendable {
    var game: GameSummary
    var locations: [GameLocation]
    var characters: [Character]
    var messagePins: [MessagePin]
    var unlockedMessages: [FriendMessage]
    var landmarks: [Landmark]
    var passportStamps: [String]?
    var finale: Finale
    var eggTypes: [EggTypeConfig]? = nil
    var playerEggs: [RemotePlayerEgg]? = nil
}

struct GameSummary: Codable, Sendable {
    let id: UUID
    let title: String
    let recipientName: String
    let introMessage: String
    let coverArtPath: String?
    let launchAt: Date?
    let xp: Int
    let avatarStyle: [String: String]?
}

struct GameLocation: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    let title: String
    let latitude: Double
    let longitude: Double
    let radiusMeters: Int
    let maxAccuracyMeters: Int?
    let dwellSeconds: Int?
    let hint: String?
    let sortOrder: Int
    let hasFallback: Bool?
}

enum CharacterRarity: String, Codable, CaseIterable, Sendable {
    case common, rare, legendary
}

enum CreatureKind: String, Sendable, CaseIterable {
    case pastry, map, candle, buddy, spark

    static func resolving(category: String, rarity: CharacterRarity = .common) -> CreatureKind {
        switch category {
        case "food": .pastry
        case "memory": .map
        case "legendary": .candle
        case "inside_joke": .spark
        default: rarity == .legendary ? .candle : .buddy
        }
    }
}

struct Character: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    let locationId: UUID?
    let name: String
    let category: String
    let rarity: CharacterRarity
    let required: Bool
    let xpValue: Int
    let sortOrder: Int
    let captured: Bool
    let description: String?
    let personality: String?
    let specialAbility: String?
    let artworkPath: String?
}

struct MessagePin: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    let locationId: UUID?
    let title: String
    let senderName: String?
    let visibility: String
    let required: Bool
    let unlocked: Bool
    var unlockType: String? = nil
    var unlockRule: String? = nil
    var characterId: UUID? = nil
    var passportStampKey: String? = nil
    var lockedHint: String? = nil
    var revealSender: Bool? = nil
    var hasPhoto: Bool? = nil
    var hasAudio: Bool? = nil
}

struct MessageMedia: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    let kind: String
    var path: String
    let mimeType: String
    let durationSeconds: Int?
}

struct FriendMessage: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    let title: String
    let senderName: String
    let body: String
    let locationId: UUID?
    let unlockedAt: Date
    var media: [MessageMedia]
    var characterId: UUID? = nil
    var passportStampKey: String? = nil
    var senderPhotoPath: String? = nil
}

struct Landmark: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    let locationId: UUID
    let title: String
    let description: String
    let story: String?
    let imagePath: String?
    let required: Bool
    let visited: Bool
    let sortOrder: Int
}

struct Finale: Codable, Sendable {
    let unlocked: Bool
    let title: String?
    let letter: String?
    let mediaPath: String?
    let destination: String?
}

@Model
final class CachedSnapshot {
    @Attribute(.unique) var gameId: UUID
    var payload: Data
    var savedAt: Date

    init(gameId: UUID, payload: Data, savedAt: Date = .now) {
        self.gameId = gameId
        self.payload = payload
        self.savedAt = savedAt
    }
}

struct PendingProgress: Codable, Identifiable, Sendable {
    let id: UUID
    let contentType: String
    let contentId: UUID
    let latitude: Double?
    let longitude: Double?
    let horizontalAccuracy: Double?
    let dwellStartedAt: Date
    let fallbackCode: String?

    enum CodingKeys: String, CodingKey {
        case id = "idempotencyKey"
        case contentType, contentId, latitude, longitude, horizontalAccuracy, dwellStartedAt, fallbackCode
    }
}

enum MarkerStatus: String, Sendable {
    case locked, nearby, available, completed

    static func resolve(
        completed: Bool,
        immediate: Bool,
        distance: Double?,
        radius: Double,
        accuracy: Double?,
        maximumAccuracy: Double
    ) -> MarkerStatus {
        if completed { return .completed }
        if immediate { return .available }
        guard let distance else { return .locked }
        if let accuracy, Proximity.isEligible(distance: distance, radius: radius, accuracy: accuracy, maximumAccuracy: maximumAccuracy) {
            return .available
        }
        if distance <= radius * 3 { return .nearby }
        return .locked
    }
}

enum Proximity {
    static func distanceMeters(
        latitude: Double, longitude: Double,
        targetLatitude: Double, targetLongitude: Double
    ) -> Double {
        let radius = 6_371_000.0
        let lat1 = latitude * .pi / 180
        let lat2 = targetLatitude * .pi / 180
        let deltaLat = (targetLatitude - latitude) * .pi / 180
        let deltaLon = (targetLongitude - longitude) * .pi / 180
        let a = sin(deltaLat / 2) * sin(deltaLat / 2)
            + cos(lat1) * cos(lat2) * sin(deltaLon / 2) * sin(deltaLon / 2)
        return radius * 2 * atan2(sqrt(a), sqrt(1 - a))
    }

    static func isEligible(distance: Double, radius: Double, accuracy: Double, maximumAccuracy: Double = 100) -> Bool {
        accuracy > 0 && accuracy <= maximumAccuracy && distance <= radius
    }
}

enum MemoryStopBand: String, Equatable, Sendable {
    case distant, nearby, inRange, collected
}

/// Visual-only preview for DEBUG builds. Release builds always read `.off`.
/// Rewards never consult this value.
enum MemoryStopProximityOverride: String, CaseIterable, Sendable {
    case off, distant, nearby, inRange

    static let defaultsKey = "memoryStopProximityOverride"

    static var stored: MemoryStopProximityOverride {
        #if DEBUG
        guard let raw = UserDefaults.standard.string(forKey: defaultsKey),
              let value = MemoryStopProximityOverride(rawValue: raw) else { return .off }
        return value
        #else
        return .off
        #endif
    }
}

enum MemoryStopProximity {
    static let nearbyMeters = 250.0
    static let inRangeMeters = 50.0
    static let hysteresisMeters = 15.0

    static func band(
        collected: Bool,
        distance: Double?,
        accuracy: Double?,
        maximumAccuracy: Double,
        previous: MemoryStopBand?
    ) -> MemoryStopBand {
        if collected { return .collected }
        guard let distance, distance.isFinite else { return .distant }

        let accurate = (accuracy ?? -1) > 0 && (accuracy ?? 0) <= maximumAccuracy
        let inRangeExit = inRangeMeters + hysteresisMeters
        let nearbyExit = nearbyMeters + hysteresisMeters
        let holdingRange = previous == .inRange && distance <= inRangeExit && accurate
        if (distance <= inRangeMeters && accurate) || holdingRange {
            return .inRange
        }

        let holdingNearby = (previous == .nearby || previous == .inRange) && distance <= nearbyExit
        if distance <= nearbyMeters || holdingNearby {
            return .nearby
        }
        return .distant
    }

    static func displayBand(
        collected: Bool,
        distance: Double?,
        accuracy: Double?,
        maximumAccuracy: Double,
        previous: MemoryStopBand?,
        override: MemoryStopProximityOverride
    ) -> MemoryStopBand {
        let gps = band(
            collected: collected,
            distance: distance,
            accuracy: accuracy,
            maximumAccuracy: maximumAccuracy,
            previous: previous
        )
        if gps == .collected { return .collected }
        switch override {
        case .off: return gps
        case .distant: return .distant
        case .nearby: return .nearby
        case .inRange: return .inRange
        }
    }
}

enum MemoryStopSpin {
    static let minimumDistance: CGFloat = 48
    static let degreesPerPoint = 0.55
    static let friction = 2.4
    static let stopVelocity = 12.0

    static func qualifies(translationWidth: CGFloat, translationHeight: CGFloat) -> Bool {
        abs(translationWidth) >= minimumDistance && abs(translationWidth) > abs(translationHeight)
    }

    static func releaseVelocity(pointsPerSecond: CGFloat, translationWidth: CGFloat) -> Double {
        let direction: Double = translationWidth >= 0 ? 1 : -1
        let magnitude = min(max(abs(Double(pointsPerSecond)) * 0.85, 320), 1_400)
        return magnitude * direction
    }

    static func velocity(initial: Double, friction: Double, elapsed: Double) -> Double {
        guard friction > 0, elapsed > 0 else { return initial }
        return initial * exp(-friction * elapsed)
    }

    static func angle(startAngle: Double, velocity: Double, friction: Double, elapsed: Double) -> Double {
        guard friction > 0, elapsed > 0 else { return startAngle }
        return startAngle + (velocity / friction) * (1 - exp(-friction * elapsed))
    }

    static func settleDuration(velocity: Double, friction: Double = friction) -> Double {
        let speed = abs(velocity)
        guard friction > 0, speed > stopVelocity else { return 0 }
        return log(speed / stopVelocity) / friction
    }
}

enum MemoryStopAward {
    static func shouldAward(
        gestureQualified: Bool,
        gpsInRange: Bool,
        alreadyComplete: Bool,
        awardInFlight: Bool
    ) -> Bool {
        gestureQualified && gpsInRange && !alreadyComplete && !awardInFlight
    }
}

enum MemoryStopArtwork {
    static func assetName(for title: String) -> String? {
        switch title {
        case "Grand Central Terminal": "MemoryStopGrandCentral"
        case "NYRR RUNCENTER": "MemoryStopRunCenter"
        case "Chip City Chelsea": "MemoryStopChelsea"
        default: nil
        }
    }
}

enum CatchPhysics {
    struct Arc: Equatable {
        var start: CGPoint
        var control: CGPoint
        var end: CGPoint
        var duration: TimeInterval
    }

    static func isThrow(_ translation: CGSize) -> Bool {
        qualifies(translation: translation, velocity: .zero)
    }

    /// A tap, a slow drag, or a sideways swipe does not launch. The release has to flick upward.
    static func qualifies(translation: CGSize, velocity: CGSize) -> Bool {
        let upward = -translation.height
        let upwardSpeed = -velocity.height
        guard upward >= 64 else { return false }
        guard upward >= abs(translation.width) * 0.55 else { return false }
        return upwardSpeed >= 380
    }

    static func landingPoint(from start: CGPoint, translation: CGSize, in bounds: CGRect) -> CGPoint {
        let projected = CGPoint(x: start.x + translation.width * 1.85, y: start.y + translation.height * 1.85)
        return CGPoint(
            x: min(max(projected.x, bounds.minX + 24), bounds.maxX - 24),
            y: min(max(projected.y, bounds.minY + 24), bounds.maxY - 24)
        )
    }

    static func controlPoint(from start: CGPoint, to end: CGPoint) -> CGPoint {
        CGPoint(x: (start.x + end.x) / 2 + (end.x - start.x) * 0.15, y: min(start.y, end.y) - 90)
    }

    static func point(start: CGPoint, control: CGPoint, end: CGPoint, t: CGFloat) -> CGPoint {
        let inverse = 1 - t
        return CGPoint(
            x: inverse * inverse * start.x + 2 * inverse * t * control.x + t * t * end.x,
            y: inverse * inverse * start.y + 2 * inverse * t * control.y + t * t * end.y
        )
    }

    static func hits(point: CGPoint, target: CGRect) -> Bool {
        target.insetBy(dx: -28, dy: -28).contains(point)
    }

    static func arc(from start: CGPoint, translation: CGSize, velocity: CGSize, in bounds: CGRect) -> Arc {
        let speed = hypot(velocity.width, velocity.height)
        let strength = min(max(speed / 1_200, 0.62), 1.75)
        let dx = translation.width * 1.25 + velocity.width * 0.08
        let dy = translation.height * 1.15 + velocity.height * 0.16
        var end = CGPoint(x: start.x + dx, y: start.y + dy)
        end.x = min(max(end.x, bounds.minX - 120), bounds.maxX + 120)
        end.y = min(end.y, start.y - 48)
        let lift = 80 + CGFloat(strength) * 70
        let control = CGPoint(
            x: (start.x + end.x) / 2 + dx * 0.12,
            y: min(start.y, end.y) - lift
        )
        let duration = min(max(0.92 - strength * 0.28, 0.42), 0.92)
        return Arc(start: start, control: control, end: end, duration: duration)
    }

    static func impactProgress(arc: Arc, target: CGRect, ballRadius: CGFloat = 30) -> CGFloat? {
        guard target.width > 1, target.height > 1 else { return nil }
        let ball = target.insetBy(dx: -ballRadius, dy: -ballRadius)
        for step in 1...28 {
            let t = CGFloat(step) / 28
            let point = point(start: arc.start, control: arc.control, end: arc.end, t: t)
            if ball.contains(point) { return t }
        }
        return nil
    }
}

enum Progression {
    static func level(xp: Int) -> Int { max(1, xp / 500 + 1) }

    static func isComplete(
        characters: [Character],
        messages: [MessagePin],
        landmarks: [Landmark]
    ) -> Bool {
        characters.filter(\.required).allSatisfy(\.captured)
            && messages.filter(\.required).allSatisfy(\.unlocked)
            && landmarks.filter(\.required).allSatisfy(\.visited)
    }
}

extension PlayerSnapshot {
    static var localAdventure: PlayerSnapshot {
        PlayerSnapshot(
            game: GameSummary(
                id: UUID(uuidString: "B1DA0000-0000-4000-8000-000000000001")!,
                title: "Birthday GO", recipientName: "friend",
                introMessage: "Explore the city, catch characters, and read birthday messages from your friends.",
                coverArtPath: nil, launchAt: nil, xp: 0, avatarStyle: nil
            ),
            locations: [], characters: [], messagePins: [], unlockedMessages: [],
            landmarks: [], passportStamps: [], finale: Finale(unlocked: false, title: nil, letter: nil, mediaPath: nil, destination: nil)
        )
    }
}

#if DEBUG
extension PlayerSnapshot {
    static var uiTest: PlayerSnapshot {
        let locationId = UUID()
        return PlayerSnapshot(
            game: GameSummary(
                id: UUID(), title: "Birthday GO", recipientName: "Alex",
                introMessage: "A private adventure made just for you.",
                coverArtPath: nil, launchAt: nil, xp: 50, avatarStyle: nil
            ),
            locations: [
                GameLocation(
                    id: locationId, title: "Hometown Park", latitude: 40.7128, longitude: -74.006,
                    radiusMeters: 75, maxAccuracyMeters: 100, dwellSeconds: 0, hint: "Look near the bakery.",
                    sortOrder: 0, hasFallback: true
                ),
            ],
            characters: [
                Character(
                    id: UUID(), locationId: locationId, name: "Cupcake Sprite", category: "food",
                    rarity: .common, required: true, xpValue: 100, sortOrder: 0, captured: false,
                    description: nil, personality: nil, specialAbility: nil, artworkPath: nil
                ),
            ],
            messagePins: [
                MessagePin(
                    id: UUID(), locationId: nil, title: "A note from a friend", senderName: nil,
                    visibility: "immediate", required: false, unlocked: false
                ),
            ],
            unlockedMessages: [
                FriendMessage(
                    id: UUID(), title: "Saved birthday note", senderName: "Sam",
                    body: "Happy birthday! This stays in your memory book.",
                    locationId: locationId, unlockedAt: .now, media: []
                ),
            ],
            landmarks: [
                Landmark(
                    id: UUID(), locationId: locationId, title: "The big oak",
                    description: "A quiet favorite place.", story: nil, imagePath: nil,
                    required: false, visited: false, sortOrder: 0
                ),
            ],
            passportStamps: ["hometown-park"],
            finale: Finale(unlocked: true, title: "You did it", letter: "Replay anytime.", mediaPath: nil, destination: nil)
        )
    }
}
#endif
