enum AnalogSwitchKind: String, CaseIterable, Codable {
    case cd4051 = "CD4051"
    case cd4052 = "CD4052"
    case cd4053 = "CD4053"

    var detail: String {
        switch self {
        case .cd4051: "Single 8-Channel Bidirectional Switch"
        case .cd4052: "Dual 4-Channel Bidirectional Switch · Shared Select"
        case .cd4053: "Triple 2-Channel Bidirectional Switch · Independent Select"
        }
    }
}

// TI SCHS047, tables 4-1 through 4-3 and 7-1.
final class AnalogSwitch: PoweredChip, SwitchedConnectivity {
    private struct Bank {
        let name: String
        let common: Int
        let channels: [Int]
        let selectors: [Int] // Least significant first.
    }

    let kind: AnalogSwitchKind
    let pins: [Int: Pin]
    private let banks: [Bank]
    var supplyPins: (vdd: Int, vss: Int) { (16, 8) }
    var additionalGroundPins: [Int] { [7] }

    init(_ kind: AnalogSwitchKind) {
        self.kind = kind
        switch kind {
        case .cd4051:
            banks = [Bank(name: "", common: 3, channels: [13, 14, 15, 12, 1, 5, 2, 4], selectors: [11, 10, 9])]
        case .cd4052:
            banks = [Bank(name: "X", common: 13, channels: [12, 14, 15, 11], selectors: [10, 9]),
                     Bank(name: "Y", common: 3, channels: [1, 5, 2, 4], selectors: [10, 9])]
        case .cd4053:
            banks = [Bank(name: "A", common: 14, channels: [12, 13], selectors: [11]),
                     Bank(name: "B", common: 15, channels: [2, 1], selectors: [10]),
                     Bank(name: "C", common: 4, channels: [5, 3], selectors: [9])]
        }

        var pins = [
            6: Pin(number: 6, name: "INH", direction: .input),
            7: Pin(number: 7, name: "VEE", direction: .power),
            8: Pin(number: 8, name: "VSS", direction: .power),
            16: Pin(number: 16, name: "VDD", direction: .power)
        ]
        let selectors = Set(banks.flatMap(\.selectors)).sorted(by: >)
        for (number, name) in zip(selectors, ["A", "B", "C"]) {
            pins[number] = Pin(number: number, name: name, direction: .input)
        }
        for bank in banks {
            let commonName = bank.name.isEmpty ? "COM" : "\(bank.name) COM"
            pins[bank.common] = Pin(number: bank.common, name: commonName, direction: .bidirectional)
            for (index, number) in bank.channels.enumerated() {
                let channel = kind == .cd4053 ? ["X", "Y"][index] : String(index)
                pins[number] = Pin(number: number, name: bank.name + channel, direction: .bidirectional)
            }
        }
        self.pins = pins
    }

    func evaluate() {}

    var closedConnections: [(Pin, Pin)] {
        // A floating or indeterminate control cannot establish a definite path.
        guard pins[6]!.state == .low else { return [] }
        return banks.compactMap { bank in
            var index = 0
            for (bit, selector) in bank.selectors.enumerated() {
                switch pins[selector]!.state {
                case .high: index |= 1 << bit
                case .low: break
                case .highImpedance, .undefined: return nil
                }
            }
            return (pins[bank.common]!, pins[bank.channels[index]]!)
        }
    }
}
