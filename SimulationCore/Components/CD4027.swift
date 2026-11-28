final class CD4027: LogicComponent {
    private enum OutputPair: Hashable {
        case reset
        case set
        case bothHigh

        static let unknown: [Self] = [.reset, .set]

        init(high: Bool) {
            self = high ? .set : .reset
        }
    }

    private struct Unit {
        let q: Pin
        let complement: Pin
        let clock: Pin
        let reset: Pin
        let k: Pin
        let j: Pin
        let set: Pin
        var history = CorrelatedClockHistory(initialStates: OutputPair.unknown)
        private var lastClock: LogicState?
        private var lastDriveObservations: [ObjectIdentifier: ClockDriveObservation] = [:]
        private var ordinal: UInt64 = 0
        private var lastSet: LogicState?
        private var lastReset: LogicState?

        init(_ numbers: [Int]) {
            q = Pin(number: numbers[0], name: "Q", direction: .output)
            complement = Pin(number: numbers[1], name: "Q̅", direction: .output)
            clock = Pin(number: numbers[2], name: "CLK", direction: .input)
            clock.tracksClockProvenance = true
            reset = Pin(number: numbers[3], name: "RESET", direction: .input)
            k = Pin(number: numbers[4], name: "K", direction: .input)
            j = Pin(number: numbers[5], name: "J", direction: .input)
            set = Pin(number: numbers[6], name: "SET", direction: .input)
        }

        var pins: [Pin] { [q, complement, clock, reset, k, j, set] }

        mutating func powerDidFail() {
            history.invalidateClock(resetTo: OutputPair.unknown)
            lastClock = nil
            lastDriveObservations = [:]
            lastSet = nil
            lastReset = nil
        }

        mutating func evaluate() {
            let setLevel = set.state
            let resetLevel = reset.state
            let controlsChanged = lastSet != setLevel || lastReset != resetLevel
            let clockChanged = lastClock != clock.state || lastDriveObservations != clock.clockDriveObservations
            if clockChanged {
                ordinal += 1
                let sample = ResolvedClockSample(id: ClockSampleID(ordinal: ordinal), level: clock.state)
                update(set: setLevel, reset: resetLevel, sample: sample)
                lastClock = clock.state
                lastDriveObservations = clock.clockDriveObservations
            } else if controlsChanged {
                update(set: setLevel, reset: resetLevel, sample: nil)
            }
            lastSet = setLevel
            lastReset = resetLevel

            if let pair = history.unanimousState {
                q.drive(pair == .reset ? .low : .high)
                complement.drive(pair == .set ? .low : .high)
                return
            }
            let pairs = history.possibleStates
            let bothHigh = pairs.contains(.bothHigh)
            q.drive(PresettableCounterState.consensus(
                low: pairs.contains(.reset), high: pairs.contains(.set) || bothHigh
            ))
            complement.drive(PresettableCounterState.consensus(
                low: pairs.contains(.set), high: pairs.contains(.reset) || bothHigh
            ))
        }

        private mutating func update(set: LogicState, reset: LogicState, sample: ResolvedClockSample?) {
            let jLevel = j.state
            let kLevel = k.state.inverted
            let forced: OutputPair?
            switch (set, reset) {
            case (.high, .high): forced = .bothHigh
            case (.high, .low): forced = .set
            case (.low, .high): forced = .reset
            default: forced = nil
            }

            // A possible simultaneous release allows either normal state.
            // Preserve the existing policy even when release coincides with a rise.
            let unforced = set != .high && reset != .high
            let releasing = unforced && (history.unanimousState.map { $0 == .bothHigh }
                ?? history.possibleStates.contains(.bothHigh))
            let normal = set == .low && reset == .low
            let definiteData = (jLevel == .low || jLevel == .high) && (kLevel == .low || kLevel == .high)

            if let sample {
                if let forced {
                    history.consume(sample) { _, _ in CollectionOfOne(forced) }
                    return
                }
                if normal && !releasing && definiteData {
                    history.consume(sample) { prior, event in
                        let input = prior == .reset ? jLevel : kLevel
                        return CollectionOfOne(event == .rising ? OutputPair(high: input == .high) : prior)
                    }
                    return
                }
            } else if let forced {
                history.updateStates { _ in CollectionOfOne(forced) }
                return
            } else if normal && !releasing {
                return
            }

            let setOptions = PresettableCounterState.possibilities(set)
            let resetOptions = PresettableCounterState.possibilities(reset)
            func successors(_ prior: OutputPair, _ event: ClockSampleTransition) -> [OutputPair] {
                var next: [OutputPair] = []
                for setHigh in setOptions {
                    for resetHigh in resetOptions {
                        switch (setHigh, resetHigh) {
                        case (true, true): next.append(.bothHigh)
                        case (true, false): next.append(.set)
                        case (false, true): next.append(.reset)
                        case (false, false):
                            if releasing {
                                next.append(contentsOf: OutputPair.unknown)
                            } else if event == .rising {
                                let input = prior == .reset ? jLevel : kLevel
                                next.append(contentsOf: PresettableCounterState.possibilities(input).map(OutputPair.init(high:)))
                            } else {
                                next.append(prior)
                            }
                        }
                    }
                }
                return next
            }

            if let sample {
                history.consume(sample, applying: successors)
            } else {
                history.updateStates { successors($0, .hold) }
            }
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
            units[index].powerDidFail()
        }
    }

    func evaluate() {
        for index in units.indices {
            units[index].evaluate()
        }
    }
}
