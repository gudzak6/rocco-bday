import SwiftUI
import ARKit
import RealityKit
import AVFoundation
import CoreLocation
import UIKit

enum ARCatchSupport {
    static var isAvailable: Bool {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-ui-testing-ready")
            || ProcessInfo.processInfo.arguments.contains("-ui-testing-invite") {
            return false
        }
        #endif
        return ARWorldTrackingConfiguration.isSupported
    }
}

struct EncounterView: View {
    @Environment(\.dismiss) private var dismiss
    let item: MapContentItem
    let character: Character?
    let currentLocation: CLLocation?
    let dwellStartedAt: Date
    let fallbackCode: String?

    @State private var cameraStatus = AVCaptureDevice.authorizationStatus(for: .video)
    @State private var preferCamera = true
    @State private var arFailed = false

    private var cameraBlocked: Bool {
        cameraStatus == .denied || cameraStatus == .restricted
    }

    private var useAR: Bool {
        preferCamera && !arFailed && !cameraBlocked && ARCatchSupport.isAvailable && cameraStatus == .authorized
    }

    var body: some View {
        Group {
            if preferCamera && ARCatchSupport.isAvailable && cameraStatus == .notDetermined {
                CameraPermissionCard(creatureName: item.title, onAllow: requestCamera, onSkip: { preferCamera = false })
            } else if useAR {
                ARCatchScreen(
                    item: item,
                    character: character,
                    currentLocation: currentLocation,
                    dwellStartedAt: dwellStartedAt,
                    fallbackCode: fallbackCode,
                    preferCamera: $preferCamera,
                    arFailed: $arFailed
                )
            } else {
                CatchGameView(
                    item: item,
                    character: character,
                    currentLocation: currentLocation,
                    dwellStartedAt: dwellStartedAt,
                    fallbackCode: fallbackCode,
                    showsAROffFallback: true
                )
                .overlay(alignment: .topLeading) {
                    CloseCatchButton(action: { dismiss() })
                        .padding()
                }
            }
        }
        .onAppear {
            if preferCamera && ARCatchSupport.isAvailable && cameraStatus == .notDetermined {
                requestCamera()
            }
            if cameraBlocked { preferCamera = false }
        }
    }

    private func requestCamera() {
        AVCaptureDevice.requestAccess(for: .video) { granted in
            Task { @MainActor in
                cameraStatus = AVCaptureDevice.authorizationStatus(for: .video)
                if !granted { preferCamera = false }
            }
        }
    }
}

private struct CameraPermissionCard: View {
    let creatureName: String
    let onAllow: () -> Void
    let onSkip: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "camera.viewfinder")
                .font(.system(size: 52))
                .foregroundStyle(Color.birthdayPurple)
            Text("Find \(creatureName) in the camera")
                .font(.system(.title, design: .rounded, weight: .bold))
                .multilineTextAlignment(.center)
            Text("Birthday GO uses your camera to discover and catch characters in the real world.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Open camera", action: onAllow)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            Button("Catch without camera", action: onSkip)
        }
        .padding(28)
        .background(Color.warmWhite.ignoresSafeArea())
    }
}

private struct CloseCatchButton: View {
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark.circle.fill")
                .font(.title)
                .symbolRenderingMode(.palette)
                .foregroundStyle(.white, .black.opacity(0.45))
        }
        .accessibilityLabel("Close catch")
    }
}

private struct ARCatchScreen: View {
    @EnvironmentObject private var store: GameStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    let item: MapContentItem
    let character: Character?
    let currentLocation: CLLocation?
    let dwellStartedAt: Date
    let fallbackCode: String?
    @Binding var preferCamera: Bool
    @Binding var arFailed: Bool

    @State private var state: CatchState = .aiming
    @State private var struck = false
    @State private var ballAnchor: CGPoint = .zero
    @State private var ballReset = 0
    @State private var targetFrame: CGRect = .zero
    @State private var code = ""
    @State private var didPlace = false

    private var resolvedCharacter: Character? {
        character ?? store.snapshot?.characters.first { $0.id == item.id }
    }

    private var spriteAsset: String? {
        resolvedCharacter?.catalog?.idleAsset ?? CatCatalog.entry(named: item.title)?.idleAsset
    }

    private var kind: CreatureKind {
        CreatureKind.resolving(category: resolvedCharacter?.category ?? item.category ?? "", rarity: resolvedCharacter?.rarity ?? .common)
    }

    private func creatureOnScreen(in field: CGRect) -> Bool {
        targetFrame.width > 1 && targetFrame.height > 1 && field.intersects(targetFrame)
    }

    var body: some View {
        GeometryReader { proxy in
            let field = CGRect(origin: .zero, size: proxy.size)
            ZStack {
                BirthdayARView(
                    kind: kind,
                    name: item.title,
                    spriteAsset: spriteAsset,
                    isCaught: state == .success,
                    isStruck: struck && state != .success,
                    isActive: scenePhase == .active && preferCamera,
                    onProjection: { targetFrame = $0 },
                    onPlaced: { didPlace = true },
                    onFail: { arFailed = true }
                )
                .accessibilityHidden(true)

                if state == .success { ConfettiBurst().ignoresSafeArea().allowsHitTesting(false) }
                VStack(spacing: 12) {
                    HStack {
                        CloseCatchButton { dismiss() }
                        Spacer()
                        Button("AR Off") { preferCamera = false }
                            .font(.footnote.weight(.semibold))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(.ultraThinMaterial, in: Capsule())
                            .accessibilityLabel("Catch without camera")
                    }
                    VStack(spacing: 4) {
                        Text(item.title)
                            .font(.system(.title, design: .rounded, weight: .bold))
                        if let resolvedCharacter {
                            Text("\(resolvedCharacter.rarity.rawValue.capitalized) · \(resolvedCharacter.displayType) · \(resolvedCharacter.combatPower) CP")
                                .font(.system(.headline, design: .rounded, weight: .bold))
                        }
                    }
                    .foregroundStyle(.white)
                    .shadow(radius: 6)
                    .allowsHitTesting(false)

                    Text(coachingText(creatureVisible: creatureOnScreen(in: field)))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(.black.opacity(0.35), in: Capsule())
                        .allowsHitTesting(false)

                    Spacer().allowsHitTesting(false)

                    if state == .success {
                        Label("Caught!", systemImage: "party.popper.fill")
                            .font(.system(.title, design: .rounded, weight: .bold))
                            .foregroundStyle(Color.mint)
                            .shadow(radius: 6)
                        Button("Continue") { dismiss() }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.large)
                    } else {
                        BallRestSlot()
                        Button(state == .authorizing ? "Saving…" : "Tap to catch instead") { finishThrow(hit: true) }
                            .buttonStyle(.borderedProminent)
                            .disabled(state == .authorizing || state == .throwing)
                            .accessibilityHint("Accessible alternative to the swipe gesture")
                        TextField("Fallback code if GPS fails", text: $code)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .padding(10)
                            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                        if state == .missed {
                            Text("Almost! Try again, or enter a fallback code.")
                                .foregroundStyle(.white.opacity(0.9))
                        }
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, proxy.safeAreaInsets.top + 8)
                .padding(.bottom, max(proxy.safeAreaInsets.bottom, 16))
                if state != .success {
                    ThrowableBall(
                        rest: ballAnchor,
                        playfield: field,
                        target: targetFrame,
                        reduceMotion: reduceMotion,
                        canThrow: state == .aiming || state == .missed,
                        resetToken: ballReset,
                        onLaunch: { state = .throwing },
                        onHit: {
                            struck = true
                            finishThrow(hit: true)
                        },
                        onMiss: {
                            state = .missed
                            UINotificationFeedbackGenerator().notificationOccurred(.warning)
                        }
                    )
                }
            }
            .onAppear {
                if code.isEmpty { code = fallbackCode ?? resolvedCharacter?.catalog?.fallbackCode ?? "" }
            }
            .overlayPreferenceValue(CatchAnchorKey.self) { anchors in
                CatchAnchorResolver(anchors: anchors)
            }
            .onPreferenceChange(ResolvedCatchKey.self) { resolved in
                ballAnchor = resolved.rest
            }
        }
        .ignoresSafeArea()
    }

    private func coachingText(creatureVisible: Bool) -> String {
        if state == .success { return "\(item.title) joined your Birthday Dex." }
        if !didPlace { return "Move your phone slowly to find a surface." }
        if creatureVisible { return "Drag the ball and swipe up to throw. Tap the room to move \(item.title)." }
        return "Look around to find \(item.title)"
    }

    private func finishThrow(hit: Bool) {
        guard hit else { return }
        guard state != .authorizing else { return }
        state = .authorizing
        Task {
            let saved = await store.complete(
                type: "character", id: item.id, location: currentLocation,
                dwellStartedAt: dwellStartedAt,
                fallbackCode: {
                    let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines)
                    return trimmed.isEmpty ? nil : trimmed
                }()
            )
            withAnimation {
                state = saved ? .success : .missed
                if !saved {
                    struck = false
                    ballReset += 1
                }
            }
            if saved { UINotificationFeedbackGenerator().notificationOccurred(.success) }
        }
    }
}

struct BirthdayARView: UIViewRepresentable {
    var kind: CreatureKind
    var name: String
    var spriteAsset: String?
    var isCaught: Bool
    var isStruck: Bool
    var isActive: Bool
    var onProjection: (CGRect) -> Void
    var onPlaced: () -> Void
    var onFail: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(
            kind: kind,
            name: name,
            spriteAsset: spriteAsset,
            onProjection: onProjection,
            onPlaced: onPlaced,
            onFail: onFail
        )
    }

    func makeUIView(context: Context) -> ARView {
        let arView = ARView(frame: .zero, cameraMode: .ar, automaticallyConfigureSession: false)
        arView.renderOptions.insert(.disableMotionBlur)
        arView.renderOptions.insert(.disableDepthOfField)
        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
        arView.addGestureRecognizer(tap)
        context.coordinator.attach(to: arView)
        return arView
    }

    func updateUIView(_ uiView: ARView, context: Context) {
        context.coordinator.kind = kind
        context.coordinator.name = name
        context.coordinator.spriteAsset = spriteAsset
        context.coordinator.onProjection = onProjection
        context.coordinator.onPlaced = onPlaced
        context.coordinator.onFail = onFail
        context.coordinator.setActive(isActive, in: uiView)
        if isCaught {
            context.coordinator.playCaught()
        } else {
            context.coordinator.setStruck(isStruck)
        }
    }

    static func dismantleUIView(_ uiView: ARView, coordinator: Coordinator) {
        coordinator.stop()
        uiView.session.pause()
    }

    final class Coordinator: NSObject, ARSessionDelegate, @unchecked Sendable {
        var kind: CreatureKind
        var name: String
        var spriteAsset: String?
        var onProjection: (CGRect) -> Void
        var onPlaced: () -> Void
        var onFail: () -> Void
        private weak var view: ARView?
        private var worldAnchor: AnchorEntity?
        private var creature: Entity?
        private var displayLink: CADisplayLink?
        private var placed = false
        private var caught = false
        private var impacted = false
        private var running = false
        private var bobStart = CACurrentMediaTime()
        private var attachTime = CACurrentMediaTime()
        private var spriteHalfHeight: Float = 0.22
        private var framesWithoutTracking = 0

        init(
            kind: CreatureKind,
            name: String,
            spriteAsset: String?,
            onProjection: @escaping (CGRect) -> Void,
            onPlaced: @escaping () -> Void,
            onFail: @escaping () -> Void
        ) {
            self.kind = kind
            self.name = name
            self.spriteAsset = spriteAsset
            self.onProjection = onProjection
            self.onPlaced = onPlaced
            self.onFail = onFail
        }

        func attach(to view: ARView) {
            self.view = view
            view.session.delegate = self
            start(on: view)
            let link = CADisplayLink(target: self, selector: #selector(tick))
            link.add(to: .main, forMode: .common)
            displayLink = link
        }

        func setActive(_ active: Bool, in view: ARView) {
            if active { start(on: view) } else if running {
                view.session.pause()
                running = false
            }
        }

        private func start(on view: ARView) {
            guard !running else { return }
            guard ARWorldTrackingConfiguration.isSupported else {
                onFail()
                return
            }
            let configuration = ARWorldTrackingConfiguration()
            configuration.planeDetection = [.horizontal]
            configuration.environmentTexturing = .automatic
            let options: ARSession.RunOptions = placed ? [] : [.resetTracking, .removeExistingAnchors]
            view.session.run(configuration, options: options)
            running = true
            if !placed { attachTime = CACurrentMediaTime() }
        }

        func stop() {
            displayLink?.invalidate()
            displayLink = nil
            running = false
            view?.session.pause()
        }

        @MainActor
        func setStruck(_ struck: Bool) {
            guard !caught, struck != impacted, let creature else { return }
            impacted = struck
            var transform = creature.transform
            transform.scale = SIMD3(repeating: struck ? 0.16 : 1)
            let duration = UIAccessibility.isReduceMotionEnabled ? 0.01 : 0.28
            creature.move(to: transform, relativeTo: creature.parent, duration: duration)
        }

        @MainActor
        func playCaught() {
            guard !caught, let creature else { return }
            caught = true
            var transform = creature.transform
            transform.scale = SIMD3(repeating: 0.01)
            let duration = UIAccessibility.isReduceMotionEnabled ? 0.01 : 0.45
            creature.move(to: transform, relativeTo: creature.parent, duration: duration)
        }

        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            guard let view, view === gesture.view else { return }
            let point = gesture.location(in: view)
            Task { @MainActor in
                guard !self.caught else { return }
                let hits = view.raycast(from: point, allowing: .estimatedPlane, alignment: .horizontal)
                guard let frame = view.session.currentFrame,
                      let hit = self.preferredHit(hits, camera: frame.camera) else { return }
                self.place(at: hit.worldTransform, in: view, animated: self.placed)
            }
        }

        @objc private func tick() {
            MainActor.assumeIsolated { step() }
        }

        @MainActor
        private func step() {
            guard let view, running else { return }
            guard let frame = view.session.currentFrame else {
                framesWithoutTracking += 1
                if framesWithoutTracking == 360 { onFail() }
                return
            }
            framesWithoutTracking = 0
            if !placed { attemptPlacement(in: view, camera: frame.camera) }
            faceCamera(using: frame.camera)
            bob()
            project(in: view, camera: frame.camera)
        }

        @MainActor
        private func attemptPlacement(in view: ARView, camera: ARCamera) {
            let center = CGPoint(x: view.bounds.midX, y: view.bounds.midY * 0.62)
            let hits = view.raycast(from: center, allowing: .estimatedPlane, alignment: .horizontal)
            if let hit = preferredHit(hits, camera: camera) {
                place(at: hit.worldTransform, in: view, animated: false)
                return
            }
            if CACurrentMediaTime() - attachTime > 8 {
                placeInFront(of: camera, in: view)
            }
        }

        private func preferredHit(_ results: [ARRaycastResult], camera: ARCamera) -> ARRaycastResult? {
            let cameraPosition = SIMD3<Float>(camera.transform.columns.3.x, camera.transform.columns.3.y, camera.transform.columns.3.z)
            let ranged = results.filter { result in
                let point = SIMD3<Float>(result.worldTransform.columns.3.x, result.worldTransform.columns.3.y, result.worldTransform.columns.3.z)
                let distance = simd_distance(cameraPosition, point)
                return distance >= 1 && distance <= 2
            }
            return ranged.first ?? results.first
        }

        @MainActor
        private func place(at transform: simd_float4x4, in view: ARView, animated: Bool) {
            var lifted = transform
            lifted.columns.3.y += spriteHalfHeight
            if let worldAnchor, animated {
                worldAnchor.move(to: Transform(matrix: lifted), relativeTo: nil, duration: 0.28)
                return
            }
            worldAnchor?.removeFromParent()
            let anchor = AnchorEntity(world: lifted)
            let entity = makeCreature()
            anchor.addChild(entity)
            view.scene.addAnchor(anchor)
            worldAnchor = anchor
            creature = entity
            if !placed {
                placed = true
                onPlaced()
            }
            bobStart = CACurrentMediaTime()
        }

        @MainActor
        private func placeInFront(of camera: ARCamera, in view: ARView) {
            var offset = matrix_identity_float4x4
            offset.columns.3 = SIMD4<Float>(0, -0.15, -1.5, 1)
            place(at: simd_mul(camera.transform, offset), in: view, animated: false)
        }

        @MainActor
        private func makeCreature() -> Entity {
            if let spriteAsset, let sprite = CreatureSpriteBuilder.make(assetName: spriteAsset) {
                spriteHalfHeight = sprite.visualBounds(relativeTo: sprite).extents.y / 2
                sprite.position.y = 0
                return sprite
            }
            spriteHalfHeight = 0.18
            return CreatureEntityBuilder.make(kind: kind, name: name)
        }

        @MainActor
        private func faceCamera(using camera: ARCamera) {
            guard let creature else { return }
            let cameraPosition = SIMD3<Float>(camera.transform.columns.3.x, camera.transform.columns.3.y, camera.transform.columns.3.z)
            let entityPosition = creature.position(relativeTo: nil)
            var direction = cameraPosition - entityPosition
            direction.y = 0
            guard simd_length(direction) > 0.01 else { return }
            let forward = simd_normalize(direction)
            let angle = atan2(forward.x, forward.z)
            creature.orientation = simd_quatf(angle: angle, axis: [0, 1, 0])
        }

        @MainActor
        private func bob() {
            guard !caught, !impacted, let creature else { return }
            let wave = Float(sin((CACurrentMediaTime() - bobStart) * 1.6)) * 0.03
            creature.position.y = wave
        }

        @MainActor
        private func project(in view: ARView, camera: ARCamera) {
            guard !caught, let creature else {
                onProjection(.zero)
                return
            }
            let world = creature.position(relativeTo: nil)
            let cameraPosition = SIMD3<Float>(camera.transform.columns.3.x, camera.transform.columns.3.y, camera.transform.columns.3.z)
            let forward = -SIMD3<Float>(camera.transform.columns.2.x, camera.transform.columns.2.y, camera.transform.columns.2.z)
            let toCreature = world - cameraPosition
            guard simd_length(toCreature) > 0.05, simd_dot(simd_normalize(toCreature), simd_normalize(forward)) > 0.2 else {
                onProjection(.zero)
                return
            }
            let box = creature.visualBounds(relativeTo: nil)
            let center = box.center
            let extent = box.extents / 2
            guard extent.x > 0.001, extent.y > 0.001 else {
                onProjection(.zero)
                return
            }
            let corners = [
                center + SIMD3<Float>(extent.x, extent.y, extent.z),
                center + SIMD3<Float>(extent.x, extent.y, -extent.z),
                center + SIMD3<Float>(extent.x, -extent.y, extent.z),
                center + SIMD3<Float>(extent.x, -extent.y, -extent.z),
                center + SIMD3<Float>(-extent.x, extent.y, extent.z),
                center + SIMD3<Float>(-extent.x, extent.y, -extent.z),
                center + SIMD3<Float>(-extent.x, -extent.y, extent.z),
                center + SIMD3<Float>(-extent.x, -extent.y, -extent.z)
            ]
            let projected = corners.compactMap { view.project($0) }
            guard projected.count >= 2 else {
                onProjection(.zero)
                return
            }
            let xs = projected.map(\.x)
            let ys = projected.map(\.y)
            guard let minX = xs.min(), let maxX = xs.max(), let minY = ys.min(), let maxY = ys.max() else {
                onProjection(.zero)
                return
            }
            onProjection(CGRect(x: minX, y: minY, width: max(maxX - minX, 1), height: max(maxY - minY, 1)))
        }

        nonisolated func session(_ session: ARSession, didFailWithError error: Error) {
            Task { @MainActor in self.onFail() }
        }

        nonisolated func sessionWasInterrupted(_ session: ARSession) {
            Task { @MainActor in self.running = false }
        }

        nonisolated func sessionInterruptionEnded(_ session: ARSession) {
            Task { @MainActor in
                guard let view = self.view else { return }
                self.running = false
                self.start(on: view)
            }
        }
    }
}

@MainActor
enum CreatureSpriteBuilder {
    static func make(assetName: String) -> ModelEntity? {
        guard let image = UIImage(named: assetName), let cgImage = image.cgImage else { return nil }
        let texture: TextureResource
        do {
            texture = try TextureResource.generate(from: cgImage, options: .init(semantic: .color))
        } catch {
            return nil
        }
        let aspect = Float(image.size.width / max(image.size.height, 1))
        let height: Float = 0.42
        let width = height * aspect
        var material = UnlitMaterial()
        material.color = .init(tint: .white, texture: .init(texture))
        material.blending = .transparent(opacity: .init(floatLiteral: 1))
        let mesh = MeshResource.generatePlane(width: width, height: height)
        let entity = ModelEntity(mesh: mesh, materials: [material])
        entity.name = assetName
        return entity
    }
}

@MainActor
enum CreatureEntityBuilder {
    static func make(kind: CreatureKind, name: String) -> Entity {
        let root = Entity()
        root.name = name
        switch kind {
        case .pastry:
            add(sphere: 0.2, color: UIColor(red: 1, green: 0.72, blue: 0.82, alpha: 1), to: root)
            add(sphere: 0.12, color: .white, to: root, y: 0.14)
            add(sphere: 0.04, color: UIColor(red: 1, green: 0.55, blue: 0.7, alpha: 1), to: root, x: 0.08, y: 0.18, z: 0.08)
            addEyes(to: root, z: 0.18)
        case .map:
            add(box: [0.28, 0.02, 0.2], color: UIColor(red: 1, green: 0.85, blue: 0.45, alpha: 1), to: root, y: 0.02, rotationY: 0.25)
            add(box: [0.24, 0.02, 0.18], color: UIColor(red: 0.4, green: 0.79, blue: 0.95, alpha: 1), to: root, y: 0.05, rotationY: -0.35)
            addEyes(to: root, y: 0.1, z: 0.1)
        case .candle:
            add(box: [0.08, 0.28, 0.08], color: UIColor(red: 1, green: 0.95, blue: 0.82, alpha: 1), to: root, y: -0.02)
            add(sphere: 0.07, color: UIColor(red: 1, green: 0.62, blue: 0.18, alpha: 1), to: root, y: 0.2)
            add(sphere: 0.035, color: UIColor(red: 1, green: 0.85, blue: 0.35, alpha: 1), to: root, y: 0.27)
            addEyes(to: root, y: 0.02, z: 0.05)
        case .spark:
            add(sphere: 0.16, color: UIColor(red: 0.46, green: 0.33, blue: 0.91, alpha: 1), to: root)
            add(sphere: 0.05, color: UIColor(red: 0.31, green: 0.79, blue: 0.6, alpha: 1), to: root, x: 0.14, y: 0.12)
            addEyes(to: root, z: 0.15)
        case .buddy:
            add(sphere: 0.18, color: UIColor(red: 0.4, green: 0.79, blue: 0.95, alpha: 1), to: root)
            addEyes(to: root, z: 0.16)
        }
        return root
    }

    private static func add(
        sphere radius: Float,
        color: UIColor,
        to root: Entity,
        x: Float = 0,
        y: Float = 0,
        z: Float = 0
    ) {
        let entity = ModelEntity(
            mesh: .generateSphere(radius: radius),
            materials: [UnlitMaterial(color: color)]
        )
        entity.position = [x, y, z]
        root.addChild(entity)
    }

    private static func add(
        box size: SIMD3<Float>,
        color: UIColor,
        to root: Entity,
        y: Float = 0,
        rotationY: Float = 0
    ) {
        let entity = ModelEntity(
            mesh: .generateBox(size: size, cornerRadius: 0.01),
            materials: [UnlitMaterial(color: color)]
        )
        entity.position.y = y
        if rotationY != 0 {
            entity.orientation = simd_quatf(angle: rotationY, axis: [0, 1, 0])
        }
        root.addChild(entity)
    }

    private static func addEyes(to root: Entity, y: Float = 0.06, z: Float = 0.16) {
        add(sphere: 0.022, color: .black, to: root, x: -0.05, y: y, z: z)
        add(sphere: 0.022, color: .black, to: root, x: 0.05, y: y, z: z)
    }
}
