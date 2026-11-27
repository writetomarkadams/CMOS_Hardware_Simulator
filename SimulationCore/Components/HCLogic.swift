// See PROJECT_STATUS.md for the TI part revisions and fixed-5 V model limits.
enum HCInput {
    case standard, schmitt

    func state(of pin: Pin) -> LogicState {
        guard let voltage = pin.dcVoltage else { return pin.state }
        // Interpolate the 4.5 V and 6 V limits for the simulator's fixed supply.
        // The Schmitt model uses the outer limits and has no history in between.
        let low = self == .standard ? 1.5 : 1.0
        let high = self == .standard ? 3.5 : 3.13 + (4.2 - 3.13) / 3
        if voltage <= low { return .low }
        if voltage >= high { return .high }
        return .undefined
    }
}

enum HCGatePackage: String, Codable {
    case hc00 = "74HC00"
    case hc02 = "74HC02"
    case hc04 = "74HC04"
    case hc14 = "74HC14"
    case hc32 = "74HC32"
    case hc86 = "74HC86"

    var quadKind: QuadLogicKind? {
        switch self {
        case .hc00: .nand
        case .hc02: .nor
        case .hc32: .or
        case .hc86: .xor
        case .hc04, .hc14: nil
        }
    }

    func quadTerminals(_ gate: QuadGate) -> (inputA: Int, inputB: Int, output: Int) {
        guard self == .hc02 else { return SN74HC08.terminals(gate) }
        switch gate {
        case .a: return (2, 3, 1)
        case .b: return (5, 6, 4)
        case .c: return (8, 9, 10)
        case .d: return (11, 12, 13)
        }
    }

    static let inverterTerminals: [(input: Int, output: Int)] = [(1, 2), (3, 4), (5, 6), (9, 8), (11, 10), (13, 12)]

    func makeComponent() -> any HCGateChip {
        if let quadKind { return HCQuadGateChip(package: self, kind: quadKind) }
        return HCHexInverter(package: self)
    }
}

protocol HCGateChip: PoweredChip {
    var package: HCGatePackage { get }
}

private final class HCQuadGateChip: QuadLogicChip, HCGateChip {
    let package: HCGatePackage

    init(package: HCGatePackage, kind: QuadLogicKind) {
        self.package = package
        super.init(kind: kind, pinout: package.quadTerminals, ground: "GND", supply: "VCC", channelNumberFirst: true)
    }

    override func inputState(_ pin: Pin) -> LogicState { HCInput.standard.state(of: pin) }
}

private final class HCHexInverter: HCGateChip {
    let package: HCGatePackage
    let pins: [Int: Pin]
    var supplyPins: (vdd: Int, vss: Int) { (14, 7) }

    init(package: HCGatePackage) {
        self.package = package
        var pinMap = [
            7: Pin(number: 7, name: "GND", direction: .power),
            14: Pin(number: 14, name: "VCC", direction: .power)
        ]
        for (index, gate) in HCGatePackage.inverterTerminals.enumerated() {
            pinMap[gate.input] = Pin(number: gate.input, name: "\(index + 1)A", direction: .input)
            pinMap[gate.output] = Pin(number: gate.output, name: "\(index + 1)Y", direction: .output)
        }
        pins = pinMap
    }

    func evaluate() {
        let inputMode: HCInput = package == .hc14 ? .schmitt : .standard
        for gate in HCGatePackage.inverterTerminals {
            pins[gate.output]!.drive(inputMode.state(of: pins[gate.input]!).inverted)
        }
    }
}
