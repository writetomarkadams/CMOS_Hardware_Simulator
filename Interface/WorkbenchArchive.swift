import SwiftUI
import UniformTypeIdentifiers

struct WorkbenchArchive: Codable, FileDocument {
    private enum Component: Codable {
        case unit(MultiUnitChip, package: Int, unit: Int)
        case counter, divider, display, transistor, diode, led, pullUp, clock
        case driver(SevenSegmentDriverKind)
        case resistance(Double, ResistanceUnit)
        case power(PowerRail)
        case switchInput(showsValue: Bool, isOn: Bool)

        init(_ part: WorkbenchPart) throws {
            if let placement = part.unitPlacement {
                self = .unit(placement.kind, package: placement.packageID, unit: placement.unit.id)
                return
            }
            switch part.component {
            case is CD4510: self = .counter
            case is CD4060: self = .divider
            case is MAN74A: self = .display
            case is NPN2N3904: self = .transistor
            case is Diode1N4148: self = .diode
            case is WorkbenchLED: self = .led
            case is WorkbenchPullUp: self = .pullUp
            case is WorkbenchClock: self = .clock
            case let driver as SevenSegmentDriver: self = .driver(driver.kind)
            case let resistor as Resistor: self = .resistance(resistor.value, resistor.unit)
            case let source as WorkbenchPower: self = .power(source.rail)
            case let source as WorkbenchSwitch: self = .switchInput(showsValue: source.showsValue, isOn: source.isOn)
            default: throw ArchiveError.unsupportedComponent
            }
        }
    }

    private struct Part: Codable {
        let id: Int
        let name: String
        let chipNumber: Int?
        let component: Component
        let position: CGPoint?
        let rotation: Int?
        let frequency: ClockFrequency?
        let colour: LEDIndicatorSymbol.LampColour?
    }

    struct Circuit {
        var parts: [WorkbenchPart] = []
        var wires: [WorkbenchWire] = []
        var positions: [Int: CGPoint] = [:]
        var rotations: [Int: Int] = [:]
        var frequencies: [Int: ClockFrequency] = [:]
        var colours: [Int: LEDIndicatorSymbol.LampColour] = [:]
        var nextChipNumber = 1
    }

    private enum ArchiveError: LocalizedError {
        case unsupportedVersion, unsupportedComponent, invalidCircuit

        var errorDescription: String? {
            switch self {
            case .unsupportedVersion: "This Workbench file uses an unsupported version."
            case .unsupportedComponent: "This circuit contains a component that cannot be saved."
            case .invalidCircuit: "This Workbench file contains invalid components or connections."
            }
        }
    }

    static var readableContentTypes: [UTType] { [.json] }
    private let version: Int
    private let powerMode: PowerMode?
    var savedPowerMode: PowerMode { powerMode ?? .explicit }
    private let parts: [Part]
    let wires: [WorkbenchWire]
    let junctions: [Int: CGPoint]

    init(bench: Workbench) throws {
        version = 2
        powerMode = bench.powerMode
        wires = bench.wires
        junctions = bench.junctions
        parts = try bench.parts.map { part in
            Part(id: part.id, name: part.name, chipNumber: part.chipNumber,
                 component: try Component(part), position: bench.positions[part.id],
                 rotation: bench.rotations[part.id], frequency: bench.clockFrequencies[part.id],
                 colour: bench.ledColours[part.id])
        }
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else { throw ArchiveError.invalidCircuit }
        self = try JSONDecoder().decode(Self.self, from: data)
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return FileWrapper(regularFileWithContents: try encoder.encode(self))
    }

    func makeCircuit() throws -> Circuit {
        guard (1...2).contains(version) else { throw ArchiveError.unsupportedVersion }
        var circuit = Circuit()
        var packages: [Int: (kind: MultiUnitChip, chip: any LogicComponent, units: Set<Int>)] = [:]
        var seenParts: [Int: WorkbenchPart] = [:]
        var chipNumbers: Set<Int> = []
        func validID(_ id: Int) -> Bool { (1..<Int.max - 2).contains(id) }
        func validPoint(_ point: CGPoint) -> Bool {
            point.x.isFinite && point.y.isFinite && abs(point.x) <= 10_000_000 && abs(point.y) <= 10_000_000
        }

        for part in parts {
            guard validID(part.id), seenParts[part.id] == nil,
                  part.position.map(validPoint) ?? true,
                  part.rotation.map({ (0...3).contains($0) }) ?? true else { throw ArchiveError.invalidCircuit }
            let component: any LogicComponent
            var placement: ChipUnitPlacement?
            switch part.component {
            case .unit(let kind, let packageID, let unitID):
                guard part.chipNumber == nil, validID(packageID),
                      let unit = kind.allUnits.first(where: { $0.id == unitID }) else { throw ArchiveError.invalidCircuit }
                if packages[packageID] == nil {
                    guard chipNumbers.insert(packageID).inserted else { throw ArchiveError.invalidCircuit }
                    packages[packageID] = (kind, kind.makeComponent(), [])
                }
                guard var package = packages[packageID], package.kind == kind,
                      package.units.insert(unitID).inserted else { throw ArchiveError.invalidCircuit }
                packages[packageID] = package
                component = package.chip
                placement = ChipUnitPlacement(kind: kind, packageID: packageID, unit: unit)
            case .counter: component = CD4510()
            case .divider: component = CD4060()
            case .display: component = MAN74A()
            case .driver(let kind): component = SevenSegmentDriver(kind)
            case .transistor: component = NPN2N3904()
            case .diode: component = Diode1N4148()
            case .led: component = WorkbenchLED()
            case .pullUp: component = WorkbenchPullUp()
            case .clock: component = WorkbenchClock()
            case .power(let rail): component = WorkbenchPower(rail)
            case .resistance(let value, let unit):
                guard value > 0, (value * unit.multiplier).isFinite else { throw ArchiveError.invalidCircuit }
                let resistor = Resistor()
                resistor.setResistance(value, unit: unit)
                component = resistor
            case .switchInput(let showsValue, let isOn):
                let source = WorkbenchSwitch(showsValue: showsValue)
                if isOn { source.toggle() }
                component = source
            }
            if let number = part.chipNumber {
                guard validID(number), chipNumbers.insert(number).inserted else { throw ArchiveError.invalidCircuit }
            }
            if let frequency = part.frequency {
                guard component is WorkbenchClock, frequency.hertz.isFinite, frequency.hertz > 0,
                      0.5 / frequency.hertz < Double(Int64.max) else { throw ArchiveError.invalidCircuit }
            }
            if part.colour != nil && !(component is WorkbenchLED) { throw ArchiveError.invalidCircuit }
            let restored = WorkbenchPart(id: part.id, name: part.name, component: component,
                                         unitPlacement: placement, chipNumber: part.chipNumber)
            seenParts[part.id] = restored
            circuit.parts.append(restored)
            circuit.positions[part.id] = part.position
            circuit.rotations[part.id] = part.rotation
            circuit.frequencies[part.id] = part.frequency
            circuit.colours[part.id] = part.colour
        }

        circuit.wires = wires
        if version == 1 {
            // Older files wired supplies on logic units. Move those endpoints to one shared power unit.
            var migrated: [Int: Int] = [:]
            for part in Array(circuit.parts) {
                guard let placement = part.unitPlacement,
                      let chip = part.component as? any PoweredChip else { continue }
                let supplyNumbers = [chip.supplyPins.vdd, chip.supplyPins.vss]
                let hasSupplyWires = wires.contains { wire in
                    [wire.first, wire.second].contains { $0.partID == part.id && supplyNumbers.contains($0.pinNumber) }
                }
                guard hasSupplyWires else { continue }
                let powerID: Int
                if let existing = migrated[placement.packageID] {
                    powerID = existing
                } else {
                    powerID = (circuit.parts.map(\.id).max() ?? 0) + 1
                    let power = WorkbenchPart(id: powerID, name: part.name, component: part.component,
                                             unitPlacement: ChipUnitPlacement(kind: placement.kind, packageID: placement.packageID,
                                                                              unit: placement.kind.powerUnit), chipNumber: nil)
                    circuit.parts.append(power)
                    seenParts[powerID] = power
                    let origin = circuit.positions[part.id] ?? .zero
                    circuit.positions[powerID] = CGPoint(x: origin.x + 200, y: origin.y)
                    migrated[placement.packageID] = powerID
                }
                func migrate(_ endpoint: WorkbenchTerminal) -> WorkbenchTerminal {
                    endpoint.partID == part.id && supplyNumbers.contains(endpoint.pinNumber)
                        ? WorkbenchTerminal(partID: powerID, pinNumber: endpoint.pinNumber) : endpoint
                }
                circuit.wires = circuit.wires.map {
                    WorkbenchWire(id: $0.id, first: migrate($0.first), second: migrate($0.second), bends: $0.bends)
                }
            }
        }

        guard junctions.allSatisfy({ validID($0.key) && validPoint($0.value) }) else { throw ArchiveError.invalidCircuit }
        func validEndpoint(_ endpoint: WorkbenchTerminal) -> Bool {
            endpoint.isJunction ? junctions[endpoint.pinNumber] != nil
                : seenParts[endpoint.partID]?.pins[endpoint.pinNumber] != nil
        }
        var wireIDs: Set<Int> = []
        for wire in circuit.wires {
            guard validID(wire.id), wireIDs.insert(wire.id).inserted,
                  wire.first != wire.second, validEndpoint(wire.first), validEndpoint(wire.second),
                  wire.bends.allSatisfy(validPoint) else { throw ArchiveError.invalidCircuit }
        }
        circuit.nextChipNumber = (chipNumbers.max() ?? 0) + 1
        return circuit
    }
}
