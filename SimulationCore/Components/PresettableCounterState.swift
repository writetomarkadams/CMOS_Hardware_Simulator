// Shared by CD4510 and CD4516, whose control pins have the same numbering.
struct PresettableCounterState {
    static let outputPins = [6, 11, 14, 2]
    static let presetPins = [4, 12, 13, 3]

    private let maximum: Int
    private var history: CorrelatedClockHistory<Int>
    private var lastClock: LogicState?
    private var lastDriveObservations: [ObjectIdentifier: ClockDriveObservation] = [:]
    private var ordinal: UInt64 = 0
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
        if let initialCount {
            history = CorrelatedClockHistory(initialState: initialCount)
        } else {
            history = CorrelatedClockHistory(initialStates: 0...maximum)
        }
    }

    var count: Int? { history.unanimousState }

    mutating func powerDidFail() {
        history.invalidateClock(resetTo: 0...maximum)
        lastClock = nil
        lastDriveObservations = [:]
        lastInputs = nil
    }

    mutating func evaluate(_ pins: [Int: Pin]) {
        let clock = pins[15]!
        let reset = pins[9]!.state
        let enablePreset = pins[1]!.state
        let inputs = Inputs(
            reset: reset,
            enablePreset: enablePreset,
            carryIn: pins[5]!.state,
            direction: pins[10]!.state,
            preset: reset != .high && enablePreset != .low ? Self.presetPins.map { pins[$0]!.state } : []
        )
        let controlsChanged = lastInputs != inputs
        if lastClock != clock.state || lastDriveObservations != clock.clockDriveObservations {
            ordinal += 1
            let sample = ResolvedClockSample(id: ClockSampleID(ordinal: ordinal), level: clock.state)
            update(inputs, sample: sample, controlsChanged: controlsChanged)
            lastClock = clock.state
            lastDriveObservations = clock.clockDriveObservations
        } else if controlsChanged {
            update(inputs, sample: nil, controlsChanged: true)
        }
        lastInputs = inputs

        if let count {
            for (bit, number) in Self.outputPins.enumerated() {
                pins[number]!.drive(count & (1 << bit) == 0 ? .low : .high)
            }
        } else {
            let candidates = history.possibleStates
            for (bit, number) in Self.outputPins.enumerated() {
                let mask = 1 << bit
                let hasLow = candidates.contains { $0 & mask == 0 }
                let hasHigh = candidates.contains { $0 & mask != 0 }
                pins[number]!.drive(Self.consensus(low: hasLow, high: hasHigh))
            }
        }
        pins[7]!.drive(carry)
    }

    private mutating func update(_ inputs: Inputs, sample: ResolvedClockSample?, controlsChanged: Bool) {
        let maximum = self.maximum
        let normalOperation = inputs.reset != .high && inputs.enablePreset != .high
        let definitePreset = inputs.preset.count == 4 &&
            inputs.preset.allSatisfy { $0 == .low || $0 == .high }
        var presetValues: [Int] = []
        if !inputs.preset.isEmpty {
            if definitePreset {
                var value = 0
                for (bit, level) in inputs.preset.enumerated() where level == .high {
                    value |= 1 << bit
                }
                presetValues = [value]
            } else {
                presetValues = (0..<16).filter { value in
                    inputs.preset.enumerated().allSatisfy { bit, state in
                        let level: LogicState = value & (1 << bit) == 0 ? .low : .high
                        return state == level || state == .undefined || state == .highImpedance
                    }
                }
            }
        }

        var sawRise = false
        var carryLow = false
        var carryHigh = false
        func recordCarry(_ value: Int, up: Bool, inhibited: Bool) {
            if !inhibited && value == (up ? maximum : 0) {
                carryLow = true
            } else {
                carryHigh = true
            }
        }

        if (inputs.reset == .high || (inputs.reset == .low &&
             (inputs.enablePreset == .low || (inputs.enablePreset == .high && definitePreset)))) &&
            (inputs.direction == .low || inputs.direction == .high) &&
            (inputs.carryIn == .low || inputs.carryIn == .high) {
            let up = inputs.direction == .high
            let inhibited = inputs.carryIn == .high
            func advance(_ count: Int, _ event: ClockSampleTransition) -> CollectionOfOne<Int> {
                let rising = event == .rising
                sawRise = sawRise || rising
                let value: Int
                if inputs.reset == .high {
                    value = 0
                } else if inputs.enablePreset == .high {
                    let preset = presetValues[0]
                    value = preset <= maximum ? preset : count
                } else if rising && !inhibited {
                    value = (count + (up ? 1 : maximum)) % (maximum + 1)
                } else {
                    value = count
                }
                recordCarry(value, up: up, inhibited: inhibited)
                return CollectionOfOne(value)
            }
            if let sample {
                history.consume(sample, applying: advance)
            } else {
                history.updateStates { advance($0, .hold) }
            }
        } else {
            let directions = Self.possibilities(inputs.direction)
            let inhibits = Self.possibilities(inputs.carryIn)
            func advance(_ count: Int, _ event: ClockSampleTransition) -> Set<Int> {
                let rising = event == .rising
                sawRise = sawRise || rising
                // RESET supersedes PE. Each invalid BCD completion holds the
                // count in its own clock branch.
                var asynchronous = Set(presetValues.map { $0 <= maximum ? $0 : count })
                if inputs.reset != .low { asynchronous.insert(0) }

                var successors: Set<Int> = []
                for up in directions {
                    for inhibited in inhibits {
                        var branch = asynchronous
                        if normalOperation {
                            let step = up ? 1 : maximum
                            branch.insert(rising && !inhibited ? (count + step) % (maximum + 1) : count)
                        }
                        for value in branch { recordCarry(value, up: up, inhibited: inhibited) }
                        successors.formUnion(branch)
                    }
                }
                return successors
            }
            if let sample {
                history.consume(sample, applying: advance)
            } else {
                history.updateStates { advance($0, .hold) }
            }
        }

        // Carry consensus from a clocked branch survives subsequent passes
        // with the same controls. A live control change uses the hold branch.
        if sawRise || controlsChanged {
            carry = Self.consensus(low: carryLow, high: carryHigh)
        }
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
