/// TI SN74LS90N / SN74LS92N / SN74LS93N (PDIP-14), SDLS940A, pp. 1–4, 8–10.
final class SN74LSCounter: PoweredChip {
    let kind: CounterChip
    let supplyPins = (vdd: 5, vss: 10)
    let pins: [Int: Pin]

    private let resetPins: (Int, Int)
    private let outputsB: [Int]
    private let sequenceB: [Int]
    private let edgeA = ClockEdgeDetector()
    private let edgeB = ClockEdgeDetector()
    private var countA: Int?
    private var countB: Int?

    init(_ kind: CounterChip) {
        self.kind = kind
        switch kind {
        case .ls90:
            resetPins = (2, 3)
            outputsB = [9, 8, 11]
            sequenceB = [0, 1, 2, 3, 4]
        case .ls92:
            resetPins = (6, 7)
            outputsB = [11, 9, 8]
            sequenceB = [0, 1, 2, 4, 5, 6]
        case .ls93:
            resetPins = (2, 3)
            outputsB = [9, 8, 11]
            sequenceB = Array(0..<8)
        default:
            preconditionFailure("An SN74LS counter designation is required")
        }

        let inputs = [(1, "CKB"), (14, "CKA"), (resetPins.0, "R0(1)"), (resetPins.1, "R0(2)")]
            + (kind == .ls90 ? [(6, "R9(1)"), (7, "R9(2)")] : [])
        let outputs = [(12, "QA")] + Array(zip(outputsB, ["QB", "QC", "QD"]))
        var pins = [
            5: Pin(number: 5, name: "VCC", direction: .power),
            10: Pin(number: 10, name: "GND", direction: .power)
        ]
        for (number, name) in inputs { pins[number] = Pin(number: number, name: name, direction: .input) }
        for (number, name) in outputs { pins[number] = Pin(number: number, name: name, direction: .output) }
        for number in 1...14 where pins[number] == nil {
            pins[number] = Pin(number: number, name: "NC", direction: .noConnect)
        }
        self.pins = pins
    }

    func powerDidFail() {
        countA = nil
        countB = nil
        edgeA.reset()
        edgeB.reset()
    }

    func evaluate() {
        // Sample both clocks even during asynchronous control, so release
        // cannot replay an edge that occurred while the control was asserted.
        let transitionA = edgeA.update(pins[14]!.state)
        let transitionB = edgeB.update(pins[1]!.state)
        let reset = asserted(resetPins.0, resetPins.1)
        let preset = kind == .ls90 ? asserted(6, 7) : .low

        if preset == .high {
            countA = 1
            countB = 4
        } else if preset == .low && reset == .high {
            countA = 0
            countB = 0
        } else if preset == .low && reset == .low {
            if transitionA == .falling, let countA { self.countA = 1 - countA }
            if transitionB == .falling, let countB { self.countB = (countB + 1) % sequenceB.count }
        } else {
            countA = nil
            countB = nil
        }

        pins[12]!.drive(bit(countA, at: 0))
        let patternB = countB.map { sequenceB[$0] }
        for (index, number) in outputsB.enumerated() {
            pins[number]!.drive(bit(patternB, at: index))
        }
    }

    private func asserted(_ first: Int, _ second: Int) -> LogicState {
        // Net.receiveDC already applies the SN74LS guaranteed thresholds.
        let a = pins[first]!.state
        let b = pins[second]!.state
        if a == .low || b == .low { return .low }
        return a == .high && b == .high ? .high : .undefined
    }

    private func bit(_ pattern: Int?, at index: Int) -> LogicState {
        guard let pattern else { return .undefined }
        return pattern & (1 << index) == 0 ? .low : .high
    }
}
