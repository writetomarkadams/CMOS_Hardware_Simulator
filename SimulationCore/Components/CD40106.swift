final class CD40106: LogicComponent {
    static let gatePins = [(1, 2), (3, 4), (5, 6), (9, 8), (11, 10), (13, 12)]
    let pins: [Int: Pin]

    init() {
        var pinMap = [
            7: Pin(number: 7, name: "VSS", direction: .power),
            14: Pin(number: 14, name: "VDD", direction: .power)
        ]
        for (index, pair) in Self.gatePins.enumerated() {
            let (input, output) = pair
            pinMap[input] = Pin(number: input, name: "A\(index + 1)", direction: .input)
            pinMap[output] = Pin(number: output, name: "Q\(index + 1)", direction: .output)
        }
        pins = pinMap
    }

    func evaluate() {
        for (input, output) in Self.gatePins {
            pins[output]!.drive(pins[input]!.state.inverted)
        }
    }
}
