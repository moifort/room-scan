import Foundation

/// The phases of a scan with dressing, independent of ARKit and RoomPlan.
///
/// RoomPlan's structure result arrives asynchronously while the user is
/// already dressing the room, so it may land before the dressing ends, after
/// the colours are computed, or fail in between. This type settles every
/// order in one place.
public struct CaptureFlow<Room: Equatable & Sendable>: Equatable, Sendable {
    public enum Phase: Equatable, Sendable {
        case idle
        case scanning
        case dressing
        case colouring(progress: Double)
        case waitingForStructure
        case finished(Room, dressed: Bool)
        case failed(String)
    }

    public enum Event: Equatable, Sendable {
        case started
        case structureFinishRequested
        case structureArrived(Room)
        case structureFailed(String)
        case dressingFinished(hasContent: Bool)
        case dressingSkipped
        case colouringProgressed(Double)
        case colouringSucceeded
        case colouringFailed
        case cancelled
    }

    private enum DressingOutcome: Equatable, Sendable {
        case succeeded, failed, skipped
    }

    public private(set) var phase: Phase = .idle
    public private(set) var structure: Room?
    private var outcome: DressingOutcome?

    public init() {}

    /// True once the colours failed to compute: the room is saved without its
    /// realistic view and the user is told why.
    public var dressingFailed: Bool { outcome == .failed }

    public mutating func handle(_ event: Event) {
        switch event {
        case .started:
            guard phase == .idle else { return }
            self = CaptureFlow()
            phase = .scanning

        case .structureFinishRequested:
            guard phase == .scanning else { return }
            phase = .dressing

        case .structureArrived(let room):
            guard isInProgress else { return }
            structure = room
            settle()

        case .structureFailed(let message):
            guard isInProgress || phase == .waitingForStructure else { return }
            phase = .failed(message)

        case .dressingFinished(let hasContent):
            guard phase == .dressing else { return }
            if hasContent {
                phase = .colouring(progress: 0)
            } else {
                outcome = .skipped
                settle()
            }

        case .dressingSkipped:
            guard phase == .dressing else { return }
            outcome = .skipped
            settle()

        case .colouringProgressed(let progress):
            guard case .colouring = phase else { return }
            phase = .colouring(progress: min(max(progress, 0), 1))

        case .colouringSucceeded:
            guard case .colouring = phase else { return }
            outcome = .succeeded
            settle()

        case .colouringFailed:
            guard case .colouring = phase else { return }
            outcome = .failed
            settle()

        case .cancelled:
            self = CaptureFlow()
        }
    }

    private var isInProgress: Bool {
        switch phase {
        case .scanning, .dressing, .colouring, .waitingForStructure: true
        case .idle, .finished, .failed: false
        }
    }

    /// Once the dressing is over, finish if the structure is there, else wait.
    private mutating func settle() {
        guard let outcome else { return }
        if let structure {
            phase = .finished(structure, dressed: outcome == .succeeded)
        } else {
            phase = .waitingForStructure
        }
    }
}
