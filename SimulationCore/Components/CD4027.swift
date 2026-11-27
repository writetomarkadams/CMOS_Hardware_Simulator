final class CD4027: LogicComponent {
    private enum OutputPair: Hashable {
        case reset
        case set
        case bothHigh

        static let unknown: Set<Self> = [.reset, .set]
    }

    private struct Unit {
        let q: Pin
        let complement: Pin
        let clock: Pin
        let reset: Pin
        let k: Pin
        let j: Pin
        let set: Pin
        let edgeDetector = ClockEdgeDetector()
        var candidates = OutputPair.unknown

        init(_ numbers: [Int]) {
            q = Pin(number: numbers[0], name: "Q", direction: .output)
            complement = Pin(number: numbers[1], name: "Q̅", direction: .output)
            clock = Pin(number: numbers[2], name: "CLK", direction: .input)
            reset = Pin(number: numbers[3], name: "RESET", direction: .input)
            k = Pin(number: numbers[4], name: "K", direction: .input)
            j = Pin(number: numbers[5], name: "J", direction: .input)
            set = Pin(number: numbers[6], name: "SET", direction: .input)
        }

        var pins: [Pin] { [q, complement, clock, reset, k, j, set] }

        mutating func evaluate() {
            let rising = edgeDetector.update(clock.state) == .rising
            var next: Set<OutputPair> = []
            for setHigh in PresettableCounterState.possibilities(set.state) {
                for resetHigh in PresettableCounterState.possibilities(reset.state) {
                    switch (setHigh, resetHigh) {
                    case (true, true): next.insert(.bothHigh)
                    case (true, false): next.insert(.set)
                    case (false, true): next.insert(.reset)
                    case (false, false): next.formUnion(unforcedCandidates(rising: rising))
                    }
                }
            }

            candidates = next
            let bothHigh = next.contains(.bothHigh)
            q.drive(PresettableCounterState.consensus(
                low: next.contains(.reset), high: next.contains(.set) || bothHigh
            ))
            complement.drive(PresettableCounterState.consensus(
                low: next.contains(.set), high: next.contains(.reset) || bothHigh
            ))
        }

        private func unforcedCandidates(rising: Bool) -> Set<OutputPair> {
            // Releasing both controls can land in either normal state. Leave
            // clock ordering during this release unresolved, even on a rising sample.
            if candidates.contains(.bothHigh) { return OutputPair.unknown }
            guard rising else { return candidates }

            var next: Set<OutputPair> = []
            for prior in candidates {
                // With Q LOW only J matters. With Q HIGH only K matters.
                let activeInput = prior == .reset ? j.state : k.state.inverted
                for high in PresettableCounterState.possibilities(activeInput) {
                    next.insert(high ? .set : .reset)
                }
            }
            return next
        }
    }

    private var units = [Unit([1, 2, 3, 4, 5, 6, 7]), Unit([15, 14, 13, 12, 11, 10, 9])]
    let pins: [Int: Pin]

    init() {
        let powerPins = [
            Pin(number: 8, name: "VSS", direction: .power),
            Pin(number: 16, name: "VDD", direction: .power)
        ]
        pins = Dictionary(uniqueKeysWithValues: (units.flatMap(\.pins) + powerPins).map { ($0.number, $0) })
    }

    func powerDidFail() {
        for index in units.indices {
            units[index].candidates = OutputPair.unknown
            units[index].edgeDetector.reset()
        }
    }

    func evaluate() {
        for index in units.indices {
            units[index].evaluate()
        }
    }
}
