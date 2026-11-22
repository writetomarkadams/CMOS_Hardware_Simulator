import CoreGraphics
import Foundation
import Testing
@testable import CMOS4000Simulator

@MainActor
struct CD4511DIPTests {
    @Test func pinoutAndGrid() throws {
        let bench = Workbench(timeSource: { 0 })
        let decoder = SevenSegmentDriver(.cd4511)
        bench.add("CD4511", component: decoder)
        bench.add("CD4543", component: SevenSegmentDriver(.cd4543))
        let part = try #require(bench.parts.first)
        let dip = try #require(DIPPackage(part: part))
        #expect(DIPPackage(part: bench.parts[1]) == nil)
        #expect(dip.pins.map(\.name) == [
            "B", "C", "LT (active low)", "BI (active low)", "LE", "D", "A", "VSS",
            "e", "d", "c", "b", "a", "g", "f", "VDD"
        ])
        #expect(dip.pins.filter { $0.direction == .output }.map(\.number) == Array(9...15))
        #expect(dip.pins.filter { $0.direction == .power }.map(\.number) == [8, 16])
        for pin in dip.pins {
            #expect(pin === decoder.pins[pin.number])
        }
        for number in 1...8 {
            let left = try #require(dip.endpoints[number])
            let right = try #require(dip.endpoints[17 - number])
            #expect(left.x < dip.body.minX && right.x > dip.body.maxX)
            #expect(left.y == right.y && left.y == CGFloat(30 + 20 * number))
        }
        for turns in 0...3 {
            let physical = SchematicPartGeometry(part: part, turns: turns, appearance: .physicalDIP)
            let schematic = SchematicPartGeometry(part: part, turns: turns)
            #expect(Set(physical.pins.keys) == Set(schematic.pins.keys))
            #expect(physical.pins != schematic.pins)
            for number in 1...16 {
                let point = try #require(physical.location(of: number, at: CGPoint(x: 321, y: 199),
                                                           turns: turns, imported: false))
                #expect(point == WorkbenchWire.snap(point))
            }
        }
    }

    @Test func wiredDisplaySurvivesAppearanceChangesAndArchive() throws {
        let bench = Workbench(timeSource: { 0 })
        bench.add("CD4511", component: SevenSegmentDriver(.cd4511))
        bench.add("MAN74A", component: MAN74A())
        let low = WorkbenchSwitch()
        let aBit = WorkbenchSwitch()
        let latch = WorkbenchSwitch()
        let lamp = WorkbenchSwitch()
        let blank = WorkbenchSwitch()
        for source in [low, aBit, latch, lamp, blank] {
            bench.add("Switch", component: source)
        }
        bench.toggle(lamp)
        bench.toggle(blank)
        bench.add("+5V", component: WorkbenchPower(.fiveVolts))
        bench.add("GND", component: WorkbenchPower(.ground))
        bench.setPowerMode(.explicit)

        func terminal(_ part: Int, _ pin: Int = 1) -> WorkbenchTerminal {
            WorkbenchTerminal(partID: part, pinNumber: pin)
        }
        func connect(_ from: WorkbenchTerminal, _ to: WorkbenchTerminal) {
            bench.select(from)
            bench.select(to)
        }
        bench.componentAppearance = .physicalDIP
        for pin in [1, 2, 6] {
            connect(terminal(3), terminal(1, pin))
        }
        connect(terminal(4), terminal(1, 7))
        connect(terminal(5), terminal(1, 5))
        connect(terminal(6), terminal(1, 3))
        connect(terminal(7), terminal(1, 4))
        connect(terminal(8), terminal(1, 16))
        for common in [4, 12] {
            connect(terminal(9), terminal(2, common))
        }
        connect(terminal(9), terminal(1, 8))

        let outputs = [13, 12, 11, 10, 9, 15, 14]
        let segments = [14, 13, 8, 7, 6, 1, 2]
        for (output, segment) in zip(outputs, segments) {
            connect(terminal(1, output), terminal(2, segment))
        }
        let probe = ScopeProbe.pin(terminal(1, 13))
        #expect(bench.placeScopeProbe(probe))
        let net = try #require(bench.scopeNet(for: probe))

        func lit(in workbench: Workbench) throws -> [Int] {
            let display = try #require(workbench.parts[1].component as? MAN74A)
            return segments.filter { segment in
                display.isLit(segment) { workbench.readings[terminal(2, $0)] ?? .highImpedance }
            }
        }

        #expect(try lit(in: bench) == [14, 13, 8, 7, 6, 1])
        bench.toggle(latch)
        bench.toggle(aBit)
        #expect(try lit(in: bench) == [14, 13, 8, 7, 6, 1])
        bench.toggle(blank)
        #expect(try lit(in: bench).isEmpty)
        bench.toggle(lamp)
        #expect(try lit(in: bench) == segments)
        bench.toggle(lamp)
        bench.toggle(blank)
        bench.toggle(latch)
        #expect(try lit(in: bench) == [13, 8])

        bench.rotatePart(1, by: 1)
        for appearance in [ComponentAppearance.schematic, .physicalDIP] {
            bench.componentAppearance = appearance
            #expect(bench.scopeNet(for: probe) === net)
            #expect(try lit(in: bench) == [13, 8])
        }

        let encoded = try WorkbenchArchive(bench: bench).encoded()
        let reopened = Workbench(timeSource: { 0 })
        try reopened.open(JSONDecoder().decode(WorkbenchArchive.self, from: encoded))
        #expect(reopened.rotations[1] == 1)
        #expect(reopened.scopeProbes.values.contains(probe))
        for appearance in [ComponentAppearance.schematic, .physicalDIP] {
            reopened.componentAppearance = appearance
            for (output, segment) in zip(outputs, segments) {
                let source = try #require(reopened.circuitNet(at: terminal(1, output)))
                #expect(source === reopened.circuitNet(at: terminal(2, segment)))
            }
            #expect(reopened.scopeNet(for: probe) === reopened.circuitNet(at: terminal(2, 14)))
            #expect(try lit(in: reopened) == [13, 8])
        }
    }
}
