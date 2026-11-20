import Testing
@testable import CMOS4000Simulator

struct DiscreteDCTests {
    @Test("The diode AND and two transistor stages resolve all four input combinations")
    func diodeTransistorCircuit() throws {
        let engine = SimulationEngine()
        let inputs = [WorkbenchSwitch(), WorkbenchSwitch()]
        let supply = WorkbenchPower(.fiveVolts)
        let ground = WorkbenchPower(.ground)
        let led = WorkbenchLED()
        let q1 = NPN2N3904(), q2 = NPN2N3904()
        let d1 = Diode1N4148(), d2 = Diode1N4148()
        let r3 = Resistor(), r4 = Resistor(), r5 = Resistor(), r6 = Resistor(), r9 = Resistor()
        for resistor in [r3, r4, r5, r6, r9] { resistor.setResistance(10, unit: .kilohms) }
        let parts: [any LogicComponent] = [inputs[0], inputs[1], supply, ground, led, q1, q2, d1, d2, r3, r4, r5, r6, r9]
        for part in parts { engine.addComponent(part) }
        func wire(_ name: String, _ endpoints: (any LogicComponent, Int)...) -> Net {
            let net = Net(name: name)
            for (part, pin) in endpoints { net.connect(part.pins[pin]!) }
            engine.addNet(net)
            return net
        }
        _ = wire("+5V", (supply, 1), (r5, 1), (r6, 1), (r9, 1))
        _ = wire("GND", (ground, 1), (q1, 1), (q2, 1))
        _ = wire("A", (inputs[0], 1), (d1, 1))
        _ = wire("B", (inputs[1], 1), (d2, 1))
        let clamp = wire("Diode junction", (d1, 2), (d2, 2), (r9, 2), (r3, 1))
        let base = wire("Q1 base", (r3, 2), (q1, 2))
        let firstStage = wire("Q1 collector", (q1, 3), (r6, 2), (r4, 1))
        _ = wire("Q2 base", (q2, 2), (r4, 2))
        let output = wire("Output", (q2, 3), (r5, 2), (led, 1))

        for step in 0..<5 {
            if step > 0 { inputs[step.isMultiple(of: 2) ? 1 : 0].toggle() }
            let on = step == 2
            #expect(engine.settle())
            #expect(output.state == (on ? .high : .low))
            let collector = try #require(firstStage.dcVoltage)
            let baseVoltage = try #require(base.dcVoltage)
            let clampVoltage = try #require(clamp.dcVoltage)
            if on {
                #expect(collector < 0.15)
                #expect(baseVoltage > 0.68)
                #expect(clampVoltage > baseVoltage)
                // With both diodes off, the two series resistors carry the same current.
                #expect(abs((5 - clampVoltage) - (clampVoltage - baseVoltage)) < 1e-5)
            } else {
                #expect(collector > 2.5)
                #expect((0.60...0.65).contains(clampVoltage))
                #expect(abs(baseVoltage - clampVoltage) < 1e-5)
            }
        }
        for input in inputs { input.toggle() }
        r9.setResistance(10, unit: .megohms)
        #expect(engine.settle())
        #expect(output.state == .low)
        r9.setResistance(10, unit: .kilohms)
        #expect(engine.settle())
        #expect(output.state == .high)
    }
}
