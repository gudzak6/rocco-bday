import SwiftUI
import MapKit
import CoreLocation
import UIKit

struct MapContentItem: Identifiable, Hashable {
    enum Kind: String { case character, message, landmark, checkpoint, memoryMoment }
    let id: UUID
    let locationId: UUID?
    let title: String
    let kind: Kind
    let completed: Bool
    let immediate: Bool
    let category: String?
}

struct ExploreView: View {
    @EnvironmentObject private var store: GameStore
    @EnvironmentObject private var location: LocationService
    @State private var camera: MapCameraPosition = .userLocation(fallback: .automatic)
    @State private var selected: MapContentItem?
    @State private var selectedMoment: MemoryMomentCatalog.Entry?
    @State private var selectedMemoryStop: CheckpointCatalog.Entry?
    @State private var queuedMemoryStop: CheckpointCatalog.Entry?
    @State private var showNearby = false
    @State private var memoryStopBands: [UUID: MemoryStopBand] = [:]
    @State private var memoryStopGPSBands: [UUID: MemoryStopBand] = [:]
    #if DEBUG
    @AppStorage(MemoryStopProximityOverride.defaultsKey) private var memoryStopOverrideRaw = MemoryStopProximityOverride.off.rawValue
    #endif

    private var items: [MapContentItem] {
        guard let snapshot = store.snapshot else { return [] }
        let checkpointLocations = Set(CheckpointCatalog.entries.map(\.locationId))
        let momentLocations = Set(MemoryMomentCatalog.entries.map(\.locationId))
        let reservedLocations = checkpointLocations.union(momentLocations)
        let characters = snapshot.characters.filter { !reservedLocations.contains($0.locationId ?? UUID()) }.map { character in
            MapContentItem(
                id: character.id, locationId: character.locationId, title: character.name,
                kind: .character, completed: character.captured, immediate: false, category: character.category
            )
        }
        let stamps = store.passportStampKeys()
        let messages = snapshot.messagePins.filter {
            $0.locationId != nil && !reservedLocations.contains($0.locationId ?? UUID())
        }.map { message in
            let eligible = BirthdayNoteRules.isEligible(message, snapshot: snapshot, stamps: stamps)
            return MapContentItem(
                id: message.id, locationId: message.locationId, title: message.title,
                kind: .message, completed: message.unlocked,
                immediate: message.visibility == "immediate" || message.unlockType == "immediate" || eligible,
                category: message.unlocked ? "unlocked" : (eligible ? "available" : "locked")
            )
        }
        let landmarks = snapshot.landmarks.filter { !reservedLocations.contains($0.locationId) }.map {
            MapContentItem(id: $0.id, locationId: $0.locationId, title: $0.title, kind: .landmark, completed: $0.visited, immediate: false, category: nil)
        }
        let checkpoints = CheckpointCatalog.entries.map { entry in
            MapContentItem(
                id: entry.id, locationId: entry.locationId, title: entry.title,
                kind: .checkpoint, completed: entry.isComplete(snapshot), immediate: false,
                category: entry.kind.rawValue
            )
        }
        let moments = MemoryMomentCatalog.entries.map { entry in
            MapContentItem(
                id: entry.id, locationId: entry.locationId, title: entry.title,
                kind: .memoryMoment, completed: false, immediate: true, category: "memory"
            )
        }
        return characters + messages + landmarks + checkpoints + moments
    }

    private var nearbyCreature: MapContentItem? {
        items.first { item in
            guard item.kind == .character, !item.completed,
                  let place = store.snapshot?.locations.first(where: { $0.id == item.locationId }) else { return false }
            return status(for: item, place: place) == .available
        }
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottomTrailing) {
                Map(position: $camera) {
                    if let coordinate = location.location?.coordinate {
                        Annotation("You", coordinate: coordinate) {
                            AvatarMarker(
                                initial: String(store.snapshot?.game.recipientName.prefix(1) ?? "Y"),
                                color: store.avatarColor
                            )
                        }
                    }
                    ForEach(items) { item in
                        if let place = store.snapshot?.locations.first(where: { $0.id == item.locationId }) {
                            let coordinate = CLLocationCoordinate2D(latitude: place.latitude, longitude: place.longitude)
                            let memoryStop = standardMemoryStop(for: item)
                            Annotation(item.title, coordinate: coordinate, anchor: memoryStop == nil ? .center : .bottom) {
                                Button {
                                    open(item)
                                } label: {
                                    PinView(
                                        item: item,
                                        status: item.kind == .memoryMoment ? .available : status(for: item, place: place),
                                        character: store.snapshot?.characters.first { $0.id == item.id },
                                        moment: MemoryMomentCatalog.entry(id: item.id),
                                        memoryStopBand: memoryStop == nil ? nil : (memoryStopBands[item.id] ?? .distant)
                                    )
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(accessibilityLabel(for: item, place: place))
                            }
                        }
                    }
                }
                .mapControls { MapCompass(); MapScaleView() }
                VStack {
                    Button { camera = .userLocation(fallback: .automatic) } label: {
                        Image(systemName: "location.fill").padding(12)
                    }
                    .background(.ultraThickMaterial, in: Circle())
                    .accessibilityLabel("Recenter map")
                    Button { showNearby = true } label: {
                        Image(systemName: "list.bullet").padding(12)
                    }
                    .background(.ultraThickMaterial, in: Circle())
                    .accessibilityLabel("Nearby list")
                }
                .buttonStyle(.plain).padding()
            }
            .navigationTitle("Explore")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Text("\(store.snapshot?.game.xp ?? 0) XP")
                        .font(.system(.subheadline, design: .rounded, weight: .bold))
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(Color.golden, in: Capsule())
                }
            }
            .safeAreaInset(edge: .top) {
                if let launch = store.snapshot?.game.launchAt, launch > .now {
                    Text("This adventure opens \(launch.formatted(date: .abbreviated, time: .shortened)).")
                        .font(.subheadline)
                        .padding(.horizontal).padding(.bottom, 8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.ultraThinMaterial)
                }
            }
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 8) {
                    if let nearbyCreature {
                        Button {
                            selected = nearbyCreature
                        } label: {
                            Label("Open camera to catch \(nearbyCreature.title)", systemImage: "camera.viewfinder")
                                .font(.system(.headline, design: .rounded, weight: .bold))
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .padding(.horizontal)
                        .accessibilityLabel("Open camera to catch \(nearbyCreature.title)")
                    }
                    if location.authorizationStatus == .notDetermined {
                        PermissionCard { location.requestAccess() }
                    } else if location.authorizationStatus == .denied || location.authorizationStatus == .restricted {
                        PermissionCard(denied: true) {}
                    }
                }
            }
            .onAppear {
                location.start()
                refreshMemoryStopBands()
            }
            .onDisappear { location.stop() }
            .onChange(of: locationToken) { _, _ in refreshMemoryStopBands() }
            .onChange(of: store.snapshot?.game.xp) { _, _ in refreshMemoryStopBands() }
            #if DEBUG
            .onChange(of: memoryStopOverrideRaw) { _, _ in refreshMemoryStopBands() }
            #endif
            .sheet(item: $selected) { item in MarkerDetail(item: item) }
            .sheet(isPresented: $showNearby, onDismiss: {
                if let queuedMemoryStop {
                    selectedMemoryStop = queuedMemoryStop
                    self.queuedMemoryStop = nil
                }
            }) {
                NearbyList(
                    items: items,
                    selected: $selected,
                    selectedMoment: $selectedMoment,
                    selectedMemoryStop: $queuedMemoryStop
                )
            }
            .fullScreenCover(item: $selectedMoment) { moment in
                MemoryMomentViewer(moment: moment)
            }
            .toolbar(selectedMemoryStop == nil ? .visible : .hidden, for: .tabBar)
            .overlay {
                if let checkpoint = selectedMemoryStop {
                    MemoryStopView(
                        checkpoint: checkpoint,
                        currentLocation: location.location,
                        dwellStartedAt: .now,
                        fallbackCode: checkpoint.fallbackCode,
                        onClose: { selectedMemoryStop = nil }
                    )
                    .ignoresSafeArea()
                }
            }
        }
    }

    private var locationToken: String {
        guard let current = location.location else { return "none" }
        return "\(current.coordinate.latitude),\(current.coordinate.longitude),\(current.horizontalAccuracy)"
    }

    private func open(_ item: MapContentItem) {
        if item.kind == .memoryMoment, let moment = MemoryMomentCatalog.entry(id: item.id) {
            selectedMoment = moment
        } else if let checkpoint = standardMemoryStop(for: item) {
            selectedMemoryStop = checkpoint
        } else {
            selected = item
        }
    }

    private func standardMemoryStop(for item: MapContentItem) -> CheckpointCatalog.Entry? {
        guard item.kind == .checkpoint, let checkpoint = CheckpointCatalog.entry(id: item.id), checkpoint.kind == .memoryStop else {
            return nil
        }
        return checkpoint
    }

    private func accessibilityLabel(for item: MapContentItem, place: GameLocation) -> String {
        if let band = memoryStopBands[item.id], standardMemoryStop(for: item) != nil {
            return "\(item.title), Memory Stop, \(band.rawValue)"
        }
        return "\(item.title), \(item.kind.rawValue), \(status(for: item, place: place).rawValue)"
    }

    private func refreshMemoryStopBands() {
        guard let snapshot = store.snapshot else { return }
        var display = memoryStopBands
        var gpsBands = memoryStopGPSBands
        var enteredRange = false
        for entry in CheckpointCatalog.entries where entry.kind == .memoryStop {
            let place = snapshot.locations.first { $0.id == entry.locationId }
            let maximum = Double(place?.maxAccuracyMeters ?? 250)
            let distance: Double? = location.location.map { current in
                Proximity.distanceMeters(
                    latitude: current.coordinate.latitude,
                    longitude: current.coordinate.longitude,
                    targetLatitude: place?.latitude ?? entry.latitude,
                    targetLongitude: place?.longitude ?? entry.longitude
                )
            }
            let collected = entry.isComplete(snapshot)
            let previousGPS = gpsBands[entry.id]
            let gps = MemoryStopProximity.band(
                collected: collected,
                distance: distance,
                accuracy: location.location?.horizontalAccuracy,
                maximumAccuracy: maximum,
                previous: previousGPS
            )
            if let previousGPS, previousGPS != .inRange, gps == .inRange {
                enteredRange = true
            }
            gpsBands[entry.id] = gps
            display[entry.id] = MemoryStopProximity.displayBand(
                collected: collected,
                distance: distance,
                accuracy: location.location?.horizontalAccuracy,
                maximumAccuracy: maximum,
                previous: previousGPS,
                override: MemoryStopProximityOverride.stored
            )
        }
        if gpsBands != memoryStopGPSBands {
            memoryStopGPSBands = gpsBands
        }
        if display != memoryStopBands {
            let duration = UIAccessibility.isReduceMotionEnabled ? 0.01 : 0.45
            withAnimation(.easeInOut(duration: duration)) {
                memoryStopBands = display
            }
        }
        if enteredRange {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
    }

    private func status(for item: MapContentItem, place: GameLocation) -> MarkerStatus {
        let distance: Double? = location.location.map {
            Proximity.distanceMeters(
                latitude: $0.coordinate.latitude, longitude: $0.coordinate.longitude,
                targetLatitude: place.latitude, targetLongitude: place.longitude
            )
        }
        if item.kind == .memoryMoment {
            return .available
        }
        return MarkerStatus.resolve(
            completed: item.completed,
            immediate: item.immediate,
            distance: distance,
            radius: Double(place.radiusMeters),
            accuracy: location.location?.horizontalAccuracy,
            maximumAccuracy: Double(place.maxAccuracyMeters ?? 100)
        )
    }
}

private struct PinView: View {
    let item: MapContentItem
    var status: MarkerStatus = .locked
    var character: Character?
    var moment: MemoryMomentCatalog.Entry?
    var memoryStopBand: MemoryStopBand?
    var body: some View {
        ZStack {
            if item.kind == .character && !item.completed && (status == .available || status == .nearby) {
                PulseRing(color: item.category == "inside_joke" ? .golden : .birthdayPurple)
                    .frame(width: 54, height: 54)
            }
            if item.kind == .memoryMoment, let moment {
                MemoryMomentMarker(moment: moment)
            } else if item.kind == .checkpoint, let checkpoint = CheckpointCatalog.entry(id: item.id), checkpoint.kind == .memoryStop {
                StandardMemoryStopMarker(band: memoryStopBand ?? (item.completed ? .collected : .distant))
            } else if item.kind == .checkpoint, let checkpoint = CheckpointCatalog.entry(id: item.id) {
                CheckpointMarker(checkpoint: checkpoint, status: status)
            } else {
            Group {
                if let character, character.catalog != nil {
                    CreatureArtwork(
                        character: character,
                        pose: .map,
                        silhouette: item.completed == false && status == .locked
                    )
                    .frame(width: 56, height: 72)
                } else {
                    Image(systemName: item.completed ? "checkmark.circle.fill" : icon)
                        .font(item.kind == .character && !item.completed ? .largeTitle : .title2)
                        .foregroundStyle(item.completed ? Color.mint : color)
                        .padding(item.kind == .character && !item.completed ? 8 : 8)
                        .background(.white, in: Circle())
                }
            }
            .shadow(color: item.kind == .character ? Color.birthdayPurple.opacity(0.35) : .black.opacity(0.15), radius: 6, y: 2)
            .opacity(status == .locked ? 0.55 : 1)
            .overlay(alignment: .bottomTrailing) {
                if item.kind == .character && !item.completed {
                    Image(systemName: "camera.fill")
                        .font(.caption2.bold())
                        .foregroundStyle(.white)
                        .padding(4)
                        .background(Color.birthdayPurple, in: Circle())
                        .offset(x: 4, y: 4)
                        .accessibilityHidden(true)
                }
            }
            }
        }
    }
    private var icon: String {
        switch item.kind {
        case .character:
            switch item.category {
            case "food": "birthday.cake.fill"
            case "memory": "map.fill"
            case "legendary": "flame.fill"
            default: "sparkles"
            }
        case .message:
            item.completed ? "envelope.open.fill" : (item.category == "locked" ? "lock.fill" : "envelope.fill")
        case .landmark: "mappin.and.ellipse"
        case .checkpoint: CheckpointCatalog.entry(id: item.id)?.markerSymbol ?? "mappin.circle.fill"
        case .memoryMoment: "camera.fill"
        }
    }
    private var color: Color {
        switch item.kind {
        case .character: .birthdayPurple
        case .message: .skyBlue
        case .landmark, .checkpoint: .golden
        case .memoryMoment: .birthdayPurple
        }
    }
}

private struct PermissionCard: View {
    var denied = false
    let action: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(denied ? "Location is off" : "Unlock nearby surprises")
                .font(.system(.headline, design: .rounded, weight: .bold))
            Text(denied ? "Use the nearby list and ask the organizer for a fallback code, or enable location in Settings." : "Birthday GO checks your position only while this map is open.")
                .font(.subheadline)
            if denied {
                Link("Open Settings", destination: URL(string: UIApplication.openSettingsURLString)!)
            } else {
                Button("Allow While Using App", action: action).buttonStyle(.borderedProminent)
            }
        }
        .padding().background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20)).padding()
    }
}

private struct NearbyList: View {
    @EnvironmentObject private var store: GameStore
    @EnvironmentObject private var location: LocationService
    @Environment(\.dismiss) private var dismiss
    let items: [MapContentItem]
    @Binding var selected: MapContentItem?
    @Binding var selectedMoment: MemoryMomentCatalog.Entry?
    @Binding var selectedMemoryStop: CheckpointCatalog.Entry?

    var body: some View {
        NavigationStack {
            List(sortedItems, id: \.0.id) { item, distance in
                Button {
                    dismiss()
                    if item.kind == .memoryMoment, let moment = MemoryMomentCatalog.entry(id: item.id) {
                        selectedMoment = moment
                    } else if item.kind == .checkpoint,
                              let checkpoint = CheckpointCatalog.entry(id: item.id),
                              checkpoint.kind == .memoryStop {
                        selectedMemoryStop = checkpoint
                    } else {
                        selected = item
                    }
                } label: {
                    HStack {
                        VStack(alignment: .leading) {
                            Text(item.title).font(.headline)
                            Text(nearbyKindLabel(item)).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(item.kind == .memoryMoment
                             ? "Open anywhere"
                             : distance.map { Measurement(value: $0, unit: UnitLength.meters).formatted(.measurement(width: .abbreviated)) } ?? (item.immediate ? "Open now" : "Distance unavailable"))
                            .font(.caption)
                    }
                }
            }
            .overlay {
                if items.isEmpty {
                    ContentUnavailableView("Nothing on the map yet", systemImage: "map", description: Text("When the organizer publishes places, they will appear here."))
                }
            }
            .navigationTitle("Nearby")
        }
    }

    private func nearbyKindLabel(_ item: MapContentItem) -> String {
        if item.kind == .memoryMoment { return "Memory Moment" }
        if item.kind == .checkpoint {
            switch CheckpointKind(rawValue: item.category ?? "") {
            case .travelStop: return "Travel Stop"
            case .memoryStop: return "Memory Stop"
            case .wildEncounter: return "Wild encounter"
            case .specialEncounter: return "Special encounter"
            case nil: return "Checkpoint"
            }
        }
        return item.kind.rawValue.capitalized
    }

    private var sortedItems: [(MapContentItem, Double?)] {
        items.map { item in
            let place = store.snapshot?.locations.first { $0.id == item.locationId }
            let distance = place.flatMap { place in location.location.map {
                Proximity.distanceMeters(latitude: $0.coordinate.latitude, longitude: $0.coordinate.longitude, targetLatitude: place.latitude, targetLongitude: place.longitude)
            }}
            return (item, distance)
        }.sorted { ($0.1 ?? ( $0.0.immediate ? 0 : .greatestFiniteMagnitude)) < ($1.1 ?? ($1.0.immediate ? 0 : .greatestFiniteMagnitude)) }
    }
}

private struct MarkerDetail: View {
    @EnvironmentObject private var store: GameStore
    @EnvironmentObject private var location: LocationService
    @Environment(\.dismiss) private var dismiss
    let item: MapContentItem
    @State private var fallbackCode = ""
    @State private var dwellStartedAt = Date()
    @State private var showEncounter = false
    @State private var showMemoryStop = false
    @State private var showMultiCatch = false
    @State private var showLetter = false
    @State private var showTravelStop = false
    @State private var now = Date()

    private var place: GameLocation? { store.snapshot?.locations.first { $0.id == item.locationId } }
    private var distance: Double? {
        guard let place, let current = location.location else { return nil }
        return Proximity.distanceMeters(latitude: current.coordinate.latitude, longitude: current.coordinate.longitude, targetLatitude: place.latitude, targetLongitude: place.longitude)
    }
    private var status: MarkerStatus {
        MarkerStatus.resolve(
            completed: item.completed,
            immediate: item.immediate,
            distance: distance,
            radius: Double(place?.radiusMeters ?? 75),
            accuracy: location.location?.horizontalAccuracy,
            maximumAccuracy: Double(place?.maxAccuracyMeters ?? 100)
        )
    }
    private var dwellRemaining: Int {
        max(0, Int(ceil(Double(place?.dwellSeconds ?? 8) - now.timeIntervalSince(dwellStartedAt))))
    }
    private var canAttempt: Bool {
        if item.completed { return false }
        if let checkpoint, checkpoint.kind == .memoryStop {
            guard let distance, let accuracy = location.location?.horizontalAccuracy else { return false }
            let gps = MemoryStopProximity.band(
                collected: false,
                distance: distance,
                accuracy: accuracy,
                maximumAccuracy: Double(place?.maxAccuracyMeters ?? 250),
                previous: nil
            )
            return gps == .inRange
        }
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-ui-testing-ready") || DeveloperMode.isEnabled { return true }
        #endif
        if item.immediate { return true }
        if let checkpoint, checkpoint.kind == .travelStop {
            let typed = fallbackCode.trimmingCharacters(in: .whitespacesAndNewlines)
            if typed.caseInsensitiveCompare(checkpoint.fallbackCode) == .orderedSame { return true }
        }
        if let place, CatCatalog.entry(named: item.title) != nil || CheckpointCatalog.entry(id: item.id) != nil {
            guard let distance, let accuracy = location.location?.horizontalAccuracy, accuracy > 0 else { return false }
            return distance <= Double(place.radiusMeters)
        }
        return status == .available || status == .nearby
    }

    private var character: Character? {
        store.snapshot?.characters.first { $0.id == item.id }
    }

    private var checkpoint: CheckpointCatalog.Entry? {
        CheckpointCatalog.entry(id: item.id) ?? item.locationId.flatMap(CheckpointCatalog.entry(locationId:))
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 18) {
                PinView(item: item, status: status, character: character).scaleEffect(1.5).padding()
                Text(item.title).font(.system(.title, design: .rounded, weight: .bold))
                if let checkpoint {
                    Text(checkpointLabel(checkpoint))
                        .font(.headline)
                        .foregroundStyle(Color.birthdayPurple)
                } else if let character {
                    Text("\(character.rarity.rawValue.capitalized) · \(character.displayType) · \(character.combatPower) CP")
                        .font(.headline)
                        .foregroundStyle(Color.birthdayPurple)
                }
                Text(status.rawValue.capitalized).font(.headline).foregroundStyle(status == .available ? Color.mint : .secondary)
                if item.kind == .character && !item.completed {
                    Text("Walk here, then open the camera. The birthday creature appears in the real world so you can catch it.")
                        .font(.subheadline)
                        .multilineTextAlignment(.center)
                }
                if item.kind == .message, let pin = store.snapshot?.messagePins.first(where: { $0.id == item.id }) {
                    Text(BirthdayNoteRules.spoilerSafePreview(pin, letter: unlockedLetter))
                        .font(.subheadline)
                        .multilineTextAlignment(.center)
                    if !item.completed {
                        Label(item.category == "locked" ? "Locked birthday note" : "Ready to open", systemImage: item.category == "locked" ? "lock.fill" : "envelope.fill")
                            .foregroundStyle(item.category == "locked" ? .secondary : Color.mint)
                    }
                }
                if item.kind == .checkpoint, let checkpoint, !item.completed {
                    Text(travelPrompt(checkpoint))
                        .font(.subheadline)
                        .multilineTextAlignment(.center)
                    if checkpoint.kind == .travelStop, let souvenir = checkpoint.souvenir {
                        Text("Reward: \(souvenir.name) · +100 XP")
                            .font(.subheadline.weight(.semibold))
                    } else if checkpoint.kind != .travelStop {
                        Text(checkpoint.message.title)
                            .font(.subheadline.weight(.semibold))
                    }
                }
                if let hint = place?.hint { Text(hint).multilineTextAlignment(.center) }
                Text(distance.map { "\(Int($0)) m away" } ?? (item.immediate ? "This surprise does not need GPS." : "Current distance unavailable"))
                    .foregroundStyle(.secondary)
                if item.completed {
                    Label("Completed", systemImage: "checkmark.seal.fill").foregroundStyle(Color.mint)
                    if item.kind == .message || checkpoint != nil, unlockedLetter != nil {
                        Button("Open birthday note") { showLetter = true }
                            .buttonStyle(.borderedProminent)
                    }
                } else {
                    if status == .available && dwellRemaining > 0 && fallbackCode.isEmpty && !item.immediate {
                        Text("Stay here for \(dwellRemaining) more seconds.")
                            .font(.subheadline)
                            .accessibilityLabel("Stay here for \(dwellRemaining) more seconds")
                    }
                    Button(actionLabel) {
                        if item.kind == .checkpoint, let checkpoint {
                            switch checkpoint.kind {
                            case .memoryStop: showMemoryStop = true
                            case .wildEncounter: showEncounter = true
                            case .specialEncounter: showMultiCatch = true
                            case .travelStop: showTravelStop = true
                            }
                        } else if item.kind == .character {
                            showEncounter = true
                        } else {
                            Task {
                                await finish()
                                if item.kind == .message, store.snapshot?.unlockedMessages.contains(where: { $0.id == item.id }) == true {
                                    showLetter = true
                                } else {
                                    dismiss()
                                }
                            }
                        }
                    }
                    .buttonStyle(.borderedProminent).controlSize(.large)
                    .disabled(!canAttempt)
                    .accessibilityLabel(actionLabel)
                    if !canAttempt && !item.immediate {
                        Text("Walk closer, or wait for a more accurate GPS reading.")
                            .font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    }
                    if checkpoint?.kind == .travelStop {
                        TextField("Airport check-in code", text: $fallbackCode)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .padding(10)
                            .background(Color.warmWhite, in: RoundedRectangle(cornerRadius: 12))
                            .accessibilityLabel("Airport check-in code")
                    }
                }
                Spacer()
            }
            .padding()
            .navigationTitle(place?.title ?? "Map stop")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear { resetDwellIfNeeded() }
            .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { value in
                now = value
                if status == .locked { dwellStartedAt = Date() }
            }
            .fullScreenCover(isPresented: $showEncounter) {
                EncounterView(
                    item: wildEncounterItem ?? item,
                    character: wildEncounterCharacter ?? character,
                    currentLocation: location.location,
                    dwellStartedAt: dwellStartedAt,
                    fallbackCode: fallbackCode.isEmpty ? checkpoint?.fallbackCode : fallbackCode
                )
            }
            .fullScreenCover(isPresented: $showMemoryStop) {
                if let checkpoint {
                    MemoryStopView(
                        checkpoint: checkpoint,
                        currentLocation: location.location,
                        dwellStartedAt: dwellStartedAt,
                        fallbackCode: fallbackCode.nilIfEmpty ?? checkpoint.fallbackCode
                    )
                }
            }
            .fullScreenCover(isPresented: $showTravelStop) {
                if let checkpoint {
                    TravelStopView(
                        checkpoint: checkpoint,
                        currentLocation: location.location,
                        dwellStartedAt: dwellStartedAt,
                        fallbackCode: fallbackCode.nilIfEmpty ?? checkpoint.fallbackCode
                    )
                }
            }
            .fullScreenCover(isPresented: $showMultiCatch) {
                if let checkpoint {
                    MultiCatchView(
                        checkpoint: checkpoint,
                        currentLocation: location.location,
                        dwellStartedAt: dwellStartedAt,
                        fallbackCode: fallbackCode.nilIfEmpty ?? checkpoint.fallbackCode
                    )
                }
            }
            .sheet(isPresented: $showLetter) {
                if let unlockedLetter {
                    NavigationStack { BirthdayLetterView(message: unlockedLetter) }
                }
            }
        }
    }

    private var unlockedLetter: FriendMessage? {
        store.snapshot?.unlockedMessages.first { $0.id == item.id }
            ?? checkpoint.flatMap { stop in store.snapshot?.unlockedMessages.first { $0.id == stop.message.id } }
    }

    private var actionLabel: String {
        guard let checkpoint else {
            if item.kind == .character { return "Open camera to catch" }
            if item.kind == .message { return item.completed ? "Open birthday note" : "Open birthday note" }
            return "Unlock"
        }
        switch checkpoint.kind {
        case .memoryStop: return "Open Memory Stop"
        case .wildEncounter: return "Open camera to catch"
        case .specialEncounter: return "Open special encounter"
        case .travelStop: return "Open Travel Stop"
        }
    }

    private var wildEncounterCharacter: Character? {
        guard let checkpoint else { return nil }
        return store.snapshot?.characters.first { character in
            checkpoint.characters.contains { $0.id == character.id || $0.name == character.name } && !character.captured
        }
    }

    private var wildEncounterItem: MapContentItem? {
        guard let character = wildEncounterCharacter else { return nil }
        return MapContentItem(
            id: character.id, locationId: character.locationId, title: character.name,
            kind: .character, completed: false, immediate: false, category: character.category
        )
    }

    private func checkpointLabel(_ checkpoint: CheckpointCatalog.Entry) -> String {
        switch checkpoint.kind {
        case .memoryStop: return "Memory Stop · +\(checkpoint.title == "Chip City Chelsea" ? 75 : 100) XP"
        case .wildEncounter: return "Wild encounter · +\(checkpoint.characters.first?.xpValue ?? 0) XP"
        case .specialEncounter: return "Special encounter · +\(checkpoint.characters.reduce(0) { $0 + $1.xpValue }) XP"
        case .travelStop: return "Travel Stop · \(checkpoint.airportCode ?? "") · +100 XP"
        }
    }

    private func travelPrompt(_ checkpoint: CheckpointCatalog.Entry) -> String {
        switch checkpoint.kind {
        case .travelStop: return "Walk to the landside terminal loop, then check in."
        case .memoryStop: return "Walk here, then spin the memory disc."
        case .wildEncounter, .specialEncounter: return "Walk here, then open the catch encounter."
        }
    }

    private func resetDwellIfNeeded() {
        if status == .available { dwellStartedAt = Date() }
    }

    private func finish() async {
        _ = await store.complete(
            type: item.kind.rawValue, id: item.id, location: location.location,
            dwellStartedAt: dwellStartedAt, fallbackCode: fallbackCode.nilIfEmpty
        )
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
