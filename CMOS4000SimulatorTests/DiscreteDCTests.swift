import Testing
@testable import CMOS4000Simulator

struct DiscreteDCTests {
    @Test("2N3904 gain at the onsemi 10 mA and 1 V point")
    func twoN3904Gain() throws {
        let stage = TransistorStage(baseOhms: 34_510, collectorOhms: 400, includeDiode: true)
        let point = try stage.operatingPoint()
        #expect(abs(point.vce - 1) < 1e-6)
        #expect(abs(point.collectorMA - 10) < 1e-5)
        // Characterize the current solver. onsemi specifies 100–300.
        #expect(abs(point.collectorMA / point.baseMA - 80) < 1e-3)
    }

    @Test("2N3904 saturation at the onsemi forced gain of 10", arguments: [1.0, 5.0])
    func twoN3904Saturation(baseMA: Double) throws {
        let collectorMA = 10 * baseMA
        let expectedVBE = baseMA == 1 ? 0.730 : 0.930
        let expectedVCE = baseMA == 1 ? 2.0 / 9 : 10.0 / 9
        let stage = TransistorStage(baseOhms: 1000 * (5 - expectedVBE) / baseMA,
                                    collectorOhms: 1000 * (5 - expectedVCE) / collectorMA,
                                    includeDiode: true)
        let point = try stage.operatingPoint()
        #expect(abs(point.baseMA - baseMA) < 1e-5)
        #expect(abs(point.collectorMA - collectorMA) < 1e-5)
        #expect(abs(point.vbe - expectedVBE) < 1e-6)
        // Characterize the current solver. onsemi maxima are 0.20 V and 0.30 V.
        #expect(abs(point.vce - expectedVCE) < 1e-6)
    }

    @Test("A resistive transistor stage uses DC only with an eligible network")
    func transistorStageEligibility() throws {
        let simple = TransistorStage(baseOhms: 10_000, collectorOhms: 1_000, includeDiode: false)
        #expect(simple.engine.settle())
        #expect(simple.collector.state == .low)
        #expect(simple.collector.dcVoltage == nil)
        #expect(simple.base.dcVoltage == nil)

        let eligible = TransistorStage(baseOhms: 10_000, collectorOhms: 1_000, includeDiode: true)
        let point = try eligible.operatingPoint()
        #expect((0.68...0.73).contains(point.vbe))
        #expect((0.01...0.2).contains(point.vce))

        let bypassed = TransistorStage(baseOhms: 10_000, collectorOhms: 1_000, includeDiode: true)
        bypassed.engine.addComponent(AnalogSwitch(.cd4051))
        #expect(bypassed.engine.settle())
        #expect(bypassed.collector.state == .low)
        #expect(bypassed.collector.dcVoltage == nil)
        #expect(bypassed.base.dcVoltage == nil)
    }

    @Test("BC547B gain and base voltage near the 2 mA, 5 V datasheet point")
    func bc547BGain() throws {
        // A 5 Ω sense resistor drops 10 mV at the 2 mA target.
        let stage = TransistorStage(.bc547B, baseOhms: 625818, collectorOhms: 5, includeDiode: true)
        let point = try stage.operatingPoint()
        #expect(abs(point.collectorMA - 2) < 0.002)
        #expect(abs(point.vce - 4.99) < 0.0001)
        #expect((200...450).contains(point.collectorMA / point.baseMA))
        #expect((0.55...0.70).contains(point.vbe))
    }

    @Test("BC547B saturation with forced gain of 20", arguments: [0.5, 5.0])
    func bc547BSaturation(baseMA: Double) throws {
        let collectorMA = 20 * baseMA
        let expectedVBE = baseMA == 0.5 ? 0.700 : 0.925
        let expectedVCE = baseMA == 0.5 ? 0.0537037037 : 0.5370370370
        let stage = TransistorStage(.bc547B, baseOhms: 1000 * (5 - expectedVBE) / baseMA,
                                    collectorOhms: 1000 * (5 - expectedVCE) / collectorMA,
                                    includeDiode: true)
        let point = try stage.operatingPoint()
        #expect(abs(point.baseMA - baseMA) < 1e-5)
        #expect(abs(point.collectorMA - collectorMA) < 1e-5)
        #expect(abs(point.vbe - expectedVBE) < 1e-6)
        #expect(abs(point.vce - expectedVCE) < 1e-6)
        #expect(point.vce <= (baseMA == 0.5 ? 0.25 : 0.60))
    }

    private struct TransistorStage {
        let engine = SimulationEngine()
        let base: Net
        let collector: Net
        let baseOhms: Double
        let collectorOhms: Double

        init(_ designation: TransistorDesignation = .twoN3904, baseOhms: Double, collectorOhms: Double, includeDiode: Bool) {
            self.baseOhms = baseOhms
            self.collectorOhms = collectorOhms
            let device = Transistor(designation)
            let supply = WorkbenchPower(.fiveVolts)
            let ground = WorkbenchPower(.ground)
            let baseFeed = Resistor()
            let collectorFeed = Resistor()
            let diode = Diode1N4148()
            baseFeed.setResistance(baseOhms, unit: .ohms)
            collectorFeed.setResistance(collectorOhms, unit: .ohms)
            let parts: [any LogicComponent] = [device, supply, ground, baseFeed, collectorFeed]
            for part in parts { engine.addComponent(part) }
            if includeDiode { engine.addComponent(diode) }

            let solver = engine
            func wire(_ name: String, _ pins: [Pin]) -> Net {
                let net = Net(name: name)
                for pin in pins { net.connect(pin) }
                solver.addNet(net)
                return net
            }
            // The reverse-biased diode enables DC without adding collector current.
            _ = wire("GND", [ground.pins[1]!, device.pin(.emitter)] + (includeDiode ? [diode.pins[2]!] : []))
            _ = wire("+5 V", [supply.pins[1]!, baseFeed.pins[1]!, collectorFeed.pins[1]!])
            base = wire("Base", [baseFeed.pins[2]!, device.pin(.base)])
            collector = wire("Collector", [collectorFeed.pins[2]!, device.pin(.collector)]
                             + (includeDiode ? [diode.pins[1]!] : []))
        }

        func operatingPoint() throws -> (vbe: Double, vce: Double, baseMA: Double, collectorMA: Double) {
            try #require(engine.settle())
            let vbe = try #require(base.dcVoltage)
            let vce = try #require(collector.dcVoltage)
            return (vbe, vce, 1000 * (5 - vbe) / baseOhms, 1000 * (5 - vce) / collectorOhms)
        }
    }

    @Test("The diode AND and two transistor stages resolve all four input combinations")
    func diodeTransistorCircuit() throws {
        let engine = SimulationEngine()
        let inputs = [WorkbenchSwitch(), WorkbenchSwitch()]
        let supply = WorkbenchPower(.fiveVolts)
        let ground = WorkbenchPower(.ground)
        let led = WorkbenchLED()
        let q1 = Transistor(), q2 = Transistor()
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

extension DiscreteDCTests {
    @Test("Series 2N3904 NAND follows live SPDT inputs", arguments: [true, false])
    func seriesNPNNAND(connectLowerHighThrow: Bool) {
        let engine = SimulationEngine()
        let high = WorkbenchPower(.fiveVolts), ground = WorkbenchPower(.ground)
        let upper = Transistor(), lower = Transistor()
        let a = MechanicalSwitch(.spdt), b = MechanicalSwitch(.spdt)
        let feedA = Resistor(), feedB = Resistor(), pullUp = Resistor()
        for feed in [feedA, feedB] { feed.setResistance(10, unit: .kilohms) }
        pullUp.setResistance(820, unit: .ohms)
        let parts: [any LogicComponent] = [high, ground, upper, lower, a, b, feedA, feedB, pullUp]
        for part in parts { engine.addComponent(part) }

        @discardableResult
        func wire(_ name: String, _ pins: Pin...) -> Net {
            let net = Net(name: name)
            for pin in pins { net.connect(pin) }
            engine.addNet(net)
            return net
        }

        let supply = wire("+5 V", high.pins[1]!, pullUp.pins[1]!, a.pins[3]!)
        if connectLowerHighThrow { supply.connect(b.pins[3]!) }
        wire("GND", ground.pins[1]!, lower.pins[1]!, a.pins[1]!, b.pins[1]!)
        wire("A common", a.pins[2]!, feedA.pins[1]!)
        wire("B common", b.pins[2]!, feedB.pins[1]!)
        wire("Upper base", feedA.pins[2]!, upper.pins[2]!)
        wire("Lower base", feedB.pins[2]!, lower.pins[2]!)
        let midpoint = wire("Series junction", upper.pins[1]!, lower.pins[3]!)
        let output = wire("NAND output", pullUp.pins[2]!, upper.pins[3]!)

        if !connectLowerHighThrow {
            a.toggle()
            #expect(engine.settle())
            #expect(output.state == .high)
            b.toggle()
            #expect(engine.settle())
            #expect(lower.pin(.base).state == .highImpedance)
            #expect(output.state == .undefined)
            return
        }

        let cases: [(Bool, Bool, LogicState)] = [
            (false, false, .high), (true, false, .high), (true, true, .low),
            (false, true, .high), (true, true, .low), (true, false, .high)
        ]
        for (upperHigh, lowerHigh, expected) in cases {
            if a.selectsThrow3 != upperHigh { a.toggle() }
            if b.selectsThrow3 != lowerHigh { b.toggle() }
            #expect(engine.settle())
            #expect(output.state == expected, "Upper: \(upperHigh), lower: \(lowerHigh)")
            #expect(midpoint.state == (lowerHigh ? .low : .highImpedance))
            #expect(output.dcVoltage == nil)
        }

        // A third connection makes the midpoint a different topology.
        midpoint.connect(Pin(number: 1, name: "External connection", direction: .input))
        #expect(engine.settle())
        #expect(output.state == .undefined)
    }
}
