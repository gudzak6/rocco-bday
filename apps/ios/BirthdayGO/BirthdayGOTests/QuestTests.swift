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
        #expect(!QuestCatalog.levels.contains { $0.title == "Gamer Mode" || $0.title == "The Loyalty Test" || $0.title == "Long Island Legend" })
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

    @Test @MainActor func completedLevelsKeepTheirOwnAlbum() {
        let suite = "quest-album-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let progress = QuestProgress(defaults: defaults)
        #expect(progress.photos(for: 1).isEmpty)
        progress.complete(1)
        let first = progress.photos(for: 1)
        #expect(progress.photos(for: 2).isEmpty)
        #expect(first.count == QuestPhotoUnlocks.count(for: 1, total: PhotoDropCatalog.drops().count))
        if !first.isEmpty {
            progress.complete(2)
            let second = progress.photos(for: 2)
            #expect(Set(first).isDisjoint(with: Set(second)))
            #expect(progress.photos(for: 1) == first)
        }
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
        #expect(progress.completed == Set([1, 2, 3, 4, 5]))
        #expect(!progress.photos(for: 5).contains("old-gamer.jpg"))
        #expect(!progress.photos(for: 5).contains("memory-lane.jpg"))
        #expect(Set(progress.photos(for: 5)).isSubset(of: catalog))
        #expect(!progress.photos(for: 5).isEmpty || catalog.isEmpty)
        defaults.removePersistentDomain(forName: suite)
    }
}
