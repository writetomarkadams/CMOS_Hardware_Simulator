import Foundation
import CoreGraphics
import Dispatch
import Observation

struct WorkbenchTerminal: Hashable, Codable {
    let partID: Int
    let pinNumber: Int

    var isJunction: Bool { partID == 0 }

    static func junction(_ id: Int) -> Self { Self(partID: 0, pinNumber: id) }
}

enum MultiUnitChip: String, CaseIterable, Identifiable, Codable {
    case and = "4081"
    case nand = "4011"
    case or = "4071"
    case xor = "4070"
    case jk = "4027"
    case inverter = "40106"
    case dualBCD = "4518"
    case dualBinary = "4520"

    var id: String { rawValue }
    var partName: String { "CD\(rawValue)" }

    var unitName: String {
        switch self {
        case .and: "AND Gate"
        case .nand: "NAND Gate"
        case .or: "OR Gate"
        case .xor: "XOR Gate"
        case .jk: "JK Flip-Flop"
        case .inverter: "Schmitt Inverter"
        case .dualBCD: "Dual BCD Counter"
        case .dualBinary: "Dual Binary Counter"
        }
    }

    func makeComponent() -> any LogicComponent {
        switch self {
        case .and: CD4081()
        case .nand: CD4011()
        case .or: CD4071()
        case .xor: CD4070()
        case .jk: CD4027()
        case .inverter: CD40106()
        case .dualBCD: DualCounter(.bcd)
        case .dualBinary: DualCounter(.binary)
        }
    }

    var powerUnit: ChipUnit {
        let chip = makeComponent() as! any PoweredChip
        return ChipUnit(id: units.count + 1, pinNumbers: [chip.supplyPins.vss, chip.supplyPins.vdd].sorted())
    }

    var allUnits: [ChipUnit] { units + [powerUnit] }

    var units: [ChipUnit] {
        switch self {
        case .and, .nand, .or, .xor: QuadGate.allCases.map { ChipUnit(id: $0.rawValue, pinNumbers: $0.pinNumbers) }
        case .jk, .dualBCD, .dualBinary: [ChipUnit(id: 1, pinNumbers: Array(1...7)), ChipUnit(id: 2, pinNumbers: Array(9...15))]
        case .inverter:
            CD40106.gatePins.enumerated().map { index, pair in
                ChipUnit(id: index + 1, pinNumbers: [pair.0, pair.1].sorted())
            }
        }
    }
}

struct ChipUnit: Identifiable, Equatable {
    let id: Int
    let pinNumbers: [Int]

    var letter: String { String(UnicodeScalar(64 + id)!) }
}

struct ChipUnitPlacement {
    let kind: MultiUnitChip
    let packageID: Int
    let unit: ChipUnit

    var reference: String { "U\(packageID)\(unit.letter)" }
    var isPowerUnit: Bool { unit.id == kind.powerUnit.id }
}

struct WorkbenchPart: Identifiable {
    let id: Int
    let name: String
    let component: any LogicComponent

    let unitPlacement: ChipUnitPlacement?
    let chipNumber: Int?

    let designation: String?
    let importedReference: String?
    let importedSymbol: ImportedSymbol?

    init(id: Int, name: String, component: any LogicComponent, unitPlacement: ChipUnitPlacement?,
         chipNumber: Int?, importedReference: String? = nil, importedSymbol: ImportedSymbol? = nil,
         designation: String? = nil) {
        self.id = id
        self.name = name
        self.component = component
        self.unitPlacement = unitPlacement
        self.chipNumber = chipNumber
        self.designation = designation
        self.importedReference = importedReference
        self.importedSymbol = importedSymbol
    }

    var referenceBase: String? {
        if let designation { return designation }
        if let importedReference { return importedReference }
        if let unitPlacement { return "U\(unitPlacement.packageID)" }
        if let chipNumber { return "U\(chipNumber)" }
        if component is PinHeader { return "J\(id)" }
        if component is Capacitor { return "C\(id)" }
        if component is Resistor { return "R\(id)" }
        if component is Diode1N4148 || component is LED3mm { return "D\(id)" }
        if component is Transistor { return "Q\(id)" }
        return nil
    }

    var reference: String? {
        referenceBase.map { $0 + (unitPlacement?.unit.letter ?? "") }
    }

    var referencePrefix: String {
        let prefix = referenceBase?.prefix(while: { $0.isLetter || $0 == "#" }) ?? ""
        if prefix.contains(where: \.isLetter) { return String(prefix).uppercased() }
        if component is WorkbenchSwitch { return "SW" }
        if component is WorkbenchLED { return "D" }
        if component is WorkbenchClock { return "X" }
        if component is WorkbenchPower { return "#PWR" }
        if component is WorkbenchPullUp { return "R" }
        return "U"
    }

    var label: String {
        let displayName = (component as? Transistor)?.designation.rawValue ?? name
        if let reference { return "\(displayName) \(reference)" }
        return "\(displayName) \(id)"
    }

    var pins: [Int: Pin] {
        guard let unitPlacement else { return component.pins }
        return component.pins.filter {
            unitPlacement.unit.pinNumbers.contains($0.key)
        }
    }
}

struct SchematicMark: Codable {
    enum Kind: String, Codable { case label, noConnect, junction }
    let kind: Kind
    let position: CGPoint
    var text: String? = nil
}

enum WireColour: String, CaseIterable, Codable {
    case black, grey, brown, red, orange, yellow, green, blue, violet

    var title: String { rawValue.capitalized }
}

struct WorkbenchWire: Identifiable, Codable {
    let id: Int
    let first: WorkbenchTerminal
    let second: WorkbenchTerminal
    let bends: [CGPoint]
    let netName: String?
    enum SourceRoute: String, Codable { case straight, alias, pinAttachment }
    let sourceRoute: SourceRoute?
    var colour: WireColour

    init(id: Int, first: WorkbenchTerminal, second: WorkbenchTerminal, bends: [CGPoint], netName: String? = nil,
         sourceRoute: SourceRoute? = nil, colour: WireColour = .green) {
        self.id = id
        self.first = first
        self.second = second
        self.bends = bends
        self.netName = netName
        self.sourceRoute = sourceRoute
        self.colour = colour
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(Int.self, forKey: .id)
        first = try values.decode(WorkbenchTerminal.self, forKey: .first)
        second = try values.decode(WorkbenchTerminal.self, forKey: .second)
        bends = try values.decode([CGPoint].self, forKey: .bends)
        netName = try values.decodeIfPresent(String.self, forKey: .netName)
        sourceRoute = try values.decodeIfPresent(SourceRoute.self, forKey: .sourceRoute)
        colour = try values.decodeIfPresent(WireColour.self, forKey: .colour) ?? .green
    }

    static let gridSpacing: CGFloat = 10

    static func snap(_ point: CGPoint) -> CGPoint {
        CGPoint(x: (point.x / gridSpacing).rounded() * gridSpacing,
                y: (point.y / gridSpacing).rounded() * gridSpacing)
    }

    func route(from start: CGPoint, to end: CGPoint) -> [CGPoint] {
        if sourceRoute == nil, netName != nil, bends.isEmpty,
           abs(start.x - end.x) > 20, abs(start.y - end.y) > 1 {
            let middleX = Self.snap(CGPoint(x: (start.x + end.x) / 2, y: 0)).x
            return Self.gridRoute(from: start, through: [
                CGPoint(x: middleX, y: Self.snap(start).y),
                CGPoint(x: middleX, y: Self.snap(end).y), end
            ])
        }
        if sourceRoute == .straight {
            return Self.orthogonalRoute(from: start, through: bends + [end])
        }
        return Self.gridRoute(from: start, through: bends + [end])
    }

    // Off-grid pins need short leads to the routing grid. Stored waypoints
    // can also be off-grid in older archives or after splitting a source wire.
    static func gridRoute(from start: CGPoint, through waypoints: [CGPoint]) -> [CGPoint] {
        var anchors: [CGPoint] = []
        var previous = start
        for target in waypoints where target != previous {
            let horizontal = previous.y == target.y
            let vertical = previous.x == target.x
            let snappedStart = snap(previous)
            let snappedEnd = snap(target)
            let shortLead = abs(previous.x - target.x) + abs(previous.y - target.y) <= gridSpacing
            if !(horizontal && (previous.y == snappedStart.y || shortLead)),
               !(vertical && (previous.x == snappedStart.x || shortLead)) {
                anchors.append(snappedStart)
                anchors.append(snappedEnd)
            }
            anchors.append(target)
            previous = target
        }
        return orthogonalRoute(from: start, through: anchors)
    }

    func isDrawn(from start: CGPoint, to end: CGPoint) -> Bool {
        sourceRoute != .alias &&
            (sourceRoute != .pinAttachment || hypot(start.x - end.x, start.y - end.y) > 0.001)
    }

    // The points describe geometry only. A bend or crossing never creates an electrical junction.
    static func orthogonalRoute(from start: CGPoint, through waypoints: [CGPoint]) -> [CGPoint] {
        var points = [start]
        for target in waypoints {
            let previous = points[points.count - 1]
            guard target != previous else { continue }
            let dx = target.x - previous.x
            let dy = target.y - previous.y
            if dx != 0, dy != 0 {
                var horizontalFirst = abs(dx) >= abs(dy)
                if points.count >= 2 {
                    let incoming = points[points.count - 2]
                    // Avoid doubling back over the leg into an existing bend.
                    if previous.y == incoming.y, (previous.x - incoming.x) * dx < 0 {
                        horizontalFirst = false
                    } else if previous.x == incoming.x, (previous.y - incoming.y) * dy < 0 {
                        horizontalFirst = true
                    }
                }
                points.append(horizontalFirst ? CGPoint(x: target.x, y: previous.y)
                                              : CGPoint(x: previous.x, y: target.y))
            }
            points.append(target)
        }
        return points
    }
}

@Observable
final class WorkbenchSwitch: LogicComponent {
    let showsValue: Bool
    private(set) var isOn = false
    let pins = [1: Pin(number: 1, name: "OUT", direction: .output)]

    init(showsValue: Bool = false) {
        self.showsValue = showsValue
        pins[1]!.drive(.low)
    }

    func toggle() {
        isOn.toggle()
        pins[1]!.drive(isOn ? .high : .low)
    }

    func evaluate() {}
}

class WorkbenchClock: LogicComponent {
    let pins: [Int: Pin]
    let output: Pin
    private(set) var phase: LogicState = .low

    var defaultFrequency: ClockFrequency { ClockFrequency(value: 1, unit: .hertz) }

    init(outputNumber: Int = 1, inputs: [Pin] = []) {
        output = Pin(number: outputNumber, name: "OUT", direction: .output)
        pins = Dictionary(uniqueKeysWithValues: (inputs + [output]).map { ($0.number, $0) })
        output.drive(.low)
    }

    func advance() {
        phase = phase.inverted
        evaluate()
    }

    func stop() {
        phase = .low
        evaluate()
    }

    func evaluate() { output.drive(phase) }
}

final class CXO_DIP8: WorkbenchClock, PoweredChip {
    let supplyPins = (vdd: 8, vss: 4)
    private let enable = Pin(number: 1, name: "EN", direction: .input)

    init() {
        super.init(outputNumber: 5, inputs: [
            enable, Pin(number: 4, name: "GND", direction: .power),
            Pin(number: 8, name: "VCC", direction: .power)
        ])
    }

    override var defaultFrequency: ClockFrequency { ClockFrequency(value: 1, unit: .megahertz) }

    var isEnabled: Bool { enable.state == .high || enable.state == .highImpedance }

    override func evaluate() {
        output.drive(isEnabled ? phase : enable.state == .low ? .highImpedance : .undefined)
    }
}

enum PowerRail: String, Codable {
    case fiveVolts = "+5V"
    case ground = "GND"

    var level: LogicState { self == .fiveVolts ? .high : .low }
}

final class WorkbenchPower: LogicComponent {
    let rail: PowerRail
    let pins: [Int: Pin]

    init(_ rail: PowerRail) {
        self.rail = rail
        let terminal = Pin(number: 1, name: rail.rawValue, direction: .power)
        terminal.drivenSupplyRail = rail == .fiveVolts ? .fiveVolts : .ground
        terminal.drive(rail.level)
        pins = [1: terminal]
    }

    func evaluate() {}
}

final class WorkbenchPullUp: LogicComponent {
    let pins = [1: Pin(number: 1, name: "OUT", direction: .output, isWeakDriver: true)]

    init() {
        pins[1]!.drive(.high)
    }

    func evaluate() {}
}

final class WorkbenchLED: LogicComponent {
    let pins = [1: Pin(number: 1, name: "IN", direction: .input)]

    func evaluate() {}
}

@Observable
final class Workbench {
    private(set) var parts: [WorkbenchPart] = []
    private(set) var wires: [WorkbenchWire] = []
    private(set) var illuminatedLEDs: Set<Int> = []
    private(set) var readings: [WorkbenchTerminal: LogicState] = [:]
    private(set) var isStable = true
    private(set) var powerMode: PowerMode = .automatic
    private(set) var powerStates: [Int: ChipPowerState] = [:]
    var hoveredTerminal: WorkbenchTerminal?

    func isTerminalConnected(_ terminal: WorkbenchTerminal) -> Bool {
        wires.contains { $0.first == terminal || $0.second == terminal }
    }

    func showsOpenPinMarker(_ terminal: WorkbenchTerminal, explicitNoConnect: Bool = false) -> Bool {
        !explicitNoConnect && !isTerminalConnected(terminal)
    }

    var componentAppearance: ComponentAppearance = .schematic
    private var chosenWireColours: [ComponentAppearance: WireColour] = [:]
    var newWireColour: WireColour {
        get { chosenWireColours[componentAppearance] ?? componentAppearance.defaultWireColour }
        set { chosenWireColours[componentAppearance] = newValue }
    }
    var wiringEnabled = true
    private(set) var selectedTerminal: WorkbenchTerminal?
    private(set) var selectedWireID: Int?
    private(set) var pendingBends: [CGPoint] = []
    private var engine = SimulationEngine()
    let scope = Oscilloscope()
    private(set) var scopeProbes: [Int: ScopeProbe] = [:]
    @ObservationIgnored private var netsByTerminal: [WorkbenchTerminal: Net] = [:]
    @ObservationIgnored private var scopeReaders: [Int: (Bool) -> ScopeValue] = [:]
    @ObservationIgnored private var pulseReaders: [Int: () -> LogicState] = [:]
    private struct RunningClock {
        let source: WorkbenchClock
        let startedAt: Double
        let halfPeriod: Double
        var edgesDelivered = 0.0

        var nextEdge: Double { startedAt + (edgesDelivered + 1) * halfPeriod }
    }

    private let clockOrigin = DispatchTime.now().uptimeNanoseconds
    @ObservationIgnored private let timeSource: (() -> Double)?

    init(timeSource: (() -> Double)? = nil) {
        self.timeSource = timeSource
        let initialRevision = UUID()
        revision = initialRevision
        document = Document(url: nil, savedRevision: initialRevision)
    }
    @ObservationIgnored private var runningClocks: [RunningClock] = []
    private(set) var hasRunningClocks = false
    private(set) var clockIsBehind = false

    private var clockTime: Double {
        timeSource?() ?? (Double(DispatchTime.now().uptimeNanoseconds - clockOrigin) / 1_000_000_000)
    }
    private(set) var servicedTime = 0.0
    private(set) var timingIssues: [Int: String] = [:]
    private var nextPartID = 1
    private var nextChipNumber = 1
    private var nextWireID = 1

    private(set) var schematicMarks: [SchematicMark] = []
    private(set) var junctions: [Int: CGPoint] = [:]
    private(set) var positions: [Int: CGPoint] = [:]
    private(set) var rotations: [Int: Int] = [:]
    private(set) var clockFrequencies: [Int: ClockFrequency] = [:]
    private(set) var ledColours: [Int: LEDIndicatorSymbol.LampColour] = [:]

    // Undo can cross a document boundary. Keep each document's save point and
    // destination with its history so Undo cannot redirect a save to another file.
    @Observable
    fileprivate final class Document {
        var url: URL?
        var savedRevision: UUID

        init(url: URL?, savedRevision: UUID) {
            self.url = url
            self.savedRevision = savedRevision
        }
    }

    @ObservationIgnored private var pendingPlacementID: Int?
    private var revision: UUID
    private var document: Document
    var circuitRevision: UUID { revision }
    var documentURL: URL? { document.url }
    var isDirty: Bool { revision != document.savedRevision }
    var hasCircuit: Bool { !parts.isEmpty || !schematicMarks.isEmpty }

    private func startDocument(at url: URL? = nil, clean: Bool) {
        document = Document(url: url, savedRevision: clean ? revision : UUID())
    }

    func save(to url: URL) throws {
        let data = try WorkbenchArchive(bench: self).encoded()
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        try data.write(to: url, options: .atomic)
        pendingPlacementID = nil
        document.url = url
        document.savedRevision = revision
    }

    private struct Edit {
        let revision: UUID
        let document: Document
        let switches: [(WorkbenchSwitch, Bool)]
        let parts: [WorkbenchPart]
        let powerMode: PowerMode
        let componentAppearance: ComponentAppearance
        let wires: [WorkbenchWire]
        let junctions: [Int: CGPoint]
        let schematicMarks: [SchematicMark]
        let positions: [Int: CGPoint]
        let rotations: [Int: Int]
        let clockFrequencies: [Int: ClockFrequency]
        let ledColours: [Int: LEDIndicatorSymbol.LampColour]
        let resistances: [(Resistor, Double, ResistanceUnit)]
        let capacitances: [(Capacitor, Double)]
        let scopeProbes: [Int: ScopeProbe]
        let nextPartID: Int
        let nextChipNumber: Int
        let nextWireID: Int
    }

    private struct HistoryEntry {
        let edit: Edit
        let presentationOnly: Bool
    }

    private var undoHistory: [HistoryEntry] = []
    private var redoHistory: [HistoryEntry] = []
    var canUndo: Bool { !undoHistory.isEmpty }
    var canRedo: Bool { !redoHistory.isEmpty }

    private var currentEdit: Edit {
        Edit(revision: revision, document: document,
             switches: parts.compactMap { part in
                 guard let source = part.component as? WorkbenchSwitch else { return nil }
                 return (source, source.isOn)
             },
             parts: parts, powerMode: powerMode, componentAppearance: componentAppearance, wires: wires, junctions: junctions, schematicMarks: schematicMarks, positions: positions, rotations: rotations,
             clockFrequencies: clockFrequencies, ledColours: ledColours,
             resistances: parts.compactMap { part in
                 guard let resistor = part.component as? Resistor else { return nil }
                 return (resistor, resistor.value, resistor.unit)
             },
             capacitances: parts.compactMap { part in
                 guard let capacitor = part.component as? Capacitor else { return nil }
                 return (capacitor, capacitor.value)
             },
             scopeProbes: scopeProbes, nextPartID: nextPartID, nextChipNumber: nextChipNumber, nextWireID: nextWireID)
    }

    private func recordEdit(presentationOnly: Bool = false) {
        pendingPlacementID = nil
        undoHistory.append(HistoryEntry(edit: currentEdit, presentationOnly: presentationOnly))
        if undoHistory.count > 100 { undoHistory.removeFirst() }
        redoHistory.removeAll()
        revision = UUID()
    }

    func undo() {
        guard let entry = undoHistory.popLast() else { return }
        redoHistory.append(HistoryEntry(edit: currentEdit, presentationOnly: entry.presentationOnly))
        restoreHistory(entry)
    }

    func redo() {
        guard let entry = redoHistory.popLast() else { return }
        undoHistory.append(HistoryEntry(edit: currentEdit, presentationOnly: entry.presentationOnly))
        restoreHistory(entry)
    }

    private func restoreHistory(_ entry: HistoryEntry) {
        if entry.presentationOnly {
            // Preserve live simulation and scope acquisition for cosmetic edits.
            revision = entry.edit.revision
            document = entry.edit.document
            componentAppearance = entry.edit.componentAppearance
            wires = entry.edit.wires
        } else {
            restore(entry.edit)
        }
    }

    private func restore(_ edit: Edit) {
        pendingPlacementID = nil
        revision = edit.revision
        document = edit.document
        for (source, isOn) in edit.switches where source.isOn != isOn { source.toggle() }
        removeClocks { source in !edit.parts.contains { $0.component === source } }
        cancelWire()
        selectedWireID = nil
        powerMode = edit.powerMode
        componentAppearance = edit.componentAppearance
        scope.clear()
        scopeProbes = edit.scopeProbes
        parts = edit.parts
        wires = edit.wires
        junctions = edit.junctions
        schematicMarks = edit.schematicMarks
        positions = edit.positions
        rotations = edit.rotations
        clockFrequencies = edit.clockFrequencies
        ledColours = edit.ledColours
        for (resistor, value, unit) in edit.resistances {
            resistor.setResistance(value, unit: unit)
        }
        for (capacitor, value) in edit.capacitances { capacitor.setCapacitance(value) }
        nextPartID = edit.nextPartID
        nextChipNumber = edit.nextChipNumber
        nextWireID = edit.nextWireID
        rebuildNets()
    }

    func setComponentAppearance(_ appearance: ComponentAppearance) {
        guard appearance != componentAppearance else { return }
        recordEdit(presentationOnly: true)
        componentAppearance = appearance
    }

    func setPowerMode(_ mode: PowerMode) {
        guard mode != powerMode else { return }
        recordEdit()
        powerMode = mode
        engine.automaticallyPowerChips = mode == .automatic
        settle()
    }

    func placeNewPart(_ id: Int, at position: CGPoint) {
        guard parts.contains(where: { $0.id == id }), positions[id] != position else { return }
        // Initial placement belongs to the insertion's undo operation.
        if pendingPlacementID != id { recordEdit() }
        pendingPlacementID = nil
        positions[id] = position
    }

    func movePart(_ id: Int, from origin: CGPoint, to position: CGPoint) {
        guard parts.contains(where: { $0.id == id }), (positions[id] ?? origin) != position else { return }
        recordEdit()
        positions[id] = position
    }

    struct Movement {
        let parts: Set<Int>
        let junctions: Set<Int>
        let delta: CGPoint

        func includes(_ terminal: WorkbenchTerminal) -> Bool {
            terminal.isJunction ? junctions.contains(terminal.pinNumber) : parts.contains(terminal.partID)
        }

        func translate(_ point: CGPoint) -> CGPoint {
            CGPoint(x: point.x + delta.x, y: point.y + delta.y)
        }

        func wire(_ wire: WorkbenchWire) -> WorkbenchWire {
            guard includes(wire.first) && includes(wire.second) else { return wire }
            return WorkbenchWire(id: wire.id, first: wire.first, second: wire.second,
                                 bends: wire.bends.map(translate), netName: wire.netName, sourceRoute: wire.sourceRoute, colour: wire.colour)
        }
    }

    func movement(of ids: Set<Int>, by translation: CGSize) -> Movement {
        let movingJunctions = junctionGroups().reduce(into: Set<Int>()) { moving, group in
            let attached = group.endpoints.filter { !$0.isJunction }
            let selected = Set(attached.filter { ids.contains($0.partID) })
            if !selected.isEmpty && selected.count == attached.count {
                moving.formUnion(group.junctions)
            } else {
                for wire in internalWires(in: group, joining: selected) {
                    for endpoint in [wire.first, wire.second] where endpoint.isJunction {
                        moving.insert(endpoint.pinNumber)
                    }
                }
            }
        }
        return Movement(parts: ids, junctions: movingJunctions,
                        delta: WorkbenchWire.snap(CGPoint(x: translation.width, y: translation.height)))
    }

    func moveParts(_ movement: Movement) {
        guard movement.delta != .zero, parts.contains(where: { movement.parts.contains($0.id) }) else { return }
        recordEdit()
        for part in parts where movement.parts.contains(part.id) {
            positions[part.id] = movement.translate(positions[part.id] ?? CGPoint(x: 20, y: 20))
        }
        for id in movement.junctions {
            if let point = junctions[id] { junctions[id] = movement.translate(point) }
        }
        wires = wires.map(movement.wire)
    }

    private struct JunctionGroup {
        var junctions: Set<Int> = []
        var endpoints: Set<WorkbenchTerminal> = []
        var wires: [WorkbenchWire] = []
    }

    private func junctionGroups() -> [JunctionGroup] {
        var incident: [Int: [WorkbenchWire]] = [:]
        for wire in wires {
            for endpoint in [wire.first, wire.second] where endpoint.isJunction {
                incident[endpoint.pinNumber, default: []].append(wire)
            }
        }
        var visited: Set<Int> = []
        var groups: [JunctionGroup] = []
        for id in incident.keys where visited.insert(id).inserted {
            var pending = [id]
            var group = JunctionGroup()
            var wireIDs: Set<Int> = []
            while let junction = pending.popLast() {
                group.junctions.insert(junction)
                for wire in incident[junction, default: []] where wireIDs.insert(wire.id).inserted {
                    group.wires.append(wire)
                    for endpoint in [wire.first, wire.second] {
                        group.endpoints.insert(endpoint)
                        if endpoint.isJunction && visited.insert(endpoint.pinNumber).inserted {
                            pending.append(endpoint.pinNumber)
                        }
                    }
                }
            }
            groups.append(group)
        }
        return groups
    }

    private func internalWires(in group: JunctionGroup, joining selected: Set<WorkbenchTerminal>) -> [WorkbenchWire] {
        guard selected.count >= 2 else { return [] }
        var internalWires = group.wires.filter { wire in
            [wire.first, wire.second].allSatisfy { $0.isJunction || selected.contains($0) }
        }
        // Drop dangling branches left after cutting external pins.
        while true {
            var degrees: [WorkbenchTerminal: Int] = [:]
            for wire in internalWires {
                degrees[wire.first, default: 0] += 1
                degrees[wire.second, default: 0] += 1
            }
            let leaves = Set(degrees.keys.filter { $0.isJunction && degrees[$0] == 1 })
            guard !leaves.isEmpty else { return internalWires }
            internalWires.removeAll { leaves.contains($0.first) || leaves.contains($0.second) }
        }
    }

    func copyParts(_ ids: Set<Int>) throws -> WorkbenchArchive {
        var internalWireIDs: Set<Int> = []
        for group in junctionGroups() {
            let attached = group.endpoints.filter { !$0.isJunction }
            let selected = attached.filter { ids.contains($0.partID) }
            guard !selected.isEmpty else { continue }
            // Only trim junction branches when cutting connections at the selection boundary.
            let routes = selected == attached ? group.wires : internalWires(in: group, joining: selected)
            internalWireIDs.formUnion(routes.map(\.id))
        }
        let copiedWires = wires.filter {
            internalWireIDs.contains($0.id)
                || (!$0.first.isJunction && !$0.second.isJunction
                    && ids.contains($0.first.partID) && ids.contains($0.second.partID))
        }
        let usedJunctions = Set(copiedWires.flatMap { [$0.first, $0.second] }
            .filter(\.isJunction).map(\.pinNumber))
        return try WorkbenchArchive(bench: self, partIDs: ids, wires: copiedWires,
                                    junctions: junctions.filter { usedJunctions.contains($0.key) })
    }

    private var reservedDesignations: Set<String> {
        var reserved: Set<String> = []
        for part in parts {
            guard let base = part.referenceBase?.uppercased() else { continue }
            reserved.insert(base)
            let prefix = part.referencePrefix
            let digits = base.dropFirst(prefix.count).prefix(while: \.isNumber)
            if let number = Int(digits) { reserved.insert(prefix + String(number)) }
        }
        return reserved
    }

    func reference(for placement: ChipUnitPlacement) -> String {
        if let base = parts.first(where: { $0.unitPlacement?.packageID == placement.packageID })?.referenceBase {
            return base + placement.unit.letter
        }
        let preferred = "U\(placement.packageID)"
        var reserved = reservedDesignations
        let base = reserved.contains(preferred) ? Self.nextDesignation(prefix: "U", reserved: &reserved) : preferred
        return base + placement.unit.letter
    }

    private static func nextDesignation(prefix: String, reserved: inout Set<String>) -> String {
        var number = 1
        while !reserved.insert(prefix + String(number)).inserted { number += 1 }
        return prefix + String(number)
    }

    @discardableResult
    func pasteParts(_ archive: WorkbenchArchive, by translation: CGSize) throws -> Set<Int> {
        let copied = try archive.makeCircuit()
        guard !copied.parts.isEmpty else { return [] }
        let movement = Movement(parts: [], junctions: [],
                                delta: WorkbenchWire.snap(CGPoint(x: translation.width, y: translation.height)))
        var reserved = reservedDesignations
        var packages: [Int: (id: Int, reference: String)] = [:]
        var partIDs: [Int: Int] = [:]
        var junctionIDs: [Int: Int] = [:]
        recordEdit()
        cancelWire()
        selectedWireID = nil

        for part in copied.parts {
            let placement: ChipUnitPlacement?
            let designation: String
            if let unit = part.unitPlacement {
                let package: (id: Int, reference: String)
                if let existing = packages[unit.packageID] {
                    package = existing
                } else {
                    package = (nextChipNumber, Self.nextDesignation(prefix: part.referencePrefix, reserved: &reserved))
                    packages[unit.packageID] = package
                    nextChipNumber += 1
                }
                placement = ChipUnitPlacement(kind: unit.kind, packageID: package.id, unit: unit.unit)
                designation = package.reference
            } else {
                placement = nil
                designation = Self.nextDesignation(prefix: part.referencePrefix, reserved: &reserved)
            }
            let id = nextPartID
            nextPartID += 1
            partIDs[part.id] = id
            parts.append(WorkbenchPart(id: id, name: part.name, component: part.component, unitPlacement: placement,
                                       chipNumber: nil, importedSymbol: part.importedSymbol, designation: designation))
            positions[id] = movement.translate(copied.positions[part.id] ?? CGPoint(x: 20, y: 20))
            rotations[id] = copied.rotations[part.id]
            clockFrequencies[id] = copied.frequencies[part.id]
            ledColours[id] = copied.colours[part.id]
        }
        for (oldID, point) in archive.junctions.sorted(by: { $0.key < $1.key }) {
            junctionIDs[oldID] = nextWireID
            junctions[nextWireID] = movement.translate(point)
            nextWireID += 1
        }
        func remap(_ endpoint: WorkbenchTerminal) -> WorkbenchTerminal? {
            if endpoint.isJunction { return junctionIDs[endpoint.pinNumber].map(WorkbenchTerminal.junction) }
            return partIDs[endpoint.partID].map { WorkbenchTerminal(partID: $0, pinNumber: endpoint.pinNumber) }
        }
        for wire in copied.wires {
            guard let first = remap(wire.first), let second = remap(wire.second) else { continue }
            wires.append(WorkbenchWire(id: nextWireID, first: first, second: second,
                                       bends: wire.bends.map(movement.translate), netName: wire.netName,
                                       sourceRoute: wire.sourceRoute, colour: wire.colour))
            nextWireID += 1
        }
        rebuildNets()
        return Set(partIDs.values)
    }

    func rotatePart(_ id: Int, by steps: Int) {
        guard parts.contains(where: { $0.id == id }), steps % 4 != 0 else { return }
        recordEdit()
        rotations[id] = (rotations[id, default: 0] + steps % 4 + 4) % 4
    }

    func clockFrequency(for id: Int, source: WorkbenchClock) -> ClockFrequency {
        clockFrequencies[id] ?? source.defaultFrequency
    }

    func setClockFrequency(_ frequency: ClockFrequency, for id: Int) {
        guard let source = parts.first(where: { $0.id == id })?.component as? WorkbenchClock,
              !(source is CXO_DIP8) || frequency.unit != .hertz,
              frequency.hertz.isFinite, frequency.hertz > 0, 0.5 / frequency.hertz < Double(Int64.max),
              clockFrequency(for: id, source: source) != frequency else { return }
        recordEdit()
        clockFrequencies[id] = frequency
        if source is CXO_DIP8 {
            synchronizeOscillators(oscillatorParts, at: clockTime)
            updateClockStatus()
        }
    }

    func setLEDColour(_ colour: LEDIndicatorSymbol.LampColour, for id: Int) {
        guard parts.contains(where: { $0.id == id && $0.component is WorkbenchLED }),
              colour != ledColours[id, default: .green] else { return }
        recordEdit()
        ledColours[id] = colour
    }

    func setResistance(_ value: Double, unit: ResistanceUnit, for resistor: Resistor) {
        let ohms = value * unit.multiplier
        guard ohms.isFinite, ohms > 0, parts.contains(where: { $0.component === resistor }),
              value != resistor.value || unit != resistor.unit else { return }
        recordEdit()
        resistor.setResistance(value, unit: unit)
        settle()
    }

    func setCapacitance(_ value: Double, for capacitor: Capacitor) {
        guard parts.contains(where: { $0.component === capacitor }),
              Capacitor.isValid(value, kind: capacitor.kind), value != capacitor.value else { return }
        recordEdit()
        capacitor.setCapacitance(value)
        settle()
    }

    func canSetTransistorDesignation(_ designation: TransistorDesignation, for id: Int) -> Bool {
        guard let part = parts.first(where: { $0.id == id }),
              let transistor = part.component as? Transistor else { return false }
        if designation.definition.preservesConnections(of: transistor.definition) { return true }
        // Imported graphics use the original symbol's pin offsets.
        return part.importedSymbol == nil && !wires.contains { $0.first.partID == id || $0.second.partID == id }
    }

    func setTransistorDesignation(_ designation: TransistorDesignation, for id: Int) {
        guard let index = parts.firstIndex(where: { $0.id == id }),
              let transistor = parts[index].component as? Transistor,
              transistor.designation != designation,
              canSetTransistorDesignation(designation, for: id) else { return }
        let part = parts[index]
        recordEdit()
        parts[index] = WorkbenchPart(id: id, name: part.name, component: Transistor(designation),
                                     unitPlacement: part.unitPlacement, chipNumber: part.chipNumber,
                                     importedReference: part.importedReference, importedSymbol: part.importedSymbol,
                                     designation: part.designation)
        cancelWire()
        rebuildNets()
    }

    func packages(for kind: MultiUnitChip) -> [Int] {
        Set(parts.compactMap { part in
            part.unitPlacement?.kind == kind ? part.unitPlacement?.packageID : nil
        }).sorted()
    }

    func availableUnits(in packageID: Int, kind: MultiUnitChip) -> [ChipUnit] {
        let placed = parts.compactMap { part in
            part.unitPlacement?.packageID == packageID ? part.unitPlacement?.unit : nil
        }
        return kind.allUnits.filter { !placed.contains($0) }
    }

    func nextUnit(for kind: MultiUnitChip) -> ChipUnitPlacement? {
        for packageID in packages(for: kind) {
            if let unit = availableUnits(in: packageID, kind: kind).first(where: { $0.id != kind.powerUnit.id }) {
                return ChipUnitPlacement(kind: kind, packageID: packageID, unit: unit)
            }
        }
        return kind.units.first.map {
            ChipUnitPlacement(kind: kind, packageID: nextChipNumber, unit: $0)
        }
    }

    func addNextUnit(for kind: MultiUnitChip) {
        guard let placement = nextUnit(for: kind) else { return }
        let packageID = placement.packageID == nextChipNumber ? nil : placement.packageID
        addUnit(placement.unit, kind: kind, to: packageID)
    }

    func addUnit(_ unit: ChipUnit, kind: MultiUnitChip, to packageID: Int? = nil) {
        guard kind.allUnits.contains(unit) else { return }
        let component: any LogicComponent
        let reference: Int
        if let packageID {
            guard availableUnits(in: packageID, kind: kind).contains(unit),
                  let package = parts.first(where: {
                      $0.unitPlacement?.packageID == packageID && $0.unitPlacement?.kind == kind
                  }) else { return }
            component = package.component
            reference = packageID
        } else {
            component = kind.makeComponent()
            reference = nextChipNumber
        }
        recordEdit()
        if packageID == nil { nextChipNumber += 1 }
        insertPart(kind.partName, component: component,
            unitPlacement: ChipUnitPlacement(kind: kind, packageID: reference, unit: unit))
    }

    func add(_ name: String, component: any LogicComponent, unitPlacement: ChipUnitPlacement? = nil) {
        recordEdit()
        insertPart(name, component: component, unitPlacement: unitPlacement)
    }

    private func insertPart(_ name: String, component: any LogicComponent, unitPlacement: ChipUnitPlacement?) {
        let chipNumber: Int?
        if (component is any PoweredChip && !(component is CXO_DIP8) && unitPlacement == nil) || component is SevenSegmentDisplay {
            chipNumber = nextChipNumber
            nextChipNumber += 1
        } else {
            chipNumber = nil
        }
        let package = unitPlacement.flatMap { placement in
            parts.first { $0.unitPlacement?.packageID == placement.packageID }
        }
        let candidate = WorkbenchPart(id: nextPartID, name: name, component: component,
                                      unitPlacement: unitPlacement, chipNumber: chipNumber)
        var reserved = reservedDesignations
        let designation: String?
        if component is CXO_DIP8 {
            designation = Self.nextDesignation(prefix: "X", reserved: &reserved)
        } else if let package {
            designation = package.designation
        } else if let preferred = candidate.referenceBase, reserved.contains(preferred.uppercased()) {
            designation = Self.nextDesignation(prefix: candidate.referencePrefix, reserved: &reserved)
        } else {
            designation = nil
        }
        pendingPlacementID = nextPartID
        parts.append(WorkbenchPart(id: nextPartID, name: name, component: component,
                                   unitPlacement: unitPlacement, chipNumber: chipNumber,
                                   importedReference: package?.importedReference, designation: designation))
        nextPartID += 1
        engine.automaticallyPowerChips = powerMode == .automatic
        if !engine.components.contains(where: { $0 === component }) {
            engine.addComponent(component)
        }
        settle()
    }

    func select(_ terminal: WorkbenchTerminal) {
        guard wiringEnabled else { return }
        selectedWireID = nil
        guard let first = selectedTerminal else {
            selectedTerminal = terminal
            return
        }

        let bends = pendingBends
        cancelWire()
        guard first != terminal, !wires.contains(where: {
            ($0.first == first && $0.second == terminal) ||
            ($0.first == terminal && $0.second == first)
        }) else { return }

        recordEdit()
        wires.append(WorkbenchWire(id: nextWireID, first: first, second: terminal, bends: bends, colour: newWireColour))
        nextWireID += 1
        rebuildNets()
    }

    func joinWire(_ id: Int, at point: CGPoint, before: [CGPoint], after: [CGPoint], splitFraction: Double = 0.5) {
        guard let source = selectedTerminal, let index = wires.firstIndex(where: { $0.id == id }) else { return }
        let target = wires[index]
        let splitRoute = target.sourceRoute == .pinAttachment ? nil : target.sourceRoute
        guard source != target.first, source != target.second else { return }
        recordEdit()
        let junctionID = nextWireID
        let endpoint = WorkbenchTerminal.junction(junctionID)
        junctions[junctionID] = point
        wires[index] = WorkbenchWire(id: target.id, first: target.first, second: endpoint, bends: before, netName: target.netName, sourceRoute: splitRoute, colour: target.colour)
        wires.append(WorkbenchWire(id: nextWireID, first: endpoint, second: target.second, bends: after, netName: target.netName, sourceRoute: splitRoute, colour: target.colour))
        wires.append(WorkbenchWire(id: nextWireID + 1, first: source, second: endpoint, bends: pendingBends, colour: newWireColour))
        for (channel, probe) in scopeProbes {
            guard case .wirePoint(let wireID, let fraction) = probe, wireID == id else { continue }
            if fraction == splitFraction {
                scopeProbes[channel] = .netPin(endpoint)
            } else if fraction < splitFraction {
                scopeProbes[channel] = .wirePoint(id: id, fraction: fraction / splitFraction)
            } else {
                scopeProbes[channel] = .wirePoint(id: nextWireID, fraction: (fraction - splitFraction) / (1 - splitFraction))
            }
        }
        nextWireID += 2
        cancelWire()
        rebuildNets()
    }

    func addBend(at point: CGPoint) {
        guard selectedTerminal != nil else { return }
        let snapped = WorkbenchWire.snap(point)
        if pendingBends.last != snapped { pendingBends.append(snapped) }
    }

    func cancelWire() {
        selectedTerminal = nil
        pendingBends.removeAll()
    }

    func selectWire(_ id: Int?) {
        selectedWireID = id
    }

    func setWireColour(_ colour: WireColour, for id: Int) {
        guard let index = wires.firstIndex(where: { $0.id == id }), wires[index].colour != colour else { return }
        recordEdit(presentationOnly: true)
        wires[index].colour = colour
    }

    func removeSelectedWire() {
        guard let selectedWireID else { return }
        removeWire(selectedWireID)
    }

    func removePart(_ id: Int) {
        removeParts([id])
    }

    func removeParts(_ ids: Set<Int>) {
        guard parts.contains(where: { ids.contains($0.id) }) else { return }
        recordEdit()
        removeClocks { source in parts.contains { ids.contains($0.id) && $0.component === source } }
        for id in ids {
            positions.removeValue(forKey: id)
            rotations.removeValue(forKey: id)
            clockFrequencies.removeValue(forKey: id)
            ledColours.removeValue(forKey: id)
        }
        if let selectedTerminal, ids.contains(selectedTerminal.partID) {
            cancelWire()
        }
        parts.removeAll { ids.contains($0.id) }
        let originalWires = wires
        let affected = Set(wires.filter { ids.contains($0.first.partID) || ids.contains($0.second.partID) }
            .flatMap { [$0.first, $0.second] }.filter(\.isJunction).map(\.pinNumber))
        wires.removeAll { ids.contains($0.first.partID) || ids.contains($0.second.partID) }
        if !affected.isEmpty {
            let orphans = Set(junctionGroups().filter {
                !$0.junctions.isDisjoint(with: affected) && $0.endpoints.allSatisfy(\.isJunction)
            }.flatMap { $0.wires.map(\.id) })
            wires.removeAll { orphans.contains($0.id) }
        }
        pruneJunctions()
        if !wires.contains(where: { $0.id == selectedWireID }) {
            selectedWireID = nil
        }
        let remainingIDs = Set(wires.map(\.id))
        rebuildNets(removedWires: originalWires.filter { !remainingIDs.contains($0.id) })
    }

    func removeWire(_ id: Int) {
        guard let wire = wires.first(where: { $0.id == id }) else { return }
        recordEdit()
        if selectedWireID == id {
            selectedWireID = nil
        }
        wires.removeAll { $0.id == id }
        pruneJunctions()
        rebuildNets(removedWires: [wire])
    }

    func junctionDots(visible: [WorkbenchWire], pinContacts: [WorkbenchWire],
                      at locations: [Int: CGPoint]? = nil) -> [CGPoint] {
        var branchCounts: [Int: Int] = [:]
        for wire in visible + pinContacts {
            for endpoint in [wire.first, wire.second] where endpoint.isJunction {
                branchCounts[endpoint.pinNumber, default: 0] += 1
            }
        }
        return branchCounts.compactMap { id, count in
            count >= 3 ? (locations ?? junctions)[id] : nil
        }
    }

    private func pruneJunctions() {
        let used = Set(wires.flatMap { [$0.first, $0.second] })
        junctions = junctions.filter { used.contains(.junction($0.key)) }
        if let selectedTerminal, selectedTerminal.isJunction, !used.contains(selectedTerminal) {
            cancelWire()
        }
    }

    func clear() {
        guard hasCircuit || isDirty || documentURL != nil else { return }
        recordEdit()
        startDocument(clean: true)
        powerMode = .automatic
        scope.clear()
        scopeProbes.removeAll()
        removeClocks { _ in true }
        positions.removeAll()
        rotations.removeAll()
        clockFrequencies.removeAll()
        ledColours.removeAll()
        cancelWire()
        selectedWireID = nil
        parts.removeAll()
        wires.removeAll()
        junctions.removeAll()
        schematicMarks.removeAll()
        nextPartID = 1
        nextChipNumber = 1
        nextWireID = 1
        rebuildNets()
    }

    func toggle(_ source: WorkbenchSwitch) {
        if parts.contains(where: { $0.component === source }) { recordEdit() }
        source.toggle()
        settle()
    }

    func advanceClock(_ source: WorkbenchClock) {
        source.advance()
        settle()
    }

    func runClock(_ source: WorkbenchClock, hertz: Double) {
        runningClocks.removeAll { $0.source === source }
        runningClocks.append(RunningClock(source: source, startedAt: clockTime, halfPeriod: 0.5 / hertz))
        updateClockStatus()
    }

    func serviceClocks() {
        serviceSimulation(until: clockTime)
    }

    // A deterministic entry point also allows tests to verify elapsed-time scheduling.
    func serviceSimulation(until now: Double) {
        guard now.isFinite, now >= servicedTime else { return }
        let budgetDeadline = clockTime + 0.012
        let oscillators = oscillatorParts
        var stable = true
        var batches = 0
        while servicedTime < now {
            let index = runningClocks.indices.min { runningClocks[$0].nextEdge < runningClocks[$1].nextEdge }
            let target = min(now, index.map { max(servicedTime, runningClocks[$0].nextEdge) } ?? now)
            let start = servicedTime
            let observe: ((Double, Bool) -> Void)? = scope.running && !scopeReaders.isEmpty
                ? { elapsed, stable in self.captureScope(at: start + elapsed, stable: stable) }
                : nil
            let advance = engine.hasTimingNetworks
                ? engine.advanceTime(by: target - start, maximumEvents: 32, onSettled: observe)
                : SimulationEngine.TimeAdvance(elapsed: target - servicedTime, stable: true)
            servicedTime += advance.elapsed
            stable = advance.stable && stable
            if servicedTime >= target, let index, runningClocks[index].nextEdge <= servicedTime {
                runningClocks[index].source.advance()
                runningClocks[index].edgesDelivered += 1
                let edgeStable = engine.settle()
                stable = edgeStable && stable
                captureScope(at: servicedTime, stable: edgeStable)
            } else if !engine.hasTimingNetworks {
                captureScope(at: servicedTime, stable: stable)
            }
            synchronizeOscillators(oscillators, at: servicedTime)
            batches += 1
            if batches >= 4_096 || clockTime >= budgetDeadline { break }
            if advance.elapsed == 0 && target > servicedTime { break }
        }
        isStable = stable
        updateClockStatus()
        publishReadings()
        let behind = now - servicedTime > 0.1
        if behind != clockIsBehind { clockIsBehind = behind }
    }

    private func removeClocks(where shouldRemove: (WorkbenchClock) -> Bool) {
        runningClocks.removeAll { clock in
            guard shouldRemove(clock.source) else { return false }
            clock.source.stop()
            return true
        }
        updateClockStatus()
    }

    private var oscillatorParts: [(id: Int, source: CXO_DIP8)] {
        parts.compactMap { part in
            (part.component as? CXO_DIP8).map { (part.id, $0) }
        }
    }

    private func synchronizeOscillators(_ oscillators: [(id: Int, source: CXO_DIP8)], at time: Double) {
        for (id, oscillator) in oscillators {
            let halfPeriod = 0.5 / clockFrequency(for: id, source: oscillator).hertz
            let active = oscillator.isEnabled && (powerMode == .automatic || oscillator.powerState == .powered)
            let index = runningClocks.firstIndex { $0.source === oscillator }
            if let index, !active || runningClocks[index].halfPeriod != halfPeriod {
                runningClocks.remove(at: index)
            } else if index != nil {
                continue
            }
            if active {
                runningClocks.append(RunningClock(source: oscillator, startedAt: time, halfPeriod: halfPeriod))
            }
        }
    }

    private func updateClockStatus() {
        let running = !runningClocks.isEmpty || engine.hasTimingNetworks
        if running && !hasRunningClocks { servicedTime = max(servicedTime, clockTime) }
        if running != hasRunningClocks { hasRunningClocks = running }
        if !running && clockIsBehind { clockIsBehind = false }
    }

    func stopClock(_ source: WorkbenchClock) {
        runningClocks.removeAll { $0.source === source }
        updateClockStatus()
        guard source.phase != .low else { return }
        source.stop()
        settle()
    }

    func open(_ archive: WorkbenchArchive, at url: URL? = nil) throws {
        let loaded = try archive.makeCircuit()
        recordEdit()
        startDocument(at: url, clean: true)
        restore(Edit(revision: revision, document: document, switches: [], parts: loaded.parts, powerMode: archive.savedPowerMode,
                     componentAppearance: archive.savedComponentAppearance, wires: loaded.wires, junctions: archive.junctions,
                     schematicMarks: archive.schematicMarks ?? [],
                     positions: loaded.positions, rotations: loaded.rotations,
                     clockFrequencies: loaded.frequencies, ledColours: loaded.colours, resistances: [], capacitances: [],
                     scopeProbes: loaded.scopeProbes, nextPartID: (loaded.parts.map(\.id).max() ?? 0) + 1,
                     nextChipNumber: loaded.nextChipNumber,
                     nextWireID: (archive.wires.map(\.id) + Array(archive.junctions.keys)).max().map { $0 + 1 } ?? 1))
    }

    @discardableResult
    func importCircuit(_ preview: CircuitImportPreview, replacing: Bool) -> WorkbenchPart? {
        guard preview.canImport else { return nil }
        let append = !replacing && !parts.isEmpty
        let bottom = (positions.values.map(\.y) + junctions.values.map(\.y) +
                      wires.flatMap { $0.bends.map(\.y) } + schematicMarks.map(\.position.y)).max() ?? 0
        let imported = preview.place(startingPart: append ? nextPartID : 1,
                                     startingChip: append ? nextChipNumber : 1,
                                     startingWire: append ? nextWireID : 1,
                                     below: append ? bottom + 600 : 30,
                                     existingReferences: append ? Set(parts.compactMap(\.reference)) : [])
        recordEdit()
        if replacing { startDocument(clean: false) }
        restore(Edit(revision: revision, document: document, switches: [], parts: (append ? parts : []) + imported.parts,
                     powerMode: append ? powerMode : .explicit, componentAppearance: componentAppearance,
                     wires: (append ? wires : []) + imported.wires,
                     junctions: (append ? junctions : [:]).merging(imported.junctions) { _, incoming in incoming },
                     schematicMarks: (append ? schematicMarks : []) + imported.schematicMarks,
                     positions: (append ? positions : [:]).merging(imported.positions) { _, incoming in incoming },
                     rotations: (append ? rotations : [:]).merging(imported.rotations) { _, incoming in incoming },
                     clockFrequencies: append ? clockFrequencies : [:],
                     ledColours: append ? ledColours : [:], resistances: [], capacitances: [],
                     scopeProbes: append ? scopeProbes : [:], nextPartID: imported.nextPartID,
                     nextChipNumber: imported.nextChipNumber, nextWireID: imported.nextWireID))
        return imported.parts.first
    }

    func label(for terminal: WorkbenchTerminal) -> String {
        if terminal.isJunction { return "Junction \(terminal.pinNumber)" }
        guard let part = parts.first(where: { $0.id == terminal.partID }),
              let pin = part.pins[terminal.pinNumber] else { return "" }
        return "\(part.label) · \(pin.name) (\(pin.number))"
    }

    func circuitNet(at terminal: WorkbenchTerminal) -> Net? {
        netsByTerminal[terminal]
    }

    private func rebuildNets(removedWires: [WorkbenchWire] = []) {
        servicedTime = max(servicedTime, clockTime)
        engine = SimulationEngine()
        engine.automaticallyPowerChips = powerMode == .automatic
        var registered: Set<ObjectIdentifier> = []
        for part in parts where registered.insert(ObjectIdentifier(part.component)).inserted {
            engine.addComponent(part.component)
            for pin in part.component.pins.values {
                pin.receive(.highImpedance)
            }
        }

        // Connected wire endpoints share a single electrical net.
        var groups: [Set<WorkbenchTerminal>] = []
        for wire in wires {
            var terminals: Set<WorkbenchTerminal> = [wire.first, wire.second]
            groups.removeAll { group in
                guard !group.isDisjoint(with: terminals) else { return false }
                terminals.formUnion(group)
                return true
            }
            groups.append(terminals)
        }

        var namesByTerminal: [WorkbenchTerminal: Set<String>] = [:]
        for wire in wires {
            if let name = wire.netName { namesByTerminal[wire.first, default: []].insert(name) }
        }
        netsByTerminal.removeAll()
        for (index, group) in groups.enumerated() {
            let names = Set(group.flatMap { namesByTerminal[$0] ?? [] }).sorted()
            let net = Net(name: names.isEmpty ? "Net \(index + 1)" : names.joined(separator: " / "))
            for terminal in group {
                netsByTerminal[terminal] = net
                if let part = parts.first(where: { $0.id == terminal.partID }),
                   let pin = part.pins[terminal.pinNumber] {
                    net.connect(pin)
                }
            }
            engine.addNet(net)
        }
        for (channel, probe) in scopeProbes {
            guard case .wirePoint(let id, let fraction) = probe,
                  let wire = removedWires.first(where: { $0.id == id }) else { continue }
            // Follow a surviving branch only when both endpoints agree or just one remains wired.
            let first = netsByTerminal[wire.first]
            let second = netsByTerminal[wire.second]
            guard first == nil || second == nil || first === second else { continue }
            let endpoints = fraction <= 0.5 ? [wire.first, wire.second] : [wire.second, wire.first]
            if let survivor = endpoints.first(where: { netsByTerminal[$0] != nil }) {
                scopeProbes[channel] = .netPin(survivor)
            }
        }
        let validProbes = scopeProbes.filter { scopeReader(for: $0.value) != nil }
        if validProbes != scopeProbes {
            for channel in scopeProbes.keys where validProbes[channel] == nil { scope.reset(channel: channel) }
            scopeProbes = validProbes
        }
        refreshScopeReaders()
        settle()
    }

    var nextScopeChannel: Int? {
        (0..<Oscilloscope.channelCount).first { scopeProbes[$0] == nil }
    }

    @discardableResult
    func placeScopeProbe(_ probe: ScopeProbe, moving channel: Int? = nil) -> Bool {
        guard let destination = channel ?? nextScopeChannel,
              channel == nil || scopeProbes[destination] != nil else { return false }
        return assignScopeProbe(probe, to: destination)
    }

    @discardableResult
    func assignScopeProbe(_ probe: ScopeProbe?, to channel: Int) -> Bool {
        guard (0..<Oscilloscope.channelCount).contains(channel),
              probe.map({ scopeReader(for: $0) != nil }) ?? true else { return false }
        guard probe != scopeProbes[channel] else { return true }
        recordEdit()
        scopeProbes[channel] = probe
        scope.reset(channel: channel)
        refreshScopeReaders()
        refreshScope()
        return true
    }

    func refreshScope() {
        captureScope(at: hasRunningClocks ? servicedTime : max(servicedTime, clockTime), stable: isStable)
    }

    private func refreshScopeReaders() {
        scopeReaders = scopeProbes.compactMapValues { scopeReader(for: $0) }
        pulseReaders = scopeProbes.compactMapValues { scopePulseReader(for: $0) }
        for (channel, read) in pulseReaders {
            scope.primePulse(channel: channel, level: read())
        }
        engine.onEvaluationPass = pulseReaders.isEmpty ? nil : { [weak self] in
            guard let self else { return }
            for (channel, read) in pulseReaders {
                scope.observePulse(channel: channel, level: read())
            }
        }
    }

    func scopeNet(for probe: ScopeProbe) -> Net? {
        if let terminal = probe.terminal { return netsByTerminal[terminal] }
        if case .wirePoint(_, let fraction) = probe, !(0...1).contains(fraction) { return nil }
        return wires.first { $0.id == probe.wireID }.flatMap { netsByTerminal[$0.first] }
    }

    private func scopePulseReader(for probe: ScopeProbe) -> (() -> LogicState)? {
        if let net = scopeNet(for: probe) { return { net.state } }
        return standaloneScopeReader(for: probe)
    }

    private func scopeReader(for probe: ScopeProbe) -> ((Bool) -> ScopeValue)? {
        if let net = scopeNet(for: probe) { return scopeNetReader(net) }
        guard let read = standaloneScopeReader(for: probe) else { return nil }
        return { stable in .logic(stable ? read() : .undefined) }
    }

    private func standaloneScopeReader(for probe: ScopeProbe) -> (() -> LogicState)? {
        guard case .pin(let terminal) = probe, !terminal.isJunction,
              let part = parts.first(where: { $0.id == terminal.partID }),
              let pin = part.pins[terminal.pinNumber] else { return nil }
        let readsNet = part.component is any SwitchedConnectivity && pin.direction == .bidirectional
        return { readsNet ? pin.state : pin.driveState }
    }

    private func scopeNetReader(_ net: Net) -> (Bool) -> ScopeValue {
        let engine = engine
        return { stable in
            guard stable else { return .logic(.undefined) }
            if let voltage = engine.timingVoltage(on: net), voltage.isFinite { return .voltage(voltage) }
            if let voltage = net.dcVoltage { return .voltage(voltage) }
            return .logic(net.state)
        }
    }

    private func captureScope(at time: Double, stable: Bool) {
        guard !scopeReaders.isEmpty else { return }
        scope.capture(at: time) { scopeReaders[$0]?(stable) }
    }

    private func settle() {
        isStable = engine.settle()
        synchronizeOscillators(oscillatorParts, at: clockTime)
        updateClockStatus()
        publishReadings()
        refreshScope()
    }

    private func publishReadings() {
        let issues = Dictionary(uniqueKeysWithValues: parts.compactMap { part -> (Int, String)? in
            guard let timer = part.component as? NE555, let issue = timer.timingIssue else { return nil }
            return (part.id, issue)
        })
        if issues != timingIssues { timingIssues = issues }
        let power = Dictionary(uniqueKeysWithValues: parts.compactMap { part -> (Int, ChipPowerState)? in
            guard let chip = part.component as? any PoweredChip else { return nil }
            return (part.id, powerMode == .automatic ? .powered : chip.powerState)
        })
        if power != powerStates { powerStates = power }
        let connectedPins = Set(engine.nets.flatMap { $0.pins.map(ObjectIdentifier.init) })
        var states: [WorkbenchTerminal: LogicState] = [:]
        for part in parts {
            for pin in part.pins.values {
                let terminal = WorkbenchTerminal(partID: part.id, pinNumber: pin.number)
                let readsNet = connectedPins.contains(ObjectIdentifier(pin)) ||
                    (part.component is any SwitchedConnectivity && pin.direction == .bidirectional)
                states[terminal] = readsNet ? pin.state : pin.driveState
            }
        }
        if readings != states { readings = states }

        let lit = Set(parts.compactMap { part -> Int? in
            guard part.component is LED3mm,
                  let cathode = circuitNet(at: WorkbenchTerminal(partID: part.id, pinNumber: 1))?.dcVoltage,
                  let anode = circuitNet(at: WorkbenchTerminal(partID: part.id, pinNumber: 2))?.dcVoltage,
                  anode - cathode - LED3mm.forwardVoltage > 1e-6 else { return nil }
            return part.id
        })
        if illuminatedLEDs != lit { illuminatedLEDs = lit }
    }
}
