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
        case .requestingPermission: "Waiting for motion access"
        case .tracking: "Counting steps"
        case .paused: "Paused"
        case .denied: "Motion access is off"
        case .completed: "Walk complete"
        }
    }
}

@MainActor
final class WalkTracker: NSObject, ObservableObject {
    @Published private(set) var status: WalkTrackingStatus = .idle
    @Published private(set) var lastAcceptedMeters: Double = 0
    @Published var activityLabel = "Steps count after you start incubating"
    @Published var pauseReason: String?

    private let pedometer = CMPedometer()
    private var shouldTrack = false
    private var liveUpdatesRunning = false
    var onAcceptedDistance: ((Double) -> Void)?

    private static let anchorKey = "eggPedometerAnchor"
    private static let creditedKey = "eggPedometerCredited"

    func start(resettingBaseline: Bool = false) {
        shouldTrack = true
        guard CMPedometer.isStepCountingAvailable() else {
            status = .denied
            pauseReason = "This device can't count steps. A physical iPhone records them even while Birthday GO is closed."
            return
        }
        if CMPedometer.authorizationStatus() == .denied || CMPedometer.authorizationStatus() == .restricted {
            status = .denied
            pauseReason = "Turn on Motion & Fitness for Birthday GO to count steps."
            return
        }
        if resettingBaseline || anchorDate == nil {
            anchorDate = Date()
            creditedMeters = 0
        }
        status = .tracking
        pauseReason = nil
        activityLabel = "Steps keep counting while Birthday GO is closed."
        catchUp()
        startLiveUpdates()
    }

    func pause(reason: String = "Walking paused. Resume to keep incubating.") {
        shouldTrack = false
        stopLiveUpdates()
        flush()
        if status != .denied, status != .completed {
            status = .paused
        }
        pauseReason = reason
        activityLabel = "Paused"
    }

    func resumeAfterPause() {
        anchorDate = Date()
        creditedMeters = 0
        start()
    }

    func handleScene(active: Bool) {
        guard shouldTrack else { return }
        if active {
            status = .tracking
            pauseReason = nil
            catchUp()
            startLiveUpdates()
        } else {
            stopLiveUpdates()
            activityLabel = "Steps keep counting while Birthday GO is closed."
        }
    }

    func stop() {
        shouldTrack = false
        stopLiveUpdates()
        clearBaseline()
        if status != .denied {
            status = .idle
        }
        pauseReason = nil
        activityLabel = "Steps count after you start incubating"
    }

    func markCompleted() {
        shouldTrack = false
        stopLiveUpdates()
        clearBaseline()
        status = .completed
        pauseReason = nil
        activityLabel = "This cookie is ready to hatch"
    }

    private func catchUp() {
        guard shouldTrack, let anchor = anchorDate else { return }
        let from = anchor
        pedometer.queryPedometerData(from: from, to: Date()) { data, _ in
            let reading = Self.reading(from: data)
            Task { @MainActor in
                self.receive(reading)
            }
        }
    }

    private func flush() {
        guard let anchor = anchorDate else { return }
        pedometer.queryPedometerData(from: anchor, to: Date()) { data, _ in
            let reading = Self.reading(from: data)
            Task { @MainActor in
                self.receive(reading, force: true)
            }
        }
    }

    private func startLiveUpdates() {
        guard shouldTrack, let anchor = anchorDate, !liveUpdatesRunning else { return }
        liveUpdatesRunning = true
        pedometer.startUpdates(from: anchor) { data, _ in
            let reading = Self.reading(from: data)
            Task { @MainActor in
                self.receive(reading)
            }
        }
    }

    private func stopLiveUpdates() {
        guard liveUpdatesRunning else { return }
        pedometer.stopUpdates()
        liveUpdatesRunning = false
    }

    private func receive(_ reading: PedometerReading?, force: Bool = false) {
        guard force || shouldTrack, let reading else { return }
        let delta = reading.meters - creditedMeters
        guard delta >= 1 else {
            activityLabel = stepLabel(reading.steps)
            return
        }
        creditedMeters = reading.meters
        lastAcceptedMeters = delta
        activityLabel = stepLabel(reading.steps)
        status = shouldTrack ? .tracking : status
        onAcceptedDistance?(delta)
    }

    private func stepLabel(_ steps: Int) -> String {
        if steps > 0 {
            return "\(steps) steps since this incubation started"
        }
        return shouldTrack ? "Steps keep counting while Birthday GO is closed." : activityLabel
    }

    private struct PedometerReading {
        var meters: Double
        var steps: Int
    }

    private static func reading(from data: CMPedometerData?) -> PedometerReading? {
        guard let data else { return nil }
        let steps = data.numberOfSteps.intValue
        let meters = data.distance?.doubleValue ?? Double(steps) * 0.78
        return PedometerReading(meters: meters, steps: steps)
    }

    private var anchorDate: Date? {
        get { UserDefaults.standard.object(forKey: Self.anchorKey) as? Date }
        set {
            if let newValue {
                UserDefaults.standard.set(newValue, forKey: Self.anchorKey)
            } else {
                UserDefaults.standard.removeObject(forKey: Self.anchorKey)
            }
        }
    }

    private var creditedMeters: Double {
        get { UserDefaults.standard.double(forKey: Self.creditedKey) }
        set { UserDefaults.standard.set(newValue, forKey: Self.creditedKey) }
    }

    private func clearBaseline() {
        anchorDate = nil
        creditedMeters = 0
        UserDefaults.standard.removeObject(forKey: Self.creditedKey)
    }
}
