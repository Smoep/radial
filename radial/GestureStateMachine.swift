import Foundation
import CoreGraphics

// MARK: - Gesture Phase

enum GesturePhase: String {
    case idle      = "Idle"
    case candidate = "Candidate"
    case active    = "Active"

    var label: String { rawValue }
}

// MARK: - Gesture State Machine

/// Tracks touch-down → candidate (hold timer) → active → idle (on lift).
///
/// Call `update(touching:elapsed:)` on every touch event / timer tick.
/// On touch-up while active, returns the finalize signal.
final class GestureStateMachine {

    private static let cooldownDuration: TimeInterval = 0.4

    private(set) var phase: GesturePhase = .idle
    private(set) var candidateStartTime: Date? = nil
    private var lastReleaseTime: Date = .distantPast

    enum Event {
        case touchDown
        case touchMove
        case touchUp
    }

    struct Result {
        var phase: GesturePhase
        var shouldFinalize: Bool = false
    }

    /// Process a touch event.
    func update(event: Event, now: Date = Date(), settings: AppSettings) -> Result {
        switch event {
        case .touchDown:
            switch phase {
            case .idle:
                let cooldownPassed = now.timeIntervalSince(lastReleaseTime) >= Self.cooldownDuration
                if cooldownPassed {
                    candidateStartTime = now
                    phase = .candidate
                }
            case .candidate, .active:
                break // already tracking
            }

        case .touchMove:
            if phase == .candidate, let start = candidateStartTime {
                let elapsed = now.timeIntervalSince(start)
                if elapsed >= max(0.05, settings.activationHoldDuration) {
                    candidateStartTime = nil
                    phase = .active
                }
            }

        case .touchUp:
            switch phase {
            case .active:
                lastReleaseTime = now
                phase = .idle
                candidateStartTime = nil
                return Result(phase: .idle, shouldFinalize: true)
            case .candidate:
                // Lifted too early — cancel
                phase = .idle
                candidateStartTime = nil
            case .idle:
                break
            }
        }

        return Result(phase: phase)
    }

    /// Also promote candidate → active during held-still touches (no move events).
    func tickCandidate(now: Date = Date(), settings: AppSettings) {
        guard phase == .candidate, let start = candidateStartTime else { return }
        let elapsed = now.timeIntervalSince(start)
        if elapsed >= max(0.05, settings.activationHoldDuration) {
            candidateStartTime = nil
            phase = .active
        }
    }

    func reset() {
        phase = .idle
        candidateStartTime = nil
    }
}
