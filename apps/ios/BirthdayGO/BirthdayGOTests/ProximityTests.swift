import Testing
import CoreGraphics
import Foundation
@testable import BirthdayGO

struct ProximityTests {
    @Test func distanceAtSameCoordinateIsZero() {
        #expect(Proximity.distanceMeters(latitude: 40, longitude: -74, targetLatitude: 40, targetLongitude: -74) < 0.01)
    }

    @Test func radiusRequiresAcceptableAccuracy() {
        #expect(Proximity.isEligible(distance: 74.9, radius: 75, accuracy: 15))
        #expect(!Proximity.isEligible(distance: 76, radius: 75, accuracy: 15))
        #expect(!Proximity.isEligible(distance: 20, radius: 75, accuracy: 120))
        #expect(!Proximity.isEligible(distance: 20, radius: 75, accuracy: -1))
    }

    @Test func knownDistanceIsReasonable() {
        let distance = Proximity.distanceMeters(
            latitude: 40.7484, longitude: -73.9857,
            targetLatitude: 40.7580, targetLongitude: -73.9855
        )
        #expect(distance > 1_000 && distance < 1_100)
    }

    @Test func markerStatusUsesDistanceAccuracyAndImmediate() {
        #expect(MarkerStatus.resolve(completed: true, immediate: false, distance: 200, radius: 75, accuracy: 10, maximumAccuracy: 100) == .completed)
        #expect(MarkerStatus.resolve(completed: false, immediate: true, distance: nil, radius: 75, accuracy: nil, maximumAccuracy: 100) == .available)
        #expect(MarkerStatus.resolve(completed: false, immediate: false, distance: 20, radius: 75, accuracy: 12, maximumAccuracy: 100) == .available)
        #expect(MarkerStatus.resolve(completed: false, immediate: false, distance: 120, radius: 75, accuracy: 12, maximumAccuracy: 100) == .nearby)
        #expect(MarkerStatus.resolve(completed: false, immediate: false, distance: 800, radius: 75, accuracy: 12, maximumAccuracy: 100) == .locked)
        #expect(MarkerStatus.resolve(completed: false, immediate: false, distance: 20, radius: 75, accuracy: 250, maximumAccuracy: 100) == .nearby)
    }
}

struct CatCatalogTests {
    @Test func includesChairCatAndRugCat() {
        #expect(CatCatalog.entries.map(\.name) == ["Chair Cat", "Rug Cat"])
        #expect(CatCatalog.entry(named: "Chair Cat")?.combatPower == 324)
        #expect(CatCatalog.entry(named: "Rug Cat")?.rarity == .rare)
        #expect(CatCatalog.entries.allSatisfy { $0.radiusMeters == 50 })
        #expect(CatCatalog.entry(named: "Chair Cat")?.idleAsset == "ChairCatIdle")
        #expect(CatCatalog.entry(named: "Chair Cat")?.mapAsset == "ChairCatMap")
        #expect(CatCatalog.entry(named: "Chair Cat")?.caughtAsset == "ChairCatCaught")
        #expect(CatCatalog.entry(named: "Rug Cat")?.idleAsset == "RugCatIdle")
        #expect(CatCatalog.entry(named: "Rug Cat")?.mapAsset == "RugCatMap")
        #expect(CatCatalog.entry(named: "Rug Cat")?.playfulAsset == "RugCatPlayful")
        #expect(CatCatalog.entry(named: "Chair Cat")?.idleAsset == "ChairCatIdle")
        #expect(CatCatalog.entry(named: "Rug Cat")?.idleAsset == "RugCatIdle")
    }

    @Test func fiftyMeterRadiusBlocksDistantPlayers() {
        let chair = CatCatalog.entry(named: "Chair Cat")!
        let inside = Proximity.distanceMeters(
            latitude: chair.latitude, longitude: chair.longitude,
            targetLatitude: chair.latitude, targetLongitude: chair.longitude
        )
        #expect(inside < 1)
        #expect(Proximity.isEligible(distance: 49, radius: 50, accuracy: 10, maximumAccuracy: 250))
        #expect(!Proximity.isEligible(distance: 51, radius: 50, accuracy: 10, maximumAccuracy: 250))
    }

    @Test func mergeDoesNotDuplicateCatalogCats() {
        let first = CatCatalog.merging(.uiTest, capturedNames: [])
        let second = CatCatalog.merging(first, capturedNames: ["Chair Cat"])
        #expect(second.characters.filter { $0.name == "Chair Cat" }.count == 1)
        #expect(second.characters.first { $0.name == "Chair Cat" }?.captured == true)
        #expect(second.characters.first { $0.name == "Rug Cat" }?.captured == false)
        let rugPlace = second.locations.first { $0.title == "The living-room rug" }
        #expect(rugPlace?.latitude == 40.7720308)
        #expect(rugPlace?.longitude == -73.9543142)
    }
}

struct CheckpointCatalogTests {
    @Test func includesSevenPublicStops() {
        let cityStops = CheckpointCatalog.entries.filter { $0.kind != .travelStop }
        #expect(cityStops.count == 7)
        #expect(Set(cityStops.map(\.title)) == [
            "Grand Central Terminal", "Penn Station", "NYRR RUNCENTER",
            "Chip City Rockefeller", "Chip City Chelsea", "Williamsburg", "Upper East Side",
        ])
        #expect(cityStops.allSatisfy { $0.radiusMeters == 75 })
    }

    @Test func chipCityStopsStayDistinct() {
        let rock = CheckpointCatalog.entry(named: "Chip City Rockefeller")!
        let chelsea = CheckpointCatalog.entry(named: "Chip City Chelsea")!
        #expect(rock.locationId != chelsea.locationId)
        #expect(rock.characters.first?.id != chelsea.souvenir?.id)
        #expect(chelsea.souvenir?.id != rock.characters.first?.id)
        #expect(rock.kind == .wildEncounter)
        #expect(chelsea.kind == .memoryStop)
        #expect(chelsea.souvenir?.name == "Chelsea Cookie Tin")
    }

    @Test func playerTitlesHideResidentialAddresses() {
        let blob = CheckpointCatalog.entries.map { "\($0.title) \($0.hint)" }.joined(separator: " ")
        #expect(!blob.contains("78th"))
        #expect(!blob.contains("Jackson St"))
        #expect(!blob.contains("334"))
        #expect(!blob.contains("71 Jackson"))
    }

    @Test func mergeAddsCheckpointsOnce() {
        let first = CheckpointCatalog.merging(.uiTest, capturedNames: [], souvenirs: [], visitedLandmarkIds: [], unlockedMessageIds: [])
        let second = CheckpointCatalog.merging(first, capturedNames: ["Joey"], souvenirs: [], visitedLandmarkIds: [], unlockedMessageIds: [])
        #expect(second.locations.filter { $0.title == "Grand Central Terminal" }.count == 1)
        #expect(second.characters.filter { $0.name == "Joey" }.count == 1)
        #expect(second.characters.first { $0.name == "Joey" }?.captured == true)
        #expect(second.characters.filter { $0.name == "Confused Anya" }.count == 1)
    }
}

struct CreatureKindTests {
    @Test func mapsPublishedExampleCreatures() {
        #expect(CreatureKind.resolving(category: "food") == .pastry)
        #expect(CreatureKind.resolving(category: "memory") == .map)
        #expect(CreatureKind.resolving(category: "legendary") == .candle)
        #expect(CreatureKind.resolving(category: "inside_joke") == .spark)
        #expect(CreatureKind.resolving(category: "friend") == .buddy)
        #expect(CreatureKind.resolving(category: "friend", rarity: .legendary) == .candle)
    }
}

struct CatchPhysicsTests {
    @Test func throwGestureNeedsUpwardMotion() {
        #expect(!CatchPhysics.isThrow(CGSize(width: 0, height: -120)))
        #expect(!CatchPhysics.isThrow(CGSize(width: 8, height: -10)))
        #expect(!CatchPhysics.qualifies(translation: CGSize(width: 180, height: -30), velocity: CGSize(width: 900, height: -40)))
        #expect(!CatchPhysics.qualifies(translation: CGSize(width: 0, height: -160), velocity: CGSize(width: 0, height: -80)))
        #expect(CatchPhysics.qualifies(translation: CGSize(width: 24, height: -90), velocity: CGSize(width: 40, height: -900)))
    }

    @Test func hitTestingUsesExpandedTarget() {
        let target = CGRect(x: 100, y: 80, width: 190, height: 180)
        #expect(CatchPhysics.hits(point: CGPoint(x: 195, y: 170), target: target))
        #expect(!CatchPhysics.hits(point: CGPoint(x: 10, y: 10), target: target))
    }

    @Test func arcHitsTheCatAndMissesShortOrWideThrows() {
        let bounds = CGRect(x: 0, y: 0, width: 390, height: 844)
        let target = CGRect(x: 120, y: 280, width: 150, height: 170)
        let hit = CatchPhysics.arc(
            from: CGPoint(x: 195, y: 700),
            translation: CGSize(width: 0, height: -140),
            velocity: CGSize(width: 0, height: -1_400),
            in: bounds
        )
        #expect(CatchPhysics.impactProgress(arc: hit, target: target) != nil)
        let short = CatchPhysics.arc(
            from: CGPoint(x: 195, y: 700),
            translation: CGSize(width: 0, height: -80),
            velocity: .zero,
            in: bounds
        )
        #expect(CatchPhysics.impactProgress(arc: short, target: target) == nil)
        let wide = CatchPhysics.arc(
            from: CGPoint(x: 80, y: 720),
            translation: CGSize(width: -40, height: -90),
            velocity: CGSize(width: -200, height: -500),
            in: bounds
        )
        #expect(CatchPhysics.impactProgress(arc: wide, target: target) == nil)
        #expect(hit.duration < short.duration)
    }

    @Test func arcStaysInsideControlEnvelope() {
        let start = CGPoint(x: 0, y: 200)
        let end = CGPoint(x: 0, y: 40)
        let control = CatchPhysics.controlPoint(from: start, to: end)
        let mid = CatchPhysics.point(start: start, control: control, end: end, t: 0.5)
        #expect(mid.y < start.y)
        #expect(mid.y < 200)
    }
}

struct MapRevealTests {
    @Test func photoDropsStayNearManhattanStops() {
        let first = PhotoDropCatalog.makeDrops(filenames: ["IMG_0009.jpg"])[0]
        let again = PhotoDropCatalog.makeDrops(filenames: ["IMG_0009.jpg"])[0]
        let other = PhotoDropCatalog.makeDrops(filenames: ["IMG_0194.jpg"])[0]
        #expect(first.id == again.id)
        #expect(first.latitude == again.latitude)
        #expect(first.longitude == again.longitude)
        #expect(first.id != other.id)
        for drop in [first, other] {
            let nearest = PhotoDropCatalog.anchors.map {
                Proximity.distanceMeters(
                    latitude: drop.latitude, longitude: drop.longitude,
                    targetLatitude: $0.latitude, targetLongitude: $0.longitude
                )
            }.min() ?? 0
            #expect(nearest >= 119 && nearest <= 410)
        }
    }

    @Test func revealRequiresThePlaceRadius() {
        #expect(MapReveal.isWithinRange(distance: 70, accuracy: 10, radius: 75, maximumAccuracy: 250))
        #expect(!MapReveal.isWithinRange(distance: 90, accuracy: 10, radius: 75, maximumAccuracy: 250))
        #expect(!MapReveal.isWithinRange(distance: 20, accuracy: nil, radius: 75, maximumAccuracy: 250))
        #expect(!MapReveal.isWithinRange(distance: 10, accuracy: 400, radius: 75, maximumAccuracy: 250))
    }

    @Test func hiddenPinsHaveTwentyTaunts() {
        #expect(WalkCloserTaunts.all.count == 20)
        #expect(Set(WalkCloserTaunts.all).count == 20)
        #expect(WalkCloserTaunts.all.contains("Walk closer ya bum for more details"))
        let first = WalkCloserTaunts.next(after: nil)
        #expect(WalkCloserTaunts.all.contains(first))
        #expect(WalkCloserTaunts.next(after: first) != first)
    }

    @Test func bundledPhotosLoadOnce() {
        let drops = PhotoDropCatalog.drops()
        #expect(drops.count == 38)
        #expect(!drops.contains { $0.filename == "000094970013.jpg" })
        #expect(!drops.contains { $0.filename == "000041920016.jpg" })
        #expect(!drops.contains { $0.filename == "000041920006.jpg" })
        #expect(!drops.contains { $0.filename == "000041920003.jpg" })
        #expect(Set(drops.map(\.id)).count == drops.count)
    }
}

struct OnboardingTests {
    @Test func hasSixHowToPlayScreens() {
        #expect(OnboardingPage.all.count == 6)
        #expect(OnboardingPage.all.map(\.headline) == [
            "A Birthday Adventure Awaits!",
            "Play the Quest",
            "Win the Mini-Games",
            "Unlock Photos",
            "A Little Birthday Love",
            "Ready to Play?",
        ])
        #expect(OnboardingPage.all.last?.buttonTitle == "Start My Adventure")
    }
}

struct BirthdayMessagesTests {
    @Test func listsFriendsInOrder() {
        #expect(BirthdayMessages.all.map(\.senderName) == ["Sharon", "Mary", "Sheba", "Joey", "Derek", "Anya"])
        #expect(Set(BirthdayMessages.all.map(\.id)).count == 6)
        #expect(BirthdayMessages.all.first { $0.senderName == "Mary" }?.body.contains("chip city closing") == true)
        #expect(BirthdayMessages.all.first { $0.senderName == "Sheba" }?.body.contains("yap session") == true)
        #expect(BirthdayMessages.all.first { $0.senderName == "Sharon" }?.body == "HAPPY BIRTHDAY ROCCO!!")
        #expect(BirthdayMessages.all.first { $0.senderName == "Derek" }?.body.contains("jets win") == true)
        #expect(BirthdayMessages.all.first { $0.senderName == "Joey" }?.body.contains("cookies and sweet treats") == true)
        let waiting = Set(BirthdayMessages.all.filter { $0.body.contains("[REPLACE]") }.map(\.senderName))
        #expect(waiting == ["Anya"])
    }
}

struct BirthdayNoteTests {
    @Test func immediateNotesAreEligibleWithoutProgress() {
        let pin = MessagePin(
            id: UUID(), locationId: nil, title: "Hello", senderName: "Hidden",
            visibility: "immediate", required: false, unlocked: false, unlockType: "immediate"
        )
        #expect(BirthdayNoteRules.isEligible(pin, snapshot: .uiTest, stamps: []))
    }

    @Test func locationNotesNeedAVisitedPlace() {
        var snapshot = PlayerSnapshot.uiTest
        let pin = MessagePin(
            id: UUID(), locationId: snapshot.locations[0].id, title: "Park note", senderName: "Sam",
            visibility: "location_locked", required: false, unlocked: false, unlockType: "location"
        )
        #expect(!BirthdayNoteRules.isEligible(pin, snapshot: snapshot, stamps: []))
        snapshot.landmarks[0] = snapshot.landmarks[0].withVisited(true)
        #expect(BirthdayNoteRules.isEligible(pin, snapshot: snapshot, stamps: []))
    }

    @Test func characterAndPassportNotesUnlockOncePrerequisitesAreMet() {
        var snapshot = PlayerSnapshot.uiTest
        let characterPin = MessagePin(
            id: UUID(), locationId: nil, title: "Catch note", senderName: nil,
            visibility: "location_locked", required: false, unlocked: false,
            unlockType: "character", characterId: snapshot.characters[0].id
        )
        #expect(!BirthdayNoteRules.isEligible(characterPin, snapshot: snapshot, stamps: []))
        snapshot.characters[0] = snapshot.characters[0].withCaptured(true)
        #expect(BirthdayNoteRules.isEligible(characterPin, snapshot: snapshot, stamps: []))

        let stampPin = MessagePin(
            id: UUID(), locationId: nil, title: "Stamp note", senderName: nil,
            visibility: "location_locked", required: false, unlocked: false,
            unlockType: "passport", passportStampKey: "grand-central"
        )
        #expect(!BirthdayNoteRules.isEligible(stampPin, snapshot: snapshot, stamps: []))
        #expect(BirthdayNoteRules.isEligible(stampPin, snapshot: snapshot, stamps: ["grand-central"]))
    }

    @Test func compositeUsesAllOrAny() {
        var snapshot = PlayerSnapshot.uiTest
        let pin = MessagePin(
            id: UUID(), locationId: snapshot.locations[0].id, title: "Both", senderName: nil,
            visibility: "location_locked", required: false, unlocked: false,
            unlockType: "composite", unlockRule: "all", characterId: snapshot.characters[0].id,
            passportStampKey: "penn-station"
        )
        snapshot.landmarks[0] = snapshot.landmarks[0].withVisited(true)
        snapshot.characters[0] = snapshot.characters[0].withCaptured(true)
        #expect(!BirthdayNoteRules.isEligible(pin, snapshot: snapshot, stamps: []))
        #expect(BirthdayNoteRules.isEligible(pin, snapshot: snapshot, stamps: ["penn-station"]))
        var anyPin = pin
        anyPin.unlockRule = "any"
        #expect(BirthdayNoteRules.isEligible(anyPin, snapshot: snapshot, stamps: []))
    }

    @Test func lockedNotesHideSenderAndBodyUnlessOrganizerAllows() {
        let locked = MessagePin(
            id: UUID(), locationId: nil, title: "Sealed", senderName: "Secret Friend",
            visibility: "location_locked", required: false, unlocked: false,
            lockedHint: "A wish is waiting.", revealSender: false
        )
        #expect(BirthdayNoteRules.spoilerSafeSender(locked) == "A friend")
        #expect(BirthdayNoteRules.spoilerSafePreview(locked, letter: nil) == "A wish is waiting.")
        #expect(!BirthdayNoteRules.spoilerSafePreview(locked, letter: nil).contains("Happy birthday"))
        var revealed = locked
        revealed.revealSender = true
        #expect(BirthdayNoteRules.spoilerSafeSender(revealed) == "Secret Friend")
    }

    @Test func cardsNeverAttachLockedBodies() {
        let cards = BirthdayNoteRules.cards(from: .uiTest)
        let locked = cards.first { $0.pin.title == "A note from a friend" }
        #expect(locked != nil)
        #expect(locked?.letter == nil)
        #expect(locked?.pin.senderName == nil)
        #expect(cards.contains { $0.pin.title == "Saved birthday note" && $0.letter != nil })
    }
}

struct MemoryStopProximityTests {
    @Test func distantNearbyAndInRangeBands() {
        #expect(MemoryStopProximity.band(collected: false, distance: 300, accuracy: 10, maximumAccuracy: 250, previous: nil) == .distant)
        #expect(MemoryStopProximity.band(collected: false, distance: 120, accuracy: 10, maximumAccuracy: 250, previous: nil) == .nearby)
        #expect(MemoryStopProximity.band(collected: false, distance: 40, accuracy: 12, maximumAccuracy: 250, previous: nil) == .inRange)
        #expect(MemoryStopProximity.band(collected: true, distance: 10, accuracy: 12, maximumAccuracy: 250, previous: nil) == .collected)
        #expect(MemoryStopProximity.band(collected: false, distance: nil, accuracy: 8, maximumAccuracy: 250, previous: nil) == .distant)
    }

    @Test func outwardHysteresisHoldsTheCurrentBand() {
        #expect(MemoryStopProximity.band(collected: false, distance: 60, accuracy: 10, maximumAccuracy: 250, previous: .inRange) == .inRange)
        #expect(MemoryStopProximity.band(collected: false, distance: 70, accuracy: 10, maximumAccuracy: 250, previous: .inRange) == .nearby)
        #expect(MemoryStopProximity.band(collected: false, distance: 260, accuracy: 10, maximumAccuracy: 250, previous: .nearby) == .nearby)
        #expect(MemoryStopProximity.band(collected: false, distance: 270, accuracy: 10, maximumAccuracy: 250, previous: .nearby) == .distant)
        #expect(MemoryStopProximity.band(collected: false, distance: 260, accuracy: 10, maximumAccuracy: 250, previous: .distant) == .distant)
    }

    @Test func poorAccuracyCannotEnterRange() {
        #expect(MemoryStopProximity.band(collected: false, distance: 20, accuracy: 400, maximumAccuracy: 250, previous: nil) == .nearby)
        #expect(MemoryStopProximity.band(collected: false, distance: 20, accuracy: -1, maximumAccuracy: 250, previous: nil) == .nearby)
        #expect(MemoryStopProximity.band(collected: false, distance: 20, accuracy: nil, maximumAccuracy: 250, previous: .inRange) == .nearby)
    }

    @Test func visualOverrideDoesNotChangeTheGPSBandUsedForRewards() {
        let gps = MemoryStopProximity.band(collected: false, distance: 400, accuracy: 10, maximumAccuracy: 250, previous: nil)
        let shown = MemoryStopProximity.displayBand(
            collected: false, distance: 400, accuracy: 10, maximumAccuracy: 250, previous: nil, override: .inRange
        )
        #expect(gps == .distant)
        #expect(shown == .inRange)
        #expect(!MemoryStopAward.shouldAward(
            gestureQualified: true, gpsInRange: gps == .inRange, alreadyComplete: false, awardInFlight: false
        ))
        #expect(MemoryStopProximity.displayBand(
            collected: true, distance: 10, accuracy: 8, maximumAccuracy: 250, previous: nil, override: .distant
        ) == .collected)
    }

    @Test func swipeThresholdRejectsTapsAndVerticalDrags() {
        #expect(!MemoryStopSpin.qualifies(translationWidth: 8, translationHeight: 6))
        #expect(!MemoryStopSpin.qualifies(translationWidth: 70, translationHeight: 90))
        #expect(MemoryStopSpin.qualifies(translationWidth: 80, translationHeight: 12))
        #expect(MemoryStopSpin.qualifies(translationWidth: -90, translationHeight: 10))
    }

    @Test func releaseVelocityCoastsAndStops() {
        let forward = MemoryStopSpin.releaseVelocity(pointsPerSecond: 700, translationWidth: 100)
        let backward = MemoryStopSpin.releaseVelocity(pointsPerSecond: -40, translationWidth: -80)
        #expect(forward > 0)
        #expect(backward < 0)
        let later = MemoryStopSpin.velocity(initial: forward, friction: MemoryStopSpin.friction, elapsed: 0.4)
        let settled = MemoryStopSpin.velocity(initial: forward, friction: MemoryStopSpin.friction, elapsed: 3)
        #expect(later < forward)
        #expect(abs(settled) < abs(later))
        let spun = MemoryStopSpin.angle(startAngle: 15, velocity: forward, friction: MemoryStopSpin.friction, elapsed: 0.3)
        #expect(spun > 15)
        #expect(MemoryStopSpin.settleDuration(velocity: forward) > 0)
    }

    @Test func awardIsOneShotAndRequiresAGPSFix() {
        #expect(MemoryStopAward.shouldAward(gestureQualified: true, gpsInRange: true, alreadyComplete: false, awardInFlight: false))
        #expect(!MemoryStopAward.shouldAward(gestureQualified: false, gpsInRange: true, alreadyComplete: false, awardInFlight: false))
        #expect(!MemoryStopAward.shouldAward(gestureQualified: true, gpsInRange: false, alreadyComplete: false, awardInFlight: false))
        #expect(!MemoryStopAward.shouldAward(gestureQualified: true, gpsInRange: true, alreadyComplete: true, awardInFlight: false))
        #expect(!MemoryStopAward.shouldAward(gestureQualified: true, gpsInRange: true, alreadyComplete: false, awardInFlight: true))
    }

    @Test func standardMemoryStopsKeepExistingXP() {
        #expect(CheckpointCatalog.entry(named: "Grand Central Terminal")?.checkpointXP == 100)
        #expect(CheckpointCatalog.entry(named: "NYRR RUNCENTER")?.checkpointXP == 100)
        #expect(CheckpointCatalog.entry(named: "Chip City Chelsea")?.checkpointXP == 75)
        #expect(CheckpointCatalog.entries.filter { $0.kind == .memoryStop }.count == 3)
    }
}

struct ProgressionTests {
    @Test func levelIncreasesEveryFiveHundredXP() {
        #expect(Progression.level(xp: 0) == 1)
        #expect(Progression.level(xp: 499) == 1)
        #expect(Progression.level(xp: 500) == 2)
        #expect(Progression.level(xp: 1250) == 3)
    }

    @Test func finaleIgnoresOptionalContent() {
        let required = Character(
            id: UUID(), locationId: UUID(), name: "Required", category: "friend", rarity: .common,
            required: true, xpValue: 100, sortOrder: 0, captured: true,
            description: nil, personality: nil, specialAbility: nil, artworkPath: nil
        )
        let optional = Character(
            id: UUID(), locationId: UUID(), name: "Optional", category: "food", rarity: .rare,
            required: false, xpValue: 150, sortOrder: 1, captured: false,
            description: nil, personality: nil, specialAbility: nil, artworkPath: nil
        )
        #expect(Progression.isComplete(characters: [required, optional], messages: [], landmarks: []))
        #expect(!Progression.isComplete(characters: [required, optional].map {
            $0.required ? Character(
                id: $0.id, locationId: $0.locationId, name: $0.name, category: $0.category, rarity: $0.rarity,
                required: true, xpValue: $0.xpValue, sortOrder: $0.sortOrder, captured: false,
                description: nil, personality: nil, specialAbility: nil, artworkPath: nil
            ) : $0
        }, messages: [], landmarks: []))
    }

    @Test func pendingProgressEncodesIdempotencyKey() throws {
        let operation = PendingProgress(
            id: UUID(), contentType: "character", contentId: UUID(),
            latitude: 40.7, longitude: -74.0, horizontalAccuracy: 8,
            dwellStartedAt: Date(timeIntervalSince1970: 0), fallbackCode: nil
        )
        let data = try JSONEncoder.supabase.encode(operation)
        let json = try #require(String(data: data, encoding: .utf8))
        #expect(json.contains("idempotencyKey"))
        #expect(!json.contains("\"id\""))
    }
}
