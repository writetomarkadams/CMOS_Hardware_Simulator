final class CD4027: LogicComponent {
    private struct Unit {
        let q: Pin
        let complement: Pin
        let clock: Pin
        let reset: Pin
        let k: Pin
        let j: Pin
        let set: Pin
        let edgeDetector = ClockEdgeDetector()
        var state: LogicState = .undefined

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
            let edge = edgeDetector.update(clock.state)
            switch (set.state, reset.state) {
            case (.high, .high):
                state = .undefined
                q.drive(.high)
                complement.drive(.high)
                return
            case (.high, .low):
                state = .high
            case (.low, .high):
                state = .low
            case (.low, .low):
                if edge == .rising {
                    switch (j.state, k.state, state) {
                    case (.high, .low, _): state = .high
                    case (.low, .high, _): state = .low
                    case (_, _, .low): state = j.state == .highImpedance ? .undefined : j.state
                    case (_, _, .high): state = k.state.inverted
                    default: state = .undefined
                    }
                }
            default:
                state = .undefined
            }

            q.drive(state)
            complement.drive(state.inverted)
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
            units[index].state = .undefined
            units[index].edgeDetector.reset()
        }
    }

    func evaluate() {
        for index in units.indices {
            units[index].evaluate()
        }
    }
}
