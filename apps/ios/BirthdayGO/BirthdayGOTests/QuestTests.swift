import Foundation
import Testing
@testable import BirthdayGO

struct QuestSoundTests {
    @Test func bundledJumpClearAndRetroWaveFiles() {
        #expect(Bundle.main.url(forResource: "smb_jump-small", withExtension: "wav", subdirectory: "Sounds") != nil)
        #expect(Bundle.main.url(forResource: "smb_world_clear", withExtension: "wav", subdirectory: "Sounds") != nil)
        #expect(Bundle.main.url(forResource: "freesound_community-retro-wave-style-track-59892", withExtension: "mp3", subdirectory: "Sounds") != nil)
    }
}

struct QuestUnlockTests {
    @Test func onlyLevelOneStartsOpen() {
        let done: Set<Int> = []
        #expect(QuestRules.isUnlocked(level: 1, completed: done))
        #expect(!QuestRules.isUnlocked(level: 2, completed: done))
        #expect(QuestRules.currentLevel(completed: done) == 1)
    }

    @Test func clearingALevelOpensTheNext() {
        var done: Set<Int> = [1]
        #expect(QuestRules.isUnlocked(level: 2, completed: done))
        #expect(!QuestRules.isUnlocked(level: 3, completed: done))
        done.insert(2)
        #expect(QuestRules.isUnlocked(level: 3, completed: done))
        #expect(QuestRules.currentLevel(completed: done) == 3)
    }

    @Test func catalogHasSevenLevelsInOrder() {
        #expect(QuestCatalog.levels.map(\.number) == Array(QuestRules.levelRange))
        #expect(Set(QuestCatalog.levels.map(\.title)).count == QuestRules.levelCount)
        #expect(!QuestCatalog.levels.contains { ["Gamer Mode", "The Loyalty Test", "Long Island Legend", "Rock Climbing Rush"].contains($0.title) })
    }
}

struct QuestPhotoUnlockTests {
    @Test func everyWinUnlocksEveryPhotoExactlyOnce() {
        let names = (1...40).map { "photo-\($0).jpg" }
        var taken = Set<String>()
        var unlocked: [String] = []
        for level in QuestRules.levelRange {
            let picked = QuestPhotoUnlocks.choose(level: level, filenames: names, taken: taken)
            #expect(picked.count == QuestPhotoUnlocks.count(for: level, total: names.count))
            #expect(Set(picked).isDisjoint(with: taken))
            taken.formUnion(picked)
            unlocked.append(contentsOf: picked)
        }
        #expect(unlocked.count == 40)
        #expect(Set(unlocked) == Set(names))
    }

    @Test @MainActor func everyAlbumShowsItsPhotosImmediately() {
        let suite = "quest-album-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let progress = QuestProgress(defaults: defaults)
        let total = PhotoDropCatalog.drops().count
        let assigned = QuestRules.levelRange.flatMap { progress.photos(for: $0) }
        #expect(assigned.count == total)
        #expect(Set(assigned).count == total)
        let first = progress.photos(for: 1)
        #expect(first.count == QuestPhotoUnlocks.count(for: 1, total: total))
        #expect(Set(first).isDisjoint(with: Set(progress.photos(for: 2))))
        progress.complete(1)
        #expect(progress.photos(for: 1) == first)
        defaults.removePersistentDomain(forName: suite)
    }

    @Test @MainActor func retiredLevelsAreDroppedAndLaterWinsKeepTheirAlbums() {
        let suite = "quest-retire-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        defaults.set([1, 2, 3, 4, 5, 8], forKey: "roccoQuest.completedLevels")
        let raw = ["5": ["old-gamer.jpg"], "8": ["memory-lane.jpg"]]
        defaults.set(try? JSONEncoder().encode(raw), forKey: "roccoQuest.photosByLevel")
        let progress = QuestProgress(defaults: defaults)
        let catalog = Set(PhotoDropCatalog.drops().map(\.filename))
        #expect(progress.completed == Set([1, 2, 3, 4]))
        #expect(!progress.photos(for: 4).contains("old-gamer.jpg"))
        #expect(!progress.photos(for: 4).contains("memory-lane.jpg"))
        #expect(Set(progress.photos(for: 4)).isSubset(of: catalog))
        #expect(!progress.photos(for: 4).isEmpty || catalog.isEmpty)
        defaults.removePersistentDomain(forName: suite)
    }
}

struct MazeMovementTests {
    private func step(_ mover: inout MazeMover, seconds: CGFloat, speed: CGFloat, blocked: (CGPoint) -> Bool) {
        mover.speed = speed
        let dt: CGFloat = 1.0 / 120.0
        let ticks = Int(seconds / dt)
        for _ in 0..<ticks {
            mover.advance(dt: dt, blocked: blocked)
        }
    }

    @Test func reverseHappensImmediately() {
        var mover = MazeMover(position: CGPoint(x: 5.4, y: 1), current: .right, requested: .left, speed: 10)
        let open: (CGPoint) -> Bool = { point in
            let x = Int(round(point.x))
            let y = Int(round(point.y))
            return !(y == 1 && (0...10).contains(x))
        }
        step(&mover, seconds: 0.1, speed: 10, blocked: open)
        #expect(mover.current == .left)
        #expect(abs(mover.position.x - 4.4) < 0.04)
        #expect(abs(mover.position.y - 1) < 0.001)
    }

    @Test func turnWaitsUntilTheIntersection() {
        var mover = MazeMover(position: CGPoint(x: 2.2, y: 1), current: .right, requested: .up, speed: 6)
        let blocked: (CGPoint) -> Bool = { point in
            let x = Int(round(point.x))
            let y = Int(round(point.y))
            let hallway = y == 1 && (0...8).contains(x)
            let shaft = x == 5 && (0...1).contains(y)
            return !(hallway || shaft)
        }
        step(&mover, seconds: 0.3, speed: 6, blocked: blocked)
        #expect(mover.current == .right)
        #expect(abs(mover.position.y - 1) < 0.001)
        #expect(abs(mover.position.x - 4.0) < 0.05)
        step(&mover, seconds: 0.35, speed: 6, blocked: blocked)
        #expect(mover.current == .up)
        #expect(abs(mover.position.x - 5) < 0.02)
        #expect(mover.position.y < 0.95)
    }

    @Test func moverStopsAtTheCenterBeforeAWall() {
        var mover = MazeMover(position: CGPoint(x: 1, y: 1), current: .right, requested: .right, speed: 10)
        let blocked: (CGPoint) -> Bool = { point in
            let x = Int(round(point.x))
            let y = Int(round(point.y))
            return !(y == 1 && (1...2).contains(x))
        }
        step(&mover, seconds: 0.5, speed: 10, blocked: blocked)
        #expect(mover.current == .right)
        #expect(abs(mover.position.x - 2) < 0.02)
        #expect(abs(mover.position.y - 1) < 0.001)
    }
}
