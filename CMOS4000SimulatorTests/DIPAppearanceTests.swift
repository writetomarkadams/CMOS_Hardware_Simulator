import CoreGraphics
import Foundation
import Testing
@testable import CMOS4000Simulator

@MainActor
struct DIPAppearanceTests {
    @Test func packageUsesPhysicalPinOrderAndGridAtEveryRotation() throws {
        let bench = Workbench()
        bench.add("CD4070", component: CD4070())
        bench.add("NE555", component: NE555())
        bench.addNextUnit(for: .or)
        bench.add("LED", component: WorkbenchLED())
        let part = bench.parts[0]
        let package = try #require(DIPPackage(part: part))
        #expect(package.pins.map(\.name) == ["A1", "B1", "Q1", "Q2", "A2", "B2", "GND",
                                             "A3", "B3", "Q3", "Q4", "A4", "B4", "VDD"])
        #expect(package.pins.filter { $0.direction == .power }.map(\.number) == [7, 14])
        #expect(package.pins.filter { $0.direction == .output }.map(\.number) == [3, 4, 10, 11])
        #expect(DIPPackage(part: bench.parts[1])?.pins.map(\.name) ==
                ["GND", "TRIG", "OUT", "RESET", "CONT", "THRES", "DISCH", "VCC"])
        #expect(DIPPackage(part: bench.parts[2]) == nil)
        #expect(DIPPackage(part: bench.parts[3]) == nil)

        for row in 1...7 {
            let left = try #require(package.endpoints[row])
            let right = try #require(package.endpoints[15 - row])
            #expect(left.x < package.body.minX && right.x > package.body.maxX)
            #expect(left.y == right.y && left.y == CGFloat(30 + 20 * row))
        }
        let position = CGPoint(x: 23, y: 48)
        for turns in 0...3 {
            let schematic = SchematicPartGeometry(part: part, turns: turns)
            let physical = SchematicPartGeometry(part: part, turns: turns, appearance: .physicalDIP)
            let center = physical.canvasOrigin(at: position, imported: false)
            #expect(center == schematic.canvasOrigin(at: position, imported: false))
            #expect(Set(physical.pins.keys) == Set(schematic.pins.keys))
            for (number, endpoint) in package.endpoints {
                let location = try #require(physical.location(of: number, at: position, turns: turns, imported: false))
                let offset = CGPoint(x: endpoint.x - physical.size.width / 2,
                                     y: endpoint.y - physical.size.height / 2).schematicRotated(turns)
                #expect(location == CGPoint(x: center.x + offset.x, y: center.y + offset.y))
                #expect(location == WorkbenchWire.snap(location))
            }
        }
    }

    @Test func appearancePreservesCircuitScopeAndExplicitColoursThroughReopen() throws {
        let bench = Workbench(timeSource: { 0 })
        bench.add("CD4070", component: CD4070())
        bench.add("Clock", component: WorkbenchClock())
        bench.add("LED", component: WorkbenchLED())
        let input = WorkbenchTerminal(partID: 1, pinNumber: 1)
        let output = WorkbenchTerminal(partID: 1, pinNumber: 3)
        let clock = WorkbenchTerminal(partID: 2, pinNumber: 1)
        let led = WorkbenchTerminal(partID: 3, pinNumber: 1)
        let start = CGPoint(x: 180, y: 100)
        let end = CGPoint(x: 320, y: 200)
        bench.movePart(1, from: .zero, to: start)
        bench.select(clock)
        bench.select(input)
        #expect(bench.wires.map(\.colour) == [.green])
        bench.setWireColour(.violet, for: try #require(bench.wires.first?.id))
        let probe = ScopeProbe.pin(input)
        #expect(bench.placeScopeProbe(probe))
        let net = try #require(bench.circuitNet(at: input))
        let bytes = try WorkbenchArchive(bench: bench).encoded()
        let revision = bench.circuitRevision

        bench.newWireColour = .yellow
        bench.componentAppearance = .physicalDIP
        #expect(bench.newWireColour == .black)
        #expect(try WorkbenchArchive(bench: bench).encoded() == bytes)
        #expect(bench.circuitRevision == revision)
        #expect(bench.circuitNet(at: clock) === net)
        #expect(bench.scopeNet(for: probe) === net)
        bench.select(output)
        bench.select(led)
        #expect(bench.wires.map(\.colour) == [.violet, .black])
        let wiredNet = try #require(bench.circuitNet(at: input))

        bench.rotatePart(1, by: 1)
        bench.movePart(1, from: start, to: end)
        let part = bench.parts[0]
        let geometry = SchematicPartGeometry(part: part, turns: 1, appearance: bench.componentAppearance)
        let pin = try #require(geometry.location(of: 1, at: end, turns: 1, imported: false))
        let firstWire = try #require(bench.wires.first)
        let route = firstWire.route(from: .zero, to: pin)
        #expect(route.last == pin)
        #expect(zip(route, route.dropFirst()).allSatisfy { $0.x == $1.x || $0.y == $1.y })
        #expect(bench.circuitNet(at: input) === wiredNet)
        #expect(bench.scopeNet(for: probe) === wiredNet)
        bench.componentAppearance = .schematic
        #expect(bench.newWireColour == .yellow)

        let reopened = Workbench()
        let archive = try WorkbenchArchive(bench: bench).encoded()
        try reopened.open(JSONDecoder().decode(WorkbenchArchive.self, from: archive))
        #expect(reopened.parts[0].component is CD4070)
        #expect(reopened.rotations[1] == 1)
        #expect(reopened.positions[1] == end)
        #expect(reopened.wires.map(\.colour) == [.violet, .black])
        #expect(reopened.circuitNet(at: clock) === reopened.circuitNet(at: input))
        #expect(reopened.scopeProbes[0] == probe)
        #expect(reopened.scopeNet(for: probe) != nil)
    }


    @Test func schematicPackageShowsFourXORGatesAndSharedPower() throws {
        let bench = Workbench()
        let chip = CD4070()
        bench.add("CD4070", component: chip)
        let part = try #require(bench.parts.first)
        let pinGroups = [[1, 2, 3], [4, 5, 6], [8, 9, 10], [11, 12, 13], [7, 14]]
        let position = CGPoint(x: 23, y: 48)

        for turns in 0...3 {
            let schematic = SchematicPartGeometry(part: part, turns: turns)
            let layout = try #require(schematic.xorLayout)
            #expect(layout.units.map(\.part.reference) == ["U1A", "U1B", "U1C", "U1D", "U1E"])
            #expect(layout.units.map { $0.symbol.terminals.map(\.id).sorted() } == pinGroups)
            #expect(layout.units.prefix(4).allSatisfy { !$0.symbol.polygon.isEmpty && $0.symbol.markings.count == 1 })
            let gate = layout.units[0].symbol
            #expect(gate.terminals.map(\.position.y) == [-2.54, 2.54, 0])
            #expect(gate.polygon.contains(gate.terminals[2].bodyEnd))
            #expect(gate.polygon[24].y == gate.polygon[25].y)
            #expect(gate.polygon[24].x < gate.polygon[25].x)
            #expect(layout.units.last?.symbol.polygon.isEmpty == true)
            #expect(Set(schematic.pins.values.map { [$0.x, $0.y] }).count == 14)

            let center = schematic.canvasOrigin(at: position, imported: false)
            #expect(center == CGPoint(x: 160, y: 200))
            for unit in layout.units {
                #expect(unit.part.id == part.id && unit.part.component === chip)
                let geometry = SchematicSymbolGeometry(symbol: unit.symbol, part: unit.part)
                for pin in unit.symbol.terminals {
                    let local = geometry.endpoint(pin)
                    let offset = CGPoint(x: local.x + unit.origin.x - layout.size.width / 2,
                                         y: local.y + unit.origin.y - layout.size.height / 2).schematicRotated(turns)
                    let endpoint = try #require(schematic.location(of: pin.id, at: position, turns: turns, imported: false))
                    #expect(endpoint == CGPoint(x: center.x + offset.x, y: center.y + offset.y))
                    #expect(endpoint == WorkbenchWire.snap(endpoint))
                }
            }
            let physical = SchematicPartGeometry(part: part, turns: turns, appearance: .physicalDIP)
            #expect(physical.xorLayout == nil)
            #expect(physical.canvasOrigin(at: position, imported: false) == center)
        }
    }

    @Test func individuallyPlacedGatesSharePinsAndSimulateThroughPowerUnit() throws {
        let bench = Workbench()
        for _ in 0..<4 { bench.addNextUnit(for: .xor) }
        let first = try #require(bench.parts.first)
        bench.addUnit(MultiUnitChip.xor.powerUnit, kind: .xor, to: 1)
        #expect(bench.parts.map(\.reference) == ["U1A", "U1B", "U1C", "U1D", "U1E"])
        #expect(bench.parts.allSatisfy { $0.component === first.component && DIPPackage(part: $0) == nil })
        bench.setPowerMode(.explicit)
        bench.add("VDD", component: WorkbenchPower(.fiveVolts))
        bench.add("GND", component: WorkbenchPower(.ground))

        func wire(_ source: Int, _ unit: Int, _ pin: Int) {
            bench.select(WorkbenchTerminal(partID: source, pinNumber: 1))
            bench.select(WorkbenchTerminal(partID: unit, pinNumber: pin))
        }
        for gate in QuadGate.allCases {
            wire(6, gate.rawValue, gate.terminals.inputA)
            wire(7, gate.rawValue, gate.terminals.inputB)
            #expect(bench.readings[WorkbenchTerminal(partID: gate.rawValue, pinNumber: gate.terminals.output)] == .undefined)
        }
        wire(6, 5, 14)
        wire(7, 5, 7)

        let reopened = Workbench()
        try reopened.open(WorkbenchArchive(bench: bench))
        for gate in QuadGate.allCases {
            let output = WorkbenchTerminal(partID: gate.rawValue, pinNumber: gate.terminals.output)
            #expect(bench.readings[output] == .high)
            #expect(reopened.readings[output] == .high)
        }
    }

    @Test func existingMultiUnitChipsRetainSchematicGeometryInPhysicalMode() throws {
        let bench = Workbench()
        for kind in MultiUnitChip.allCases where kind != .xor {
            bench.addNextUnit(for: kind)
            let part = try #require(bench.parts.last)
            let schematic = SchematicPartGeometry(part: part, turns: 0)
            let physical = SchematicPartGeometry(part: part, turns: 0, appearance: .physicalDIP)
            #expect(part.reference?.hasSuffix("A") == true)
            #expect(schematic.xorLayout == nil && physical.xorLayout == nil)
            #expect(DIPPackage(part: part) == nil)
            #expect(schematic.pins == physical.pins)
        }
    }

    @Test func xorUsesEachPhysicalGatePair() {
        let chip = CD4070()
        let cases: [(LogicState, LogicState, LogicState)] = [
            (.low, .low, .low), (.low, .high, .high), (.high, .low, .high),
            (.high, .high, .low), (.high, .highImpedance, .undefined),
            (.low, .undefined, .undefined)
        ]
        for gate in QuadGate.allCases {
            let (a, b, q) = gate.terminals
            for (first, second, expected) in cases {
                chip.pins[a]?.receive(first)
                chip.pins[b]?.receive(second)
                chip.evaluate()
                #expect(chip.pins[q]?.driveState == expected)
            }
        }
    }
}
