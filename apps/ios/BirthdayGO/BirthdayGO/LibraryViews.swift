import SwiftUI
import AVFoundation
import UIKit

struct CollectionView: View {
    @EnvironmentObject private var store: GameStore
    @State private var rarity: CharacterRarity?
    @State private var category: String?
    private let columns = [GridItem(.adaptive(minimum: 145), spacing: 14)]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    EggsInventorySection()
                    Text("FriendDex")
                        .font(.system(.title2, design: .rounded, weight: .bold))
                        .padding(.horizontal)
                        .padding(.top, 8)
                    if let total = store.snapshot?.characters.count, total > 0 {
                        let caught = store.snapshot?.characters.filter(\.captured).count ?? 0
                        Text("\(caught) of \(total) discovered")
                            .font(.system(.headline, design: .rounded, weight: .bold))
                            .padding(.horizontal)
                    }
                    LazyVGrid(columns: columns, spacing: 14) {
                        ForEach(filtered) { character in
                            NavigationLink { CharacterDetail(character: character) } label: {
                                VStack(spacing: 10) {
                                    CreatureCardArt(character: character)
                                    Text(character.captured ? character.name : "Undiscovered")
                                        .font(.system(.headline, design: .rounded, weight: .bold))
                                    Text(character.rarity.rawValue.capitalized)
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                .padding().background(.white, in: RoundedRectangle(cornerRadius: 20))
                            }
                            .buttonStyle(.plain)
                        }
                    }.padding(.horizontal)
                    TravelCollectionSection()
                    if !store.souvenirs().isEmpty {
                        Text("Souvenirs")
                            .font(.system(.title2, design: .rounded, weight: .bold))
                            .padding(.horizontal)
                            .padding(.top, 8)
                        ForEach(store.souvenirs(), id: \.souvenirId) { souvenir in
                            HStack(spacing: 12) {
                                Image(systemName: souvenir.symbol)
                                    .font(.title)
                                    .foregroundStyle(Color.golden)
                                    .frame(width: 44, height: 44)
                                VStack(alignment: .leading) {
                                    Text(souvenir.name).font(.headline)
                                    Text(souvenir.checkpointTitle).font(.caption).foregroundStyle(.secondary)
                                    Text(souvenir.detail).font(.subheadline)
                                }
                            }
                            .padding()
                            .background(.white, in: RoundedRectangle(cornerRadius: 18))
                            .padding(.horizontal)
                        }
                    }
                }.padding(.vertical)
            }
            .background(Color.warmWhite)
            .navigationTitle("Birthday Dex")
            .toolbar {
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
    }

    private var filtered: [Character] {
        (store.snapshot?.characters ?? []).filter {
            (rarity == nil || $0.rarity == rarity) && (category == nil || $0.category == category)
        }
    }
}

private struct TravelCollectionSection: View {
    @EnvironmentObject private var store: GameStore

    var body: some View {
        let collected = store.travelSouvenirs()
        let collectedIds = Set(collected.map(\.souvenirId))
        VStack(alignment: .leading, spacing: 12) {
            Text("Travel Collection")
                .font(.system(.title2, design: .rounded, weight: .bold))
                .padding(.horizontal)
            Text("\(collectedIds.count) of \(TravelStops.airports.count) airports")
                .font(.system(.headline, design: .rounded, weight: .bold))
                .padding(.horizontal)
            ForEach(TravelStops.airports, id: \.id) { airport in
                let souvenir = airport.souvenir
                let owned = souvenir.flatMap { item in collected.first { $0.souvenirId == item.id } }
                HStack(spacing: 12) {
                    Image(systemName: owned == nil ? "airplane" : (souvenir?.symbol ?? "checkmark.circle.fill"))
                        .font(.title)
                        .foregroundStyle(owned == nil ? Color.secondary : Color.skyBlue)
                        .frame(width: 44, height: 44)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(souvenir?.name ?? airport.title)
                            .font(.headline)
                            .foregroundStyle(owned == nil ? .secondary : .primary)
                        Text("\(airport.airportCode ?? "") · \(airport.title)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if let owned {
                            Text("Collected \(owned.collectedAt.formatted(date: .abbreviated, time: .omitted))")
                                .font(.caption)
                                .foregroundStyle(Color.mint)
                        } else {
                            Text("Not collected yet")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    if owned != nil {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.mint)
                    }
                }
                .padding()
                .background(.white, in: RoundedRectangle(cornerRadius: 18))
                .padding(.horizontal)
                .accessibilityLabel("\(souvenir?.name ?? airport.title), \(owned == nil ? "uncollected" : "collected")")
            }
            if store.hasNYCJetsetter() {
                HStack(spacing: 12) {
                    Image(systemName: "medal.fill")
                        .font(.title)
                        .foregroundStyle(Color.golden)
                    VStack(alignment: .leading) {
                        Text(TravelStops.achievementTitle)
                            .font(.system(.headline, design: .rounded, weight: .bold))
                        Text("Checked in at JFK, LGA, and EWR.")
                            .font(.subheadline)
                        if let date = store.jetsetterAchievedAt() {
                            Text(date.formatted(date: .abbreviated, time: .omitted))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding()
                .background(Color.golden.opacity(0.2), in: RoundedRectangle(cornerRadius: 18))
                .padding(.horizontal)
            }
        }
        .padding(.top, 8)
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
    @State private var messages = BirthdayMessages.all

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Birthday Messages")
                            .font(.system(.largeTitle, design: .rounded, weight: .bold))
                        Text("A little birthday love from your friends")
                            .font(.system(.title3, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal)

                    ForEach(Array(messages.enumerated()), id: \.element.id) { index, message in
                        NavigationLink {
                            BirthdayMessageDetailView(message: message)
                        } label: {
                            BirthdayMessageRow(message: message, color: BirthdayMessages.avatarColor(at: index))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical)
            }
            .background(Color.warmWhite)
            .navigationTitle("Birthday Messages")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear { messages = BirthdayMessages.all }
        }
    }
}

private struct BirthdayMessageRow: View {
    let message: BirthdayFriendMessage
    let color: Color

    var body: some View {
        HStack(spacing: 14) {
            Text(message.initial)
                .font(.system(.title3, design: .rounded, weight: .black))
                .foregroundStyle(.white)
                .frame(width: 48, height: 48)
                .background(color, in: Circle())
                .accessibilityHidden(true)
            Text(message.senderName)
                .font(.system(.title3, design: .rounded, weight: .bold))
                .foregroundStyle(.primary)
            Spacer()
            Image(systemName: "chevron.right")
                .font(.headline.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(16)
        .background(.white, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .shadow(color: color.opacity(0.18), radius: 10, y: 4)
        .padding(.horizontal)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(message.senderName)
        .accessibilityHint("Opens this birthday message")
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
    private let colors = ["purple", "sky", "gold", "mint"]
    #if DEBUG
    @AppStorage(MemoryStopProximityOverride.defaultsKey) private var memoryStopOverride = MemoryStopProximityOverride.off.rawValue
    #endif

    var body: some View {
        NavigationStack {
            List {
                if let snapshot = store.snapshot {
                    Section {
                        Text("Happy Birthday, \(snapshot.game.recipientName)!")
                            .font(.system(.title2, design: .rounded, weight: .bold))
                        LabeledContent("XP", value: "\(snapshot.game.xp)")
                        LabeledContent("Level", value: "\(Progression.level(xp: snapshot.game.xp))")
                        LabeledContent("Characters", value: "\(snapshot.characters.filter(\.captured).count) / \(snapshot.characters.count)")
                        LabeledContent("Notes", value: "\(snapshot.unlockedMessages.count) / \(max(snapshot.messagePins.count, snapshot.unlockedMessages.count))")
                    }
                    Section("NYC Memory Passport") {
                        ForEach(MemoryPassport.stamps, id: \.key) { stamp in
                            Label(stamp.title, systemImage: store.passportStampKeys().contains(stamp.key) ? stamp.symbol : "lock.fill")
                                .foregroundStyle(store.passportStampKeys().contains(stamp.key) ? Color.golden : .secondary)
                        }
                    }
                    Section("Map avatar") {
                        HStack {
                            ForEach(colors, id: \.self) { token in
                                Button {
                                    store.setAvatar(color: token)
                                } label: {
                                    AvatarMarker(initial: String(snapshot.game.recipientName.prefix(1)), color: token)
                                        .overlay {
                                            if store.avatarColor == token {
                                                Circle().stroke(Color.birthdayPurple, lineWidth: 3)
                                            }
                                        }
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("\(token) avatar")
                            }
                        }
                    }
                    if snapshot.finale.unlocked {
                        Section("Final surprise") { FinaleView(finale: snapshot.finale) }
                    } else {
                        Section("Final surprise") {
                            Label(
                                Progression.isComplete(characters: snapshot.characters, messages: snapshot.messagePins, landmarks: snapshot.landmarks)
                                ? "Refreshing your finale…"
                                : "Complete required adventures to unlock",
                                systemImage: "lock.fill"
                            )
                        }
                    }
                    Section {
                        Button("How to Play") { store.showHowToPlay = true }
                        Button("Refresh adventure") { Task { await store.synchronize() } }
                    }
                    #if DEBUG
                    Section("Developer") {
                        Toggle("Developer encounters (no GPS)", isOn: Binding(
                            get: { UserDefaults.standard.bool(forKey: DeveloperMode.defaultsKey) },
                            set: { UserDefaults.standard.set($0, forKey: DeveloperMode.defaultsKey) }
                        ))
                        Text("Places Chair Cat and Rug Cat on the map around mock coordinates so both can be caught in Simulator.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        Picker("Memory Stop distance preview", selection: $memoryStopOverride) {
                            Text("Off").tag(MemoryStopProximityOverride.off.rawValue)
                            Text("Distant").tag(MemoryStopProximityOverride.distant.rawValue)
                            Text("Nearby").tag(MemoryStopProximityOverride.nearby.rawValue)
                            Text("In range").tag(MemoryStopProximityOverride.inRange.rawValue)
                        }
                        Text("Changes how Memory Stops look. It does not collect them or change saved XP.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        Button("Grant another 1-mile test egg") { store.grantEgg(typeId: EggCatalog.oneMileId, isTest: true) }
                        Button("Grant another 10-mile test egg") { store.grantEgg(typeId: EggCatalog.tenMileId, isTest: true) }
                        Button("Reset test egg progress") { store.resetTestEggs() }
                    }
                    #endif
                }
            }.navigationTitle("Your Adventure")
        }
    }
}

private struct FinaleView: View {
    let finale: Finale
    @State private var celebrate = false
    var body: some View {
        ZStack {
            if celebrate { ConfettiBurst().frame(height: 180) }
            VStack(spacing: 14) {
                Image(systemName: "party.popper.fill").font(.system(size: 54))
                    .foregroundStyle(Color.golden).scaleEffect(celebrate ? 1.15 : 0.85)
                Text(finale.title ?? "Your final surprise")
                    .font(.system(.title2, design: .rounded, weight: .bold))
                if let letter = finale.letter { Text(letter) }
                if let destination = finale.destination {
                    Label(destination, systemImage: "mappin.and.ellipse")
                }
                if let path = finale.mediaPath, let url = URL(string: path) {
                    AsyncImage(url: url) { image in image.resizable().scaledToFit() } placeholder: { EmptyView() }
                        .frame(maxHeight: 180)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                }
                Text("You can replay this surprise anytime.").font(.caption).foregroundStyle(.secondary)
            }
            .padding(.vertical)
        }
        .onAppear { withAnimation(.spring(duration: 0.8)) { celebrate = true } }
    }
}
