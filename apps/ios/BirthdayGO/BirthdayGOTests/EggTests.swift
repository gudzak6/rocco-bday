import Foundation
import Testing
@testable import BirthdayGO

struct EggDistanceTests {
    @Test func oneAndTenMileConversions() {
        #expect(abs(EggDistance.meters(fromMiles: 1) - 1_609.344) < 0.001)
        #expect(abs(EggDistance.meters(fromMiles: 10) - 16_093.44) < 0.001)
        #expect(abs(EggDistance.miles(fromMeters: 1_609.344) - 1) < 0.001)
        #expect(EggDistance.formattedMiles(1_126.54) == "0.7")
    }
}

struct WalkFilterTests {
    @Test func rejectsInaccurateAndDrift() {
        let start = WalkSample(latitude: 40.7720, longitude: -73.9543, timestamp: Date(timeIntervalSince1970: 1_000), horizontalAccuracy: 8, reportedSpeed: 1.2)
        let drift = WalkSample(latitude: 40.772001, longitude: -73.9543, timestamp: Date(timeIntervalSince1970: 1_004), horizontalAccuracy: 8, reportedSpeed: 0.1)
        let fuzzy = WalkSample(latitude: 40.7722, longitude: -73.9543, timestamp: Date(timeIntervalSince1970: 1_006), horizontalAccuracy: 80, reportedSpeed: 1.2)
        #expect(WalkFilter.acceptedMeters(from: start, to: drift, activity: .walking) == nil)
        #expect(WalkFilter.acceptedMeters(from: start, to: fuzzy, activity: .walking) == nil)
    }

    @Test func rejectsVehicleAndSubwayLikeJumps() {
        let start = WalkSample(latitude: 40.7720, longitude: -73.9543, timestamp: Date(timeIntervalSince1970: 2_000), horizontalAccuracy: 10, reportedSpeed: 1)
        let jump = WalkSample(latitude: 40.7800, longitude: -73.9543, timestamp: Date(timeIntervalSince1970: 2_008), horizontalAccuracy: 12, reportedSpeed: 18)
        let car = WalkSample(latitude: 40.7723, longitude: -73.9543, timestamp: Date(timeIntervalSince1970: 2_004), horizontalAccuracy: 12, reportedSpeed: 12)
        #expect(WalkFilter.acceptedMeters(from: start, to: jump, activity: .unknown) == nil)
        #expect(WalkFilter.acceptedMeters(from: start, to: car, activity: .automotive) == nil)
        #expect(WalkFilter.acceptedMeters(from: start, to: car, activity: .cycling) == nil)
        #expect(WalkFilter.acceptedMeters(from: start, to: car, activity: .stationary) == nil)
    }

    @Test func acceptsAWalkingStep() {
        let start = WalkSample(latitude: 40.77200, longitude: -73.95430, timestamp: Date(timeIntervalSince1970: 3_000), horizontalAccuracy: 8, reportedSpeed: 1.3)
        let next = WalkSample(latitude: 40.77208, longitude: -73.95430, timestamp: Date(timeIntervalSince1970: 3_008), horizontalAccuracy: 8, reportedSpeed: 1.3)
        let meters = WalkFilter.acceptedMeters(from: start, to: next, activity: .walking)
        #expect(meters != nil)
        #expect((meters ?? 0) > 5 && (meters ?? 0) < 20)
    }

    @Test func uncertainActivityUsesConservativeSpeeds() {
        let start = WalkSample(latitude: 40.77200, longitude: -73.95430, timestamp: Date(timeIntervalSince1970: 4_000), horizontalAccuracy: 8, reportedSpeed: 3.0)
        let fast = WalkSample(latitude: 40.77225, longitude: -73.95430, timestamp: Date(timeIntervalSince1970: 4_004), horizontalAccuracy: 8, reportedSpeed: 3.0)
        #expect(WalkFilter.acceptedMeters(from: start, to: fast, activity: nil) == nil)
        #expect(WalkFilter.acceptedMeters(from: start, to: fast, activity: .unknown) == nil)
    }
}

struct EggRewardPickerTests {
    private let balloon = EggCatalog.exclusiveCharacters[0]
    private let snack = EggCatalog.exclusiveCharacters[1]
    private let crown = EggCatalog.exclusiveCharacters[4]

    @Test func oneMilePoolExcludesLegendary() {
        var generator = SeededGenerator(seed: 3)
        let type = EggCatalog.defaults[0]
        let decision = EggRewardPicker.decide(
            type: type,
            characters: EggCatalog.exclusiveCharacters,
            collectedIds: [],
            collectedNames: [],
            generator: &generator
        )
        guard case .character(let id, let xp) = decision else {
            Issue.record("expected a character")
            return
        }
        let chosen = EggCatalog.exclusiveCharacters.first { $0.id == id }
        #expect(chosen?.rarity != .legendary)
        #expect(xp == 50)
    }

    @Test func duplicatePolicyAwardsConfiguredXp() {
        var generator = SeededGenerator(seed: 1)
        let type = EggCatalog.defaults[0]
        let collected = Set(EggCatalog.exclusiveCharacters.map(\.id))
        let decision = EggRewardPicker.decide(
            type: type,
            characters: EggCatalog.exclusiveCharacters,
            collectedIds: collected,
            collectedNames: Set(EggCatalog.exclusiveCharacters.map(\.name)),
            generator: &generator
        )
        #expect(decision == .duplicate(xp: 15))
    }

    @Test func persistedChoiceDoesNotReroll() {
        #expect(balloon.id != snack.id)
        let first = HatchDecision.character(balloon.id, xp: 50)
        let second = HatchDecision.character(balloon.id, xp: 50)
        #expect(first == second)
        #expect(crown.rarity == .legendary)
    }

    @Test func catalogDistancesAreConfigurable() {
        #expect(EggCatalog.defaults.contains { $0.key == "one-mile" && abs($0.requiredMeters - 1_609.344) < 0.01 })
        #expect(EggCatalog.defaults.contains { $0.key == "ten-mile" && abs($0.requiredMeters - 16_093.44) < 0.01 })
    }
}

struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        return state
    }
}
