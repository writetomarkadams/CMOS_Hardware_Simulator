// These digital models require reset or preset to establish an initial count.
private func counterPins(inputs: [(Int, String)], outputs: [(Int, String)]) -> [Int: Pin] {
    var pins = [
        8: Pin(number: 8, name: "VSS", direction: .power),
        16: Pin(number: 16, name: "VDD", direction: .power)
    ]
    for (number, name) in inputs { pins[number] = Pin(number: number, name: name, direction: .input) }
    for (number, name) in outputs { pins[number] = Pin(number: number, name: name, direction: .output) }
    return pins
}

private func and(_ a: LogicState, _ b: LogicState) -> LogicState {
    if a == .low || b == .low { return .low }
    return a == .high && b == .high ? .high : .undefined
}

// Only CD4017 and CD4026 use this clock/inhibit rule. Capture both
// resolved pin levels on every pass, including while reset is asserted.
private struct DecodedDecadeState {
    private static let allCounts = Set(0..<10)
    private var candidates = Self.allCounts
    private var previousClock: LogicState = .undefined
    private var previousInhibit: LogicState = .undefined

    mutating func update(clock: LogicState, inhibit: LogicState, reset: LogicState) {
        defer {
            previousClock = clock
            previousInhibit = inhibit
        }

        if reset == .high {
            candidates = [0]
            return
        }

        let risingClock = previousClock == .low && clock == .high
        let stableInhibit = previousInhibit == inhibit
        let fallingInhibit = previousInhibit == .high && inhibit == .low
        let stableHighClock = previousClock == .high && clock == .high

        if risingClock && stableInhibit {
            let inhibitLevels = PresettableCounterState.possibilities(inhibit)
            if inhibitLevels.contains(false) {
                let advanced = Set(candidates.map { ($0 + 1) % 10 })
                candidates = inhibitLevels.contains(true) ? candidates.union(advanced) : advanced
            }
        } else if fallingInhibit && stableHighClock {
            candidates = Set(candidates.map { ($0 + 1) % 10 })
        }

        if reset != .low { candidates.insert(0) }
    }

    func output(_ highAtCount: (Int) -> Bool) -> LogicState {
        PresettableCounterState.consensus(
            low: candidates.contains { !highAtCount($0) },
            high: candidates.contains(where: highAtCount)
        )
    }
}

final class CD4017: PoweredChip {
    static let outputPins = [3, 2, 4, 7, 10, 1, 5, 6, 9, 11]
    let supplyPins = (vdd: 16, vss: 8)
    let pins = counterPins(
        inputs: [(14, "CLK"), (13, "CLOCK INHIBIT"), (15, "RESET")],
        outputs: Array(zip(CD4017.outputPins, (0...9).map { "Q\($0)" })) + [(12, "CARRY OUT")]
    )
    private var sequence = DecodedDecadeState()

    func powerDidFail() { sequence = DecodedDecadeState() }

    func evaluate() {
        sequence.update(clock: pins[14]!.state, inhibit: pins[13]!.state, reset: pins[15]!.state)
        for (digit, number) in Self.outputPins.enumerated() {
            pins[number]!.drive(sequence.output { $0 == digit })
        }
        pins[12]!.drive(sequence.output { $0 < 5 })
    }
}

final class CD4026: PoweredChip {
    static let segmentPins = [10, 12, 13, 9, 11, 6, 7]
    private static let digits = ["abcdef", "bc", "abdeg", "abcdg", "bcfg",
                                 "acdfg", "acdefg", "abc", "abcdefg", "abcdfg"]
    let supplyPins = (vdd: 16, vss: 8)
    let pins = counterPins(
        inputs: [(1, "CLK"), (2, "CLOCK INHIBIT"), (3, "DISPLAY ENABLE"), (15, "RESET")],
        outputs: Array(zip(CD4026.segmentPins, "abcdefg".map(String.init))) +
            [(4, "DISPLAY ENABLE OUT"), (5, "CARRY OUT"), (14, "UNGATED c")]
    )
    private var sequence = DecodedDecadeState()

    func powerDidFail() { sequence = DecodedDecadeState() }

    func evaluate() {
        sequence.update(clock: pins[1]!.state, inhibit: pins[2]!.state, reset: pins[15]!.state)
        let enable = pins[3]!.state
        pins[4]!.drive(enable == .highImpedance ? .undefined : enable)
        for (number, segment) in zip(Self.segmentPins, "abcdefg") {
            let decoded = sequence.output { Self.digits[$0].contains(segment) }
            pins[number]!.drive(and(enable, decoded))
        }
        pins[14]!.drive(sequence.output { Self.digits[$0].contains("c") })
        pins[5]!.drive(sequence.output { $0 < 5 })
    }
}

final class CD4516: PoweredChip {
    static let outputPins = PresettableCounterState.outputPins
    static let presetPins = PresettableCounterState.presetPins
    let supplyPins = (vdd: 16, vss: 8)
    let pins = counterPins(
        inputs: [(1, "PE"), (5, "CARRY IN"), (9, "RESET"), (10, "UP/DOWN"), (15, "CLK")] +
            Array(zip(CD4516.presetPins, (0...3).map { "P\($0)" })),
        outputs: Array(zip(CD4516.outputPins, (0...3).map { "Q\($0)" })) + [(7, "CARRY OUT")]
    )
    private var counter = PresettableCounterState(maximum: 15)

    init() {
        pins[15]!.tracksClockProvenance = true
    }

    func powerDidFail() {
        counter.powerDidFail()
    }

    func evaluate() {
        counter.evaluate(pins)
    }
}

final class CD4029: PoweredChip {
    static let outputPins = PresettableCounterState.outputPins // Q1 through Q4, least significant first.
    static let jamPins = PresettableCounterState.presetPins
    let supplyPins = (vdd: 16, vss: 8)
    let pins = counterPins(
        inputs: [(1, "PE"), (5, "CARRY IN"), (9, "BINARY/DECADE"), (10, "UP/DOWN"), (15, "CLK")] +
            Array(zip(CD4029.jamPins, (1...4).map { "JAM \($0)" })),
        outputs: Array(zip(CD4029.outputPins, (1...4).map { "Q\($0)" })) + [(7, "CARRY OUT")]
    )
    private static let allCounts = 0..<16
    private var history = CorrelatedClockHistory(initialStates: CD4029.allCounts)
    private var lastClock: LogicState?
    private var lastDriveObservations: [ObjectIdentifier: ClockDriveObservation] = [:]
    private var ordinal: UInt64 = 0
    private var lastInputs: Inputs?
    private var carry: LogicState = .undefined

    private struct Inputs: Equatable {
        let presetEnable: LogicState
        let carryIn: LogicState
        let binaryMode: LogicState
        let direction: LogicState
        let jam: [LogicState]
    }

    init() {
        pins[15]!.tracksClockProvenance = true
    }

    func powerDidFail() {
        history.invalidateClock(resetTo: Self.allCounts)
        lastClock = nil
        lastDriveObservations = [:]
        lastInputs = nil
    }

    func evaluate() {
        let clock = pins[15]!
        let presetEnable = pins[1]!.state
        let inputs = Inputs(
            presetEnable: presetEnable,
            carryIn: pins[5]!.state,
            binaryMode: pins[9]!.state,
            direction: pins[10]!.state,
            jam: presetEnable == .low ? [] : Self.jamPins.map { pins[$0]!.state }
        )
        let controlsChanged = lastInputs != inputs
        // The engine resolves inputs before evaluation, so common-clock
        // counters sample settled pre-edge CI regardless of registration order.
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

        if let count = history.unanimousState {
            for (bit, number) in Self.outputPins.enumerated() {
                pins[number]!.drive(count & (1 << bit) == 0 ? .low : .high)
            }
        } else {
            let candidates = history.possibleStates
            for (bit, number) in Self.outputPins.enumerated() {
                let mask = 1 << bit
                let hasLow = candidates.contains { $0 & mask == 0 }
                let hasHigh = candidates.contains { $0 & mask != 0 }
                pins[number]!.drive(PresettableCounterState.consensus(low: hasLow, high: hasHigh))
            }
        }
        pins[7]!.drive(carry)
    }

    private func update(_ inputs: Inputs, sample: ResolvedClockSample?, controlsChanged: Bool) {
        var sawRise = false
        var carryLow = false
        var carryHigh = false
        func recordCarry(_ value: Int, modulus: Int, up: Bool, inhibited: Bool) {
            let terminal = up ? modulus - 1 : 0
            carryLow = carryLow || (!inhibited && (value >= modulus || value == terminal))
            carryHigh = carryHigh || inhibited || value != terminal
        }

        let definiteJam = inputs.jam.allSatisfy { $0 == .low || $0 == .high }
        if definiteJam && [inputs.presetEnable, inputs.carryIn, inputs.binaryMode, inputs.direction]
            .allSatisfy({ $0 == .low || $0 == .high }) {
            let modulus = inputs.binaryMode == .high ? 16 : 10
            let up = inputs.direction == .high
            let inhibited = inputs.carryIn == .high
            var jam = 0
            for (bit, level) in inputs.jam.enumerated() where level == .high { jam |= 1 << bit }

            func advance(_ count: Int, _ event: ClockSampleTransition) -> CountSuccessors {
                let rising = event == .rising
                sawRise = sawRise || rising
                let successors: CountSuccessors
                if inputs.presetEnable == .high {
                    successors = .one(jam)
                } else if rising && !inhibited {
                    successors = Self.advance(count, modulus: modulus, up: up)
                } else {
                    successors = .one(count)
                }
                for value in successors { recordCarry(value, modulus: modulus, up: up, inhibited: inhibited) }
                return successors
            }
            apply(sample, transition: advance)
        } else {
            let preset: Set<Int> = inputs.jam.isEmpty ? [] : Set(Self.allCounts.filter { value in
                inputs.jam.enumerated().allSatisfy { bit, state in
                    let level: LogicState = value & (1 << bit) == 0 ? .low : .high
                    return state == level || state == .undefined || state == .highImpedance
                }
            })
            let modes = PresettableCounterState.possibilities(inputs.binaryMode)
            let directions = PresettableCounterState.possibilities(inputs.direction)
            let inhibits = PresettableCounterState.possibilities(inputs.carryIn)

            func advance(_ count: Int, _ event: ClockSampleTransition) -> Set<Int> {
                let rising = event == .rising
                sawRise = sawRise || rising
                var successors: Set<Int> = []
                for binary in modes {
                    let modulus = binary ? 16 : 10
                    for up in directions {
                        for inhibited in inhibits {
                            var branch = preset
                            if inputs.presetEnable != .high {
                                if rising && !inhibited {
                                    branch.formUnion(Self.advance(count, modulus: modulus, up: up))
                                } else {
                                    branch.insert(count)
                                }
                            }
                            for value in branch {
                                recordCarry(value, modulus: modulus, up: up, inhibited: inhibited)
                            }
                            successors.formUnion(branch)
                        }
                    }
                }
                return successors
            }
            apply(sample, transition: advance)
        }

        // Keep carry computed from the same mode, direction and CI branches
        // that produced these counts. A control change recomputes it.
        if sawRise || controlsChanged {
            carry = PresettableCounterState.consensus(low: carryLow, high: carryHigh)
        }
    }

    private func apply<Successors: Sequence>(
        _ sample: ResolvedClockSample?,
        transition: (Int, ClockSampleTransition) -> Successors
    ) where Successors.Element == Int {
        if let sample {
            history.consume(sample, applying: transition)
        } else {
            history.updateStates { transition($0, .hold) }
        }
    }

    private enum CountSuccessors: Sequence {
        case one(Int)
        case all

        func makeIterator() -> Range<Int>.Iterator {
            switch self {
            case .one(let count): (count..<(count + 1)).makeIterator()
            case .all: CD4029.allCounts.makeIterator()
            }
        }
    }

    private static func advance(_ count: Int, modulus: Int, up: Bool) -> CountSuccessors {
        // Preserve the full four-bit result for an enabled invalid decade
        // transition, confined to the clock branch in which it happens.
        guard count < modulus else { return .all }
        let step = up ? 1 : modulus - 1
        return .one((count + step) % modulus)
    }
}

enum DualCounterKind: String, CaseIterable {
    case bcd = "CD4518"
    case binary = "CD4520"
    var modulus: Int { self == .bcd ? 10 : 16 }
}

private struct DualCounterSequence {
    let modulus: Int
    private var candidates: Set<Int>
    private var previousClock: LogicState = .undefined
    private var previousEnable: LogicState = .undefined

    init(modulus: Int) {
        self.modulus = modulus
        candidates = Set(0..<modulus)
    }

    mutating func update(clock: LogicState, enable: LogicState, reset: LogicState) {
        defer {
            previousClock = clock
            previousEnable = enable
        }

        if reset == .high {
            candidates = [0]
            return
        }

        // SCHS076D: qualify the physical edge using the other resolved pin.
        // A sample with both pins changing leaves edge ordering to Phase 5.
        var countAllowed: [Bool] = [false]
        if previousClock == .low && clock == .high && previousEnable == enable {
            countAllowed = PresettableCounterState.possibilities(enable)
        } else if previousEnable == .high && enable == .low && previousClock == clock {
            countAllowed = PresettableCounterState.possibilities(clock.inverted)
        }

        if countAllowed.contains(true) {
            let advanced = Set(candidates.map { ($0 + 1) % modulus })
            candidates = countAllowed.contains(false) ? candidates.union(advanced) : advanced
        }
        if reset != .low { candidates.insert(0) }
    }

    func bit(_ bit: Int) -> LogicState {
        let mask = 1 << bit
        return PresettableCounterState.consensus(
            low: candidates.contains { $0 & mask == 0 },
            high: candidates.contains { $0 & mask != 0 }
        )
    }
}

final class DualCounter: PoweredChip {
    let kind: DualCounterKind
    let supplyPins = (vdd: 16, vss: 8)
    let pins: [Int: Pin]
    private var sequences: [DualCounterSequence]

    init(_ kind: DualCounterKind) {
        self.kind = kind
        sequences = Array(repeating: DualCounterSequence(modulus: kind.modulus), count: 2)
        pins = counterPins(
            inputs: [(1, "CLK A"), (2, "ENABLE A"), (7, "RESET A"),
                     (9, "CLK B"), (10, "ENABLE B"), (15, "RESET B")],
            outputs: (0..<2).flatMap { unit in
                (0..<4).map { (3 + unit * 8 + $0, "Q\($0 + 1)") }
            }
        )
    }

    func powerDidFail() {
        for index in sequences.indices { sequences[index] = DualCounterSequence(modulus: kind.modulus) }
    }

    func evaluate() {
        for unit in sequences.indices {
            let offset = unit * 8
            sequences[unit].update(
                clock: pins[1 + offset]!.state,
                enable: pins[2 + offset]!.state,
                reset: pins[7 + offset]!.state
            )
            for bit in 0..<4 { pins[3 + offset + bit]!.drive(sequences[unit].bit(bit)) }
        }
    }
}

enum CounterChip: String, CaseIterable, Codable {
    case cd4017 = "CD4017"
    case cd4026 = "CD4026"
    case cd4029 = "CD4029"
    case cd4516 = "CD4516"
    case ls90 = "SN74LS90"
    case ls92 = "SN74LS92"
    case ls93 = "SN74LS93"

    var isTTL: Bool {
        switch self {
        case .ls90, .ls92, .ls93: true
        default: false
        }
    }

    var detail: String {
        switch self {
        case .cd4017: "Decade Counter · Ten Decoded Outputs"
        case .cd4026: "Decade Counter · Seven-Segment Driver"
        case .cd4029: "Presettable Binary/Decade Up/Down Counter"
        case .cd4516: "Presettable Binary Up/Down Counter"
        case .ls90: "Decade Counter · Divide by 2 and 5"
        case .ls92: "Divide-by-12 Counter · Divide by 2 and 6"
        case .ls93: "Binary Counter · Divide by 2 and 8"
        }
    }

    func makeComponent() -> any PoweredChip {
        switch self {
        case .cd4017: CD4017()
        case .cd4026: CD4026()
        case .cd4029: CD4029()
        case .cd4516: CD4516()
        case .ls90, .ls92, .ls93: SN74LSCounter(self)
        }
    }

    static func kind(of component: any LogicComponent) -> Self? {
        switch component {
        case is CD4017: .cd4017
        case is CD4026: .cd4026
        case is CD4029: .cd4029
        case is CD4516: .cd4516
        case let chip as SN74LSCounter: chip.kind
        default: nil
        }
    }
}
