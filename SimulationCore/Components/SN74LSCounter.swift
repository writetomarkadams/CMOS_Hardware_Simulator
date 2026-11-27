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
    private struct Count: Hashable {
        let a: Int
        let bIndex: Int
    }

    private let possibleCounts: Set<Count>
    private var candidates: Set<Count>

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

        let possibleCounts = Set(sequenceB.indices.flatMap { index in
            [Count(a: 0, bIndex: index), Count(a: 1, bIndex: index)]
        })
        self.possibleCounts = possibleCounts
        candidates = possibleCounts

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
        candidates = possibleCounts
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

        // Include each feasible control outcome as a whole package state.
        // A definite preset excludes both reset and normal counting.
        var next: Set<Count> = []
        if preset != .low { next.insert(Count(a: 1, bIndex: 4)) }
        if preset != .high && reset != .low { next.insert(Count(a: 0, bIndex: 0)) }
        if preset != .high && reset != .high {
            if transitionA == .falling || transitionB == .falling {
                next.formUnion(candidates.map { count in
                    Count(
                        a: transitionA == .falling ? 1 - count.a : count.a,
                        bIndex: transitionB == .falling ? (count.bIndex + 1) % sequenceB.count : count.bIndex
                    )
                })
            } else {
                next.formUnion(candidates)
            }
        }
        candidates = next

        var allHigh = 0b1111
        var anyHigh = 0
        for count in candidates {
            let word = (sequenceB[count.bIndex] << 1) | count.a
            allHigh &= word
            anyHigh |= word
        }
        for (index, pin) in ([12] + outputsB).enumerated() {
            let mask = 1 << index
            let state: LogicState = allHigh & mask != 0 ? .high : anyHigh & mask == 0 ? .low : .undefined
            pins[pin]!.drive(state)
        }
    }

    private func asserted(_ first: Int, _ second: Int) -> LogicState {
        // Net.receiveDC already applies the SN74LS guaranteed thresholds.
        let a = pins[first]!.state
        let b = pins[second]!.state
        if a == .low || b == .low { return .low }
        return a == .high && b == .high ? .high : .undefined
    }
}
