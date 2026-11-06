import Testing
@testable import RoomDressing

private typealias Flow = CaptureFlow<String>

private func flow(_ events: [Flow.Event]) -> Flow {
    var f = Flow()
    for e in events { f.handle(e) }
    return f
}

@Test func structureBeforeDressingEndsFinishedAfterColouring() {
    let f = flow([.started, .structureFinishRequested, .structureArrived("salon"),
                  .dressingFinished(hasContent: true), .colouringProgressed(0.5),
                  .colouringSucceeded])
    #expect(f.phase == .finished("salon", dressed: true))
}

@Test func structureAfterColouringWaitsThenFinishes() {
    var f = flow([.started, .structureFinishRequested, .dressingFinished(hasContent: true),
                  .colouringSucceeded])
    #expect(f.phase == .waitingForStructure)
    f.handle(.structureArrived("salon"))
    #expect(f.phase == .finished("salon", dressed: true))
}

@Test func structureArrivingMidColouringKeepsColouring() {
    let f = flow([.started, .structureFinishRequested, .dressingFinished(hasContent: true),
                  .colouringProgressed(0.3), .structureArrived("salon")])
    #expect(f.phase == .colouring(progress: 0.3))
}

@Test func structureFailureDuringDressingFails() {
    let f = flow([.started, .structureFinishRequested, .structureFailed("RoomPlan")])
    #expect(f.phase == .failed("RoomPlan"))
}

@Test func structureFailureWhileWaitingFails() {
    let f = flow([.started, .structureFinishRequested, .dressingSkipped, .structureFailed("x")])
    #expect(f.phase == .failed("x"))
}

@Test func colouringFailureFinishesUndressed() {
    let f = flow([.started, .structureFinishRequested, .structureArrived("salon"),
                  .dressingFinished(hasContent: true), .colouringFailed])
    #expect(f.phase == .finished("salon", dressed: false))
    #expect(f.dressingFailed)
}

@Test func emptyDressingFinishesWithoutDressing() {
    let f = flow([.started, .structureFinishRequested, .structureArrived("salon"),
                  .dressingFinished(hasContent: false)])
    #expect(f.phase == .finished("salon", dressed: false))
    #expect(!f.dressingFailed)
}

@Test func skipDressingFinishesWithoutDressing() {
    let f = flow([.started, .structureFinishRequested, .dressingSkipped, .structureArrived("salon")])
    #expect(f.phase == .finished("salon", dressed: false))
}

@Test func cancelDuringColouringEndsIdle() {
    let f = flow([.started, .structureFinishRequested, .dressingFinished(hasContent: true),
                  .cancelled])
    #expect(f.phase == .idle)
    #expect(f.structure == nil)
}

@Test func lateEventsAfterFinishAreIgnored() {
    let f = flow([.started, .structureFinishRequested, .structureArrived("salon"), .dressingSkipped,
                  .structureFailed("late"), .colouringSucceeded])
    #expect(f.phase == .finished("salon", dressed: false))
}
