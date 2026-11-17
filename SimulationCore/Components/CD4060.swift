final class CD4060: LogicComponent {
    private static let outputStages = [
        1: 12, 2: 13, 3: 14, 4: 6, 5: 5,
        6: 7, 7: 4, 13: 9, 14: 8, 15: 10
    ]

    let pins: [Int: Pin]
    private let clock = ClockEdgeDetector()
    private var count: Int?

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

    func evaluate() {
        let edge = clock.update(pins[11]!.state)
        switch pins[12]!.state {
        case .high:
            count = 0
        case .low:
            if edge == .falling, let count {
                self.count = (count + 1) & 0x3FFF
            }
        case .highImpedance, .undefined:
            count = nil
        }

        for (number, stage) in Self.outputStages {
            let state: LogicState
            if let count {
                state = (count & (1 << (stage - 1))) == 0 ? .low : .high
            } else {
                state = .undefined
            }
            pins[number]!.drive(state)
        }
    }
}
