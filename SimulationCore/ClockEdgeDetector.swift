//
//  ClockEdgeDetector.swift
//  CMOS4000Simulator
//
//  Created by Mark Adams on 16/11/2026.
//

enum ClockEdge {
    case rising
    case falling
    case none
}

final class ClockEdgeDetector {
    private var previousState: LogicState = .undefined

    func update(_ currentState: LogicState) -> ClockEdge {
        defer {
            previousState = currentState
        }

        switch (previousState, currentState) {
        case (.low, .high):
            return .rising

        case (.high, .low):
            return .falling

        default:
            return .none
        }
    }

    func reset() {
        previousState = .undefined
    }
}
