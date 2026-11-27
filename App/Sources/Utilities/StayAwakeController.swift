import Foundation
import IOKit.pwr_mgt

@MainActor
final class StayAwakeController: ObservableObject {
    static let shared = StayAwakeController()

    @Published private(set) var isActive = false
    @Published private(set) var expiresAt: Date?

    private var assertionID: IOPMAssertionID = 0
    private var hasAssertion = false

    private init() {}

    deinit {
        if hasAssertion {
            IOPMAssertionRelease(assertionID)
        }
    }

    func toggle(duration: TimeInterval? = nil) {
        if isActive {
            stop()
        } else {
            start(duration: duration)
        }
    }

    func start(duration: TimeInterval? = nil, now: Date = Date()) {
        stop()
        var newID: IOPMAssertionID = 0
        let result = IOPMAssertionCreateWithName(
            kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            "Ufuq Stay Awake" as CFString,
            &newID
        )
        guard result == kIOReturnSuccess else {
            NSLog("Ufuq: Stay Awake assertion failed (\(result))")
            return
        }
        assertionID = newID
        hasAssertion = true
        isActive = true
        expiresAt = duration.map { now.addingTimeInterval($0) }
    }

    func stop() {
        if hasAssertion {
            IOPMAssertionRelease(assertionID)
            hasAssertion = false
            assertionID = 0
        }
        isActive = false
        expiresAt = nil
    }

    func tick(at now: Date) {
        guard isActive, let expiresAt, now >= expiresAt else { return }
        stop()
    }
}
