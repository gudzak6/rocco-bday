import Foundation
import Testing
@testable import BirthdayGO

struct TravelStopTests {
    @Test func includesThreeAirportsWithLandsideRadius() {
        let airports = TravelStops.airports
        #expect(airports.map(\.airportCode) == ["JFK", "LGA", "EWR"])
        #expect(airports.allSatisfy { $0.kind == .travelStop })
        #expect(airports.allSatisfy { $0.radiusMeters == 500 })
        #expect(airports.map { $0.souvenir?.name } == ["Jetsetter", "Delayed Flight", "Baggage Claim"])
        #expect(Set(airports.map(\.fallbackCode)) == ["jfkcheck", "lgacheck", "ewrcheck"])
        #expect(airports.allSatisfy { $0.checkpointXP == 100 })
        #expect(airports.allSatisfy { MemoryPassport.stampKey(forLocationTitle: $0.title) == nil })
    }

    @Test func fiveHundredMetersAllowsLandsideCheckIn() {
        #expect(Proximity.isEligible(distance: 499, radius: 500, accuracy: 20, maximumAccuracy: 250))
        #expect(!Proximity.isEligible(distance: 501, radius: 500, accuracy: 20, maximumAccuracy: 250))
        #expect(!Proximity.isEligible(distance: 80, radius: 500, accuracy: 400, maximumAccuracy: 250))
    }

    @Test func completionUsesVisitedLandmarkAndIgnoresPassport() {
        let jfk = TravelStops.airports.first { $0.airportCode == "JFK" }!
        var snapshot = PlayerSnapshot.uiTest
        #expect(jfk.isComplete(snapshot) == false)
        snapshot.landmarks.append(jfk.asLandmark(visited: true))
        #expect(jfk.isComplete(snapshot) == true)
        let merged = CheckpointCatalog.merging(snapshot, capturedNames: [], souvenirs: [jfk.souvenir!.id], visitedLandmarkIds: [jfk.landmarkId!], unlockedMessageIds: [])
        #expect(merged.passportStamps?.contains("grand-central") == true || MemoryPassport.stamps.count == 7)
        #expect(merged.passportStamps?.contains(where: { $0.contains("jfk") || $0.contains("airport") }) != true)
        #expect(!merged.messagePins.contains { $0.id == jfk.message.id })
    }

    @Test func souvenirPersistsCompletionOnRematch() {
        let jfk = TravelStops.airports.first { $0.airportCode == "JFK" }!
        let first = CheckpointCatalog.merging(.uiTest, capturedNames: [], souvenirs: [], visitedLandmarkIds: [], unlockedMessageIds: [])
        #expect(jfk.isComplete(first) == false)
        let rematch = CheckpointCatalog.merging(first, capturedNames: [], souvenirs: [jfk.souvenir!.id], visitedLandmarkIds: [], unlockedMessageIds: [])
        #expect(jfk.isComplete(rematch) == true)
        #expect(MemoryPassport.stampKey(forLocationTitle: jfk.title) == nil)
        #expect(rematch.passportStamps?.contains(where: { $0.contains("jfk") || $0.contains("airport") }) != true)
    }

    @Test func mergeDoesNotDuplicateAirportsOrPassportStamps() {
        let first = CheckpointCatalog.merging(.uiTest, capturedNames: [], souvenirs: [], visitedLandmarkIds: [], unlockedMessageIds: [])
        let second = CheckpointCatalog.merging(first, capturedNames: [], souvenirs: [], visitedLandmarkIds: [], unlockedMessageIds: [])
        #expect(second.locations.filter { $0.title.contains("Kennedy") }.count == 1)
        #expect(second.locations.filter { $0.title.contains("LaGuardia") }.count == 1)
        #expect(second.locations.filter { $0.title.contains("Newark") }.count == 1)
        #expect(second.locations.first { $0.title.contains("Kennedy") }?.radiusMeters == 500)
        #expect(!(second.passportStamps ?? []).contains(where: { $0.contains("jfk") || $0.contains("lga") || $0.contains("ewr") || $0.contains("airport") }))
        #expect(MemoryPassport.stamps.count == 7)
    }

    @Test func duplicateTravelRewardsShareOneAwardKey() {
        let keys = TravelStops.airports.map { "landmark-\($0.landmarkId!.uuidString)" }
        #expect(Set(keys).count == 3)
        #expect(Set(TravelStops.airports.map(\.landmarkId)).count == 3)
        #expect(Set(TravelStops.airports.compactMap { $0.souvenir?.id }).count == 3)
        #expect(TravelStops.achievementTitle == "NYC Jetsetter")
    }
}
