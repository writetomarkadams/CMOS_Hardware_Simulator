import CoreGraphics
import Testing
@testable import CMOS4000Simulator

@MainActor
struct LED3mmTests {
    private func pin(_ id: Int, _ number: Int = 1) -> WorkbenchTerminal {
        WorkbenchTerminal(partID: id, pinNumber: number)
    }

    private func connect(_ bench: Workbench, _ first: WorkbenchTerminal, _ second: WorkbenchTerminal) {
        bench.select(first)
        bench.select(second)
    }

    @Test func seriesResistorLetsForwardBiasedLEDLight() throws {
        let bench = Workbench()
        let source = WorkbenchSwitch(showsValue: true)
        let resistor = Resistor()
        resistor.setResistance(330, unit: .ohms)
        bench.add("LED_D3.0mm", component: LED3mm())
        bench.add("Resistor", component: resistor)
        bench.add("Switch", component: source)
        bench.add("GND", component: WorkbenchPower(.ground))

        #expect(bench.parts[0].reference == "D1")
        #expect(bench.parts[0].pins[1]?.name == "K")
        #expect(bench.parts[0].pins[2]?.name == "A")
        #expect(Set(SchematicPartGeometry(part: bench.parts[0], turns: 1).pins.keys) == [1, 2])
        connect(bench, pin(3), pin(2))
        connect(bench, pin(2, 2), pin(1, 2))
        bench.toggle(source)
        #expect(bench.illuminatedLEDs.isEmpty)
        connect(bench, pin(4), pin(1))
        #expect(bench.illuminatedLEDs == [1])
        let voltage = try #require(bench.circuitNet(at: pin(1, 2))?.dcVoltage)
        #expect(abs(voltage - (1.8 + 3.2 * 20 / 350)) < 1e-6)

        let reopened = Workbench()
        try reopened.open(WorkbenchArchive(bench: bench))
        #expect(reopened.parts[0].component is LED3mm)
        #expect(reopened.illuminatedLEDs == [1])
        #expect(try bench.pasteParts(bench.copyParts([1]), by: .zero) == [5])
        #expect(bench.illuminatedLEDs == [1])

        bench.toggle(source)
        #expect(bench.illuminatedLEDs.isEmpty)
        bench.toggle(source)
        let leads = bench.wires.filter { $0.second.partID == 1 }
        for lead in leads { bench.removeWire(lead.id) }
        connect(bench, pin(2, 2), pin(1))
        connect(bench, pin(4), pin(1, 2))
        #expect(bench.illuminatedLEDs.isEmpty)
    }

    @Test func importsMatchingKiCadSymbolAndFootprint() throws {
        let input = """
        (export (components
          (comp (ref D8) (value LED) (footprint LED_THT:LED_D3.0mm) (libsource (lib Device) (part LED)))
          (comp (ref D9) (value LED) (footprint LED_THT:LED_D5.0mm) (libsource (lib Device) (part LED))))
          (nets (net (code 1) (name GND) (node (ref D8) (pin 1)))
                (net (code 2) (name +5V) (node (ref D8) (pin 2)))))
        """
        let preview = try CircuitImportPreview.read(input, filenameExtension: "net")
        #expect(preview.supportedCount == 1)
        let bench = Workbench()
        _ = bench.importCircuit(preview, replacing: true)
        let part = try #require(bench.parts.first { $0.component is LED3mm })
        #expect(part.reference == "D8")
        #expect(bench.illuminatedLEDs == [part.id])
    }
}
