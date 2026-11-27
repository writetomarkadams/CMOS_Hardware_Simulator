import CoreGraphics
import Testing
@testable import CMOS4000Simulator

@MainActor
struct CD4510DIPTests {
    @Test func physicalPinoutAndGrid() throws {
        let bench = Workbench(timeSource: { 0 })
        let chip = CD4510()
        bench.add("CD4510", component: chip)
        let part = try #require(bench.parts.first)
        let package = try #require(DIPPackage(part: part))
        #expect(package.pins.map(\.name) == [
            "PE", "Q4", "P4", "P1", "CARRY_IN", "Q1", "CARRY_OUT", "VSS",
            "RESET", "UP_DOWN", "Q2", "P2", "P3", "Q3", "CLOCK", "VDD"
        ])
        #expect(package.pins.filter { $0.direction == .output }.map(\.number) == [2, 6, 7, 11, 14])
        #expect(package.pins.filter { $0.direction == .power }.map(\.number) == [8, 16])
        #expect(package.pins.filter { $0.direction == .input }.map(\.number) == [1, 3, 4, 5, 9, 10, 12, 13, 15])
        for pin in package.pins {
            #expect(pin === chip.pins[pin.number])
        }
        for row in 1...8 {
            let left = try #require(package.endpoints[row])
            let right = try #require(package.endpoints[17 - row])
            #expect(left.x < package.body.minX && right.x > package.body.maxX)
            #expect(left.y == right.y && left.y == CGFloat(30 + 20 * row))
        }
        for turns in 0...3 {
            let physical = SchematicPartGeometry(part: part, turns: turns, appearance: .physicalDIP)
            let schematic = SchematicPartGeometry(part: part, turns: turns)
            #expect(Set(physical.pins.keys) == Set(schematic.pins.keys))
            for number in physical.pins.keys {
                let point = try #require(physical.location(of: number, at: CGPoint(x: 323, y: 198),
                                                           turns: turns, imported: false))
                #expect(point == WorkbenchWire.snap(point))
            }
        }
    }

    @Test func wiresAndProbeFollowCounterThroughRotationAndMovement() throws {
        let bench = Workbench(timeSource: { 0 })
        let chip = CD4510()
        let clock = WorkbenchClock()
        let high = WorkbenchSwitch()
        let reset = WorkbenchSwitch()
        bench.add("CD4510", component: chip)
        bench.add("Clock", component: clock)
        bench.add("Low", component: WorkbenchSwitch())
        bench.add("High", component: high)
        bench.add("LED", component: WorkbenchLED())
        bench.add("Reset", component: reset)
        bench.toggle(high)
        bench.toggle(reset)

        let output = WorkbenchTerminal(partID: 1, pinNumber: 6)
        let led = WorkbenchTerminal(partID: 5, pinNumber: 1)
        bench.componentAppearance = .physicalDIP
        for (source, pin) in [(2, 15), (3, 1), (3, 5), (6, 9), (4, 10)] {
            bench.select(WorkbenchTerminal(partID: source, pinNumber: 1))
            bench.select(WorkbenchTerminal(partID: 1, pinNumber: pin))
        }
        bench.toggle(reset)
        bench.select(output)
        bench.select(led)
        let probe = ScopeProbe.pin(output)
        #expect(bench.placeScopeProbe(probe))
        let net = try #require(bench.circuitNet(at: led))

        let destination = CGPoint(x: 320, y: 200)
        let part = try #require(bench.parts.first)
        bench.rotatePart(part.id, by: 1)
        bench.movePart(part.id, from: .zero, to: destination)
        let geometry = SchematicPartGeometry(part: part, turns: 1, appearance: .physicalDIP)
        let endpoint = try #require(geometry.location(of: 6, at: destination, turns: 1, imported: false))
        let wire = try #require(bench.wires.last)
        let route = wire.route(from: endpoint, to: .zero)
        #expect(route.first == endpoint)
        #expect(zip(route, route.dropFirst()).allSatisfy { $0.x == $1.x || $0.y == $1.y })
        #expect(bench.circuitNet(at: output) === net)
        #expect(bench.scopeNet(for: probe) === net)
        #expect(bench.readings[led] == .low)
        bench.advanceClock(clock)
        #expect(chip.count == 1)
        #expect(bench.readings[led] == .high)
        bench.componentAppearance = .schematic
        #expect(bench.scopeNet(for: probe) === net)
        #expect(bench.readings[led] == .high)
    }
}
