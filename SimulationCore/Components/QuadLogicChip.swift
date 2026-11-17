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

    var pinNumbers: [Int] {
        [terminals.inputA, terminals.inputB, terminals.output].sorted()
    }
}

enum QuadLogicKind {
    case and, nand
}

class QuadLogicChip: LogicComponent {
    let pins: [Int: Pin]
    private let kind: QuadLogicKind

    init(kind: QuadLogicKind) {
        self.kind = kind
        var pinMap = [
            7: Pin(number: 7, name: "VSS", direction: .power),
            14: Pin(number: 14, name: "VDD", direction: .power)
        ]
        for gate in QuadGate.allCases {
            let (inputA, inputB, output) = gate.terminals
            pinMap[inputA] = Pin(number: inputA, name: "A\(gate.rawValue)", direction: .input)
            pinMap[inputB] = Pin(number: inputB, name: "B\(gate.rawValue)", direction: .input)
            pinMap[output] = Pin(number: output, name: "Q\(gate.rawValue)", direction: .output)
        }
        pins = pinMap
    }

    func evaluate() {
        for gate in QuadGate.allCases {
            let (inputA, inputB, output) = gate.terminals
            let a = pins[inputA]!.state
            let b = pins[inputB]!.state
            let result: LogicState

            if a == .low || b == .low {
                result = kind == .nand ? .high : .low
            } else if a == .high && b == .high {
                result = kind == .nand ? .low : .high
            } else {
                result = .undefined
            }

            pins[output]!.drive(result)
        }
    }
}
