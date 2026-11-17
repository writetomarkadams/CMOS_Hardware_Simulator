//
//  BCDCountState.swift
//  CMOS4000Simulator
//
//  Created by Mark Adams on 16/11/2026.
//

struct BCDCountState {

    private(set) var value: Int = 0

    // Count upwards: 0 -> 9 -> 0
    mutating func countUp() {
        value = (value + 1) % 10
    }

    // Count downwards: 9 -> 0 -> 9
    mutating func countDown() {
        value = (value + 9) % 10
    }

    // Reset the counter to zero.
    mutating func reset() {
        value = 0
    }

    // Load a BCD value (0...9).
    // Returns false for invalid values.
    @discardableResult
    mutating func load(_ newValue: Int) -> Bool {
        guard (0...9).contains(newValue) else {
            return false
        }

        value = newValue
        return true
    }

    // Four-bit BCD output, least significant bit first.
    var bits: [LogicState] {
        (0..<4).map { bit in
            (value & (1 << bit)) != 0 ? .high : .low
        }
    }
}
