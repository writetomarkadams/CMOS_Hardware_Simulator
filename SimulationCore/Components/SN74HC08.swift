/// Texas Instruments SN74HC08N (PDIP-14), SCLS081J, sections 4, 5.3 and 7.4.
final class SN74HC08: QuadLogicChip {
    static let operatingSupplyRange = 2.0...6.0

    static func terminals(_ gate: QuadGate) -> (inputA: Int, inputB: Int, output: Int) {
        switch gate {
        case .a: (1, 2, 3)
        case .b: (4, 5, 6)
        case .c: (9, 10, 8)
        case .d: (12, 13, 11)
        }
    }

    init() {
        super.init(kind: .and, pinout: Self.terminals, ground: "GND", supply: "VCC", channelNumberFirst: true)
    }

    override func inputState(_ pin: Pin) -> LogicState {
        HCInput.standard.state(of: pin)
    }
}
