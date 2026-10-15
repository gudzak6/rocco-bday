import Foundation
import SwiftData
import UIKit
import CoreLocation

@MainActor
final class GameStore: ObservableObject {
    enum Phase { case loading, needsInvitation, ready }

    @Published private(set) var phase: Phase = .loading
    @Published private(set) var snapshot: PlayerSnapshot?
    @Published var errorMessage: String?
    @Published var isWorking = false
    @Published var hasSeenWelcome = false
    @Published var showHowToPlay = false
    @Published var avatarColor = "purple"
    @Published var noteUnlockBanner: String?
    @Published var eggReadyBanner: String?
    @Published private(set) var eggRevision = 0

    enum HatchPresentation: Equatable {
        case character(Character, xp: Int)
        case duplicate(xp: Int)

        var xp: Int {
            switch self {
            case .character(_, let xp), .duplicate(let xp): xp
            }
        }
    }

    let installationId: UUID
    private let api: APIClient?
    private var modelContext: ModelContext?
    private var pending: [PendingProgress] = []
    private weak var walkTracker: WalkTracker?

    init() {
        if let saved = UserDefaults.standard.string(forKey: "installationId"), let id = UUID(uuidString: saved) {
            installationId = id
        } else {
            let id = UUID()
            installationId = id
            UserDefaults.standard.set(id.uuidString, forKey: "installationId")
        }
        avatarColor = UserDefaults.standard.string(forKey: "avatarColor") ?? "purple"
        hasSeenWelcome = UserDefaults.standard.bool(forKey: "hasSeenWelcome")
        api = try? APIClient()
        pending = (try? JSONDecoder.supabase.decode(
            [PendingProgress].self,
            from: UserDefaults.standard.data(forKey: "pendingProgress") ?? Data()
        )) ?? []
    }

    func configure(modelContext: ModelContext) {
        guard self.modelContext == nil else { return }
        self.modelContext = modelContext
    }

    func launch() async {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-ui-testing-ready") {
            snapshot = mergedSnapshot(.uiTest)
            hasSeenWelcome = true
            phase = .ready
            grantStarterEggsIfNeeded()
            return
        }
        if ProcessInfo.processInfo.arguments.contains("-ui-testing-onboarding") {
            snapshot = mergedSnapshot(.uiTest)
            hasSeenWelcome = false
            phase = .ready
            return
        }
        if ProcessInfo.processInfo.arguments.contains("-ui-testing-invite") {
            phase = .needsInvitation
            return
        }
        #endif
        applyForcedOnboardingIfNeeded()
        applyForcedCollectionResetIfNeeded()
        loadCache()
        grantStarterEggsIfNeeded()
        await CheckpointCatalog.refreshCoordinates()
        await MemoryMomentCatalog.refreshCoordinates()
        if let current = snapshot { snapshot = mergedSnapshot(current) }
        evaluateBirthdayNotes()
        if (try? KeychainStore.read("playerAccessToken")) == nil {
            await joinOpenAdventure()
            return
        }
        await synchronize()
        if phase != .ready {
            await joinOpenAdventure()
        }
    }

    func joinOpenAdventure() async {
        guard let api else {
            enterLocalAdventure()
            return
        }
        isWorking = true
        defer { isWorking = false }
        do {
            let response = try await api.joinOpenGame(
                deviceName: UIDevice.current.name,
                installationId: installationId
            )
            try KeychainStore.save(response.accessToken, key: "playerAccessToken")
            await synchronize()
        } catch {
            enterLocalAdventure()
        }
    }

    func redeem(code: String) async {
        guard let api else {
            errorMessage = APIError.configuration.localizedDescription
            return
        }
        isWorking = true
        defer { isWorking = false }
        do {
            let response = try await api.redeem(
                invitationToken: code.trimmingCharacters(in: .whitespacesAndNewlines),
                deviceName: UIDevice.current.name,
                installationId: installationId
            )
            try KeychainStore.save(response.accessToken, key: "playerAccessToken")
            hasSeenWelcome = false
            UserDefaults.standard.set(false, forKey: "hasSeenWelcome")
            await synchronize()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func recover(code: String) async {
        guard let api else {
            errorMessage = APIError.configuration.localizedDescription
            return
        }
        isWorking = true
        defer { isWorking = false }
        do {
            let response = try await api.recover(
                recoveryToken: code.trimmingCharacters(in: .whitespacesAndNewlines),
                deviceName: UIDevice.current.name,
                installationId: installationId
            )
            try KeychainStore.save(response.accessToken, key: "playerAccessToken")
            await synchronize()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func acknowledgeWelcome() {
        hasSeenWelcome = true
        UserDefaults.standard.set(true, forKey: "hasSeenWelcome")
    }

    private let onboardingEpoch = 1

    private func applyForcedOnboardingIfNeeded() {
        guard UserDefaults.standard.integer(forKey: "onboardingEpoch") < onboardingEpoch else { return }
        UserDefaults.standard.set(onboardingEpoch, forKey: "onboardingEpoch")
        hasSeenWelcome = false
        UserDefaults.standard.set(false, forKey: "hasSeenWelcome")
        UserDefaults.standard.set(0, forKey: "onboardingPage")
    }

    private let friendDexEpoch = 2

    private func applyForcedCollectionResetIfNeeded() {
        guard UserDefaults.standard.integer(forKey: "friendDexEpoch") < friendDexEpoch else { return }
        UserDefaults.standard.set(friendDexEpoch, forKey: "friendDexEpoch")
        UserDefaults.standard.set(true, forKey: "friendDexReset")
        pending.removeAll { $0.contentType == "character" }
        savePending()
        clearLocalCollection()
        if var current = snapshot {
            current.characters = current.characters.map { $0.withCaptured(false) }
            current.game = current.game.withXP(0)
            snapshot = mergedSnapshot(current)
            persist(snapshot!)
        }
        Task { await resetRemoteCollection() }
    }

    func setAvatar(color: String) {
        avatarColor = color
        UserDefaults.standard.set(color, forKey: "avatarColor")
        Task { await synchronize() }
    }

    func synchronize() async {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-ui-testing-ready")
            || ProcessInfo.processInfo.arguments.contains("-ui-testing-invite")
            || ProcessInfo.processInfo.arguments.contains("-ui-testing-onboarding") {
            return
        }
        #endif
        guard let api else {
            errorMessage = APIError.configuration.localizedDescription
            phase = snapshot == nil ? .needsInvitation : .ready
            return
        }
        do {
            let updated = try await api.sync(installationId: installationId, avatarStyle: ["color": avatarColor])
            apply(updated)
            await flushPending()
            await cacheUnlockedMedia()
            evaluateBirthdayNotes()
            grantStarterEggsIfNeeded()
            restoreIncubationTracking()
        } catch APIError.unauthorized {
            KeychainStore.delete("playerAccessToken")
            await joinOpenAdventure()
        } catch {
            if snapshot == nil {
                enterLocalAdventure()
            } else {
                errorMessage = nil
                phase = .ready
            }
        }
    }

    func complete(
        type: String,
        id: UUID,
        location: CLLocation?,
        dwellStartedAt: Date,
        fallbackCode: String? = nil
    ) async -> Bool {
        if type == "character", let character = snapshot?.characters.first(where: { $0.id == id }), character.captured {
            return true
        }
        let catalogCat = snapshot?.characters.first(where: { $0.id == id })?.catalog ?? CatCatalog.entry(id: id)
        let checkpoint = CheckpointCatalog.entry(id: id)
        let localUnlock = catalogCat != nil || checkpoint != nil || DeveloperMode.isEnabled
        let operation = PendingProgress(
            id: UUID(), contentType: type, contentId: id,
            latitude: location?.coordinate.latitude, longitude: location?.coordinate.longitude,
            horizontalAccuracy: location.flatMap { $0.horizontalAccuracy > 0 ? $0.horizontalAccuracy : nil },
            dwellStartedAt: dwellStartedAt, fallbackCode: fallbackCode ?? catalogCat?.fallbackCode ?? checkpoint?.fallbackCode
        )
        if type == "character", localUnlock {
            rememberCapture(id: id)
            markCapturedLocally(id: id)
            if let creature = checkpoint?.characters.first(where: { $0.id == id }) {
                grantXP(creature.xpValue, key: "character-\(id.uuidString)")
            }
            if let locationId = snapshot?.characters.first(where: { $0.id == id })?.locationId
                ?? checkpoint?.locationId {
                grantStamp(forLocationId: locationId)
            }
            evaluateBirthdayNotes()
        }
        if type == "landmark", let checkpoint {
            markLandmarkVisited(checkpoint.landmarkId ?? id)
            if let souvenir = checkpoint.souvenir { rememberSouvenir(souvenir, checkpointTitle: checkpoint.title) }
            grantXP(checkpoint.kind == .travelStop ? 100 : (checkpoint.title == "Chip City Chelsea" ? 75 : 100), key: "landmark-\(id.uuidString)")
            if checkpoint.kind != .travelStop {
                unlockCheckpointNote(checkpoint)
                grantStamp(forLocationTitle: checkpoint.title)
            }
            evaluateBirthdayNotes()
        }
        if type == "message", let checkpoint {
            unlockCheckpointNote(checkpoint)
            grantStamp(forLocationTitle: checkpoint.title)
            evaluateBirthdayNotes()
        }
        guard let api else { return localUnlock }
        do {
            let updated = try await api.progress(operation, installationId: installationId)
            apply(updated)
            await cacheUnlockedMedia()
            evaluateBirthdayNotes()
            return true
        } catch is URLError {
            pending.append(operation)
            savePending()
            if localUnlock { return true }
            errorMessage = "Saved on this device. Birthday GO will finish unlocking when you are back online."
            return false
        } catch {
            if localUnlock { return true }
            errorMessage = error.localizedDescription
            return false
        }
    }

    func completeCheckpoint(
        _ checkpoint: CheckpointCatalog.Entry,
        currentLocation: CLLocation?,
        dwellStartedAt: Date,
        fallbackCode: String?
    ) async -> Bool {
        var saved = true
        if let landmarkId = checkpoint.landmarkId {
            saved = await complete(
                type: "landmark", id: landmarkId, location: currentLocation,
                dwellStartedAt: dwellStartedAt, fallbackCode: fallbackCode ?? checkpoint.fallbackCode
            ) && saved
        }
        if checkpoint.unlocksCharacterOnVisit {
            for creature in checkpoint.characters {
                rememberCapture(id: creature.id)
                markCapturedLocally(id: creature.id)
            }
        }
        if let souvenir = checkpoint.souvenir {
            rememberSouvenir(souvenir, checkpointTitle: checkpoint.title)
        }
        if checkpoint.kind != .travelStop {
            unlockCheckpointNote(checkpoint)
            grantStamp(forLocationTitle: checkpoint.title)
        }
        evaluateBirthdayNotes()
        return saved
    }

    func toggleFavorite(noteId: UUID) {
        guard let context = modelContext else { return }
        let preference = notePreference(noteId, in: context)
        preference.isFavorite.toggle()
        preference.updatedAt = .now
        try? context.save()
        objectWillChange.send()
    }

    func markNoteRead(noteId: UUID) {
        guard let context = modelContext else { return }
        let preference = notePreference(noteId, in: context)
        preference.isRead = true
        preference.updatedAt = .now
        try? context.save()
    }

    func isFavorite(noteId: UUID) -> Bool {
        notePreferences().first { $0.noteId == noteId }?.isFavorite == true
    }

    func isRead(noteId: UUID) -> Bool {
        notePreferences().first { $0.noteId == noteId }?.isRead == true
    }

    func passportStampKeys() -> Set<String> {
        var stamps = Set(snapshot?.passportStamps ?? [])
        stamps.formUnion(((try? modelContext?.fetch(FetchDescriptor<LocalPassportStamp>())) ?? []).map(\.stampKey))
        return stamps
    }

    func evaluateBirthdayNotes() {
        guard var current = snapshot else { return }
        var stamps = passportStampKeys()
        for entry in CheckpointCatalog.entries where entry.isComplete(current) {
            if let key = MemoryPassport.stampKey(forLocationTitle: entry.title) {
                rememberStamp(key)
                stamps.insert(key)
            }
        }
        current.passportStamps = stamps.sorted()

        var unlockedNames: [String] = []
        var pendingServer: [UUID] = []
        for pin in current.messagePins where !pin.unlocked {
            guard BirthdayNoteRules.isEligible(pin, snapshot: current, stamps: stamps) else { continue }
            if let checkpoint = CheckpointCatalog.entries.first(where: { $0.message.id == pin.id }) {
                if let index = current.messagePins.firstIndex(where: { $0.id == pin.id }) {
                    current.messagePins[index] = current.messagePins[index].withUnlocked(true)
                }
                if !current.unlockedMessages.contains(where: { $0.id == pin.id }) {
                    current.unlockedMessages.append(checkpoint.asFriendMessage())
                }
                unlockedNames.append(checkpoint.message.senderName)
            } else if current.unlockedMessages.contains(where: { $0.id == pin.id }) {
                if let index = current.messagePins.firstIndex(where: { $0.id == pin.id }) {
                    current.messagePins[index] = current.messagePins[index].withUnlocked(true)
                }
            } else {
                pendingServer.append(pin.id)
            }
        }
        snapshot = current
        persist(current)
        if !unlockedNames.isEmpty {
            noteUnlockBanner = "You've unlocked a birthday message from a friend!"
        }
        if !pendingServer.isEmpty {
            Task { await unlockEligibleServerNotes(pendingServer) }
        }
    }

    func souvenirs() -> [CollectedSouvenir] {
        allSouvenirs().filter { !TravelStops.isTravelSouvenir($0.souvenirId) }
    }

    func travelSouvenirs() -> [CollectedSouvenir] {
        allSouvenirs().filter { TravelStops.isTravelSouvenir($0.souvenirId) }
    }

    func hasNYCJetsetter() -> Bool {
        let collected = Set(travelSouvenirs().map(\.souvenirId))
        let required = Set(TravelStops.airports.compactMap(\.souvenir?.id))
        return !required.isEmpty && required.isSubset(of: collected)
    }

    func jetsetterAchievedAt() -> Date? {
        guard hasNYCJetsetter() else { return nil }
        let awards = (try? modelContext?.fetch(FetchDescriptor<AwardedCheckpoint>())) ?? []
        if let awarded = awards.first(where: { $0.awardKey == "achievement-nyc-jetsetter" }) {
            return awarded.awardedAt
        }
        return travelSouvenirs().map(\.collectedAt).max()
    }

    private func allSouvenirs() -> [CollectedSouvenir] {
        guard let context = modelContext else { return [] }
        return (try? context.fetch(FetchDescriptor<CollectedSouvenir>())) ?? []
    }

    private func flushPending() async {
        guard let api else { return }
        while let operation = pending.first {
            do {
                let updated = try await api.progress(operation, installationId: installationId)
                pending.removeFirst()
                savePending()
                apply(updated)
            } catch {
                break
            }
        }
    }

    private func apply(_ updated: PlayerSnapshot) {
        let merged = mergedSnapshot(updated)
        snapshot = merged
        phase = .ready
        errorMessage = nil
        persist(merged)
    }

    private func mergedSnapshot(_ snapshot: PlayerSnapshot) -> PlayerSnapshot {
        var incoming = snapshot
        if UserDefaults.standard.bool(forKey: "friendDexReset") {
            incoming.characters = incoming.characters.map { $0.withCaptured(false) }
        }
        let cats = CatCatalog.merging(incoming, capturedNames: localCapturedNames())
        let eggs = EggCatalog.merging(cats, capturedNames: localCapturedNames())
        let moments = MemoryMomentCatalog.merging(eggs)
        return CheckpointCatalog.merging(
            moments,
            capturedNames: localCapturedNames(),
            souvenirs: localSouvenirIds(),
            visitedLandmarkIds: localVisitedLandmarks(),
            unlockedMessageIds: localUnlockedMessages()
        )
    }

    private func enterLocalAdventure() {
        snapshot = mergedSnapshot(snapshot ?? .localAdventure)
        phase = .ready
        errorMessage = nil
        persist(snapshot!)
        grantStarterEggsIfNeeded()
    }

    private func clearLocalCollection() {
        guard let context = modelContext else { return }
        (try? context.fetch(FetchDescriptor<CapturedCreature>()))?.forEach { context.delete($0) }
        (try? context.fetch(FetchDescriptor<CollectedSouvenir>()))?.forEach { context.delete($0) }
        (try? context.fetch(FetchDescriptor<AwardedCheckpoint>()))?.forEach { context.delete($0) }
        (try? context.fetch(FetchDescriptor<LocalPassportStamp>()))?.forEach { context.delete($0) }
        try? context.save()
    }

    private func resetRemoteCollection() async {
        guard let api else { return }
        do {
            let updated = try await api.sync(installationId: installationId, resetCollection: true)
            UserDefaults.standard.set(false, forKey: "friendDexReset")
            apply(updated)
        } catch {
            if var current = snapshot {
                current.characters = current.characters.map { $0.withCaptured(false) }
                snapshot = mergedSnapshot(current)
                persist(snapshot!)
            }
        }
    }

    private func persist(_ updated: PlayerSnapshot) {
        guard let context = modelContext, let data = try? JSONEncoder.supabase.encode(updated) else { return }
        let descriptor = FetchDescriptor<CachedSnapshot>()
        if let existing = try? context.fetch(descriptor).first {
            existing.gameId = updated.game.id
            existing.payload = data
            existing.savedAt = .now
        } else {
            context.insert(CachedSnapshot(gameId: updated.game.id, payload: data))
        }
        try? context.save()
    }

    private func loadCache() {
        guard let context = modelContext,
              let cache = try? context.fetch(FetchDescriptor<CachedSnapshot>()).first,
              let cached = try? JSONDecoder.supabase.decode(PlayerSnapshot.self, from: cache.payload)
        else { return }
        snapshot = mergedSnapshot(cached)
        phase = .ready
    }

    private func localCapturedNames() -> Set<String> {
        guard let context = modelContext else { return [] }
        let rows = (try? context.fetch(FetchDescriptor<CapturedCreature>())) ?? []
        return Set(rows.map(\.name))
    }

    private func rememberCapture(id: UUID) {
        guard let context = modelContext else { return }
        let name = snapshot?.characters.first(where: { $0.id == id })?.name
            ?? CatCatalog.entry(id: id)?.name
            ?? CheckpointCatalog.entry(id: id)?.characters.first { $0.id == id }?.name
            ?? id.uuidString
        let existing = try? context.fetch(FetchDescriptor<CapturedCreature>()).contains(where: { $0.characterId == id || $0.name == name })
        if existing == true { return }
        context.insert(CapturedCreature(characterId: id, name: name))
        try? context.save()
    }

    private func markCapturedLocally(id: UUID) {
        guard var current = snapshot, let index = current.characters.firstIndex(where: { $0.id == id }) else { return }
        current.characters[index] = current.characters[index].withCaptured(true)
        snapshot = current
        persist(current)
    }

    private func markLandmarkVisited(_ id: UUID) {
        guard var current = snapshot else { return }
        if let index = current.landmarks.firstIndex(where: { $0.id == id }) {
            current.landmarks[index] = current.landmarks[index].withVisited(true)
        }
        snapshot = current
        persist(current)
    }

    private func rememberSouvenir(_ souvenir: CheckpointCatalog.Souvenir, checkpointTitle: String) {
        guard let context = modelContext else { return }
        let exists = (try? context.fetch(FetchDescriptor<CollectedSouvenir>()))?.contains { $0.souvenirId == souvenir.id } == true
        if exists { return }
        context.insert(CollectedSouvenir(
            souvenirId: souvenir.id, name: souvenir.name, checkpointTitle: checkpointTitle,
            detail: souvenir.detail, symbol: souvenir.symbol
        ))
        try? context.save()
        if TravelStops.isTravelSouvenir(souvenir.id), hasNYCJetsetter() {
            rememberTravelAchievement()
        }
    }

    private func unlockCheckpointNote(_ checkpoint: CheckpointCatalog.Entry) {
        guard var current = snapshot else { return }
        if let index = current.messagePins.firstIndex(where: { $0.id == checkpoint.message.id }) {
            current.messagePins[index] = current.messagePins[index].withUnlocked(true)
        }
        if !current.unlockedMessages.contains(where: { $0.id == checkpoint.message.id }) {
            current.unlockedMessages.append(checkpoint.asFriendMessage())
        }
        snapshot = current
        persist(current)
    }

    private var isUnlockingServerNotes = false

    private func unlockEligibleServerNotes(_ ids: [UUID]) async {
        guard !isUnlockingServerNotes else { return }
        isUnlockingServerNotes = true
        defer { isUnlockingServerNotes = false }
        var unlockedAny = false
        for id in ids {
            if snapshot?.unlockedMessages.contains(where: { $0.id == id }) == true { continue }
            let saved = await complete(type: "message", id: id, location: nil, dwellStartedAt: .now)
            if saved, snapshot?.unlockedMessages.contains(where: { $0.id == id }) == true {
                unlockedAny = true
            }
        }
        if unlockedAny {
            noteUnlockBanner = "You've unlocked a birthday message from a friend!"
        }
    }

    private func grantStamp(forLocationTitle title: String) {
        guard let key = MemoryPassport.stampKey(forLocationTitle: title) else { return }
        rememberStamp(key)
        mergeStamp(key)
    }

    private func grantStamp(forLocationId locationId: UUID) {
        if let title = snapshot?.locations.first(where: { $0.id == locationId })?.title {
            grantStamp(forLocationTitle: title)
            return
        }
        if let title = CheckpointCatalog.entry(locationId: locationId)?.title {
            grantStamp(forLocationTitle: title)
        }
    }

    private func rememberStamp(_ key: String) {
        guard let context = modelContext else { return }
        let exists = (try? context.fetch(FetchDescriptor<LocalPassportStamp>()))?.contains { $0.stampKey == key } == true
        if exists { return }
        context.insert(LocalPassportStamp(stampKey: key))
        try? context.save()
    }

    private func mergeStamp(_ key: String) {
        guard var current = snapshot else { return }
        var stamps = Set(current.passportStamps ?? [])
        stamps.insert(key)
        current.passportStamps = stamps.sorted()
        snapshot = current
        persist(current)
    }

    private func notePreferences() -> [NotePreference] {
        (try? modelContext?.fetch(FetchDescriptor<NotePreference>())) ?? []
    }

    private func notePreference(_ noteId: UUID, in context: ModelContext) -> NotePreference {
        if let existing = (try? context.fetch(FetchDescriptor<NotePreference>()))?.first(where: { $0.noteId == noteId }) {
            return existing
        }
        let preference = NotePreference(noteId: noteId)
        context.insert(preference)
        return preference
    }

    private func rememberTravelAchievement() {
        guard let context = modelContext else { return }
        let exists = (try? context.fetch(FetchDescriptor<AwardedCheckpoint>()))?.contains { $0.awardKey == "achievement-nyc-jetsetter" } == true
        if exists { return }
        context.insert(AwardedCheckpoint(awardKey: "achievement-nyc-jetsetter", xp: 0))
        try? context.save()
    }

    private func grantXP(_ amount: Int, key: String) {
        guard amount > 0, let context = modelContext else { return }
        let exists = (try? context.fetch(FetchDescriptor<AwardedCheckpoint>()))?.contains { $0.awardKey == key } == true
        if exists { return }
        context.insert(AwardedCheckpoint(awardKey: key, xp: amount))
        try? context.save()
        guard var current = snapshot else { return }
        current.game = current.game.addingXP(amount)
        snapshot = current
        persist(current)
    }

    private func localSouvenirIds() -> Set<UUID> {
        Set(((try? modelContext?.fetch(FetchDescriptor<CollectedSouvenir>())) ?? []).map(\.souvenirId))
    }

    private func localVisitedLandmarks() -> Set<UUID> {
        var ids = Set((snapshot?.landmarks ?? []).filter(\.visited).map(\.id))
        for souvenir in allSouvenirs() {
            if let landmarkId = CheckpointCatalog.entry(id: souvenir.souvenirId)?.landmarkId {
                ids.insert(landmarkId)
            }
        }
        for award in (try? modelContext?.fetch(FetchDescriptor<AwardedCheckpoint>())) ?? [] {
            if award.awardKey.hasPrefix("landmark-"),
               let id = UUID(uuidString: String(award.awardKey.dropFirst("landmark-".count))) {
                ids.insert(id)
            }
        }
        return ids
    }

    private func localUnlockedMessages() -> Set<UUID> {
        Set((snapshot?.unlockedMessages ?? []).map(\.id) + (snapshot?.messagePins ?? []).filter(\.unlocked).map(\.id))
    }

    private func savePending() {
        UserDefaults.standard.set(try? JSONEncoder.supabase.encode(pending), forKey: "pendingProgress")
    }

    private func cacheUnlockedMedia() async {
        guard var current = snapshot else { return }
        let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: "BirthdayGO/media", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for messageIndex in current.unlockedMessages.indices {
            for mediaIndex in current.unlockedMessages[messageIndex].media.indices {
                let media = current.unlockedMessages[messageIndex].media[mediaIndex]
                let destination = folder.appending(path: media.id.uuidString)
                if FileManager.default.fileExists(atPath: destination.path) {
                    current.unlockedMessages[messageIndex].media[mediaIndex].path = destination.absoluteString
                    continue
                }
                guard let remote = URL(string: media.path), let scheme = remote.scheme, scheme.hasPrefix("http") else { continue }
                do {
                    let (data, _) = try await URLSession.shared.data(from: remote)
                    try data.write(to: destination, options: .atomic)
                    current.unlockedMessages[messageIndex].media[mediaIndex].path = destination.absoluteString
                } catch {
                    continue
                }
            }
        }
        for messageIndex in current.unlockedMessages.indices {
            let message = current.unlockedMessages[messageIndex]
            guard let path = message.senderPhotoPath, let remote = URL(string: path),
                  let scheme = remote.scheme, scheme.hasPrefix("http") else { continue }
            let destination = folder.appending(path: "sender-\(message.id.uuidString)")
            if FileManager.default.fileExists(atPath: destination.path) {
                current.unlockedMessages[messageIndex].senderPhotoPath = destination.absoluteString
                continue
            }
            do {
                let (data, _) = try await URLSession.shared.data(from: remote)
                try data.write(to: destination, options: .atomic)
                current.unlockedMessages[messageIndex].senderPhotoPath = destination.absoluteString
            } catch {
                continue
            }
        }
        snapshot = current
        persist(current)
    }

    func attachWalkTracker(_ tracker: WalkTracker) {
        walkTracker = tracker
        tracker.onAcceptedDistance = { [weak self] meters in
            self?.addWalkedMeters(meters)
        }
        restoreIncubationTracking()
    }

    func refreshEggs() {
        eggRevision += 1
    }

    func playerEggs() -> [PlayerEggRecord] {
        _ = eggRevision
        guard let context = modelContext else { return [] }
        let rows = (try? context.fetch(FetchDescriptor<PlayerEggRecord>())) ?? []
        return rows.sorted { lhs, rhs in
            if lhs.status == rhs.status { return lhs.typeTitle < rhs.typeTitle }
            return Self.eggSort(lhs.status) < Self.eggSort(rhs.status)
        }
    }

    func egg(id: UUID) -> PlayerEggRecord? {
        playerEggs().first { $0.id == id }
    }

    func activeIncubation() -> PlayerEggRecord? {
        playerEggs().first { $0.status == .incubating || $0.status == .ready }
    }

    func startIncubating(eggId: UUID) {
        guard let context = modelContext, let egg = egg(id: eggId) else { return }
        if let active = activeIncubation(), active.id != egg.id {
            errorMessage = "Only one egg can incubate at a time."
            return
        }
        egg.status = .incubating
        egg.startedAt = egg.startedAt ?? .now
        egg.pausedAt = nil
        egg.updatedAt = .now
        try? context.save()
        refreshEggs()
        walkTracker?.start()
    }

    func pauseIncubation() {
        if let egg = playerEggs().first(where: { $0.status == .incubating }) {
            egg.pausedAt = .now
            egg.updatedAt = .now
            try? modelContext?.save()
            refreshEggs()
        }
        walkTracker?.pause(reason: "Walking paused. Resume to keep incubating.")
    }

    func resumeIncubation() {
        guard playerEggs().contains(where: { $0.status == .incubating }) else { return }
        walkTracker?.start()
        refreshEggs()
    }

    func addWalkedMeters(_ meters: Double) {
        guard meters > 0, let context = modelContext else { return }
        guard let egg = playerEggs().first(where: { $0.status == .incubating }) else { return }
        egg.metersWalked = min(egg.metersWalked + meters, egg.requiredMeters)
        egg.updatedAt = .now
        if egg.metersWalked + 0.01 >= egg.requiredMeters {
            egg.metersWalked = egg.requiredMeters
            egg.status = .ready
            egg.readyAt = .now
            eggReadyBanner = "Your Egg Is Ready!"
            walkTracker?.markCompleted()
        }
        try? context.save()
        refreshEggs()
    }

    func hatch(eggId: UUID) -> HatchPresentation? {
        guard let context = modelContext, let egg = egg(id: eggId) else { return nil }
        if egg.status == .hatched, let presentation = existingHatch(for: egg) {
            return presentation
        }
        guard egg.status == .ready || egg.metersWalked + 0.01 >= egg.requiredMeters else { return nil }
        if egg.hatchIdempotencyKey == nil { egg.hatchIdempotencyKey = UUID() }

        let type = EggCatalog.type(id: egg.typeId) ?? EggCatalog.type(key: egg.typeKey) ?? EggCatalog.defaults[0]
        if egg.rewardCharacterId == nil {
            let collectedIds = Set((snapshot?.characters ?? []).filter(\.captured).map(\.id))
            let decision = EggRewardPicker.decide(
                type: type,
                characters: snapshot?.characters ?? EggCatalog.exclusiveCharacters,
                collectedIds: collectedIds,
                collectedNames: localCapturedNames()
            )
            switch decision {
            case .character(let id, _):
                egg.rewardCharacterId = id
                egg.rewardName = snapshot?.characters.first(where: { $0.id == id })?.name
                    ?? EggCatalog.exclusiveCharacters.first(where: { $0.id == id })?.name
            case .duplicate:
                egg.rewardCharacterId = nil
                egg.rewardName = nil
            }
        }

        egg.status = .hatched
        egg.hatchedAt = egg.hatchedAt ?? .now
        egg.updatedAt = .now
        try? context.save()

        let presentation: HatchPresentation
        if let rewardId = egg.rewardCharacterId,
           var character = snapshot?.characters.first(where: { $0.id == rewardId })
            ?? EggCatalog.exclusiveCharacters.first(where: { $0.id == rewardId }) {
            if localCapturedNames().contains(character.name) || character.captured {
                grantXP(type.duplicateXp, key: "egg-hatch-\(egg.id.uuidString)")
                presentation = .duplicate(xp: type.duplicateXp)
            } else {
                rememberCapture(id: character.id)
                markCapturedLocally(id: character.id)
                character = character.withCaptured(true)
                grantXP(type.xpValue, key: "egg-hatch-\(egg.id.uuidString)")
                presentation = .character(character, xp: type.xpValue)
            }
        } else {
            grantXP(type.duplicateXp, key: "egg-hatch-\(egg.id.uuidString)")
            presentation = .duplicate(xp: type.duplicateXp)
        }

        walkTracker?.stop()
        refreshEggs()
        Task { await synchronizeEggProgress() }
        return presentation
    }

    func simulateWalk(meters: Double) {
        #if DEBUG
        addWalkedMeters(max(0, meters))
        #endif
    }

    func grantEgg(typeId: UUID, isTest: Bool = false) {
        guard let type = EggCatalog.type(id: typeId) ?? EggCatalog.defaults.first(where: { $0.id == typeId }) else { return }
        insertEgg(from: type, isTest: isTest)
    }

    func resetTestEggs() {
        guard let context = modelContext else { return }
        let rows = (try? context.fetch(FetchDescriptor<PlayerEggRecord>())) ?? []
        for egg in rows where egg.isTest {
            egg.status = .available
            egg.metersWalked = 0
            egg.startedAt = nil
            egg.pausedAt = nil
            egg.readyAt = nil
            egg.hatchedAt = nil
            egg.rewardCharacterId = nil
            egg.rewardName = nil
            egg.hatchIdempotencyKey = nil
            egg.updatedAt = .now
        }
        try? context.save()
        walkTracker?.stop()
        refreshEggs()
    }

    private func grantStarterEggsIfNeeded() {
        mergeRemoteEggs(snapshot?.playerEggs ?? [])
        let existing = playerEggs()
        for type in EggCatalog.resolvedTypes() {
            if !existing.contains(where: { $0.typeId == type.id || $0.typeKey == type.key }) {
                insertEgg(from: type, isTest: false)
            }
        }
        restoreIncubationTracking()
    }

    private func insertEgg(from type: EggTypeConfig, isTest: Bool) {
        guard let context = modelContext else { return }
        context.insert(PlayerEggRecord(
            typeId: type.id,
            typeKey: type.key,
            typeTitle: type.title,
            requiredMeters: type.requiredMeters,
            xpValue: type.xpValue,
            artworkStyle: type.artworkStyle,
            rarityLabel: type.rarityLabel,
            isTest: isTest
        ))
        try? context.save()
        refreshEggs()
    }

    private func mergeRemoteEggs(_ remote: [RemotePlayerEgg]) {
        guard let context = modelContext else { return }
        let local = (try? context.fetch(FetchDescriptor<PlayerEggRecord>())) ?? []
        for incoming in remote {
            let type = EggCatalog.type(id: incoming.eggTypeId)
                ?? EggCatalog.type(key: incoming.typeKey ?? "")
            if let existing = local.first(where: { $0.id == incoming.id }) {
                existing.metersWalked = max(existing.metersWalked, incoming.metersWalked)
                if existing.status == .hatched { continue }
                if incoming.status == "hatched" {
                    existing.status = .hatched
                    existing.hatchedAt = incoming.hatchedAt ?? .now
                    existing.rewardCharacterId = incoming.rewardCharacterId
                } else if incoming.status == "ready" || existing.metersWalked + 0.01 >= (incoming.requiredMeters ?? existing.requiredMeters) {
                    existing.status = .ready
                    existing.readyAt = incoming.readyAt ?? existing.readyAt ?? .now
                } else if incoming.status == "incubating", existing.status == .available {
                    existing.status = .incubating
                    existing.startedAt = incoming.startedAt ?? .now
                }
                existing.updatedAt = .now
            } else if let type {
                let egg = PlayerEggRecord(
                    id: incoming.id,
                    typeId: type.id,
                    typeKey: type.key,
                    typeTitle: type.title,
                    requiredMeters: incoming.requiredMeters ?? type.requiredMeters,
                    xpValue: type.xpValue,
                    artworkStyle: type.artworkStyle,
                    rarityLabel: type.rarityLabel,
                    status: EggStatus(rawValue: incoming.status) ?? .available,
                    metersWalked: incoming.metersWalked,
                    isTest: incoming.isTest ?? false
                )
                egg.startedAt = incoming.startedAt
                egg.readyAt = incoming.readyAt
                egg.hatchedAt = incoming.hatchedAt
                egg.rewardCharacterId = incoming.rewardCharacterId
                context.insert(egg)
            }
        }
        try? context.save()
        refreshEggs()
    }

    private func restoreIncubationTracking() {
        if playerEggs().contains(where: { $0.status == .incubating }) {
            walkTracker?.start()
        } else if playerEggs().contains(where: { $0.status == .ready }) {
            walkTracker?.markCompleted()
        }
    }

    private func existingHatch(for egg: PlayerEggRecord) -> HatchPresentation? {
        let type = EggCatalog.type(id: egg.typeId) ?? EggCatalog.type(key: egg.typeKey)
        if let id = egg.rewardCharacterId,
           let character = snapshot?.characters.first(where: { $0.id == id })
            ?? EggCatalog.exclusiveCharacters.first(where: { $0.id == id }) {
            return .character(character.withCaptured(true), xp: type?.xpValue ?? egg.xpValue)
        }
        return .duplicate(xp: type?.duplicateXp ?? 0)
    }

    private func synchronizeEggProgress() async {
        guard let api, let egg = playerEggs().first(where: { $0.hatchedAt != nil && $0.rewardCharacterId != nil }) else { return }
        if let rewardId = egg.rewardCharacterId {
            _ = await complete(type: "character", id: rewardId, location: nil, dwellStartedAt: .now)
        }
        _ = api
    }

    private static func eggSort(_ status: EggStatus) -> Int {
        switch status {
        case .ready: 0
        case .incubating: 1
        case .available: 2
        case .hatched: 3
        }
    }
}
