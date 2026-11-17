final class NPN2N3904: LogicComponent {
    let pins = [
        1: Pin(number: 1, name: "E", direction: .input),
        2: Pin(number: 2, name: "B", direction: .input),
        3: Pin(number: 3, name: "C", direction: .output)
    ]

    func evaluate() {
        let emitter = pins[1]!.state
        let base = pins[2]!.state
        let collector: LogicState

        // Digital low-side switch with a grounded emitter.
        switch (base, emitter) {
        case (.low, _): collector = .highImpedance
        case (.high, .low): collector = .low
        default: collector = .undefined
        }
        pins[3]!.drive(collector)
    }
}
