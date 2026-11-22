import Foundation

struct CircuitImportPreview {
    struct Entry: Identifiable {
        let part: ImportedCircuit.Part
        let model: String?
        var id: String { part.reference }
    }

    let entries: [Entry]
    let nets: [ImportedCircuit.Net]
    let warnings: [String]
    private let schematic: KiCadSchematic?
    fileprivate let mappings: [Mapping]
    fileprivate let routedNets: [RoutedNet]

    var canImport: Bool { !mappings.isEmpty }
    var supportedCount: Int { mappings.count }

    fileprivate struct Mapping {
        let reference: String
        let model: Model
    }

    fileprivate struct Model {
        let name: String
        var units: MultiUnitChip? = nil
        let make: () -> any LogicComponent
    }

    fileprivate struct RoutedNet {
        let name: String
        let terminals: [ImportedCircuit.Terminal]
        let rail: PowerRail?
    }

    static func read(_ text: String, filenameExtension: String) throws -> Self {
        if filenameExtension.lowercased() == "kicad_sch" {
            let schematic = try KiCadSchematicParser.parse(text)
            return Self(schematic.circuit, schematic: schematic)
        }
        return Self(try KiCadNetlistParser.parse(text))
    }

    init(_ circuit: ImportedCircuit, schematic: KiCadSchematic? = nil) {
        self.schematic = schematic
        let instances = Dictionary(grouping: schematic?.instances ?? [], by: \.reference)
        let singletonPins = Set(circuit.nets.filter { $0.terminals.count == 1 }.flatMap(\.terminals))
        let countsByName = Dictionary(grouping: circuit.nets, by: \.name).mapValues(\.count)
        let netsByPin = Dictionary(grouping: circuit.nets.flatMap { net in
            net.terminals.map { (terminal: $0, net: net.name) }
        }, by: { $0.terminal.reference })
        let railsByNet = Dictionary(uniqueKeysWithValues: circuit.nets.map { net in
            (net.id, Set(net.terminals.compactMap { instances[$0.reference]?.first?.rail?.rawValue }))
        })
        let suppliesByPin = circuit.nets.reduce(into: [ImportedCircuit.Terminal: Set<String>]()) { supplies, net in
            for pin in net.terminals { supplies[pin] = railsByNet[net.id, default: []] }
        }
        var entries: [Entry] = []
        var models: [String: any LogicComponent] = [:]
        var ignoredNoConnects: Set<ImportedCircuit.Terminal> = []
        var mappings: [Mapping] = []
        var warnings = schematic?.warnings ?? []

        for part in circuit.parts {
            let connections = netsByPin[part.reference, default: []]
            let model: Model?
            do {
                if let rail = instances[part.reference]?.first?.rail {
                    model = Model(name: rail.rawValue) { WorkbenchPower(rail) }
                } else {
                    model = try Self.model(for: part)
                }
                if model == nil {
                    warnings.append("\(part.reference): unsupported symbol \(part.library):\(part.symbol).")
                }
            } catch {
                warnings.append("\(part.reference): invalid or unsupported value “\(part.value)”.")
                entries.append(Entry(part: part, model: nil))
                continue
            }
            guard let model else {
                entries.append(Entry(part: part, model: nil))
                continue
            }
            let component = model.make()
            if schematic != nil {
                let placements = instances[part.reference, default: []]
                let valid = !placements.isEmpty && placements.allSatisfy { instance in
                    let expected: Set<Int>
                    if let kind = model.units {
                        guard let unit = kind.allUnits.first(where: { $0.id == instance.unit }) else { return false }
                        expected = Set(unit.pinNumbers)
                    } else {
                        guard placements.count == 1, instance.unit == 1 else { return false }
                        expected = Set(component.pins.keys)
                    }
                    return instance.drawing.isValid && expected.isSubset(of: instance.drawing.pins.map(\.id))
                }
                guard valid else {
                    warnings.append("\(part.reference): embedded geometry or unit pin mapping is incompatible with \(model.name). Entire part omitted.")
                    entries.append(Entry(part: part, model: nil))
                    continue
                }
            }
            let availablePins = model.units?.allUnits.flatMap(\.pinNumbers) ?? Array(component.pins.keys)
            let pinNumbers = Set(availablePins.filter { component.pins[$0] != nil }.map { String($0) })
            let noConnectPins: Set<String>
            switch component {
            case is MAN72A: noConnectPins = ["4", "5", "9", "12"]
            case is MAN74A: noConnectPins = ["3", "5", "10", "11"]
            default: noConnectPins = []
            }
            let unsupported = connections.filter { connection in
                let terminal = connection.terminal
                return !pinNumbers.contains(terminal.pin) &&
                    !(noConnectPins.contains(terminal.pin) && singletonPins.contains(terminal) && PowerRail(rawValue: connection.net) == nil)
            }.map(\.terminal.pin).sorted()
            guard unsupported.isEmpty else {
                warnings.append("\(part.reference): unsupported pin map (pins \(unsupported.joined(separator: ", "))). Entire part omitted.")
                entries.append(Entry(part: part, model: nil))
                continue
            }
            ignoredNoConnects.formUnion(connections.map(\.terminal).filter { noConnectPins.contains($0.pin) })
            let missing = pinNumbers.subtracting(connections.map(\.terminal.pin)).sorted()
            if schematic == nil && !missing.isEmpty {
                warnings.append("\(part.reference): pins absent from the export: \(missing.joined(separator: ", ")).")
            }
            if component is MAN74A && schematic != nil {
                for pin in MAN74A.commonPins where suppliesByPin[.init(reference: part.reference, pin: String(pin))] != ["GND"] {
                    warnings.append("\(part.reference) pin \(pin): common cathode needs a ground connection to light the display.")
                }
            }
            if let chip = component as? any PoweredChip {
                let expected = [(chip.supplyPins.vdd, "+5V")] +
                    ([chip.supplyPins.vss] + chip.additionalGroundPins).map { ($0, "GND") }
                for (pin, rail) in expected {
                    let hasSupply = schematic == nil
                        ? connections.contains { $0.terminal.pin == String(pin) && $0.net == rail && countsByName[rail] == 1 }
                        : suppliesByPin[.init(reference: part.reference, pin: String(pin))] == [rail]
                    guard !hasSupply else { continue }
                    warnings.append("\(part.reference) pin \(pin): expected a \(rail) supply. Check this connection before simulating.")
                }
            }
            entries.append(Entry(part: part, model: model.name))
            mappings.append(Mapping(reference: part.reference, model: model))
            models[part.reference] = component
        }

        // KiCad omits global power symbols from the component list. The exact
        // global names below are the only rails the simulator can provide.
        var routedNets: [RoutedNet] = []
        for net in circuit.nets {
            if net.terminals.count == 1, let terminal = net.terminals.first, ignoredNoConnects.contains(terminal) {
                continue
            }
            let terminals = net.terminals.filter { models[$0.reference] != nil }
            if terminals.count != net.terminals.count {
                warnings.append("\(net.name): \(net.terminals.count - terminals.count) endpoint(s) omitted with unsupported parts.")
            }
            guard !terminals.isEmpty else {
                if schematic == nil && net.terminals.isEmpty { warnings.append("\(net.name): net has no endpoints.") }
                continue
            }
            let rail = countsByName[net.name] == 1 ? PowerRail(rawValue: net.name) : nil
            if let rail, schematic == nil {
                warnings.append("\(net.name): import adds a simulator \(rail.rawValue) source.")
            } else if railsByNet[net.id, default: []].count > 1 {
                warnings.append("\(net.name): conflicting +5V and GND supplies.")
            } else if schematic != nil && !railsByNet[net.id, default: []].isEmpty {
                // Explicit source symbols will be placed at their original coordinates.
            } else if terminals.count == 1 {
                warnings.append("\(net.name): unconnected pin \(terminals[0].reference).\(terminals[0].pin).")
            } else if !terminals.contains(where: { endpoint in
                guard let number = Int(endpoint.pin),
                      let pin = models[endpoint.reference]?.pins[number] else { return false }
                return pin.direction == .output || pin.direction == .bidirectional
            }) {
                warnings.append("\(net.name): potentially floating; no modeled output or bidirectional pin.")
            }
            if schematic == nil, rail == nil, PowerRail(rawValue: net.name) != nil {
                warnings.append("\(net.name): name is shared by distinct nets; no supply synthesized.")
            }
            routedNets.append(RoutedNet(name: net.name, terminals: terminals, rail: rail))
        }
        self.entries = entries
        self.nets = circuit.nets
        self.mappings = mappings
        self.routedNets = routedNets
        self.warnings = warnings
    }

    private enum ValueError: Error { case invalid }

    private static func model(for part: ImportedCircuit.Part) throws -> Model? {
        switch (part.library, part.symbol) {

        case ("Device", "R"), ("Device", "R_Small"), ("Device", "R_US"), ("Device", "R_Small_US"):
            guard let ohms = magnitude(part.value, units: ["Ω", "Ω", "ohms", "ohm"], scales: [
                "R": 1, "r": 1, "k": 1e3, "K": 1e3, "M": 1e6, "m": 1e-3,
                "u": 1e-6, "μ": 1e-6, "µ": 1e-6, "G": 1e9
            ]) else { throw ValueError.invalid }
            let unit: ResistanceUnit = ohms >= 1e6 ? .megohms : ohms >= 1e3 ? .kilohms : .ohms
            return Model(name: "R_Small") {
                let resistor = Resistor()
                resistor.setResistance(ohms / unit.multiplier, unit: unit)
                return resistor
            }
        case ("Device", "C"), ("Device", "C_Small"), ("Device", "CP"), ("Device", "CP_Small"),
             ("Device", "C_Polarized"), ("Device", "C_Polarized_Small"):
            let kind: CapacitorKind = ["C", "C_Small"].contains(part.symbol) ? .small : .polarized
            guard let farads = magnitude(part.value, units: ["F", "f"], scales: [
                "p": 1e-12, "n": 1e-9, "u": 1e-6, "µ": 1e-6, "μ": 1e-6, "m": 1e-3
            ]) else { throw ValueError.invalid }
            let value = farads / kind.multiplier
            guard Capacitor.isValid(value, kind: kind) else { throw ValueError.invalid }
            return Model(name: kind.rawValue) {
                let capacitor = Capacitor(kind)
                capacitor.setCapacitance(value)
                return capacitor
            }
        case ("Connector", _), ("Connector_Generic", _):
            guard let kind = PinHeaderKind.allCases.first(where: { $0.footprint == part.footprint }),
                  (part.library == "Connector" && part.symbol == kind.schematicSymbol + "_Pin") ||
                  (part.library == "Connector_Generic" && part.symbol == kind.schematicSymbol) else { return nil }
            return Model(name: kind.name) { PinHeader(kind) }
        case ("4xxx", _):
            if let kind = MultiUnitChip(rawValue: part.symbol) {
                return Model(name: kind.partName, units: kind, make: kind.makeComponent)
            }
            let name = "CD" + part.symbol
            if let kind = AnalogSwitchKind(rawValue: name) { return Model(name: name) { AnalogSwitch(kind) } }
            if let kind = CounterChip(rawValue: name) { return Model(name: name, make: kind.makeComponent) }
            if let kind = SevenSegmentDriverKind(rawValue: name) { return Model(name: name) { SevenSegmentDriver(kind) } }
            switch part.symbol {
            case "4060": return Model(name: name) { CD4060() }
            case "4510": return Model(name: name) { CD4510() }
            default: return nil
            }
        case ("4xxx_IEEE", "4029"):
            let kind = CounterChip.cd4029
            return Model(name: kind.rawValue, make: kind.makeComponent)
        case ("4xxx_IEEE", "4511"):
            return Model(name: "CD4511") { SevenSegmentDriver(.cd4511) }
        case ("Timer", "NE555"), ("Timer", "NE555P"), ("Timer", "NE555D"):
            return Model(name: "NE555") { NE555() }
        case ("Display_Character", "MAN72A"): return Model(name: "MAN72A") { MAN72A() }
        case ("Display_Character", "MAN74A"): return Model(name: "MAN74A") { MAN74A() }
        case ("Transistor_BJT", "2N3904"): return Model(name: "2N3904") { NPN2N3904() }
        case ("Device", "LED") where part.footprint == LED3mm.footprint:
            return Model(name: "LED_D3.0mm") { LED3mm() }
        case ("Diode", "1N4148"): return Model(name: "1N4148") { Diode1N4148() }
        default: return nil
        }
    }

    /// Accept decimal/scientific notation, SI suffixes and marked decimals such as 4k7 or 2n2.
    private static func magnitude(_ value: String, units: [String], scales: [String: Double]) -> Double? {
        var text = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if let unit = units.first(where: { text.hasSuffix($0) }) {
            text = String(text.dropLast(unit.count)).trimmingCharacters(in: .whitespaces)
        }
        let number: Double?
        if let plain = Double(text) {
            number = plain
        } else if let suffix = text.last, let scale = scales[String(suffix)] {
            number = Double(text.dropLast().trimmingCharacters(in: .whitespaces)).map { $0 * scale }
        } else if let marker = text.firstIndex(where: { scales[String($0)] != nil }),
                  let scale = scales[String(text[marker])] {
            let whole = text[..<marker]
            let fraction = text[text.index(after: marker)...]
            guard !whole.isEmpty, !fraction.isEmpty,
                  whole.allSatisfy(\.isASCIIWholeNumber), fraction.allSatisfy(\.isASCIIWholeNumber) else { return nil }
            number = Double("\(whole).\(fraction)").map { $0 * scale }
        } else {
            number = nil
        }
        guard let number, number.isFinite, number > 0 else { return nil }
        return number
    }
}

private extension Character {
    var isASCIIWholeNumber: Bool { isASCII && isNumber }
}

extension CircuitImportPreview {
    struct Placement {
        var parts: [WorkbenchPart] = []
        var positions: [Int: CGPoint] = [:]
        var wires: [WorkbenchWire] = []
        var junctions: [Int: CGPoint] = [:]
        var rotations: [Int: Int] = [:]
        var schematicMarks: [SchematicMark] = []
        var nextPartID: Int
        var nextChipNumber: Int
        var nextWireID: Int
    }

    func place(startingPart: Int, startingChip: Int, startingWire: Int,
               below originY: CGFloat, existingReferences: Set<String>) -> Placement {
        if let schematic {
            return placeSchematic(schematic, startingPart: startingPart, startingChip: startingChip,
                                  startingWire: startingWire, below: originY, existingReferences: existingReferences)
        }
        var placement = Placement(nextPartID: startingPart, nextChipNumber: startingChip, nextWireID: startingWire)
        var terminals: [ImportedCircuit.Terminal: WorkbenchTerminal] = [:]
        var usedReferences = existingReferences

        @discardableResult
        func addPart(_ name: String, _ component: any LogicComponent,
                     unit: ChipUnitPlacement? = nil, chip: Int? = nil, reference: String? = nil) -> WorkbenchPart {
            let id = placement.nextPartID
            placement.nextPartID += 1
            let index = placement.parts.count
            let part = WorkbenchPart(id: id, name: name, component: component, unitPlacement: unit,
                                     chipNumber: chip, importedReference: reference)
            placement.parts.append(part)
            let x = CGFloat(30 + (index % 4) * 330)
            let y = WorkbenchWire.snap(CGPoint(x: 0, y: originY)).y + CGFloat(index / 4) * 480
            placement.positions[id] = CGPoint(x: x, y: y)
            return part
        }

        for mapping in mappings {
            let component = mapping.model.make()
            let kind = mapping.model.units
            let units = kind?.allUnits ?? []
            var reference = mapping.reference
            var suffix = 2
            while !usedReferences.isDisjoint(with: units.isEmpty ? [reference] : units.map({ reference + $0.letter })) {
                reference = "\(mapping.reference) (\(suffix))"
                suffix += 1
            }
            var parts: [WorkbenchPart] = []
            if let kind {
                let package = placement.nextChipNumber
                placement.nextChipNumber += 1
                for unit in units {
                    parts.append(addPart(mapping.model.name, component,
                                         unit: ChipUnitPlacement(kind: kind, packageID: package, unit: unit),
                                         reference: reference))
                }
            } else {
                let numbered = component is any PoweredChip || component is SevenSegmentDisplay
                let chip = numbered ? placement.nextChipNumber : nil
                if numbered { placement.nextChipNumber += 1 }
                parts.append(addPart(mapping.model.name, component, chip: chip, reference: reference))
            }
            for part in parts {
                if let label = part.reference { usedReferences.insert(label) }
                for pin in part.pins.keys {
                    terminals[.init(reference: mapping.reference, pin: String(pin))] =
                        WorkbenchTerminal(partID: part.id, pinNumber: pin)
                }
            }
        }

        for (index, net) in routedNets.enumerated() {
            var endpoints = net.terminals.compactMap { terminals[$0] }
            if let rail = net.rail {
                let source = addPart(rail.rawValue, WorkbenchPower(rail))
                endpoints.append(WorkbenchTerminal(partID: source.id, pinNumber: 1))
            }
            guard endpoints.count >= 2 else { continue }

            func connect(_ first: WorkbenchTerminal, _ second: WorkbenchTerminal, bends: [CGPoint] = []) {
                placement.wires.append(WorkbenchWire(id: placement.nextWireID, first: first, second: second,
                                                     bends: bends, netName: net.name))
                placement.nextWireID += 1
            }
            if endpoints.count == 2 {
                let first = placement.positions[endpoints[0].partID, default: .zero]
                let second = placement.positions[endpoints[1].partID, default: .zero]
                // Terminals on the same card need a bend outside the card.
                let bends = first == second ? [CGPoint(x: first.x + 300, y: first.y + 120)] : []
                connect(endpoints[0], endpoints[1], bends: bends)
            } else {
                let id = placement.nextWireID
                placement.nextWireID += 1
                let origins = endpoints.map { placement.positions[$0.partID, default: .zero] }
                let right = origins.map(\.x).max() ?? 0
                let middle = origins.map(\.y).sorted()[origins.count / 2]
                let point = CGPoint(x: right + 280 + CGFloat(index % 4) * 10,
                                    y: middle + 240 + CGFloat(index % 17) * 10)
                placement.junctions[id] = point
                for endpoint in endpoints { connect(endpoint, .junction(id)) }
            }
        }
        return placement
    }
}

private extension CircuitImportPreview {
    func placeSchematic(_ schematic: KiCadSchematic, startingPart: Int, startingChip: Int, startingWire: Int,
                        below originY: CGFloat, existingReferences: Set<String>) -> Placement {
        typealias Point = KiCadSchematic.Point
        var placement = Placement(nextPartID: startingPart, nextChipNumber: startingChip, nextWireID: startingWire)
        let instances = Dictionary(grouping: schematic.instances, by: \.reference)
        let points = schematic.edges.flatMap { [$0.first, $0.second] } + schematic.instances.map(\.origin) +
            Array(schematic.noConnects) + Array(schematic.labels.keys)
        let minimumX = points.map(\.millimetres.x).min() ?? 0
        let minimumY = points.map(\.millimetres.y).min() ?? 0
        func canvas(_ point: Point) -> CGPoint {
            let mm = point.millimetres
            return WorkbenchWire.snap(CGPoint(x: 120 + (mm.x - minimumX) * SchematicSymbolGeometry.scale,
                                             y: WorkbenchWire.snap(CGPoint(x: 0, y: originY)).y + 100
                                                + (mm.y - minimumY) * SchematicSymbolGeometry.scale))
        }

        var usedReferences = existingReferences
        let activeTerminals = Set(schematic.circuit.nets.flatMap(\.terminals))
        var terminals: [Point: [WorkbenchTerminal]] = [:]
        var markedPins: Set<Point> = []
        for mapping in mappings {
            let component = mapping.model.make()
            let source = instances[mapping.reference, default: []]
            let kind = mapping.model.units
            let units = source.compactMap { instance in kind?.allUnits.first { $0.id == instance.unit } }
            var reference = mapping.reference
            var suffix = 2
            while !usedReferences.isDisjoint(with: units.isEmpty ? [reference] : units.map({ reference + $0.letter })) {
                reference = "\(mapping.reference) (\(suffix))"
                suffix += 1
            }
            let numbered = kind != nil || component is any PoweredChip || component is SevenSegmentDisplay
            let chip = numbered ? placement.nextChipNumber : nil
            if numbered { placement.nextChipNumber += 1 }

            for instance in source {
                let unit = units.first { $0.id == instance.unit }
                let package = kind.flatMap { kind in
                    unit.flatMap { unit in chip.map { ChipUnitPlacement(kind: kind, packageID: $0, unit: unit) } }
                }
                let id = placement.nextPartID
                placement.nextPartID += 1
                var drawing = instance.drawing
                drawing.mirror = instance.mirror
                let available = Set(unit?.pinNumbers ?? Array(component.pins.keys))
                let origin = canvas(instance.origin)
                let turns = (4 - instance.turns) % 4
                var offsets: [Int: CGPoint] = [:]
                for pin in drawing.pins {
                    guard let source = instance.pins[String(pin.id)] else { continue }
                    let endpoint = canvas(source)
                    let delta = CGPoint(x: endpoint.x - origin.x, y: endpoint.y - origin.y)
                    offsets[pin.id] = drawing.localReflection(delta.schematicRotated(-turns), turns: turns)
                }
                drawing.gridPinOffsets = offsets
                drawing.noConnectPins = available.sorted().filter {
                    guard let point = instance.pins[String($0)], schematic.noConnects.contains(point) else { return false }
                    markedPins.insert(point)
                    return true
                }
                let part = WorkbenchPart(id: id, name: mapping.model.name, component: component,
                                         unitPlacement: package, chipNumber: kind == nil ? chip : nil,
                                         importedReference: reference, importedSymbol: drawing)
                placement.parts.append(part)
                usedReferences.insert(part.reference ?? reference)
                placement.positions[id] = origin
                placement.rotations[id] = turns
                for pin in available.sorted() {
                    if activeTerminals.contains(.init(reference: mapping.reference, pin: String(pin))),
                       let point = instance.pins[String(pin)] {
                        terminals[point, default: []].append(.init(partID: id, pinNumber: pin))
                    }
                }
            }
        }

        func addWire(_ first: WorkbenchTerminal, _ second: WorkbenchTerminal, at point: Point, route: WorkbenchWire.SourceRoute, bends: [CGPoint] = []) {
            guard first != second else { return }
            placement.wires.append(WorkbenchWire(id: placement.nextWireID, first: first, second: second,
                                                 bends: bends, netName: schematic.names[point],
                                                 sourceRoute: route))
            placement.nextWireID += 1
        }

        var endpoints: [Point: WorkbenchTerminal] = [:]
        func endpoint(_ point: Point) -> WorkbenchTerminal {
            if let existing = endpoints[point] { return existing }
            let pins = terminals[point, default: []]
            let result: WorkbenchTerminal
            if pins.count == 1, !schematic.junctions.contains(point), let pin = pins.first {
                result = pin
            } else {
                let id = placement.nextWireID
                placement.nextWireID += 1
                result = .junction(id)
                placement.junctions[id] = canvas(point)
                for pin in pins { addWire(pin, result, at: point, route: .pinAttachment) }
            }
            endpoints[point] = result
            return result
        }
        for edge in schematic.edges {
            let first = endpoint(edge.first)
            let second = endpoint(edge.second)
            let start = canvas(edge.first)
            let end = canvas(edge.second)
            let route = start.x == end.x || start.y == end.y
                ? [start, end] : WorkbenchWire.gridRoute(from: start, through: [end])
            let bends = edge.isAlias ? [] : Array(route.dropFirst().dropLast())
            addWire(first, second, at: edge.first, route: edge.isAlias ? .alias : .straight, bends: bends)
        }
        for point in terminals.keys.sorted(by: { ($0.x, $0.y) < ($1.x, $1.y) }) where terminals[point, default: []].count > 1 {
            _ = endpoint(point)
        }
        func ordered(_ points: some Sequence<Point>) -> [Point] {
            points.sorted { ($0.x, $0.y) < ($1.x, $1.y) }
        }
        placement.schematicMarks = ordered(schematic.labels.keys).flatMap { point in
            schematic.labels[point, default: []].map { SchematicMark(kind: .label, position: canvas(point), text: $0) }
        } + ordered(schematic.noConnects.subtracting(markedPins)).map {
            SchematicMark(kind: .noConnect, position: canvas($0))
        } + ordered(schematic.junctions).map {
            SchematicMark(kind: .junction, position: canvas($0))
        }
        return placement
    }
}
