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
        case .and, .nand, .or: QuadGate.allCases.map { ChipUnit(id: $0.rawValue, pinNumbers: $0.pinNumbers) }
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

    let importedReference: String?
    let importedSymbol: ImportedSymbol?

    init(id: Int, name: String, component: any LogicComponent, unitPlacement: ChipUnitPlacement?,
         chipNumber: Int?, importedReference: String? = nil, importedSymbol: ImportedSymbol? = nil) {
        self.id = id
        self.name = name
        self.component = component
        self.unitPlacement = unitPlacement
        self.chipNumber = chipNumber
        self.importedReference = importedReference
        self.importedSymbol = importedSymbol
    }

    var reference: String? {
        if let importedReference { return importedReference + (unitPlacement?.unit.letter ?? "") }
        if component is PinHeader { return "J\(id)" }
        if component is Capacitor { return "C\(id)" }
        if component is Resistor { return "R\(id)" }
        if component is Diode1N4148 { return "D\(id)" }
        if component is NPN2N3904 { return "Q\(id)" }
        return unitPlacement?.reference ?? chipNumber.map { "U\($0)" }
    }

    var label: String {
        if let reference { return "\(name) \(reference)" }
        return "\(name) \(id)"
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

struct WorkbenchWire: Identifiable, Codable {
    let id: Int
    let first: WorkbenchTerminal
    let second: WorkbenchTerminal
    let bends: [CGPoint]
    let netName: String?
    enum SourceRoute: String, Codable { case straight, alias, pinAttachment }
    let sourceRoute: SourceRoute?

    init(id: Int, first: WorkbenchTerminal, second: WorkbenchTerminal, bends: [CGPoint], netName: String? = nil,
         sourceRoute: SourceRoute? = nil) {
        self.id = id
        self.first = first
        self.second = second
        self.bends = bends
        self.netName = netName
        self.sourceRoute = sourceRoute
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

final class WorkbenchClock: LogicComponent {
    let pins: [Int: Pin]
    let output: Pin
    private(set) var phase: LogicState = .low

    init() {
        output = Pin(number: 1, name: "OUT", direction: .output)
        pins = [output.number: output]
        output.drive(.low)
    }

    func advance() {
        phase = phase.inverted
        output.drive(phase)
    }

    func stop() {
        phase = .low
        output.drive(.low)
    }

    func evaluate() {}
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
    private(set) var readings: [WorkbenchTerminal: LogicState] = [:]
    private(set) var isStable = true
    private(set) var powerMode: PowerMode = .automatic
    private(set) var powerStates: [Int: ChipPowerState] = [:]
    var wiringEnabled = true
    private(set) var selectedTerminal: WorkbenchTerminal?
    private(set) var selectedWireID: Int?
    private(set) var pendingBends: [CGPoint] = []
    private var engine = SimulationEngine()
    let scope = Oscilloscope()
    private(set) var scopeProbes: [Int: ScopeProbe] = [:]
    @ObservationIgnored private var netsByTerminal: [WorkbenchTerminal: Net] = [:]
    @ObservationIgnored private var scopeReaders: [Int: (Bool) -> ScopeValue] = [:]
    private struct RunningClock {
        let source: WorkbenchClock
        let startedAt: Double
        let halfPeriod: Double
        var edgesDelivered = 0.0

        var nextEdge: Double { startedAt + (edgesDelivered + 1) * halfPeriod }
    }

    private let clockOrigin = DispatchTime.now().uptimeNanoseconds
    @ObservationIgnored private let timeSource: (() -> Double)?

    init(timeSource: (() -> Double)? = nil) { self.timeSource = timeSource }
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

    private struct Edit {
        let parts: [WorkbenchPart]
        let powerMode: PowerMode
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

    private var undoHistory: [Edit] = []
    private var redoHistory: [Edit] = []
    var canUndo: Bool { !undoHistory.isEmpty }
    var canRedo: Bool { !redoHistory.isEmpty }

    private var currentEdit: Edit {
        Edit(parts: parts, powerMode: powerMode, wires: wires, junctions: junctions, schematicMarks: schematicMarks, positions: positions, rotations: rotations,
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

    private func recordEdit() {
        undoHistory.append(currentEdit)
        if undoHistory.count > 100 { undoHistory.removeFirst() }
        redoHistory.removeAll()
    }

    func undo() {
        guard let edit = undoHistory.popLast() else { return }
        redoHistory.append(currentEdit)
        restore(edit)
    }

    func redo() {
        guard let edit = redoHistory.popLast() else { return }
        undoHistory.append(currentEdit)
        restore(edit)
    }

    private func restore(_ edit: Edit) {
        removeClocks { source in !edit.parts.contains { $0.component === source } }
        cancelWire()
        selectedWireID = nil
        powerMode = edit.powerMode
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

    func setPowerMode(_ mode: PowerMode) {
        guard mode != powerMode else { return }
        recordEdit()
        powerMode = mode
        engine.automaticallyPowerChips = mode == .automatic
        settle()
    }

    func placeNewPart(_ id: Int, at position: CGPoint) {
        // The insertion is already one undo operation.
        positions[id] = position
    }

    func movePart(_ id: Int, from origin: CGPoint, to position: CGPoint) {
        guard origin != position else { return }
        recordEdit()
        positions[id] = position
    }

    func rotatePart(_ id: Int, by steps: Int) {
        recordEdit()
        rotations[id] = (rotations[id, default: 0] + steps + 4) % 4
    }

    func setClockFrequency(_ frequency: ClockFrequency, for id: Int) {
        let current = clockFrequencies[id] ?? ClockFrequency(value: 1, unit: .hertz)
        guard current != frequency else { return }
        recordEdit()
        clockFrequencies[id] = frequency
    }

    func setLEDColour(_ colour: LEDIndicatorSymbol.LampColour, for id: Int) {
        guard colour != ledColours[id, default: .green] else { return }
        recordEdit()
        ledColours[id] = colour
    }

    func setResistance(_ value: Double, unit: ResistanceUnit, for resistor: Resistor) {
        guard value != resistor.value || unit != resistor.unit else { return }
        recordEdit()
        resistor.setResistance(value, unit: unit)
        settle()
    }

    func setCapacitance(_ value: Double, for capacitor: Capacitor) {
        guard Capacitor.isValid(value, kind: capacitor.kind), value != capacitor.value else { return }
        recordEdit()
        capacitor.setCapacitance(value)
        settle()
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
        if (component is any PoweredChip && unitPlacement == nil) || component is SevenSegmentDisplay {
            chipNumber = nextChipNumber
            nextChipNumber += 1
        } else {
            chipNumber = nil
        }
        let importedReference = unitPlacement.flatMap { placement in
            parts.first { $0.unitPlacement?.packageID == placement.packageID }?.importedReference
        }
        parts.append(WorkbenchPart(id: nextPartID, name: name, component: component,
                                   unitPlacement: unitPlacement, chipNumber: chipNumber,
                                   importedReference: importedReference))
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
        wires.append(WorkbenchWire(id: nextWireID, first: first, second: terminal, bends: bends))
        nextWireID += 1
        rebuildNets()
    }

    func joinWire(_ id: Int, at point: CGPoint, before: [CGPoint], after: [CGPoint]) {
        guard let source = selectedTerminal, let index = wires.firstIndex(where: { $0.id == id }) else { return }
        let target = wires[index]
        let splitRoute = target.sourceRoute == .pinAttachment ? nil : target.sourceRoute
        guard source != target.first, source != target.second else { return }
        recordEdit()
        let junctionID = nextWireID
        let endpoint = WorkbenchTerminal.junction(junctionID)
        junctions[junctionID] = point
        wires[index] = WorkbenchWire(id: target.id, first: target.first, second: endpoint, bends: before, netName: target.netName, sourceRoute: splitRoute)
        wires.append(WorkbenchWire(id: nextWireID, first: endpoint, second: target.second, bends: after, netName: target.netName, sourceRoute: splitRoute))
        wires.append(WorkbenchWire(id: nextWireID + 1, first: source, second: endpoint, bends: pendingBends))
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
        wires.removeAll { ids.contains($0.first.partID) || ids.contains($0.second.partID) }
        pruneJunctions()
        if !wires.contains(where: { $0.id == selectedWireID }) {
            selectedWireID = nil
        }
        rebuildNets()
    }

    func removeWire(_ id: Int) {
        guard wires.contains(where: { $0.id == id }) else { return }
        recordEdit()
        if selectedWireID == id {
            selectedWireID = nil
        }
        wires.removeAll { $0.id == id }
        pruneJunctions()
        rebuildNets()
    }

    func junctionDots(visible: [WorkbenchWire], pinContacts: [WorkbenchWire]) -> [CGPoint] {
        var branchCounts: [Int: Int] = [:]
        for wire in visible + pinContacts {
            for endpoint in [wire.first, wire.second] where endpoint.isJunction {
                branchCounts[endpoint.pinNumber, default: 0] += 1
            }
        }
        return branchCounts.compactMap { id, count in
            count >= 3 ? junctions[id] : nil
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
        guard !parts.isEmpty else { return }
        recordEdit()
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
            batches += 1
            if batches >= 1 && clockTime >= budgetDeadline { break }
            if advance.elapsed == 0 && target > servicedTime { break }
        }
        isStable = stable
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

    func open(_ archive: WorkbenchArchive) throws {
        let loaded = try archive.makeCircuit()
        recordEdit()
        restore(Edit(parts: loaded.parts, powerMode: archive.savedPowerMode, wires: loaded.wires, junctions: archive.junctions,
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
        restore(Edit(parts: (append ? parts : []) + imported.parts,
                     powerMode: append ? powerMode : .explicit,
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

    private func rebuildNets() {
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
        let validProbes = scopeProbes.filter { scopeReader(for: $0.value) != nil }
        if validProbes != scopeProbes {
            for channel in scopeProbes.keys where validProbes[channel] == nil { scope.reset(channel: channel) }
            scopeProbes = validProbes
        }
        refreshScopeReaders()
        settle()
    }

    func assignScopeProbe(_ probe: ScopeProbe?, to channel: Int) {
        guard (0..<Oscilloscope.channelCount).contains(channel), probe != scopeProbes[channel],
              probe.map({ scopeReader(for: $0) != nil }) ?? true else { return }
        recordEdit()
        scopeProbes[channel] = probe
        scope.reset(channel: channel)
        refreshScopeReaders()
        refreshScope()
    }

    func refreshScope() {
        captureScope(at: hasRunningClocks ? servicedTime : max(servicedTime, clockTime), stable: isStable)
    }

    private func refreshScopeReaders() {
        scopeReaders = scopeProbes.compactMapValues { scopeReader(for: $0) }
    }

    private func scopeReader(for probe: ScopeProbe) -> ((Bool) -> ScopeValue)? {
        let terminal: WorkbenchTerminal
        switch probe {
        case .wire(let id):
            guard let wire = wires.first(where: { $0.id == id }),
                  let net = netsByTerminal[wire.first] else { return nil }
            return scopeNetReader(net)
        case .pin(let pin):
            terminal = pin
        }
        guard let part = parts.first(where: { $0.id == terminal.partID }),
              let pin = part.pins[terminal.pinNumber] else { return nil }
        if let net = netsByTerminal[terminal] { return scopeNetReader(net) }
        let readsNet = part.component is any SwitchedConnectivity && pin.direction == .bidirectional
        return { stable in .logic(stable ? (readsNet ? pin.state : pin.driveState) : .undefined) }
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
    }
}
