import SwiftUI
import MapKit
import CoreLocation
import UIKit

struct MapContentItem: Identifiable, Hashable {
    enum Kind: String { case character, message, landmark, checkpoint, memoryMoment, photo }
    let id: UUID
    let locationId: UUID?
    let title: String
    let kind: Kind
    let completed: Bool
    let immediate: Bool
    let category: String?
    var assetName: String? = nil
}

struct ExploreView: View {
    var openDex: () -> Void = {}
    @EnvironmentObject private var store: GameStore
    @EnvironmentObject private var location: LocationService
    @State private var cameraPosition: MapCameraPosition = .automatic
    @State private var followingUser = true
    @State private var acceptMapGestures = false
    @State private var playerCoordinate: CLLocationCoordinate2D?
    @State private var followAnchor: CLLocationCoordinate2D?
    @State private var closerTaunt: WalkCloserTaunt?
    #if DEBUG
    @AppStorage(HiddenPlacePreview.defaultsKey) private var showHiddenPlaces = false
    #endif
    @State private var discovered = DiscoveredPlaces.ids()
    @State private var selectedPhoto: PhotoDrop?
    @State private var queuedPhoto: PhotoDrop?
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

    /// Catalog cats stay on the map even when a checkpoint shares their place.
    private var mapItems: [MapContentItem] {
        var annotated = items
        let seen = Set(annotated.map(\.id))
        for cat in CatCatalog.entries where !seen.contains(cat.id) {
            let captured = store.snapshot?.characters.contains {
                ($0.id == cat.id || $0.name.caseInsensitiveCompare(cat.name) == .orderedSame) && $0.captured
            } ?? false
            annotated.append(MapContentItem(
                id: cat.id, locationId: cat.locationId, title: cat.name,
                kind: .character, completed: captured, immediate: false, category: cat.category
            ))
        }
        return annotated + photoItems
    }

    private var photoItems: [MapContentItem] {
        PhotoDropCatalog.drops().map { drop in
            MapContentItem(
                id: drop.id, locationId: drop.id, title: "Photo",
                kind: .photo, completed: false, immediate: false, category: "photo",
                assetName: drop.filename
            )
        }
    }

    private var nearbyItems: [MapContentItem] {
        if ProcessInfo.processInfo.arguments.contains("-ui-testing-ready") { return mapItems }
        return mapItems.filter(isRevealed)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                map
                    .ignoresSafeArea()
                VStack(spacing: 0) {
                    HStack {
                        xpBadge
                        Spacer()
                    }
                    Spacer()
                    if location.authorizationStatus == .notDetermined {
                        PermissionCard { location.requestAccess() }
                    } else if location.authorizationStatus == .denied || location.authorizationStatus == .restricted {
                        PermissionCard(denied: true) {}
                    }
                    HStack(alignment: .bottom, spacing: 12) {
                        explorePanel
                        VStack(spacing: 12) {
                            mapButton("location.fill", label: "Recenter map", action: recenter)
                            mapButton("square.grid.2x2.fill", label: "Birthday Dex", action: openDex)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
            }
            .toolbar(.hidden, for: .navigationBar)
            .safeAreaInset(edge: .top) {
                if let launch = store.snapshot?.game.launchAt, launch > .now {
                    Text("This adventure opens \(launch.formatted(date: .abbreviated, time: .shortened)).")
                        .font(.subheadline)
                        .padding(.horizontal).padding(.bottom, 8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.ultraThinMaterial)
                }
            }
            .onAppear {
                location.start()
                refreshMemoryStopBands()
                rememberPlacesInRange()
                adopt(location.location, forceCamera: true)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
                    acceptMapGestures = true
                }
            }
            .onDisappear { location.stop() }
            .onChange(of: locationToken) { _, _ in
                refreshMemoryStopBands()
                rememberPlacesInRange()
                adopt(location.location, forceCamera: false)
            }
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
                if let queuedPhoto {
                    selectedPhoto = queuedPhoto
                    self.queuedPhoto = nil
                }
            }) {
                NearbyList(
                    items: nearbyItems,
                    selected: $selected,
                    selectedMoment: $selectedMoment,
                    selectedMemoryStop: $queuedMemoryStop,
                    selectedPhoto: $queuedPhoto
                )
            }
            .sheet(item: $selectedPhoto) { drop in
                PhotoDropViewer(drop: drop)
            }
            .sheet(item: $closerTaunt) { taunt in
                WalkCloserSheet(message: taunt.text)
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
                }
            }
        }
    }

    private var locationToken: String {
        guard let current = location.location else { return "none" }
        return "\(current.coordinate.latitude),\(current.coordinate.longitude),\(current.horizontalAccuracy)"
    }

    private func open(_ item: MapContentItem) {
        if item.kind == .photo, let drop = PhotoDropCatalog.drop(id: item.id) {
            selectedPhoto = drop
        } else if item.kind == .memoryMoment, let moment = MemoryMomentCatalog.entry(id: item.id) {
            selectedMoment = moment
        } else if let checkpoint = standardMemoryStop(for: item) {
            selectedMemoryStop = checkpoint
        } else {
            selected = item
        }
    }

    private var map: some View {
        Map(position: $cameraPosition, interactionModes: [.pan, .zoom]) {
            if let playerCoordinate {
                Annotation("", coordinate: playerCoordinate, anchor: .center) {
                    PlayerLocationMarker()
                }
            }
            ForEach(mapItems) { item in
                if let coordinate = coordinate(for: item) {
                    let revealed = isRevealed(item)
                    Annotation(revealed ? item.title : "Something nearby", coordinate: coordinate, anchor: .center) {
                        Button {
                            selectOnMap(item)
                        } label: {
                            if revealed {
                                ExploreMapMarker(item: item, character: store.snapshot?.characters.first { $0.id == item.id })
                            } else {
                                HiddenMapMarker()
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(revealed ? item.title : "Something nearby")
                    }
                }
            }
        }
        .flatExploreStyle()
        .onMapCameraChange(frequency: .onEnd) { context in
            guard acceptMapGestures, followingUser, let user = location.location?.coordinate else { return }
            let drifted = Proximity.distanceMeters(
                latitude: user.latitude, longitude: user.longitude,
                targetLatitude: context.camera.centerCoordinate.latitude,
                targetLongitude: context.camera.centerCoordinate.longitude
            )
            if drifted > 40 { followingUser = false }
        }
    }

    private var xpBadge: some View {
        Text("\(store.snapshot?.game.xp ?? 0) XP")
            .font(.system(.subheadline, design: .rounded, weight: .bold))
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.white, in: Capsule())
            .shadow(color: .black.opacity(0.12), radius: 6, y: 2)
            .accessibilityLabel("\(store.snapshot?.game.xp ?? 0) XP")
    }

    private var explorePanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Explore")
                .font(.system(.title2, design: .rounded, weight: .bold))
            Button { showNearby = true } label: {
                Label("Nearby", systemImage: "list.bullet")
                    .font(.subheadline.weight(.semibold))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Nearby list")
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .shadow(color: .black.opacity(0.12), radius: 10, y: 4)
    }

    private func mapButton(_ systemName: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.body.weight(.semibold))
                .frame(width: 48, height: 48)
                .background(.white, in: Circle())
                .shadow(color: .black.opacity(0.12), radius: 6, y: 2)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private func neighborhoodCamera(_ coordinate: CLLocationCoordinate2D) -> MapCameraPosition {
        .camera(MapCamera(centerCoordinate: coordinate, distance: 1_400, heading: 0, pitch: 0))
    }

    private func adopt(_ fix: CLLocation?, forceCamera: Bool) {
        guard let coordinate = fix?.coordinate else { return }
        if let playerCoordinate {
            let moved = Proximity.distanceMeters(
                latitude: playerCoordinate.latitude, longitude: playerCoordinate.longitude,
                targetLatitude: coordinate.latitude, targetLongitude: coordinate.longitude
            )
            if moved >= 4 { self.playerCoordinate = coordinate }
        } else {
            playerCoordinate = coordinate
        }
        guard followingUser else { return }
        let fromAnchor = followAnchor.map {
            Proximity.distanceMeters(
                latitude: $0.latitude, longitude: $0.longitude,
                targetLatitude: coordinate.latitude, targetLongitude: coordinate.longitude
            )
        } ?? .greatestFiniteMagnitude
        guard forceCamera || followAnchor == nil || fromAnchor >= 25 else { return }
        followAnchor = coordinate
        acceptMapGestures = false
        if forceCamera {
            cameraPosition = neighborhoodCamera(coordinate)
        } else {
            cameraPosition = neighborhoodCamera(coordinate)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
            acceptMapGestures = true
        }
    }

    private func recenter() {
        let coordinate = location.location?.coordinate ?? playerCoordinate
        guard let coordinate else { return }
        followingUser = true
        followAnchor = coordinate
        playerCoordinate = coordinate
        acceptMapGestures = false
        withAnimation(.easeInOut(duration: 0.35)) {
            cameraPosition = neighborhoodCamera(coordinate)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            acceptMapGestures = true
        }
    }

    private func selectOnMap(_ item: MapContentItem) {
        if isRevealed(item) {
            open(item)
        } else {
            closerTaunt = WalkCloserTaunt(text: WalkCloserTaunts.next(after: closerTaunt?.text))
        }
    }

    private func isRevealed(_ item: MapContentItem) -> Bool {
        #if DEBUG
        if showHiddenPlaces { return true }
        #endif
        return discovered.contains(item.id) || isInRange(item)
    }

    private func isInRange(_ item: MapContentItem) -> Bool {
        guard let place = place(for: item), let fix = location.location else { return false }
        let distance = Proximity.distanceMeters(
            latitude: fix.coordinate.latitude, longitude: fix.coordinate.longitude,
            targetLatitude: place.latitude, targetLongitude: place.longitude
        )
        return MapReveal.isWithinRange(
            distance: distance,
            accuracy: fix.horizontalAccuracy,
            radius: Double(place.radiusMeters),
            maximumAccuracy: Double(place.maxAccuracyMeters ?? 250)
        )
    }

    private func rememberPlacesInRange() {
        var changed = false
        for item in mapItems where !discovered.contains(item.id) && isInRange(item) {
            DiscoveredPlaces.remember(item.id)
            changed = true
        }
        if changed { discovered = DiscoveredPlaces.ids() }
    }

    private func coordinate(for item: MapContentItem) -> CLLocationCoordinate2D? {
        guard let place = place(for: item) else { return nil }
        return CLLocationCoordinate2D(latitude: place.latitude, longitude: place.longitude)
    }

    private func place(for item: MapContentItem) -> GameLocation? {
        if item.kind == .photo, let drop = PhotoDropCatalog.drop(id: item.id) {
            return drop.asLocation
        }
        if let place = store.snapshot?.locations.first(where: { $0.id == item.locationId }) {
            return place
        }
        if let cat = CatCatalog.entry(id: item.id) ?? CatCatalog.entry(named: item.title) {
            return cat.asLocation
        }
        if let stop = CheckpointCatalog.entry(id: item.id) {
            return stop.asLocation
        }
        if let moment = MemoryMomentCatalog.entry(id: item.id) {
            return moment.asLocation
        }
        return nil
    }

    private func standardMemoryStop(for item: MapContentItem) -> CheckpointCatalog.Entry? {
        guard item.kind == .checkpoint, let checkpoint = CheckpointCatalog.entry(id: item.id), checkpoint.kind == .memoryStop else {
            return nil
        }
        return checkpoint
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

private struct PlayerLocationMarker: View {
    var body: some View {
        ZStack {
            Circle()
                .fill(Color.green.opacity(0.22))
                .frame(width: 36, height: 36)
            Circle()
                .fill(Color.green)
                .frame(width: 16, height: 16)
                .overlay(Circle().stroke(.white, lineWidth: 3))
                .shadow(color: .black.opacity(0.2), radius: 2, y: 1)
        }
        .allowsHitTesting(false)
    }
}

private struct ExploreMapMarker: View {
    let item: MapContentItem
    let character: Character?

    var body: some View {
        markerImage
            .frame(width: 40, height: 40)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .padding(4)
            .background(.white, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(border, lineWidth: legendary ? 2.5 : 0)
            }
            .shadow(color: .black.opacity(0.18), radius: 4, y: 2)
            .opacity(item.completed ? 0.72 : 1)
    }

    private var legendary: Bool {
        character?.category == "legendary" || character?.rarity == .legendary
    }

    private var border: Color {
        legendary ? Color.golden : .white
    }

    @ViewBuilder
    private var markerImage: some View {
        if item.kind == .character, let character {
            CreatureArtwork(character: character, useIcon: true)
        } else if item.kind == .character,
                  let cat = CatCatalog.entry(id: item.id) ?? CatCatalog.entry(named: item.title),
                  UIImage(named: cat.mapAsset) != nil {
            Image(cat.mapAsset).resizable().scaledToFill()
        } else if item.kind == .memoryMoment,
                  let name = MemoryMomentCatalog.entry(id: item.id)?.thumbnailAsset,
                  UIImage(named: name) != nil {
            Image(name).resizable().scaledToFill()
        } else if item.kind == .photo,
                  let name = item.assetName,
                  let image = PhotoDropImage.thumbnail(filename: name) {
            Image(uiImage: image).resizable().scaledToFill()
        } else if item.kind == .checkpoint,
                  let checkpoint = CheckpointCatalog.entry(id: item.id),
                  let name = MemoryStopArtwork.assetName(for: checkpoint.title),
                  UIImage(named: name) != nil {
            Image(name).resizable().scaledToFill()
        } else {
            Image(systemName: fallbackSymbol)
                .font(.title3)
                .foregroundStyle(Color.golden)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.golden.opacity(0.12))
        }
    }

    private var fallbackSymbol: String {
        switch item.kind {
        case .character: "pawprint.fill"
        case .memoryMoment: "sparkles"
        case .checkpoint: CheckpointCatalog.entry(id: item.id)?.markerSymbol ?? "mappin"
        case .message: "envelope.fill"
        case .landmark: "star.fill"
        case .photo: "photo"
        }
    }
}

private struct WalkCloserSheet: View {
    let message: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "figure.walk")
                .font(.largeTitle)
                .foregroundStyle(Color.birthdayPurple)
            Text(message)
                .font(.system(.title3, design: .rounded, weight: .bold))
                .multilineTextAlignment(.center)
            Button("I'll walk") { dismiss() }
                .buttonStyle(.borderedProminent)
                .tint(Color.birthdayPurple)
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.warmWhite)
        .presentationDetents([.height(260)])
        .presentationDragIndicator(.visible)
    }
}

private struct HiddenMapMarker: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(.white)
            .frame(width: 48, height: 48)
            .overlay {
                Image(systemName: "questionmark")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(.secondary)
            }
            .shadow(color: .black.opacity(0.18), radius: 4, y: 2)
    }
}

struct PhotoDropViewer: View {
    let drop: PhotoDrop
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if let image = PhotoDropImage.image(filename: drop.filename) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .padding()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.black)
            .navigationTitle("Photo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
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
        case .photo: "photo"
        }
    }
    private var color: Color {
        switch item.kind {
        case .character: .birthdayPurple
        case .message: .skyBlue
        case .landmark, .checkpoint: .golden
        case .memoryMoment, .photo: .birthdayPurple
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
            Text(denied ? "Use the nearby list and ask the organizer for a fallback code, or enable location in Settings." : "Birthday GO checks your position only while Explore is open.")
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
    @Binding var selectedPhoto: PhotoDrop?

    var body: some View {
        NavigationStack {
            List(sortedItems, id: \.0.id) { item, distance in
                Button {
                    dismiss()
                    if item.kind == .photo, let drop = PhotoDropCatalog.drop(id: item.id) {
                        selectedPhoto = drop
                    } else if item.kind == .memoryMoment, let moment = MemoryMomentCatalog.entry(id: item.id) {
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
        if item.kind == .photo { return "Photo" }
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
            let coordinate: (latitude: Double, longitude: Double)? = {
                if let place = store.snapshot?.locations.first(where: { $0.id == item.locationId }) {
                    return (place.latitude, place.longitude)
                }
                if let drop = PhotoDropCatalog.drop(id: item.id) {
                    return (drop.latitude, drop.longitude)
                }
                return nil
            }()
            let distance = coordinate.flatMap { place in location.location.map {
                Proximity.distanceMeters(
                    latitude: $0.coordinate.latitude, longitude: $0.coordinate.longitude,
                    targetLatitude: place.latitude, targetLongitude: place.longitude
                )
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

private extension View {
    @ViewBuilder
    func flatExploreStyle() -> some View {
        if #available(iOS 18.0, *) {
            self.mapStyle(.standard(elevation: .flat, emphasis: .muted, pointsOfInterest: .excludingAll, showsTraffic: false))
        } else {
            self.mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll, showsTraffic: false))
        }
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
