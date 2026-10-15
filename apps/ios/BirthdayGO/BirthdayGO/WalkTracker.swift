@preconcurrency import CoreLocation
import CoreMotion
import Foundation

enum WalkTrackingStatus: String, Equatable, Sendable {
    case idle
    case requestingPermission
    case tracking
    case paused
    case denied
    case completed

    var title: String {
        switch self {
        case .idle: "Not tracking"
        case .requestingPermission: "Waiting for location access"
        case .tracking: "Tracking a walk"
        case .paused: "Paused"
        case .denied: "Location access is off"
        case .completed: "Walk complete"
        }
    }
}

@MainActor
final class WalkTracker: NSObject, ObservableObject {
    @Published private(set) var status: WalkTrackingStatus = .idle
    @Published private(set) var authorizationStatus: CLAuthorizationStatus
    @Published private(set) var lastAcceptedMeters: Double = 0
    @Published private(set) var activityLabel = "Waiting for movement"
    @Published var pauseReason: String?

    private let manager = CLLocationManager()
    private let motion = CMMotionActivityManager()
    private var lastSample: WalkSample?
    private var currentActivity: WalkActivity?
    private var isAppActive = true
    private var shouldTrack = false
    var onAcceptedDistance: ((Double) -> Void)?

    override init() {
        authorizationStatus = manager.authorizationStatus
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = 5
        manager.activityType = .fitness
        manager.pausesLocationUpdatesAutomatically = true
        manager.allowsBackgroundLocationUpdates = false
    }

    func requestAccess() {
        status = .requestingPermission
        manager.requestWhenInUseAuthorization()
    }

    func start() {
        shouldTrack = true
        let auth = manager.authorizationStatus
        authorizationStatus = auth
        guard auth == .authorizedWhenInUse || auth == .authorizedAlways else {
            status = auth == .notDetermined ? .requestingPermission : .denied
            if auth == .notDetermined { manager.requestWhenInUseAuthorization() }
            return
        }
        guard isAppActive else {
            status = .paused
            pauseReason = "Walking only counts while Birthday GO is open."
            return
        }
        lastSample = nil
        status = .tracking
        pauseReason = nil
        manager.startUpdatingLocation()
        startMotion()
    }

    func pause(reason: String = "Tracking paused.") {
        shouldTrack = shouldTrack && reason == "Walking only counts while Birthday GO is open."
        if reason != "Walking only counts while Birthday GO is open." {
            shouldTrack = false
        }
        manager.stopUpdatingLocation()
        lastSample = nil
        if status != .denied, status != .completed {
            status = .paused
        }
        pauseReason = reason
    }

    func resumeIfNeeded() {
        isAppActive = true
        guard shouldTrack else { return }
        start()
    }

    func handleScene(active: Bool) {
        isAppActive = active
        if active {
            resumeIfNeeded()
        } else if shouldTrack {
            pause(reason: "Walking only counts while Birthday GO is open.")
            shouldTrack = true
        }
    }

    func stop() {
        shouldTrack = false
        manager.stopUpdatingLocation()
        motion.stopActivityUpdates()
        lastSample = nil
        currentActivity = nil
        if status != .denied {
            status = .idle
        }
        pauseReason = nil
    }

    func markCompleted() {
        shouldTrack = false
        manager.stopUpdatingLocation()
        lastSample = nil
        status = .completed
        pauseReason = nil
    }

    #if DEBUG
    func simulate(meters: Double) {
        guard meters > 0 else { return }
        lastAcceptedMeters = meters
        onAcceptedDistance?(meters)
    }
    #endif

    private func startMotion() {
        guard CMMotionActivityManager.isActivityAvailable() else {
            activityLabel = "Walk filter is using GPS only"
            currentActivity = nil
            return
        }
        motion.startActivityUpdates(to: .main) { [weak self] activity in
            guard let self, let activity else { return }
            let classified = Self.classify(activity)
            self.currentActivity = classified
            self.activityLabel = Self.label(for: classified)
        }
    }

    private static func classify(_ activity: CMMotionActivity) -> WalkActivity {
        if activity.automotive { return .automotive }
        if activity.cycling { return .cycling }
        if activity.stationary { return .stationary }
        if activity.running { return .running }
        if activity.walking { return .walking }
        return .unknown
    }

    private static func label(for activity: WalkActivity) -> String {
        switch activity {
        case .walking: "Walking"
        case .running: "Running"
        case .cycling: "Bike ride ignored"
        case .automotive: "Vehicle movement ignored"
        case .stationary: "Standing still"
        case .unknown: "Uncertain — counting conservatively"
        }
    }

    private func consider(_ location: CLLocation) {
        guard shouldTrack, isAppActive, status == .tracking else { return }
        guard location.timestamp.timeIntervalSinceNow > -20 else { return }
        let sample = WalkSample(
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude,
            timestamp: location.timestamp,
            horizontalAccuracy: location.horizontalAccuracy,
            reportedSpeed: location.speed
        )
        if let previous = lastSample,
           let meters = WalkFilter.acceptedMeters(from: previous, to: sample, activity: currentActivity) {
            lastAcceptedMeters = meters
            onAcceptedDistance?(meters)
        }
        if sample.horizontalAccuracy > 0, sample.horizontalAccuracy <= WalkFilter.maxAccuracyMeters {
            lastSample = sample
        }
    }
}

extension WalkTracker: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            authorizationStatus = status
            if status == .authorizedWhenInUse || status == .authorizedAlways {
                if shouldTrack { start() }
            } else if status == .denied || status == .restricted {
                self.status = .denied
                pauseReason = "Turn on Location for Birthday GO to incubate eggs."
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let newest = locations.last else { return }
        Task { @MainActor in consider(newest) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            if status == .tracking {
                pauseReason = error.localizedDescription
            }
        }
    }
}
