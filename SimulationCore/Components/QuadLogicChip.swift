enum QuadGate: Int, CaseIterable {
    case a = 1, b, c, d

    var terminals: (inputA: Int, inputB: Int, output: Int) {
        switch self {
        case .a: (1, 2, 3)
        case .b: (5, 6, 4)
        case .c: (8, 9, 10)
        case .d: (12, 13, 11)
        }
    }
}

enum QuadLogicKind {
    case and, nand, or, nor, xor
}

class QuadLogicChip: LogicComponent {
    let pins: [Int: Pin]
    private let kind: QuadLogicKind
    private let pinout: (QuadGate) -> (inputA: Int, inputB: Int, output: Int)

    init(kind: QuadLogicKind, pinout: @escaping (QuadGate) -> (inputA: Int, inputB: Int, output: Int) = { $0.terminals },
         ground: String? = nil, supply: String = "VDD", channelNumberFirst: Bool = false) {
        self.kind = kind
        self.pinout = pinout
        var pinMap = [
            7: Pin(number: 7, name: ground ?? (kind == .xor ? "GND" : "VSS"), direction: .power),
            14: Pin(number: 14, name: supply, direction: .power)
        ]
        for gate in QuadGate.allCases {
            let (inputA, inputB, output) = pinout(gate)
            func label(_ letter: String) -> String {
                channelNumberFirst ? "\(gate.rawValue)\(letter)" : "\(letter)\(gate.rawValue)"
            }
            pinMap[inputA] = Pin(number: inputA, name: label("A"), direction: .input)
            pinMap[inputB] = Pin(number: inputB, name: label("B"), direction: .input)
            pinMap[output] = Pin(number: output, name: label(channelNumberFirst ? "Y" : "Q"), direction: .output)
        }
        pins = pinMap
    }

    func inputState(_ pin: Pin) -> LogicState { pin.state }

    func evaluate() {
        for gate in QuadGate.allCases {
            let (inputA, inputB, output) = pinout(gate)
            let a = inputState(pins[inputA]!)
            let b = inputState(pins[inputB]!)
            let result: LogicState

            if kind == .xor {
                result = if (a == .high || a == .low) && (b == .high || b == .low) {
                    a == b ? .low : .high
                } else {
                    .undefined
                }
            } else if kind == .or || kind == .nor {
                if a == .high || b == .high {
                    result = .high
                } else if a == .low && b == .low {
                    result = .low
                } else {
                    result = .undefined
                }
            } else if a == .low || b == .low {
                result = kind == .nand ? .high : .low
            } else if a == .high && b == .high {
                result = kind == .nand ? .low : .high
            } else {
                result = .undefined
            }

            pins[output]!.drive(kind == .nor ? result.inverted : result)
        }
    }
}
