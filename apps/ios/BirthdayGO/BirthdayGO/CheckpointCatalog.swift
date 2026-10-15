import Foundation
import SwiftData
import SwiftUI
import MapKit
import CoreLocation

@Model
final class CollectedSouvenir {
    @Attribute(.unique) var souvenirId: UUID
    var name: String
    var checkpointTitle: String
    var detail: String
    var symbol: String
    var collectedAt: Date

    init(souvenirId: UUID, name: String, checkpointTitle: String, detail: String, symbol: String, collectedAt: Date = .now) {
        self.souvenirId = souvenirId
        self.name = name
        self.checkpointTitle = checkpointTitle
        self.detail = detail
        self.symbol = symbol
        self.collectedAt = collectedAt
    }
}

@Model
final class AwardedCheckpoint {
    @Attribute(.unique) var awardKey: String
    var xp: Int
    var awardedAt: Date

    init(awardKey: String, xp: Int, awardedAt: Date = .now) {
        self.awardKey = awardKey
        self.xp = xp
        self.awardedAt = awardedAt
    }
}

enum CheckpointKind: String, Sendable {
    case memoryStop, wildEncounter, specialEncounter, travelStop
}

enum CheckpointCatalog {
    struct Souvenir: Identifiable, Sendable {
        let id: UUID
        let name: String
        let detail: String
        let symbol: String
    }

    struct FriendNote: Identifiable, Sendable {
        let id: UUID
        let title: String
        let senderName: String
        let body: String
        let xpValue: Int
    }

    struct Creature: Identifiable, Sendable {
        let id: UUID
        let name: String
        let rarity: CharacterRarity
        let combatPower: Int
        let type: String
        let ability: String
        let description: String
        let personality: String
        let category: String
        let xpValue: Int
    }

    struct Entry: Identifiable, Sendable {
        let id: UUID
        let locationId: UUID
        let landmarkId: UUID?
        let title: String
        let geocodeQuery: String
        var latitude: Double
        var longitude: Double
        let radiusMeters: Int
        let kind: CheckpointKind
        let hint: String
        let fallbackCode: String
        let markerSymbol: String
        let characters: [Creature]
        let souvenir: Souvenir?
        let message: FriendNote
        let sortOrder: Int
        let unlocksCharacterOnVisit: Bool
    }

    private static let coordinatePrefix = "checkpoint.coordinate."

    static var entries: [Entry] {
        baseEntries.map { entry in
            var copy = entry
            if let stored = storedCoordinate(for: entry.id) {
                copy.latitude = stored.latitude
                copy.longitude = stored.longitude
            }
            return copy
        }
    }

    static func entry(id: UUID) -> Entry? {
        entries.first { $0.id == id || $0.locationId == id || $0.landmarkId == id || $0.characters.contains { $0.id == id } || $0.message.id == id || $0.souvenir?.id == id }
    }

    static func entry(locationId: UUID) -> Entry? {
        entries.first { $0.locationId == locationId }
    }

    static func entry(named title: String) -> Entry? {
        entries.first { $0.title.caseInsensitiveCompare(title) == .orderedSame }
    }

    static func containsLocation(_ id: UUID) -> Bool {
        entries.contains { $0.locationId == id }
    }

    @MainActor
    static func refreshCoordinates() async {
        for entry in baseEntries {
            if let coordinate = await resolve(entry.geocodeQuery) {
                store(coordinate, for: entry.id)
            }
        }
    }

    static func merging(
        _ snapshot: PlayerSnapshot,
        capturedNames: Set<String>,
        souvenirs: Set<UUID>,
        visitedLandmarkIds: Set<UUID>,
        unlockedMessageIds: Set<UUID>
    ) -> PlayerSnapshot {
        var locations = snapshot.locations
        var characters = snapshot.characters
        var landmarks = snapshot.landmarks
        var messagePins = snapshot.messagePins
        var unlocked = snapshot.unlockedMessages

        for entry in entries {
            if let index = locations.firstIndex(where: { $0.id == entry.locationId || $0.title == entry.title }) {
                let existing = locations[index]
                locations[index] = GameLocation(
                    id: existing.id, title: entry.title, latitude: entry.latitude, longitude: entry.longitude,
                    radiusMeters: entry.radiusMeters, maxAccuracyMeters: existing.maxAccuracyMeters ?? 250,
                    dwellSeconds: 0, hint: entry.hint, sortOrder: existing.sortOrder, hasFallback: true
                )
            } else {
                locations.append(entry.asLocation)
            }

            for creature in entry.characters {
                if let index = characters.firstIndex(where: { $0.id == creature.id || $0.name.caseInsensitiveCompare(creature.name) == .orderedSame }) {
                    if capturedNames.contains(creature.name) || capturedNames.contains(where: { $0.caseInsensitiveCompare(creature.name) == .orderedSame }) {
                        characters[index] = characters[index].withCaptured(true)
                    }
                } else {
                    characters.append(creature.asCharacter(locationId: entry.locationId, captured: capturedNames.contains(creature.name)))
                }
            }

            if let landmarkId = entry.landmarkId {
                let souvenirOwned = entry.souvenir.map { souvenirs.contains($0.id) } ?? false
                let visited = visitedLandmarkIds.contains(landmarkId)
                    || landmarks.contains { $0.id == landmarkId && $0.visited }
                    || souvenirOwned
                if let index = landmarks.firstIndex(where: { $0.id == landmarkId || $0.title == entry.title }) {
                    landmarks[index] = landmarks[index].withVisited(visited)
                } else {
                    landmarks.append(entry.asLandmark(visited: visited))
                }
            }

            if entry.kind != .travelStop {
                if let index = messagePins.firstIndex(where: { $0.id == entry.message.id || $0.title == entry.message.title }) {
                    if unlockedMessageIds.contains(entry.message.id) {
                        messagePins[index] = messagePins[index].withUnlocked(true)
                    }
                } else {
                    messagePins.append(entry.asMessagePin(unlocked: unlockedMessageIds.contains(entry.message.id)))
                }
                if unlockedMessageIds.contains(entry.message.id), !unlocked.contains(where: { $0.id == entry.message.id }) {
                    unlocked.append(entry.asFriendMessage())
                }
            }
        }

        var updated = snapshot
        updated.locations = locations
        updated.characters = characters
        updated.landmarks = landmarks
        updated.messagePins = messagePins
        updated.unlockedMessages = unlocked
        var stamps = Set(snapshot.passportStamps ?? [])
        for entry in entries where entry.isComplete(updated) {
            if let key = MemoryPassport.stampKey(forLocationTitle: entry.title) {
                stamps.insert(key)
            }
        }
        updated.passportStamps = stamps.sorted()
        return updated
    }

    private static func resolve(_ query: String) async -> CLLocationCoordinate2D? {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        request.resultTypes = .pointOfInterest
        request.region = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 40.72, longitude: -73.95),
            span: MKCoordinateSpan(latitudeDelta: 0.7, longitudeDelta: 0.7)
        )
        do {
            let response = try await MKLocalSearch(request: request).start()
            if let coordinate = response.mapItems.first?.placemark.coordinate {
                return coordinate
            }
        } catch {
            return nil
        }
        return await withCheckedContinuation { continuation in
            CLGeocoder().geocodeAddressString(query) { marks, _ in
                continuation.resume(returning: marks?.first?.location?.coordinate)
            }
        }
    }

    private static func storedCoordinate(for id: UUID) -> CLLocationCoordinate2D? {
        let defaults = UserDefaults.standard
        let lat = defaults.object(forKey: coordinatePrefix + id.uuidString + ".lat") as? Double
        let lon = defaults.object(forKey: coordinatePrefix + id.uuidString + ".lon") as? Double
        guard let lat, let lon else { return nil }
        return CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }

    private static func store(_ coordinate: CLLocationCoordinate2D, for id: UUID) {
        UserDefaults.standard.set(coordinate.latitude, forKey: coordinatePrefix + id.uuidString + ".lat")
        UserDefaults.standard.set(coordinate.longitude, forKey: coordinatePrefix + id.uuidString + ".lon")
    }

    /// Public MapKit queries and fallbacks. Residential street numbers stay out of player-facing titles.
    private static let baseEntries: [Entry] = [
        Entry(
            id: UUID(uuidString: "C1A55E01-0001-4000-8000-000000000001")!,
            locationId: UUID(uuidString: "C1A55E01-1001-4000-8000-000000000001")!,
            landmarkId: UUID(uuidString: "C1A55E01-2001-4000-8000-000000000001")!,
            title: "Grand Central Terminal",
            geocodeQuery: "Grand Central Terminal, New York",
            latitude: 40.752726, longitude: -73.977229,
            radiusMeters: 75, kind: .memoryStop,
            hint: "Meet under the constellation ceiling, then spin the memory disc.",
            fallbackCode: "grandcentral", markerSymbol: "tram.fill",
            characters: [
                Creature(
                    id: UUID(uuidString: "C1A55E01-4001-4000-8000-000000000001")!,
                    name: "LIRR Train", rarity: .rare, combatPower: 410, type: "Transit",
                    ability: "On-Time Arrival",
                    description: "A gleaming commuter companion who knows every platform announcement by heart.",
                    personality: "Punctual, proud, a little loud in tunnels.",
                    category: "memory", xpValue: 0
                ),
            ],
            souvenir: nil,
            message: FriendNote(
                id: UUID(uuidString: "C1A55E01-5001-4000-8000-000000000001")!,
                title: "Meet me under the clock", senderName: "A commuter friend",
                body: "If we can find each other in Grand Central, we can find anything. Happy birthday — the next train is yours.",
                xpValue: 0
            ),
            sortOrder: 20, unlocksCharacterOnVisit: true
        ),
        Entry(
            id: UUID(uuidString: "C1A55E01-0002-4000-8000-000000000002")!,
            locationId: UUID(uuidString: "C1A55E01-1002-4000-8000-000000000002")!,
            landmarkId: nil,
            title: "Penn Station",
            geocodeQuery: "Moynihan Train Hall, New York",
            latitude: 40.750580, longitude: -73.993584,
            radiusMeters: 75, kind: .wildEncounter,
            hint: "A wild Anya appeared between the concourse crowds.",
            fallbackCode: "pennstation", markerSymbol: "sparkles",
            characters: [
                Creature(
                    id: UUID(uuidString: "C1A55E01-4002-4000-8000-000000000002")!,
                    name: "Confused Anya", rarity: .rare, combatPower: 388, type: "Playful",
                    ability: "Wrong Staircase",
                    description: "Always one hallway from the right track, never short on stories.",
                    personality: "Lost, laughing, somehow still on time.",
                    category: "inside_joke", xpValue: 150
                ),
            ],
            souvenir: nil,
            message: FriendNote(
                id: UUID(uuidString: "C1A55E01-5002-4000-8000-000000000002")!,
                title: "This way. No, that way.", senderName: "Someone circling with you",
                body: "If you are confused, you are doing Penn Station correctly. Catch the moment anyway.",
                xpValue: 0
            ),
            sortOrder: 21, unlocksCharacterOnVisit: false
        ),
        Entry(
            id: UUID(uuidString: "C1A55E01-0003-4000-8000-000000000003")!,
            locationId: UUID(uuidString: "C1A55E01-1003-4000-8000-000000000003")!,
            landmarkId: UUID(uuidString: "C1A55E01-2003-4000-8000-000000000003")!,
            title: "NYRR RUNCENTER",
            geocodeQuery: "NYRR RUNCENTER, 320 West 57th Street, New York",
            latitude: 40.76694, longitude: -73.98300,
            radiusMeters: 75, kind: .memoryStop,
            hint: "Grab a bib and remember the start-line butterflies.",
            fallbackCode: "runcenter", markerSymbol: "figure.run",
            characters: [],
            souvenir: Souvenir(
                id: UUID(uuidString: "C1A55E01-3003-4000-8000-000000000003")!,
                name: "Race Bib",
                detail: "A bright start-line bib from the RUNCENTER, saved apart from FriendDex creatures.",
                symbol: "tag.fill"
            ),
            message: FriendNote(
                id: UUID(uuidString: "C1A55E01-5003-4000-8000-000000000003")!,
                title: "Pin it on", senderName: "Your running buddy",
                body: "Miles look shorter when someone is waiting at the finish. This bib is yours.",
                xpValue: 0
            ),
            sortOrder: 22, unlocksCharacterOnVisit: false
        ),
        Entry(
            id: UUID(uuidString: "C1A55E01-0004-4000-8000-000000000004")!,
            locationId: UUID(uuidString: "C1A55E01-1004-4000-8000-000000000004")!,
            landmarkId: nil,
            title: "Chip City Rockefeller",
            geocodeQuery: "30 Rockefeller Plaza, New York",
            latitude: 40.758740, longitude: -73.978674,
            radiusMeters: 75, kind: .wildEncounter,
            hint: "A concourse cookie is on the loose under the plaza.",
            fallbackCode: "chiprock", markerSymbol: "birthday.cake.fill",
            characters: [
                Creature(
                    id: UUID(uuidString: "C1A55E01-4004-4000-8000-000000000004")!,
                    name: "Rockefeller Cookie", rarity: .common, combatPower: 220, type: "Sweet",
                    ability: "Warm Batch",
                    description: "A plaza cookie who thinks every elevator is a oven timer.",
                    personality: "Gooey, optimistic, slightly famous.",
                    category: "food", xpValue: 100
                ),
            ],
            souvenir: nil,
            message: FriendNote(
                id: UUID(uuidString: "C1A55E01-5004-4000-8000-000000000004")!,
                title: "Concourse sugar", senderName: "A cookie accomplice",
                body: "If you can smell butter in the Rockefeller concourse, you are close.",
                xpValue: 0
            ),
            sortOrder: 23, unlocksCharacterOnVisit: false
        ),
        Entry(
            id: UUID(uuidString: "C1A55E01-0005-4000-8000-000000000005")!,
            locationId: UUID(uuidString: "C1A55E01-1005-4000-8000-000000000005")!,
            landmarkId: UUID(uuidString: "C1A55E01-2005-4000-8000-000000000005")!,
            title: "Chip City Chelsea",
            geocodeQuery: "Chip City, 272 7th Avenue, New York",
            latitude: 40.74579, longitude: -73.99477,
            radiusMeters: 75, kind: .memoryStop,
            hint: "Chelsea’s cookie counter has a quieter birthday treat.",
            fallbackCode: "chipchelsea", markerSymbol: "cup.and.saucer.fill",
            characters: [],
            souvenir: Souvenir(
                id: UUID(uuidString: "C1A55E01-3005-4000-8000-000000000005")!,
                name: "Chelsea Cookie Tin",
                detail: "A Chelsea-only cookie keepsake. Separate from the Rockefeller cookie catch.",
                symbol: "gift.fill"
            ),
            message: FriendNote(
                id: UUID(uuidString: "C1A55E01-5005-4000-8000-000000000005")!,
                title: "Seventh Avenue sweet", senderName: "A Chelsea regular",
                body: "Different shop, different tin. Do not mix this one up with the plaza cookie.",
                xpValue: 0
            ),
            sortOrder: 24, unlocksCharacterOnVisit: false
        ),
        Entry(
            id: UUID(uuidString: "C1A55E01-0006-4000-8000-000000000006")!,
            locationId: UUID(uuidString: "C1A55E01-1006-4000-8000-000000000006")!,
            landmarkId: nil,
            title: "Williamsburg",
            geocodeQuery: "McCarren Park, Brooklyn, NY",
            latitude: 40.72148, longitude: -73.95236,
            radiusMeters: 75, kind: .specialEncounter,
            hint: "A pair of Chrises is holding court near the park paths.",
            fallbackCode: "williamsburg", markerSymbol: "person.2.fill",
            characters: [
                Creature(
                    id: UUID(uuidString: "C1A55E01-4006-4000-8000-000000000006")!,
                    name: "Chris One", rarity: .rare, combatPower: 460, type: "Friend",
                    ability: "Plus One",
                    description: "Half of a legendary duo. Shows up early and claims the good bench.",
                    personality: "Warm, competitive about snacks.",
                    category: "friend", xpValue: 100
                ),
                Creature(
                    id: UUID(uuidString: "C1A55E01-4006-4000-8000-000000000016")!,
                    name: "Chris Two", rarity: .rare, combatPower: 460, type: "Friend",
                    ability: "Also Plus One",
                    description: "The other half. Arrives fashionably and finishes the story.",
                    personality: "Witty, loyal, never travels alone.",
                    category: "friend", xpValue: 100
                ),
            ],
            souvenir: nil,
            message: FriendNote(
                id: UUID(uuidString: "C1A55E01-5006-4000-8000-000000000006")!,
                title: "Both Chrises", senderName: "The group chat",
                body: "If you only catch one Chris, the other will never let it go. Get both.",
                xpValue: 0
            ),
            sortOrder: 25, unlocksCharacterOnVisit: false
        ),
        Entry(
            id: UUID(uuidString: "C1A55E01-0007-4000-8000-000000000007")!,
            locationId: UUID(uuidString: "8F1A2C10-1002-4000-8000-000000000002")!,
            landmarkId: nil,
            title: "Upper East Side",
            geocodeQuery: "John Jay Park, New York, NY",
            latitude: 40.77203, longitude: -73.95431,
            radiusMeters: 75, kind: .specialEncounter,
            hint: "Joey is nearby, somewhere a friend would actually wait.",
            fallbackCode: "uppereast", markerSymbol: "star.fill",
            characters: [
                Creature(
                    id: UUID(uuidString: "C1A55E01-4007-4000-8000-000000000007")!,
                    name: "Joey", rarity: .rare, combatPower: 444, type: "Friend",
                    ability: "Neighborhood Radar",
                    description: "A UES regular who always knows the next good stop on the block.",
                    personality: "Easygoing, funny, first to buy a snack for the table.",
                    category: "friend", xpValue: 150
                ),
            ],
            souvenir: nil,
            message: FriendNote(
                id: UUID(uuidString: "C1A55E01-5007-4000-8000-000000000007")!,
                title: "On the block", senderName: "Joey",
                body: "Made it to the neighborhood. Come find me — I will not make you guess the building number.",
                xpValue: 0
            ),
            sortOrder: 26, unlocksCharacterOnVisit: false
        ),
        Entry(
            id: UUID(uuidString: "C1A55E01-00A1-4000-8000-0000000000A1")!,
            locationId: UUID(uuidString: "C1A55E01-10A1-4000-8000-0000000000A1")!,
            landmarkId: UUID(uuidString: "C1A55E01-20A1-4000-8000-0000000000A1")!,
            title: "JFK — John F. Kennedy International Airport",
            geocodeQuery: "JFK Terminal 5, JFK Access Road, Queens, NY",
            latitude: 40.6468134, longitude: -73.7798601,
            radiusMeters: 500, kind: .travelStop,
            hint: "Check in at Terminal 5 landside or the AirTrain platform — no boarding pass needed.",
            fallbackCode: "jfkcheck", markerSymbol: "airplane.departure",
            characters: [],
            souvenir: Souvenir(
                id: UUID(uuidString: "C1A55E01-30A1-4000-8000-0000000000A1")!,
                name: "Jetsetter",
                detail: "A JFK travel collectible from the Terminal 5 landside loop.",
                symbol: "airplane"
            ),
            message: FriendNote(
                id: UUID(uuidString: "C1A55E01-50A1-4000-8000-0000000000A1")!,
                title: "JFK check-in", senderName: "Ground transportation",
                body: "You made it to JFK. The AirTrain counts.",
                xpValue: 0
            ),
            sortOrder: 30, unlocksCharacterOnVisit: false
        ),
        Entry(
            id: UUID(uuidString: "C1A55E01-00A2-4000-8000-0000000000A2")!,
            locationId: UUID(uuidString: "C1A55E01-10A2-4000-8000-0000000000A2")!,
            landmarkId: UUID(uuidString: "C1A55E01-20A2-4000-8000-0000000000A2")!,
            title: "LGA — LaGuardia Airport",
            geocodeQuery: "LaGuardia Airport, East Elmhurst, NY 11371",
            latitude: 40.7757145, longitude: -73.8733640,
            radiusMeters: 500, kind: .travelStop,
            hint: "Check in at the Terminal B landside arrivals loop — stay curbside.",
            fallbackCode: "lgacheck", markerSymbol: "airplane.departure",
            characters: [],
            souvenir: Souvenir(
                id: UUID(uuidString: "C1A55E01-30A2-4000-8000-0000000000A2")!,
                name: "Delayed Flight",
                detail: "A LaGuardia travel collectible for waiting it out landside.",
                symbol: "clock.badge.exclamationmark"
            ),
            message: FriendNote(
                id: UUID(uuidString: "C1A55E01-50A2-4000-8000-0000000000A2")!,
                title: "LGA check-in", senderName: "Arrivals",
                body: "LaGuardia still counts, delay or not.",
                xpValue: 0
            ),
            sortOrder: 31, unlocksCharacterOnVisit: false
        ),
        Entry(
            id: UUID(uuidString: "C1A55E01-00A3-4000-8000-0000000000A3")!,
            locationId: UUID(uuidString: "C1A55E01-10A3-4000-8000-0000000000A3")!,
            landmarkId: UUID(uuidString: "C1A55E01-20A3-4000-8000-0000000000A3")!,
            title: "EWR — Newark Liberty International Airport",
            geocodeQuery: "Terminal C, 3 Brewster Road, Newark, NJ 07114",
            latitude: 40.6948162, longitude: -74.1782262,
            radiusMeters: 500, kind: .travelStop,
            hint: "Check in at Terminal C landside on Brewster Road — the bus loop is public.",
            fallbackCode: "ewrcheck", markerSymbol: "airplane.departure",
            characters: [],
            souvenir: Souvenir(
                id: UUID(uuidString: "C1A55E01-30A3-4000-8000-0000000000A3")!,
                name: "Baggage Claim",
                detail: "A Newark travel collectible from the Terminal C landside loop.",
                symbol: "suitcase.rolling"
            ),
            message: FriendNote(
                id: UUID(uuidString: "C1A55E01-50A3-4000-8000-0000000000A3")!,
                title: "EWR check-in", senderName: "Landside",
                body: "Newark is part of the trip too.",
                xpValue: 0
            ),
            sortOrder: 32, unlocksCharacterOnVisit: false
        ),
    ]
}

extension CheckpointCatalog.Entry {
    var asLocation: GameLocation {
        GameLocation(
            id: locationId, title: title, latitude: latitude, longitude: longitude,
            radiusMeters: radiusMeters, maxAccuracyMeters: 250, dwellSeconds: 0, hint: hint,
            sortOrder: sortOrder, hasFallback: true
        )
    }

    func asLandmark(visited: Bool) -> Landmark {
        Landmark(
            id: landmarkId ?? id, locationId: locationId, title: title,
            description: hint, story: message.body, imagePath: nil,
            required: false, visited: visited, sortOrder: sortOrder
        )
    }

    func asMessagePin(unlocked: Bool) -> MessagePin {
        MessagePin(
            id: message.id, locationId: locationId, title: message.title,
            senderName: unlocked ? message.senderName : nil, visibility: "location_locked",
            required: false, unlocked: unlocked,
            unlockType: kind == .memoryStop ? "passport" : "location",
            unlockRule: "all",
            passportStampKey: MemoryPassport.stampKey(forLocationTitle: title),
            lockedHint: "A birthday note is waiting after this stop.",
            revealSender: false,
            hasPhoto: false,
            hasAudio: false
        )
    }

    func asFriendMessage() -> FriendMessage {
        FriendMessage(
            id: message.id, title: message.title, senderName: message.senderName,
            body: message.body, locationId: locationId, unlockedAt: .now, media: [],
            passportStampKey: MemoryPassport.stampKey(forLocationTitle: title)
        )
    }

    var checkpointXP: Int {
        switch kind {
        case .memoryStop:
            return title == "Chip City Chelsea" ? 75 : 100
        case .wildEncounter:
            return characters.first?.xpValue ?? 0
        case .specialEncounter:
            return characters.reduce(0) { $0 + $1.xpValue }
        case .travelStop:
            return 100
        }
    }

    var airportCode: String? {
        if title.hasPrefix("JFK") { return "JFK" }
        if title.hasPrefix("LGA") { return "LGA" }
        if title.hasPrefix("EWR") { return "EWR" }
        return nil
    }

    var isComplete: (PlayerSnapshot) -> Bool {
        { snapshot in
            if kind == .travelStop {
                return snapshot.landmarks.contains { $0.id == landmarkId && $0.visited }
            }
            let charactersDone = characters.allSatisfy { creature in
                snapshot.characters.contains { $0.id == creature.id && $0.captured }
            }
            let landmarkDone = landmarkId == nil || snapshot.landmarks.contains { $0.id == landmarkId && $0.visited }
            return charactersDone && landmarkDone
        }
    }
}

enum TravelStops {
    static var airports: [CheckpointCatalog.Entry] {
        CheckpointCatalog.entries.filter { $0.kind == .travelStop }
    }

    static func isTravelSouvenir(_ id: UUID) -> Bool {
        airports.contains { $0.souvenir?.id == id }
    }

    static let achievementTitle = "NYC Jetsetter"
}

extension CheckpointCatalog.Creature {
    func asCharacter(locationId: UUID, captured: Bool) -> Character {
        Character(
            id: id, locationId: locationId, name: name, category: category, rarity: rarity,
            required: false, xpValue: xpValue, sortOrder: 0, captured: captured,
            description: description, personality: personality, specialAbility: ability,
            artworkPath: nil
        )
    }
}

extension Landmark {
    func withVisited(_ visited: Bool) -> Landmark {
        Landmark(
            id: id, locationId: locationId, title: title, description: description,
            story: story, imagePath: imagePath, required: required, visited: visited, sortOrder: sortOrder
        )
    }
}

extension MessagePin {
    func withUnlocked(_ unlocked: Bool) -> MessagePin {
        MessagePin(
            id: id, locationId: locationId, title: title, senderName: senderName,
            visibility: visibility, required: required, unlocked: unlocked,
            unlockType: unlockType, unlockRule: unlockRule, characterId: characterId,
            passportStampKey: passportStampKey, lockedHint: lockedHint, revealSender: revealSender,
            hasPhoto: hasPhoto, hasAudio: hasAudio
        )
    }
}

extension GameSummary {
    func addingXP(_ amount: Int) -> GameSummary {
        withXP(xp + amount)
    }

    func withXP(_ value: Int) -> GameSummary {
        GameSummary(
            id: id, title: title, recipientName: recipientName, introMessage: introMessage,
            coverArtPath: coverArtPath, launchAt: launchAt, xp: max(0, value), avatarStyle: avatarStyle
        )
    }
}

extension Character {
    var checkpointCreature: CheckpointCatalog.Creature? {
        CheckpointCatalog.entries.flatMap(\.characters).first { $0.id == id || $0.name.caseInsensitiveCompare(name) == .orderedSame }
    }
}
