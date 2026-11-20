import Observation

enum ResistanceUnit: String, CaseIterable, Identifiable, Codable {
    case ohms = "Ω"
    case kilohms = "kΩ"
    case megohms = "MΩ"

    var id: Self { self }

    var multiplier: Double {
        switch self {
        case .ohms: 1
        case .kilohms: 1_000
        case .megohms: 1_000_000
        }
    }
}

@Observable
final class Resistor: LogicComponent, Identifiable {
    let pins = [
        1: Pin(number: 1, name: "1", direction: .bidirectional, isWeakDriver: true),
        2: Pin(number: 2, name: "2", direction: .bidirectional, isWeakDriver: true)
    ]
    private(set) var value: Double = 470
    private(set) var unit: ResistanceUnit = .ohms

    func setResistance(_ value: Double, unit: ResistanceUnit) {
        let ohms = value * unit.multiplier
        guard ohms.isFinite, ohms > 0 else { return }
        self.value = value
        self.unit = unit
    }

    var isTimingElement = false

    func evaluate() {
        if isTimingElement {
            pins[1]!.drive(.highImpedance)
            pins[2]!.drive(.highImpedance)
            return
        }
        // Sample direct drivers only so the resistor cannot feed its own weak output back.
        pins[1]!.drive(pins[2]!.strongState)
        pins[2]!.drive(pins[1]!.strongState)
    }
}
