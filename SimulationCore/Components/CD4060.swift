final class CD4060: LogicComponent {
    private static let outputStages = [
        1: 12, 2: 13, 3: 14, 4: 6, 5: 5,
        6: 7, 7: 4, 13: 9, 14: 8, 15: 10
    ]

    let pins: [Int: Pin]
    private let clock: Pin
    private let reset: Pin
    private let dividerOutputs: [(pin: Pin, bit: Int)]
    private var lastClock: LogicState?
    private var lastDriveObservations: [ObjectIdentifier: ClockDriveObservation] = [:]
    private static let countMask = 0x3FFF

    enum Candidates {
        case single(Int)
        case interval(ClosedRange<Int>)
        // Two or more sorted, nonadjacent inclusive ranges.
        case ranges([ClosedRange<Int>])
        case unknown

        private static func contiguous(_ range: ClosedRange<Int>) -> Self {
            if range.lowerBound == range.upperBound { return .single(range.lowerBound) }
            if range == 0...CD4060.countMask { return .unknown }
            return .interval(range)
        }

        mutating func transition(falling: Bool, mayReset: Bool) {
            switch self {
            case .unknown:
                // Advancing all counts permutes them, and zero is already present.
                return
            case .single(let count):
                let next = falling ? (count + 1) & CD4060.countMask : count
                self = mayReset && next != 0 ? Self.includingZero(in: next...next) : .single(next)
            case .interval(let range):
                if !falling {
                    if mayReset && range.lowerBound != 0 { self = Self.includingZero(in: range) }
                } else if range.upperBound == CD4060.countMask {
                    // The old upper endpoint becomes zero. The rest shifts up.
                    self = Self.includingZero(in: (range.lowerBound + 1)...CD4060.countMask)
                } else {
                    let shifted = (range.lowerBound + 1)...(range.upperBound + 1)
                    self = mayReset ? Self.includingZero(in: shifted) : .interval(shifted)
                }
            case .ranges(let ranges):
                if !falling && (!mayReset || ranges[0].lowerBound == 0) { return }
                let increment = falling ? 1 : 0
                let wraps = falling && ranges.last!.upperBound == CD4060.countMask
                var result = RangeBuilder(expectedCount: ranges.count + 1)
                if mayReset || wraps { result.append(0...0) }
                for range in ranges {
                    let lower = range.lowerBound + increment
                    if lower > CD4060.countMask { break }
                    result.append(lower...min(range.upperBound + increment, CD4060.countMask))
                }
                self = result.finish()
            }
        }

        private static func includingZero(in range: ClosedRange<Int>) -> Self {
            if range.lowerBound <= 1 { return contiguous(0...range.upperBound) }
            return .ranges([0...0, range])
        }

        func union(_ other: Self) -> Self {
            if case .unknown = self { return .unknown }
            if case .unknown = other { return .unknown }
            if case .single(let a) = self, case .single(let b) = other, a == b {
                return self
            }

            let leftCount = rangeCount
            let rightCount = other.rangeCount
            if leftCount == 1 && rightCount == 1 {
                let left = self[0]
                let right = other[0]
                let (first, second) = left.lowerBound <= right.lowerBound ? (left, right) : (right, left)
                if first.upperBound + 1 >= second.lowerBound {
                    return Self.contiguous(first.lowerBound...max(first.upperBound, second.upperBound))
                }
                return .ranges([first, second])
            }

            var result = RangeBuilder(expectedCount: max(leftCount, rightCount))
            var left = 0
            var right = 0
            while left < leftCount && right < rightCount {
                let a = self[left]
                let b = other[right]
                if a.lowerBound <= b.lowerBound {
                    result.append(a)
                    left += 1
                } else {
                    result.append(b)
                    right += 1
                }
            }
            while left < leftCount {
                result.append(self[left])
                left += 1
            }
            while right < rightCount {
                result.append(other[right])
                right += 1
            }
            return result.finish()
        }

        // Keep the open range inline. Allocate only when a gap is confirmed.
        private struct RangeBuilder {
            let expectedCount: Int
            private var finished: [ClosedRange<Int>] = []
            private var pending: ClosedRange<Int>?

            init(expectedCount: Int) {
                self.expectedCount = expectedCount
            }

            mutating func append(_ range: ClosedRange<Int>) {
                if let previous = pending {
                    if previous.upperBound + 1 >= range.lowerBound {
                        pending = previous.lowerBound...max(previous.upperBound, range.upperBound)
                        return
                    }
                    if finished.isEmpty { finished.reserveCapacity(expectedCount) }
                    finished.append(previous)
                }
                pending = range
            }

            mutating func finish() -> Candidates {
                let last = pending!
                if finished.isEmpty { return Candidates.contiguous(last) }
                finished.append(last)
                return .ranges(finished)
            }
        }

        var rangeCount: Int {
            if case .ranges(let ranges) = self { return ranges.count }
            return 1
        }

        subscript(index: Int) -> ClosedRange<Int> {
            switch self {
            case .single(let count): return count...count
            case .interval(let range): return range
            case .ranges(let ranges): return ranges[index]
            case .unknown: return 0...CD4060.countMask
            }
        }

        private static func bits(in range: ClosedRange<Int>) -> (high: Int, ambiguous: Int) {
            // Every bit up to the highest differing endpoint bit varies.
            let different = range.lowerBound ^ range.upperBound
            let width = Int.bitWidth - different.leadingZeroBitCount
            let varying = (1 << width) - 1
            return (range.lowerBound & ~varying, varying)
        }

        var outputBits: (high: Int, ambiguous: Int) {
            switch self {
            case .single(let count):
                return (count, 0)
            case .interval(let range):
                return Self.bits(in: range)
            case .unknown:
                return (0, CD4060.countMask)
            case .ranges(let ranges):
                var allHigh = CD4060.countMask
                var anyHigh = 0
                for range in ranges {
                    let (high, ambiguous) = Self.bits(in: range)
                    allHigh &= high
                    anyHigh |= high | ambiguous
                }
                return (allHigh, allHigh ^ anyHigh)
            }
        }
    }

    // A definite sample uses one bucket. An X/Z sample stores LOW in
    // candidates and HIGH in highCandidates. Before the first sample,
    // candidates contains counts whose clock has not been initialized.
    private(set) var candidates = Candidates.unknown
    private(set) var highCandidates: Candidates?

    init() {
        var pinMap = [
            8: Pin(number: 8, name: "VSS", direction: .power),
            9: Pin(number: 9, name: "OSC 9", direction: .output),
            10: Pin(number: 10, name: "OSC 10", direction: .output),
            11: Pin(number: 11, name: "CLK", direction: .input),
            12: Pin(number: 12, name: "RESET", direction: .input),
            16: Pin(number: 16, name: "VDD", direction: .power)
        ]
        dividerOutputs = Self.outputStages.map { number, stage in
            let pin = Pin(number: number, name: "Q\(stage)", direction: .output)
            pinMap[number] = pin
            return (pin: pin, bit: 1 << (stage - 1))
        }
        pins = pinMap
        clock = pinMap[11]!
        reset = pinMap[12]!
        clock.tracksClockProvenance = true
    }

    func powerDidFail() {
        candidates = .unknown
        highCandidates = nil
        lastClock = nil
        lastDriveObservations = [:]
    }

    func evaluate() {
        let level = clock.state
        let resetLevel = reset.state
        let uncertain = level == .undefined || level == .highImpedance

        if uncertain {
            if level != lastClock || lastDriveObservations != clock.clockDriveObservations {
                sampleUncertain(resetLevel: resetLevel)
                lastClock = level
                lastDriveObservations = clock.clockDriveObservations
            } else {
                // A control-only update must retain both previous levels.
                Self.applyReset(resetLevel, falling: false, to: &candidates)
                if highCandidates != nil {
                    Self.applyReset(resetLevel, falling: false, to: &highCandidates!)
                }
            }
        } else if let high = highCandidates {
            if level == .low {
                var advanced = high
                advanced.transition(falling: true, mayReset: false)
                candidates = candidates.union(advanced)
            } else {
                candidates = candidates.union(high)
            }
            Self.applyReset(resetLevel, falling: false, to: &candidates)
            highCandidates = nil
            lastDriveObservations = [:]
            lastClock = level
        } else {
            Self.applyReset(resetLevel, falling: lastClock == .high && level == .low, to: &candidates)
            lastClock = level
        }

        var (high, ambiguous) = candidates.outputBits
        if let highCandidates {
            let other = highCandidates.outputBits
            ambiguous |= other.ambiguous | (high ^ other.high)
            high &= other.high
        }
        for (pin, bit) in dividerOutputs {
            let state: LogicState = ambiguous & bit != 0 ? .undefined : high & bit == 0 ? .low : .high
            pin.drive(state)
        }
    }

    private func sampleUncertain(resetLevel: LogicState) {
        if resetLevel == .high {
            candidates = .single(0)
            highCandidates = .single(0)
            return
        }

        var nextHigh = candidates
        if let high = highCandidates {
            // A HIGH sample holds both buckets. A LOW sample advances
            // only the counts whose previous level was HIGH.
            nextHigh = candidates.union(high)
            var advanced = high
            advanced.transition(falling: true, mayReset: false)
            candidates = candidates.union(advanced)
        } else if lastClock == .high {
            candidates.transition(falling: true, mayReset: false)
        }
        Self.applyReset(resetLevel, falling: false, to: &candidates)
        Self.applyReset(resetLevel, falling: false, to: &nextHigh)
        highCandidates = nextHigh
    }

    private static func applyReset(_ level: LogicState, falling: Bool, to counts: inout Candidates) {
        switch level {
        case .high:
            counts = .single(0)
        case .low:
            if falling { counts.transition(falling: true, mayReset: false) }
        case .undefined, .highImpedance:
            counts.transition(falling: falling, mayReset: true)
        }
    }
}
