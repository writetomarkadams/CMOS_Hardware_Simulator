final class LED3mm: LogicComponent {
    static let footprint = "LED_THT:LED_D3.0mm"
    static let forwardVoltage = 1.8
    static let dynamicResistanceKilohms = 0.02

    let pins = [
        1: Pin(number: 1, name: "K", direction: .bidirectional),
        2: Pin(number: 2, name: "A", direction: .bidirectional)
    ]

    func evaluate() {}
}
