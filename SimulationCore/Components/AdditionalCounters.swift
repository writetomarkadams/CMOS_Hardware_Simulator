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

private struct CounterSequence {
    var count: Int?
    let modulus: Int
    private let edge = ClockEdgeDetector()

    init(modulus: Int) { self.modulus = modulus }

    mutating func update(clock: LogicState, reset: LogicState) {
        let transition = edge.update(clock)
        if reset == .high {
            count = 0
        } else if reset != .low || (clock != .low && clock != .high) {
            count = nil
        } else if transition == .rising, let count {
            self.count = (count + 1) % modulus
        }
    }

    mutating func invalidate() {
        count = nil
        edge.reset()
    }

    func bit(_ bit: Int) -> LogicState {
        guard let count else { return .undefined }
        return count & (1 << bit) == 0 ? .low : .high
    }
}

final class CD4017: PoweredChip {
    static let outputPins = [3, 2, 4, 7, 10, 1, 5, 6, 9, 11]
    let supplyPins = (vdd: 16, vss: 8)
    let pins = counterPins(
        inputs: [(14, "CLK"), (13, "CLOCK INHIBIT"), (15, "RESET")],
        outputs: Array(zip(CD4017.outputPins, (0...9).map { "Q\($0)" })) + [(12, "CARRY OUT")]
    )
    private var sequence = CounterSequence(modulus: 10)

    func powerDidFail() { sequence.invalidate() }

    func evaluate() {
        sequence.update(clock: and(pins[14]!.state, pins[13]!.state.inverted), reset: pins[15]!.state)
        for (digit, number) in Self.outputPins.enumerated() {
            pins[number]!.drive(sequence.count.map { $0 == digit ? .high : .low } ?? .undefined)
        }
        pins[12]!.drive(sequence.count.map { $0 < 5 ? .high : .low } ?? .undefined)
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
    private var sequence = CounterSequence(modulus: 10)

    func powerDidFail() { sequence.invalidate() }

    func evaluate() {
        sequence.update(clock: and(pins[1]!.state, pins[2]!.state.inverted), reset: pins[15]!.state)
        let enable = pins[3]!.state
        pins[4]!.drive(enable == .highImpedance ? .undefined : enable)
        let pattern = sequence.count.map { Self.digits[$0] }
        for (number, segment) in zip(Self.segmentPins, "abcdefg") {
            let decoded: LogicState = pattern.map { $0.contains(segment) ? .high : .low } ?? .undefined
            pins[number]!.drive(and(enable, decoded))
        }
        pins[14]!.drive(pattern.map { $0.contains("c") ? .high : .low } ?? .undefined)
        pins[5]!.drive(sequence.count.map { $0 < 5 ? .high : .low } ?? .undefined)
    }
}

final class CD4516: PoweredChip {
    static let outputPins = [6, 11, 14, 2]
    static let presetPins = [4, 12, 13, 3]
    let supplyPins = (vdd: 16, vss: 8)
    let pins = counterPins(
        inputs: [(1, "PE"), (5, "CARRY IN"), (9, "RESET"), (10, "UP/DOWN"), (15, "CLK")] +
            Array(zip(CD4516.presetPins, (0...3).map { "P\($0)" })),
        outputs: Array(zip(CD4516.outputPins, (0...3).map { "Q\($0)" })) + [(7, "CARRY OUT")]
    )
    private var count: Int?
    private let clock = ClockEdgeDetector()

    func powerDidFail() {
        count = nil
        clock.reset()
    }

    func evaluate() {
        let edge = clock.update(pins[15]!.state)
        let reset = pins[9]!.state
        let preset = pins[1]!.state
        if reset == .high {
            count = 0
        } else if reset != .low {
            count = nil
        } else if preset == .high {
            var value = 0
            var valid = true
            for (bit, number) in Self.presetPins.enumerated() {
                switch pins[number]!.state {
                case .high: value |= 1 << bit
                case .low: break
                default: valid = false
                }
            }
            count = valid ? value : nil
        } else if preset != .low {
            count = nil
        } else if edge == .rising {
            switch (pins[5]!.state, pins[10]!.state) {
            case (.high, _): break
            case (.low, .high): count = count.map { ($0 + 1) & 15 }
            case (.low, .low): count = count.map { ($0 + 15) & 15 }
            default: count = nil
            }
        }
        for (bit, number) in Self.outputPins.enumerated() {
            pins[number]!.drive(count.map { $0 & (1 << bit) == 0 ? .low : .high } ?? .undefined)
        }
        let carry: LogicState
        if pins[5]!.state == .high {
            carry = .high
        } else if let count, pins[5]!.state == .low {
            switch pins[10]!.state {
            case .high: carry = count == 15 ? .low : .high
            case .low: carry = count == 0 ? .low : .high
            default: carry = (1...14).contains(count) ? .high : .undefined
            }
        } else {
            carry = .undefined
        }
        pins[7]!.drive(carry)
    }
}

enum DualCounterKind: String, CaseIterable {
    case bcd = "CD4518"
    case binary = "CD4520"
    var modulus: Int { self == .bcd ? 10 : 16 }
}

final class DualCounter: PoweredChip {
    let kind: DualCounterKind
    let supplyPins = (vdd: 16, vss: 8)
    let pins: [Int: Pin]
    private var sequences: [CounterSequence]

    init(_ kind: DualCounterKind) {
        self.kind = kind
        sequences = [CounterSequence(modulus: kind.modulus), CounterSequence(modulus: kind.modulus)]
        pins = counterPins(
            inputs: [(1, "CLK A"), (2, "ENABLE A"), (7, "RESET A"),
                     (9, "CLK B"), (10, "ENABLE B"), (15, "RESET B")],
            outputs: (0..<2).flatMap { unit in
                (0..<4).map { (3 + unit * 8 + $0, "Q\($0 + 1)") }
            }
        )
    }

    func powerDidFail() {
        for index in sequences.indices { sequences[index].invalidate() }
    }

    func evaluate() {
        for unit in sequences.indices {
            let offset = unit * 8
            // CLOCK OR NOT ENABLE counts on CLK rising with EN high, or EN falling with CLK low.
            let effectiveClock = and(pins[1 + offset]!.state.inverted, pins[2 + offset]!.state).inverted
            sequences[unit].update(clock: effectiveClock, reset: pins[7 + offset]!.state)
            for bit in 0..<4 { pins[3 + offset + bit]!.drive(sequences[unit].bit(bit)) }
        }
    }
}

enum CounterChip: String, CaseIterable, Codable {
    case cd4017 = "CD4017"
    case cd4026 = "CD4026"
    case cd4516 = "CD4516"

    var detail: String {
        switch self {
        case .cd4017: "Decade Counter · Ten Decoded Outputs"
        case .cd4026: "Decade Counter · Seven-Segment Driver"
        case .cd4516: "Presettable Binary Up/Down Counter"
        }
    }

    func makeComponent() -> any PoweredChip {
        switch self {
        case .cd4017: CD4017()
        case .cd4026: CD4026()
        case .cd4516: CD4516()
        }
    }

    static func kind(of component: any LogicComponent) -> Self? {
        switch component {
        case is CD4017: .cd4017
        case is CD4026: .cd4026
        case is CD4516: .cd4516
        default: nil
        }
    }
}
