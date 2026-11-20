import Observation

enum CapacitorKind: String, Codable, CaseIterable {
    case polarized = "C_Polarized"
    case small = "C_Small"
    var unit: String { self == .polarized ? "µF" : "nF" }
    var multiplier: Double { self == .polarized ? 1e-6 : 1e-9 }
}

@Observable
final class Capacitor: LogicComponent, Identifiable {
    let kind: CapacitorKind
    let pins: [Int: Pin]
    private(set) var value: Double
    var farads: Double { value * kind.multiplier }
    // Only recognised NE555 timing networks integrate this ideal capacitor voltage.
    @ObservationIgnored var voltage: Double = 0

    init(_ kind: CapacitorKind) {
        self.kind = kind
        value = kind == .polarized ? 10 : 100
        pins = [1: Pin(number: 1, name: kind == .polarized ? "+" : "1", direction: .input),
                2: Pin(number: 2, name: kind == .polarized ? "−" : "2", direction: .input)]
    }

    static func isValid(_ value: Double, kind: CapacitorKind) -> Bool {
        let farads = value * kind.multiplier
        return farads.isFinite && farads > 0
    }

    func setCapacitance(_ value: Double) {
        guard Self.isValid(value, kind: kind) else { return }
        self.value = value
    }

    func evaluate() {} // A capacitor is never a DC logic driver.
}
