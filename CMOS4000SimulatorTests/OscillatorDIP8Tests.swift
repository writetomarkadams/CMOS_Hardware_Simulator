import CoreGraphics
import Testing
@testable import CMOS4000Simulator

@MainActor
struct OscillatorDIP8Tests {
    private func pin(_ id: Int, _ number: Int = 1) -> WorkbenchTerminal {
        WorkbenchTerminal(partID: id, pinNumber: number)
    }

    private func connect(_ bench: Workbench, _ first: WorkbenchTerminal, _ second: WorkbenchTerminal) {
        bench.select(first)
        bench.select(second)
    }

    @Test func oscillatorUsesPhysicalPinsAndRunsOnlyWithPowerAndEnable() throws {
        let bench = Workbench(timeSource: { 0 })
        bench.setPowerMode(.explicit)
        let oscillator = CXO_DIP8()
        let enable = WorkbenchSwitch(showsValue: true)
        bench.add("CXO_DIP8", component: oscillator)
        bench.add("+5V", component: WorkbenchPower(.fiveVolts))
        bench.add("GND", component: WorkbenchPower(.ground))
        bench.add("Enable", component: enable)
        let geometry = SchematicPartGeometry(part: bench.parts[0], turns: 0)
        #expect(Set(geometry.pins.keys) == [1, 4, 5, 8])
        #expect(bench.parts[0].reference == "X1")
        #expect(!bench.hasRunningClocks)
        #expect(bench.readings[pin(1, 5)] == .undefined)

        connect(bench, pin(2), pin(1, 8))
        connect(bench, pin(3), pin(1, 4))
        #expect(bench.hasRunningClocks)
        bench.serviceSimulation(until: 0.51e-6)
        #expect(bench.readings[pin(1, 5)] == .high)
        bench.serviceSimulation(until: 1.01e-6)
        #expect(bench.readings[pin(1, 5)] == .low)

        connect(bench, pin(4), pin(1))
        #expect(!bench.hasRunningClocks)
        #expect(bench.readings[pin(1, 5)] == .highImpedance)
        bench.toggle(enable)
        #expect(bench.hasRunningClocks)
        let supply = try #require(bench.wires.first { $0.second == pin(1, 8) })
        bench.removeWire(supply.id)
        #expect(!bench.hasRunningClocks)
        #expect(bench.readings[pin(1, 5)] == .undefined)
    }

    @Test func frequencyUnitsPersistThroughUndoArchiveAndDuplication() throws {
        let bench = Workbench(timeSource: { 0 })
        let oscillator = CXO_DIP8()
        bench.add("CXO_DIP8", component: oscillator)
        #expect(bench.hasRunningClocks)
        let kilohertz = ClockFrequency(value: 32.768, unit: .kilohertz)
        bench.setClockFrequency(kilohertz, for: 1)
        bench.serviceSimulation(until: 15.2e-6)
        #expect(bench.readings[pin(1, 5)] == .low)
        bench.serviceSimulation(until: 15.3e-6)
        #expect(bench.readings[pin(1, 5)] == .high)

        bench.setClockFrequency(.init(value: 2.5, unit: .megahertz), for: 1)
        bench.undo()
        #expect(bench.clockFrequency(for: 1, source: oscillator) == kilohertz)
        bench.redo()
        let megahertz = ClockFrequency(value: 2.5, unit: .megahertz)
        #expect(bench.clockFrequency(for: 1, source: oscillator) == megahertz)
        bench.setClockFrequency(.init(value: 15, unit: .hertz), for: 1)
        #expect(bench.clockFrequency(for: 1, source: oscillator) == megahertz)

        let duplicate = try bench.pasteParts(bench.copyParts([1]), by: .zero)
        #expect(duplicate == [2])
        #expect(bench.parts.last?.reference == "X2")
        let reopened = Workbench(timeSource: { 0 })
        try reopened.open(WorkbenchArchive(bench: bench))
        let sources = reopened.parts.compactMap { $0.component as? CXO_DIP8 }
        #expect(sources.count == 2)
        #expect(reopened.clockFrequencies == [1: megahertz, 2: megahertz])
        #expect(reopened.hasRunningClocks)
    }
}
