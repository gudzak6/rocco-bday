import SwiftUI
import AVFoundation
import UIKit

struct CollectionView: View {
    @EnvironmentObject private var store: GameStore
    @State private var rarity: CharacterRarity?
    @State private var category: String?
    @State private var found = DiscoveredPlaces.ids()
    @State private var selectedPhoto: PhotoDrop?
    @State private var selectedMoment: MemoryMomentCatalog.Entry?
    @State private var selectedPlace: CheckpointCatalog.Entry?
    @State private var page = DexPage.friendDex
    #if DEBUG
    @AppStorage(HiddenPlacePreview.defaultsKey) private var showHiddenPlaces = false
    #endif
    private let columns = [GridItem(.adaptive(minimum: 145), spacing: 14)]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Picker("Collection", selection: $page) {
                        Text("Cookies").tag(DexPage.eggs)
                        Text("FriendDex").tag(DexPage.friendDex)
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal)

                    if page == .eggs {
                        EggsInventorySection()
                    } else {
                        Text("\(friendDexFound) of \(friendDexTotal) discovered")
                            .font(.system(.headline, design: .rounded, weight: .bold))
                            .padding(.horizontal)
                        LazyVGrid(columns: columns, spacing: 14) {
                            friendDexCards
                        }
                        .padding(.horizontal)
                    }
                }
                .padding(.vertical)
            }
            .background(Color.warmWhite)
            .onAppear { found = DiscoveredPlaces.ids() }
            .navigationTitle("Birthday Dex")
            .toolbar {
                if page == .friendDex {
                    Menu {
                        Button("All rarities") { rarity = nil }
                        ForEach(CharacterRarity.allCases, id: \.self) { value in
                            Button(value.rawValue.capitalized) { rarity = value }
                        }
                        Divider()
                        Button("All categories") { category = nil }
                        ForEach(["friend", "food", "memory", "inside_joke", "legendary"], id: \.self) { value in
                            Button(value.replacingOccurrences(of: "_", with: " ").capitalized) { category = value }
                        }
                    } label: { Label("Filter", systemImage: "line.3.horizontal.decrease.circle") }
                }
            }
            .sheet(item: $selectedPhoto) { drop in
                PhotoDropViewer(drop: drop)
            }
            .fullScreenCover(item: $selectedMoment) { moment in
                MemoryMomentViewer(moment: moment)
            }
            .sheet(item: $selectedPlace) { stop in
                NavigationStack {
                    PlaceDexDetail(stop: stop)
                }
            }
        }
    }

    @ViewBuilder
    private var friendDexCards: some View {
        ForEach(filtered) { character in
            NavigationLink { CharacterDetail(character: character) } label: {
                DexTile(
                    title: character.captured ? character.name : "Undiscovered",
                    subtitle: character.rarity.rawValue.capitalized
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel(character.captured ? character.name : "Undiscovered")
        }
        if rarity == nil && category == nil {
            ForEach(PhotoDropCatalog.drops()) { drop in
                let revealed = isFound(drop.id)
                Button {
                    if revealed { selectedPhoto = drop }
                } label: {
                    DexTile(title: revealed ? "Photo" : "Undiscovered", subtitle: "Photo")
                }
                .buttonStyle(.plain)
                .accessibilityLabel(revealed ? "Photo" : "Undiscovered")
            }
            ForEach(MemoryMomentCatalog.entries) { moment in
                let revealed = isFound(moment.id)
                Button {
                    if revealed { selectedMoment = moment }
                } label: {
                    DexTile(title: revealed ? moment.title : "Undiscovered", subtitle: "Memory")
                }
                .buttonStyle(.plain)
                .accessibilityLabel(revealed ? moment.title : "Undiscovered")
            }
            ForEach(CheckpointCatalog.entries) { stop in
                let revealed = placeRevealed(stop)
                Button {
                    if revealed { selectedPlace = stop }
                } label: {
                    DexTile(title: revealed ? stop.title : "Undiscovered", subtitle: placeSubtitle(stop))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(revealed ? stop.title : "Undiscovered")
            }
            ForEach(store.souvenirs(), id: \.souvenirId) { souvenir in
                DexTile(title: souvenir.name, subtitle: "Souvenir")
                    .accessibilityLabel(souvenir.name)
            }
            if store.hasNYCJetsetter() {
                DexTile(title: TravelStops.achievementTitle, subtitle: "Achievement")
            }
        }
    }

    private var filtered: [Character] {
        (store.snapshot?.characters ?? []).filter {
            (rarity == nil || $0.rarity == rarity) && (category == nil || $0.category == category)
        }
    }

    private var placeCount: Int {
        MemoryMomentCatalog.entries.count + CheckpointCatalog.entries.count
    }

    private var friendDexFound: Int {
        let characters = store.snapshot?.characters.filter(\.captured).count ?? 0
        let extras = store.souvenirs().count + (store.hasNYCJetsetter() ? 1 : 0)
        return characters + foundPhotos + foundPlaces + extras
    }

    private var friendDexTotal: Int {
        let characters = store.snapshot?.characters.count ?? 0
        let extras = store.souvenirs().count + (store.hasNYCJetsetter() ? 1 : 0)
        return characters + PhotoDropCatalog.drops().count + placeCount + extras
    }

    private var foundPhotos: Int {
        PhotoDropCatalog.drops().filter { isFound($0.id) }.count
    }

    private var foundPlaces: Int {
        MemoryMomentCatalog.entries.filter { isFound($0.id) }.count
            + CheckpointCatalog.entries.filter { placeRevealed($0) }.count
    }

    private func isFound(_ id: UUID) -> Bool {
        #if DEBUG
        if showHiddenPlaces { return true }
        #endif
        return found.contains(id)
    }

    private func placeRevealed(_ stop: CheckpointCatalog.Entry) -> Bool {
        if isFound(stop.id) { return true }
        guard let souvenirId = stop.souvenir?.id else { return false }
        return store.travelSouvenirs().contains { $0.souvenirId == souvenirId }
            || store.souvenirs().contains { $0.souvenirId == souvenirId }
    }

    private func placeSubtitle(_ stop: CheckpointCatalog.Entry) -> String {
        switch stop.kind {
        case .memoryStop: "Memory Stop"
        case .wildEncounter: "Wild encounter"
        case .specialEncounter: "Special encounter"
        case .travelStop: "Travel Stop"
        }
    }
}

private enum DexPage: String {
    case eggs
    case friendDex
}

private struct DexTile: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 24)
                    .fill(Color.gray.opacity(0.15))
                Image(systemName: "questionmark")
                    .font(.largeTitle.weight(.bold))
                    .foregroundStyle(.secondary)
            }
            .frame(height: 130)
            .clipShape(RoundedRectangle(cornerRadius: 24))
            Text(title)
                .font(.system(.headline, design: .rounded, weight: .bold))
                .multilineTextAlignment(.center)
                .lineLimit(2)
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(.white, in: RoundedRectangle(cornerRadius: 20))
    }
}

private struct PlaceDexDetail: View {
    let stop: CheckpointCatalog.Entry

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if let name = MemoryStopArtwork.assetName(for: stop.title), UIImage(named: name) != nil {
                    Image(name)
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: 240)
                        .clipShape(RoundedRectangle(cornerRadius: 20))
                } else {
                    Image(systemName: stop.markerSymbol)
                        .font(.system(size: 64))
                        .foregroundStyle(Color.golden)
                }
                Text(stop.title)
                    .font(.system(.largeTitle, design: .rounded, weight: .bold))
                    .multilineTextAlignment(.center)
                Text(stop.hint)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding()
        }
        .background(Color.warmWhite)
        .navigationTitle("Place")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct CreatureCardArt: View {
    let character: Character
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 24).fill(character.captured ? Color.skyBlue.opacity(0.25) : .gray.opacity(0.15))
            CreatureArtwork(
                character: character,
                pose: character.captured ? .caught : .idle,
                silhouette: !character.captured
            )
                .padding(10)
        }
        .frame(height: 130)
        .accessibilityLabel(character.captured ? character.name : "Undiscovered character silhouette")
    }
}

private struct CharacterDetail: View {
    let character: Character
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                CreatureCardArt(character: character).frame(maxWidth: 300)
                Text(character.captured ? character.name : "Keep exploring")
                    .font(.system(.largeTitle, design: .rounded, weight: .bold))
                if character.captured {
                    Text(character.description ?? "")
                    DetailRow(title: "CP", value: "\(character.combatPower)")
                    DetailRow(title: "Type", value: character.displayType)
                    DetailRow(title: "Personality", value: character.personality)
                    DetailRow(title: "Special ability", value: character.specialAbility)
                    DetailRow(title: "Rarity", value: character.rarity.rawValue.capitalized)
                    DetailRow(title: "Category", value: character.category.replacingOccurrences(of: "_", with: " ").capitalized)
                } else {
                    Text("This character's story stays secret until you catch them.")
                        .foregroundStyle(.secondary)
                }
            }.padding()
        }.background(Color.warmWhite).navigationTitle("Character")
    }
}

private struct DetailRow: View {
    let title: String
    let value: String?
    var body: some View {
        if let value, !value.isEmpty {
            VStack(alignment: .leading) {
                Text(title).font(.headline)
                Text(value)
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct MemoryBookView: View {
    @EnvironmentObject private var progress: QuestProgress

    private var messages: [BirthdayFriendMessage] {
        BirthdayMessages.all.sorted { $0.unlockLevel < $1.unlockLevel }
    }

    private var unlockedCount: Int {
        messages.filter { $0.isUnlocked(completed: progress.completed) }.count
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Birthday Messages")
                            .font(.system(.largeTitle, design: .rounded, weight: .bold))
                        Text("Win a level to unlock that friend’s note.")
                            .font(.system(.title3, design: .rounded))
                            .foregroundStyle(.secondary)
                        Text("\(unlockedCount) of \(messages.count) unlocked")
                            .font(.system(.headline, design: .rounded, weight: .bold))
                    }
                    .padding(.horizontal)

                    ForEach(Array(messages.enumerated()), id: \.element.id) { index, message in
                        let unlocked = message.isUnlocked(completed: progress.completed)
                        if unlocked {
                            NavigationLink {
                                BirthdayMessageDetailView(message: message)
                            } label: {
                                BirthdayMessageRow(
                                    message: message,
                                    color: BirthdayMessages.avatarColor(at: index),
                                    isUnlocked: true
                                )
                            }
                            .buttonStyle(.plain)
                        } else {
                            BirthdayMessageRow(
                                message: message,
                                color: BirthdayMessages.avatarColor(at: index),
                                isUnlocked: false
                            )
                        }
                    }
                }
                .padding(.vertical)
            }
            .background(Color.warmWhite)
            .navigationTitle("Birthday Messages")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

private struct BirthdayMessageRow: View {
    let message: BirthdayFriendMessage
    let color: Color
    var isUnlocked = true

    private var unlockHint: String {
        let level = QuestCatalog.level(message.unlockLevel)
        return "Win Level \(level.number) · \(level.title)"
    }

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Text(message.initial)
                    .font(.system(.title3, design: .rounded, weight: .black))
                    .foregroundStyle(.white)
                    .frame(width: 48, height: 48)
                    .background(color.opacity(isUnlocked ? 1 : 0.35), in: Circle())
                if !isUnlocked {
                    Image(systemName: "lock.fill")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.white)
                        .offset(x: 16, y: 16)
                }
            }
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(message.senderName)
                    .font(.system(.title3, design: .rounded, weight: .bold))
                    .foregroundStyle(.primary)
                if !isUnlocked {
                    Text(unlockHint)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Image(systemName: isUnlocked ? "chevron.right" : "lock.fill")
                .font(.headline.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(16)
        .background(.white, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .shadow(color: color.opacity(isUnlocked ? 0.18 : 0.08), radius: 10, y: 4)
        .padding(.horizontal)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(isUnlocked ? message.senderName : "\(message.senderName), locked. \(unlockHint)")
        .accessibilityHint(isUnlocked ? "Opens this birthday message" : "Win this level to unlock the note")
    }
}

private struct BirthdayMessageDetailView: View {
    let message: BirthdayFriendMessage

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Happy Birthday!")
                    .font(.system(.largeTitle, design: .rounded, weight: .bold))
                    .foregroundStyle(Color.birthdayPurple)
                Text(message.senderName)
                    .font(.system(.title2, design: .rounded, weight: .semibold))
                    .foregroundStyle(Color.skyBlue)
                if let imageAsset = message.imageAsset {
                    Image(imageAsset)
                        .resizable()
                        .scaledToFit()
                        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                        .accessibilityLabel("Photo from \(message.senderName)")
                }
                Text(message.body)
                    .font(.system(.body, design: .rounded))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(22)
                    .background(.white, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                    .shadow(color: .birthdayPurple.opacity(0.08), radius: 12, y: 6)
            }
            .padding(24)
        }
        .background(Color.warmWhite)
        .navigationTitle(message.senderName)
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(false)
    }
}

struct BirthdayLetterView: View {
    @EnvironmentObject private var store: GameStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let message: FriendMessage
    @State private var opened = false
    @State private var player: AVPlayer?
    @State private var isPlaying = false
    @State private var playbackError: String?

    var body: some View {
        ZStack {
            LinearGradient(colors: [.warmWhite, .skyBlue.opacity(0.18), .golden.opacity(0.2)], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
            if opened { ConfettiBurst().opacity(0.55).ignoresSafeArea() }
            ScrollView {
                VStack(spacing: 22) {
                    Image(systemName: opened ? "envelope.open.fill" : "envelope.fill")
                        .font(.system(size: 72))
                        .foregroundStyle(Color.skyBlue)
                        .rotation3DEffect(.degrees(opened ? 0 : 18), axis: (x: 1, y: 0, z: 0))
                        .shadow(color: .birthdayPurple.opacity(0.2), radius: 12, y: 6)
                    Text(message.title)
                        .font(.system(.largeTitle, design: .rounded, weight: .bold))
                        .multilineTextAlignment(.center)
                    HStack(spacing: 12) {
                        senderPhoto
                        Text("From \(message.senderName)")
                            .font(.system(.title3, design: .rounded, weight: .semibold))
                            .foregroundStyle(Color.birthdayPurple)
                    }
                    Text(message.body)
                        .font(.system(.body, design: .serif))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(22)
                        .background(.white, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                        .shadow(color: .black.opacity(0.06), radius: 12, y: 6)
                    if let place = associatedPlace {
                        Label(place, systemImage: "mappin.and.ellipse")
                            .font(.headline)
                            .foregroundStyle(Color.birthdayPurple)
                    }
                    Text("Unlocked \(message.unlockedAt.formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let playbackError {
                        Text(playbackError).foregroundStyle(.red)
                    }
                    ForEach(message.media) { media in
                        if media.kind == "audio" {
                            Button {
                                toggleAudio(media)
                            } label: {
                                Label(isPlaying ? "Pause voice note" : "Play voice note", systemImage: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                                    .font(.headline)
                            }
                            .buttonStyle(.borderedProminent)
                        } else if media.kind == "image", let url = URL(string: media.path) {
                            AsyncImage(url: url) { phase in
                                switch phase {
                                case .success(let image): image.resizable().scaledToFit()
                                case .failure: Text("Photo couldn’t be loaded.").foregroundStyle(.secondary)
                                default: ProgressView()
                                }
                            }
                            .clipShape(RoundedRectangle(cornerRadius: 20))
                            .shadow(radius: 8, y: 4)
                        }
                    }
                }
                .padding(24)
            }
        }
        .toolbar {
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                store.toggleFavorite(noteId: message.id)
            } label: {
                Label(store.isFavorite(noteId: message.id) ? "Favorited" : "Favorite", systemImage: store.isFavorite(noteId: message.id) ? "heart.fill" : "heart")
            }
            .accessibilityLabel(store.isFavorite(noteId: message.id) ? "Remove favorite" : "Favorite this note")
        }
        .onAppear {
            store.markNoteRead(noteId: message.id)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            if reduceMotion { opened = true }
            else { withAnimation(.spring(duration: 0.7)) { opened = true } }
        }
        .onDisappear {
            player?.pause()
            isPlaying = false
        }
    }

    @ViewBuilder
    private var senderPhoto: some View {
        if let path = message.senderPhotoPath, let url = URL(string: path) {
            AsyncImage(url: url) { image in image.resizable().scaledToFill() } placeholder: { Circle().fill(Color.skyBlue.opacity(0.3)) }
                .frame(width: 44, height: 44)
                .clipShape(Circle())
        }
    }

    private var associatedPlace: String? {
        BirthdayNoteRules.associationLabel(
            pin: MessagePin(
                id: message.id, locationId: message.locationId, title: message.title,
                senderName: message.senderName, visibility: "immediate", required: false, unlocked: true,
                characterId: message.characterId, passportStampKey: message.passportStampKey
            ),
            letter: message,
            snapshot: store.snapshot
        )
    }

    private func toggleAudio(_ media: MessageMedia) {
        if isPlaying {
            player?.pause()
            isPlaying = false
            return
        }
        guard let url = URL(string: media.path) else {
            playbackError = "This audio isn’t available offline yet."
            return
        }
        player = AVPlayer(url: url)
        player?.play()
        isPlaying = true
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
    }
}

struct ProfileView: View {
    @EnvironmentObject private var store: GameStore

    var body: some View {
        NavigationStack {
            List {
                if store.snapshot != nil {
                    Section {
                        VStack(alignment: .leading, spacing: 16) {
                            Image("ProfileCard")
                                .resizable()
                                .scaledToFit()
                                .frame(maxWidth: 280)
                                .frame(maxWidth: .infinity)
                                .accessibilityLabel("Chip City Trainer")
                            Text("Happy Birthday Rocco")
                                .font(.system(.title2, design: .rounded, weight: .bold))
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Text("The Ultimate Air Rounder - Level 27")
                                .font(.system(.headline, design: .rounded, weight: .semibold))
                                .foregroundStyle(.secondary)
                            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                                ProfileStat(symbol: "🏃", title: "Running", value: "96")
                                ProfileStat(symbol: "🍪", title: "Cookie Consumption", value: "99")
                                ProfileStat(symbol: "🧗", title: "Rock Climbing", value: "94")
                                ProfileStat(symbol: "❤️", title: "Boyfriend Rating", value: "100")
                                ProfileStat(symbol: "🤝", title: "Friend Loyalty", value: "100")
                                ProfileStat(symbol: "🎮", title: "Gaming", value: "98")
                            }
                        }
                        .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 16, trailing: 16))
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.warmWhite)
                    }
                    Section {
                        Button("How to Play") { store.showHowToPlay = true }
                    }
                }
            }.navigationTitle("Your Adventure")
        }
    }
}

private struct ProfileStat: View {
    let symbol: String
    let title: String
    let value: String

    var body: some View {
        VStack(spacing: 8) {
            Text("\(symbol) \(title)")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
            Text(value)
                .font(.system(size: 28, weight: .bold, design: .rounded))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .padding(.horizontal, 8)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.black.opacity(0.08), lineWidth: 1))
    }
}
