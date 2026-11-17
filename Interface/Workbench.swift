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
    case jk = "4027"
    case inverter = "40106"

    var id: String { rawValue }
    var partName: String { "CD\(rawValue)" }

    var unitName: String {
        switch self {
        case .and: "AND Gate"
        case .nand: "NAND Gate"
        case .jk: "JK Flip-Flop"
        case .inverter: "Schmitt Inverter"
        }
    }

    func makeComponent() -> any LogicComponent {
        switch self {
        case .and: CD4081()
        case .nand: CD4011()
        case .jk: CD4027()
        case .inverter: CD40106()
        }
    }

    var units: [ChipUnit] {
        switch self {
        case .and, .nand: QuadGate.allCases.map { ChipUnit(id: $0.rawValue, pinNumbers: $0.pinNumbers) }
        case .jk: [ChipUnit(id: 1, pinNumbers: Array(1...7)), ChipUnit(id: 2, pinNumbers: Array(9...15))]
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

    var letter: String { ["A", "B", "C", "D", "E", "F"][id - 1] }
}

struct ChipUnitPlacement {
    let kind: MultiUnitChip
    let packageID: Int
    let unit: ChipUnit

    var reference: String { "U\(packageID)\(unit.letter)" }
}

struct WorkbenchPart: Identifiable {
    let id: Int
    let name: String
    let component: any LogicComponent

    let unitPlacement: ChipUnitPlacement?
    let chipNumber: Int?

    var reference: String? {
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
        return component.pins.filter { unitPlacement.unit.pinNumbers.contains($0.key) }
    }
}

struct WorkbenchWire: Identifiable, Codable {
    let id: Int
    let first: WorkbenchTerminal
    let second: WorkbenchTerminal
    let bends: [CGPoint]
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
    private(set) var selectedTerminal: WorkbenchTerminal?
    private(set) var selectedWireID: Int?
    private(set) var pendingBends: [CGPoint] = []
    private var engine = SimulationEngine()
    private struct RunningClock {
        let source: WorkbenchClock
        let startedAt: Double
        let halfPeriod: Double
        var edgesDelivered = 0.0

        var nextEdge: Double { startedAt + (edgesDelivered + 1) * halfPeriod }
    }

    private let clockOrigin = DispatchTime.now().uptimeNanoseconds
    @ObservationIgnored private var runningClocks: [RunningClock] = []
    private(set) var hasRunningClocks = false
    private(set) var clockIsBehind = false

    private var clockTime: Double {
        Double(DispatchTime.now().uptimeNanoseconds - clockOrigin) / 1_000_000_000
    }
    private var nextPartID = 1
    private var nextChipNumber = 1
    private var nextWireID = 1

    private(set) var junctions: [Int: CGPoint] = [:]
    private(set) var positions: [Int: CGPoint] = [:]
    private(set) var rotations: [Int: Int] = [:]
    private(set) var clockFrequencies: [Int: ClockFrequency] = [:]
    private(set) var ledColours: [Int: LEDIndicatorSymbol.LampColour] = [:]

    private struct Edit {
        let parts: [WorkbenchPart]
        let wires: [WorkbenchWire]
        let junctions: [Int: CGPoint]
        let positions: [Int: CGPoint]
        let rotations: [Int: Int]
        let clockFrequencies: [Int: ClockFrequency]
        let ledColours: [Int: LEDIndicatorSymbol.LampColour]
        let resistances: [(Resistor, Double, ResistanceUnit)]
        let nextPartID: Int
        let nextChipNumber: Int
        let nextWireID: Int
    }

    private var undoHistory: [Edit] = []
    private var redoHistory: [Edit] = []
    var canUndo: Bool { !undoHistory.isEmpty }
    var canRedo: Bool { !redoHistory.isEmpty }

    private var currentEdit: Edit {
        Edit(parts: parts, wires: wires, junctions: junctions, positions: positions, rotations: rotations,
             clockFrequencies: clockFrequencies, ledColours: ledColours,
             resistances: parts.compactMap { part in
                 guard let resistor = part.component as? Resistor else { return nil }
                 return (resistor, resistor.value, resistor.unit)
             },
             nextPartID: nextPartID, nextChipNumber: nextChipNumber, nextWireID: nextWireID)
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
        parts = edit.parts
        wires = edit.wires
        junctions = edit.junctions
        positions = edit.positions
        rotations = edit.rotations
        clockFrequencies = edit.clockFrequencies
        ledColours = edit.ledColours
        for (resistor, value, unit) in edit.resistances {
            resistor.setResistance(value, unit: unit)
        }
        nextPartID = edit.nextPartID
        nextChipNumber = edit.nextChipNumber
        nextWireID = edit.nextWireID
        rebuildNets()
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
        return kind.units.filter { !placed.contains($0) }
    }

    func nextUnit(for kind: MultiUnitChip) -> ChipUnitPlacement? {
        for packageID in packages(for: kind) {
            if let unit = availableUnits(in: packageID, kind: kind).first {
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
        guard kind.units.contains(unit) else { return }
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
        if component is CD4510 || component is CD4060 || component is SevenSegmentDriver || component is MAN74A {
            chipNumber = nextChipNumber
            nextChipNumber += 1
        } else {
            chipNumber = nil
        }
        parts.append(WorkbenchPart(id: nextPartID, name: name, component: component,
                                   unitPlacement: unitPlacement, chipNumber: chipNumber))
        nextPartID += 1
        if !engine.components.contains(where: { $0 === component }) {
            engine.addComponent(component)
        }
        settle()
    }

    func select(_ terminal: WorkbenchTerminal) {
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
        guard source != target.first, source != target.second else { return }
        recordEdit()
        let junctionID = nextWireID
        let endpoint = WorkbenchTerminal.junction(junctionID)
        junctions[junctionID] = point
        wires[index] = WorkbenchWire(id: target.id, first: target.first, second: endpoint, bends: before)
        wires.append(WorkbenchWire(id: nextWireID, first: endpoint, second: target.second, bends: after))
        wires.append(WorkbenchWire(id: nextWireID + 1, first: source, second: endpoint, bends: pendingBends))
        nextWireID += 2
        cancelWire()
        rebuildNets()
    }

    func addBend(at point: CGPoint) {
        guard selectedTerminal != nil else { return }
        pendingBends.append(point)
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
        let now = clockTime
        let budgetDeadline = now + 0.012
        var edgeCount = 0
        var stable = true
        while let index = runningClocks.indices.min(by: { runningClocks[$0].nextEdge < runningClocks[$1].nextEdge }),
              runningClocks[index].nextEdge <= now {
            runningClocks[index].source.advance()
            runningClocks[index].edgesDelivered += 1
            stable = engine.settle() && stable
            edgeCount += 1
            // Leave time for the UI and retain every unprocessed edge for the next batch.
            if edgeCount.isMultiple(of: 32), clockTime >= budgetDeadline { break }
        }
        if edgeCount > 0 {
            isStable = stable
            publishReadings()
        }
        let behind = runningClocks.contains { $0.nextEdge < now - 0.1 }
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
        let running = !runningClocks.isEmpty
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
        restore(Edit(parts: loaded.parts, wires: archive.wires, junctions: archive.junctions,
                     positions: loaded.positions, rotations: loaded.rotations,
                     clockFrequencies: loaded.frequencies, ledColours: loaded.colours, resistances: [],
                     nextPartID: (loaded.parts.map(\.id).max() ?? 0) + 1,
                     nextChipNumber: loaded.nextChipNumber,
                     nextWireID: (archive.wires.map(\.id) + Array(archive.junctions.keys)).max().map { $0 + 1 } ?? 1))
    }

    func label(for terminal: WorkbenchTerminal) -> String {
        if terminal.isJunction { return "Junction \(terminal.pinNumber)" }
        guard let part = parts.first(where: { $0.id == terminal.partID }),
              let pin = part.pins[terminal.pinNumber] else { return "" }
        return "\(part.label) · \(pin.name) (\(pin.number))"
    }

    private func rebuildNets() {
        engine = SimulationEngine()
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

        for (index, group) in groups.enumerated() {
            let net = Net(name: "Net \(index + 1)")
            for terminal in group {
                if let part = parts.first(where: { $0.id == terminal.partID }),
                   let pin = part.pins[terminal.pinNumber] {
                    net.connect(pin)
                }
            }
            engine.addNet(net)
        }
        settle()
    }

    private func settle() {
        isStable = engine.settle()
        publishReadings()
    }

    private func publishReadings() {
        let connectedPins = Set(engine.nets.flatMap { $0.pins.map(ObjectIdentifier.init) })
        var states: [WorkbenchTerminal: LogicState] = [:]
        for part in parts {
            for pin in part.pins.values {
                let terminal = WorkbenchTerminal(partID: part.id, pinNumber: pin.number)
                states[terminal] = connectedPins.contains(ObjectIdentifier(pin)) ? pin.state : pin.driveState
            }
        }
        if readings != states { readings = states }
    }
}
