import CoreGraphics
import Foundation
import Testing
@testable import CMOS4000Simulator

struct SchematicPinGeometryTests {
    @Test func allLibraryPinsStayDistinctAndOnGridThroughQuarterTurns() {
        let bench = Workbench()
        let standalone: [any LogicComponent] = [
            CD4510(), CD4060(), NE555(), MAN72A(), MAN74A(), NPN2N3904(), Resistor(), Diode1N4148(),
            WorkbenchSwitch(), WorkbenchSwitch(showsValue: true), WorkbenchPower(.ground),
            WorkbenchPower(.fiveVolts), WorkbenchClock(), WorkbenchLED(), WorkbenchPullUp()
        ]
        let families: [any LogicComponent] =
            CounterChip.allCases.map { $0.makeComponent() } +
            AnalogSwitchKind.allCases.map { AnalogSwitch($0) } +
            SevenSegmentDriverKind.allCases.map { SevenSegmentDriver($0) } +
            CapacitorKind.allCases.map { Capacitor($0) } +
            PinHeaderKind.allCases.map { PinHeader($0) }
        for component in standalone + families {
            bench.add(String(describing: type(of: component)), component: component)
        }
        for kind in MultiUnitChip.allCases {
            for unit in kind.allUnits {
                bench.addUnit(unit, kind: kind, to: bench.packages(for: kind).first)
            }
        }

        // Older archives can have off-grid card positions. The displayed pins still align.
        let position = CGPoint(x: 47.3, y: 112.8)
        for part in bench.parts {
            let base = SchematicPartGeometry(part: part, turns: 0)
            #expect(Set(base.pins.keys) == Set(part.pins.keys), "\(part.label)")
            #expect(Set(base.pins.values.map { [$0.x, $0.y] }).count == part.pins.count, "\(part.label)")
            let center = base.canvasOrigin(at: position, imported: false)
            for number in base.pins.keys {
                let initial = base.location(of: number, at: position, turns: 0, imported: false)!
                let dx = initial.x - center.x
                let dy = initial.y - center.y
                let expected = [initial, CGPoint(x: center.x - dy, y: center.y + dx),
                                CGPoint(x: center.x - dx, y: center.y - dy),
                                CGPoint(x: center.x + dy, y: center.y - dx)]
                for turns in 0..<4 {
                    let location = base.location(of: number, at: position, turns: turns, imported: false)!
                    #expect(location == WorkbenchWire.snap(location), "\(part.label) pin \(number)")
                    #expect(location == expected[turns])
                }
            }
        }
    }

    @Test func man74aHasSegmentLeadsOnTheLeftAndCathodesOnTheBottom() {
        let symbol = KiCadSymbol.man74a
        let left = symbol.terminals.filter { $0.bodyEnd.x == symbol.body.minX }
            .sorted { $0.position.y < $1.position.y }
        let bottom = symbol.terminals.filter { $0.bodyEnd.y == symbol.body.maxY }
            .sorted { $0.position.x < $1.position.x }
        #expect(left.map(\.id) == MAN74A.segmentPins)
        #expect(left.map(\.name) == ["A", "B", "C", "D", "E", "F", "G", "DP"])
        #expect(bottom.map(\.id) == MAN74A.commonPins)
        #expect(bottom.map(\.name) == ["CC", "CC"])
    }

    @Test func man74aSchematicMovesOnlyCathodeEndpointsToTheRight() throws {
        let part = WorkbenchPart(id: 1, name: "MAN74A", component: MAN74A(),
                                 unitPlacement: nil, chipNumber: nil)
        let symbol = try #require(part.librarySymbol(for: .schematic))
        let right = symbol.terminals.filter { abs($0.bodyEnd.x - symbol.body.maxX) < 0.001 }
            .sorted { $0.position.y < $1.position.y }
        #expect(right.map(\.id) == [12, 4])
        #expect(right.map(\.name) == ["CC", "CC"])
        #expect(right.allSatisfy { $0.inward.dx == -1 })
        for turns in 0...3 {
            let schematic = SchematicPartGeometry(part: part, turns: turns, appearance: .schematic)
            let physical = SchematicPartGeometry(part: part, turns: turns, appearance: .physicalDIP)
            #expect(schematic.size == physical.size)
            for number in MAN74A.segmentPins + MAN74A.commonPins {
                let location = try #require(schematic.location(of: number, at: .zero, turns: turns, imported: false))
                #expect(location == WorkbenchWire.snap(location))
                #expect((location == physical.location(of: number, at: .zero, turns: turns, imported: false))
                    == MAN74A.segmentPins.contains(number))
            }
        }
    }

    @Test func referenceSymbolsFollowPhysicalPinOrder() throws {
        let counter = try #require(KiCadSymbol.counter)
        func order(_ numbers: Set<Int>) -> [Int] {
            counter.terminals.filter { numbers.contains($0.id) }.sorted { $0.position.y < $1.position.y }.map(\.id)
        }
        #expect(order([4, 12, 13, 3, 5, 10, 15, 1, 9]) == [4, 12, 13, 3, 5, 10, 15, 1, 9])
        #expect(order([6, 11, 14, 2, 7]) == [6, 11, 14, 2, 7])
        #expect(counter.terminals.first { $0.id == 16 }?.name == "VDD")
        #expect(counter.terminals.first { $0.id == 8 }?.name == "VSS")
        let inverters = try #require(KiCadSymbol.chipUnits[.inverter])
        let pairs = [(1, 2), (3, 4), (5, 6), (9, 8), (11, 10), (13, 12)]
        for (index, pair) in pairs.enumerated() {
            let symbol = try #require(inverters[index + 1])
            #expect(symbol.terminals.first { $0.inward.dx == 1 }?.id == pair.0)
            #expect(symbol.terminals.first { $0.style == "inverted" }?.id == pair.1)
        }
        #expect(inverters[7]?.terminals.map(\.id).sorted() == [7, 14])
    }

    @Test(arguments: [0.25, 0.5, 1.0, 2.0, 4.0] as [CGFloat])
    func pinHitTargetsStayCenteredAndSeparateWhenZoomed(zoom: CGFloat) {
        var viewport = WorkbenchViewport()
        viewport.pan(x: -75, y: 260)
        viewport.zoom(to: zoom, around: CGPoint(x: 200, y: 130))
        let endpoint = CGPoint(x: 170, y: 70)
        let adjacent = CGPoint(x: 180, y: 70)
        let pitch = schematicPinSpacing(at: endpoint, among: [endpoint, adjacent])
        let width = SchematicPinButton.hitSize(zoom: zoom, spacing: pitch)
        let hitRect = CGRect(x: endpoint.x - width / 2, y: endpoint.y - width / 2, width: width, height: width)
        let screenCenter = viewport.screenPoint(at: endpoint)
        let near = CGPoint(x: screenCenter.x + width * zoom / 4, y: screenCenter.y)
        #expect(hitRect.contains(viewport.worldPoint(at: near)))
        #expect(!hitRect.contains(viewport.worldPoint(at: viewport.screenPoint(at: adjacent))))
        #expect(width * zoom <= 16)
    }

    @Test func crossingMoveRotationAndArchivePreserveElectricalMarkerState() throws {
        let bench = Workbench()
        let source = WorkbenchSwitch()
        bench.add("Switch", component: source)
        bench.add("LED", component: WorkbenchLED())
        bench.add("Crossed pin", component: WorkbenchLED())
        let positions = [CGPoint(x: 20, y: 20), CGPoint(x: 180, y: 20), CGPoint(x: 100, y: 20)]
        for (part, position) in zip(bench.parts, positions) {
            bench.placeNewPart(part.id, at: position)
        }
        let pins = bench.parts.map { WorkbenchTerminal(partID: $0.id, pinNumber: 1) }
        let start = pins[0], end = pins[1], crossed = pins[2]
        #expect(pins.allSatisfy { bench.showsOpenPinMarker($0) })
        #expect(!bench.showsOpenPinMarker(crossed, explicitNoConnect: true))
        bench.select(start)
        #expect(bench.showsOpenPinMarker(start))
        bench.addBend(at: CGPoint(x: 238, y: 71))
        bench.select(end)
        bench.toggle(source)
        let wire = try #require(bench.wires.first)
        #expect(wire.bends == [CGPoint(x: 240, y: 70)])
        #expect(!bench.showsOpenPinMarker(start))
        #expect(!bench.showsOpenPinMarker(end))
        #expect(bench.showsOpenPinMarker(crossed))
        #expect(bench.readings[end] == .high)
        #expect(bench.readings[crossed] == .highImpedance)

        bench.movePart(start.partID, from: positions[0], to: CGPoint(x: 50, y: 110))
        bench.rotatePart(end.partID, by: 1)
        let restored = Workbench()
        try restored.open(WorkbenchArchive(bench: bench))
        #expect(restored.wires.first?.first == start)
        #expect(restored.wires.first?.second == end)
        #expect(restored.wires.first?.bends == wire.bends)
        #expect(restored.rotations[end.partID] == 1)
        #expect(!restored.showsOpenPinMarker(end))
        #expect(restored.showsOpenPinMarker(crossed))
        #expect(restored.readings[end] == .high)
        restored.removeWire(wire.id)
        #expect(restored.showsOpenPinMarker(end))
        restored.undo()
        #expect(!restored.showsOpenPinMarker(end))
    }
}
