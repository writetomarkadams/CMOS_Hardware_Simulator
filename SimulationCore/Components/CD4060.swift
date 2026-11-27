final class CD4060: LogicComponent {
    private static let outputStages = [
        1: 12, 2: 13, 3: 14, 4: 6, 5: 5,
        6: 7, 7: 4, 13: 9, 14: 8, 15: 10
    ]

    let pins: [Int: Pin]
    private let clock = ClockEdgeDetector()
    private static let countMask = 0x3FFF

    private enum Candidates {
        case single(Int)
        // Sorted, nonadjacent inclusive ranges. A full range is stored as .unknown.
        case ranges([ClosedRange<Int>])
        case unknown

        mutating func transition(falling: Bool, mayReset: Bool) {
            switch self {
            case .unknown:
                // Advancing all counts permutes them, and zero is already present.
                return
            case .single(let count):
                let next = falling ? (count + 1) & CD4060.countMask : count
                if !mayReset || next == 0 {
                    self = .single(next)
                } else if next == 1 {
                    self = .ranges([0...1])
                } else {
                    self = .ranges([0...0, next...next])
                }
            case .ranges(let ranges):
                if !falling && (!mayReset || ranges[0].lowerBound == 0) { return }
                let increment = falling ? 1 : 0
                let wraps = falling && ranges.last!.upperBound == CD4060.countMask
                var next: [ClosedRange<Int>] = []
                next.reserveCapacity(ranges.count + 1)
                if mayReset || wraps { next.append(0...0) }
                for range in ranges {
                    let lower = range.lowerBound + increment
                    if lower > CD4060.countMask { break }
                    let upper = min(range.upperBound + increment, CD4060.countMask)
                    if let previous = next.last, previous.upperBound + 1 >= lower {
                        next[next.count - 1] = previous.lowerBound...upper
                    } else {
                        next.append(lower...upper)
                    }
                }
                self = next.count == 1 && next[0] == 0...CD4060.countMask
                    ? .unknown : .ranges(next)
            }
        }

        var outputBits: (high: Int, ambiguous: Int) {
            switch self {
            case .single(let count):
                return (count, 0)
            case .unknown:
                return (0, CD4060.countMask)
            case .ranges(let ranges):
                var allHigh = CD4060.countMask
                var anyHigh = 0
                for range in ranges {
                    // A contiguous range changes every bit through the highest
                    // bit where its endpoints differ. Higher bits stay fixed.
                    let different = range.lowerBound ^ range.upperBound
                    let width = Int.bitWidth - different.leadingZeroBitCount
                    let varying = (1 << width) - 1
                    allHigh &= range.lowerBound & ~varying
                    anyHigh |= range.lowerBound | varying
                }
                return (allHigh, allHigh ^ anyHigh)
            }
        }
    }

    private var candidates = Candidates.unknown

    init() {
        var pinMap = [
            8: Pin(number: 8, name: "VSS", direction: .power),
            9: Pin(number: 9, name: "OSC 9", direction: .output),
            10: Pin(number: 10, name: "OSC 10", direction: .output),
            11: Pin(number: 11, name: "CLK", direction: .input),
            12: Pin(number: 12, name: "RESET", direction: .input),
            16: Pin(number: 16, name: "VDD", direction: .power)
        ]
        for (number, stage) in Self.outputStages {
            pinMap[number] = Pin(number: number, name: "Q\(stage)", direction: .output)
        }
        pins = pinMap
    }

    func powerDidFail() {
        candidates = .unknown
        clock.reset()
    }

    func evaluate() {
        let falling = clock.update(pins[11]!.state) == .falling
        switch pins[12]!.state {
        case .high:
            candidates = .single(0)
        case .low:
            if falling { candidates.transition(falling: true, mayReset: false) }
        case .highImpedance, .undefined:
            candidates.transition(falling: falling, mayReset: true)
        }

        let (high, ambiguous) = candidates.outputBits
        for (number, stage) in Self.outputStages {
            let bit = 1 << (stage - 1)
            let state: LogicState = ambiguous & bit != 0 ? .undefined : high & bit == 0 ? .low : .high
            pins[number]!.drive(state)
        }
    }
}
