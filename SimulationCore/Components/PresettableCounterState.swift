// Shared by CD4510 and CD4516, whose control pins have the same numbering.
struct PresettableCounterState {
    static let outputPins = [6, 11, 14, 2]
    static let presetPins = [4, 12, 13, 3]

    private let maximum: Int
    private let clock = ClockEdgeDetector()
    private var candidates: Set<Int>
    private var lastInputs: Inputs?
    private var carry: LogicState = .undefined

    private struct Inputs: Equatable {
        let reset: LogicState
        let enablePreset: LogicState
        let carryIn: LogicState
        let direction: LogicState
        let preset: [LogicState]
    }

    init(maximum: Int, initialCount: Int? = nil) {
        self.maximum = maximum
        candidates = initialCount.map { [$0] } ?? Set(0...maximum)
    }

    var count: Int? { candidates.count == 1 ? candidates.first : nil }

    mutating func powerDidFail() {
        candidates = Set(0...maximum)
        lastInputs = nil
        clock.reset()
    }

    mutating func evaluate(_ pins: [Int: Pin]) {
        let rising = clock.update(pins[15]!.state) == .rising
        let reset = pins[9]!.state
        let enablePreset = pins[1]!.state
        let canPreset = reset != .high && enablePreset != .low
        let inputs = Inputs(
            reset: reset,
            enablePreset: enablePreset,
            carryIn: pins[5]!.state,
            direction: pins[10]!.state,
            preset: canPreset ? Self.presetPins.map { pins[$0]!.state } : []
        )
        // Keep the branch-consistent carry across passes with identical controls.
        // A live control change can update asynchronous state and carry, but the
        // clock detector consumes a rising edge on its first evaluation.
        if rising || lastInputs != inputs {
            update(inputs, rising: rising)
            lastInputs = inputs
        }

        for (bit, number) in Self.outputPins.enumerated() {
            let mask = 1 << bit
            let hasLow = candidates.contains { $0 & mask == 0 }
            let hasHigh = candidates.contains { $0 & mask != 0 }
            pins[number]!.drive(Self.consensus(low: hasLow, high: hasHigh))
        }
        pins[7]!.drive(carry)
    }

    private mutating func update(_ inputs: Inputs, rising: Bool) {
        var asynchronousStates: Set<Int> = []
        if inputs.reset != .low {
            asynchronousStates.insert(0)
        }
        if !inputs.preset.isEmpty {
            for value in 0..<16 where inputs.preset.enumerated().allSatisfy({ bit, state in
                let level: LogicState = value & (1 << bit) == 0 ? .low : .high
                return state == level || state == .undefined || state == .highImpedance
            }) {
                if value <= maximum {
                    asynchronousStates.insert(value)
                } else {
                    // CD4510 ignores a non-BCD preset. Each invalid completion
                    // of a partial preset has the same hold behavior.
                    asynchronousStates.formUnion(candidates)
                }
            }
        }

        let normalOperation = inputs.reset != .high && inputs.enablePreset != .high
        var nextStates: Set<Int> = []
        var carryLow = false
        var carryHigh = false
        for up in Self.possibilities(inputs.direction) {
            let terminal = up ? maximum : 0
            for inhibited in Self.possibilities(inputs.carryIn) {
                var branch = asynchronousStates
                if normalOperation {
                    if rising && !inhibited {
                        let modulus = maximum + 1
                        let step = up ? 1 : maximum
                        branch.formUnion(candidates.map { ($0 + step) % modulus })
                    } else {
                        branch.formUnion(candidates)
                    }
                }

                nextStates.formUnion(branch)
                carryLow = carryLow || (!inhibited && branch.contains(terminal))
                carryHigh = carryHigh || inhibited || branch.contains { $0 != terminal }
            }
        }
        candidates = nextStates
        carry = Self.consensus(low: carryLow, high: carryHigh)
    }

    static func possibilities(_ state: LogicState) -> [Bool] {
        switch state {
        case .low: [false]
        case .high: [true]
        case .undefined, .highImpedance: [false, true]
        }
    }

    static func consensus(low: Bool, high: Bool) -> LogicState {
        if low && high { return .undefined }
        return high ? .high : .low
    }
}
