/// The designation selects a package pinout, schematic symbol, and simulator model.
enum TransistorDesignation: String, CaseIterable, Codable, Identifiable {
    case twoN3904 = "2N3904"
    case bc547B = "BC547B"
    case twoN3906 = "2N3906"

    static let defaultDevice = Self.twoN3904
    var id: Self { self }

    var definition: TransistorDefinition {
        switch self {
        case .twoN3904:
            // onsemi 2N3904/D, TO-92 case 135AN, flat face forward and leads down.
            // https://www.onsemi.com/download/data-sheet/pdf/2n3904-d.pdf
            TransistorDefinition(package: .to92, leads: [.emitter, .base, .collector],
                                 symbol: .npn2N3904,
                                 model: .groundedNPN(.init(baseKnee: 0.68, baseResistanceKilohms: 0.05,
                                                          gain: 100, saturationResistanceKilohms: 0.02)))
        case .bc547B:
            // onsemi BC547BG, TO-92 case 29 style 17. See PROJECT_STATUS.md for the DC fit.
            TransistorDefinition(package: .to92, leads: [.collector, .base, .emitter],
                                 symbol: .bc547,
                                 model: .groundedNPN(.init(baseKnee: 0.675, baseResistanceKilohms: 0.05,
                                                          gain: 290, saturationResistanceKilohms: 0.005)))
        case .twoN3906:
            // onsemi 2N3906/D, TO-92 case 29 style 1, straight leads.
            TransistorDefinition(package: .to92, leads: [.emitter, .base, .collector],
                                 symbol: .pnp2N3906, model: .digitalHighSidePNP)
        }
    }
}

struct TransistorDefinition {
    enum Package: Equatable { case to92 }

    enum Terminal: String, Equatable {
        case emitter = "E", base = "B", collector = "C"
    }

    enum Symbol: Equatable { case npn2N3904, bc547, pnp2N3906 }

    struct NPNParameters {
        let baseKnee: Double
        let baseResistanceKilohms: Double
        let gain: Double
        let saturationResistanceKilohms: Double
    }

    enum Model {
        case groundedNPN(NPNParameters)
        case digitalHighSidePNP
    }

    let package: Package
    // Physical pin numbers start at 1 and follow the front-facing lead order.
    let leads: [Terminal]
    let symbol: Symbol
    let model: Model

    func preservesConnections(of other: Self) -> Bool {
        package == other.package && leads == other.leads && symbol == other.symbol
    }
}

final class Transistor: LogicComponent {
    let designation: TransistorDesignation
    let pins: [Int: Pin]
    var definition: TransistorDefinition { designation.definition }

    init(_ designation: TransistorDesignation = .defaultDevice) {
        self.designation = designation
        pins = Dictionary(uniqueKeysWithValues: designation.definition.leads.enumerated().map { index, terminal in
            let number = index + 1
            return (number, Pin(number: number, name: terminal.rawValue,
                                direction: terminal == .collector ? .output : .input))
        })
    }

    func pin(_ terminal: TransistorDefinition.Terminal) -> Pin {
        pins[definition.leads.firstIndex(of: terminal)! + 1]!
    }

    func evaluate() {
        let collector: LogicState
        switch definition.model {
        case .groundedNPN:
            switch (pin(.base).state, pin(.emitter).state) {
            case (.low, _): collector = .highImpedance
            case (.high, .low): collector = .low
            default: collector = .undefined
            }
        case .digitalHighSidePNP:
            // With the emitter HIGH, a LOW base represents forward E–B bias.
            switch (pin(.base).state, pin(.emitter).state) {
            case (.high, .high): collector = .highImpedance
            case (.low, .high): collector = .high
            default: collector = .undefined
            }
        }
        pin(.collector).drive(collector)
    }
}
