final class Diode1N4148: LogicComponent {
    let pins = [
        1: Pin(number: 1, name: "K", direction: .bidirectional, isWeakDriver: true),
        2: Pin(number: 2, name: "A", direction: .bidirectional, isWeakDriver: true)
    ]

    func evaluate() {
        let cathode = pins[1]!
        let anode = pins[2]!
        // Forward conduction can source HIGH at K or sink LOW at A.
        cathode.drive(anode.strongState == .high ? .high : .highImpedance)
        anode.drive(cathode.strongState == .low ? .low : .highImpedance)
    }
}
