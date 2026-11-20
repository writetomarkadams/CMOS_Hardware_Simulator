import Foundation
import Testing
@testable import CMOS4000Simulator

struct CapacitorTimingTests {
    final class Circuit {
        let engine = SimulationEngine()
        let timer = NE555()
        let cap: Capacitor
        let ra = Resistor()
        let rb = Resistor()
        let reset = WorkbenchSwitch()
        let trigger = WorkbenchSwitch()
        let vcc = WorkbenchPower(.fiveVolts)
        let ground = WorkbenchPower(.ground)
        let downstream = CD4017()
        let supply = Pin(number: 1, name: "Timer VCC", direction: .output)
        let astable: Bool

        init(astable: Bool = true, kind: CapacitorKind = .polarized, reverse: Bool = false) {
            self.astable = astable
            cap = Capacitor(kind)
            ra.setResistance(10, unit: .kilohms)
            rb.setResistance(20, unit: .kilohms)
            reset.toggle()
            trigger.toggle()
            supply.drivenSupplyRail = .fiveVolts
            supply.drive(.high)
            for component: any LogicComponent in [timer, cap, ra, rb, reset, trigger, vcc, ground, downstream] {
                engine.addComponent(component)
            }
            wire([supply, timer.pins[8]!])
            wire([ground.pins[1]!, timer.pins[1]!, cap.pins[reverse ? 1 : 2]!, downstream.pins[8]!, downstream.pins[13]!])
            wire([reset.pins[1]!, timer.pins[4]!])
            wire([vcc.pins[1]!, ra.pins[1]!, downstream.pins[16]!])
            wire([timer.pins[3]!, downstream.pins[14]!])
            if astable {
                wire([timer.pins[2]!, timer.pins[6]!, cap.pins[reverse ? 2 : 1]!, rb.pins[2]!])
                wire([timer.pins[7]!, ra.pins[2]!, rb.pins[1]!])
            } else {
                wire([timer.pins[6]!, timer.pins[7]!, cap.pins[reverse ? 2 : 1]!, ra.pins[2]!])
                wire([trigger.pins[1]!, timer.pins[2]!])
            }
            // Reset downstream counter to a known state before counting real RC edges.
            let counterReset = Pin(number: 1, name: "RST", direction: .output)
            counterReset.drive(.high)
            wire([counterReset, downstream.pins[15]!])
            engine.settle()
            counterReset.drive(.low)
            engine.settle()
        }
        func wire(_ pins: [Pin]) {
            let net = Net(name: "Test")
            for pin in pins { net.connect(pin) }
            engine.addNet(net)
        }
        @discardableResult func advance(_ time: Double, events: Int = 256) -> SimulationEngine.TimeAdvance {
            engine.advanceTime(by: time, maximumEvents: events)
        }
        var out: LogicState { timer.pins[3]!.driveState }
    }

    @Test("Capacitors validate positive finite values, remain open at DC, and import physical plates")
    func valuesAndSymbols() throws {
        for kind in CapacitorKind.allCases {
            let cap = Capacitor(kind)
            cap.setCapacitance(2.2)
            #expect(abs(cap.farads - 2.2 * kind.multiplier) < 1e-18)
            for invalid in [0, -1, Double.nan, .infinity, Double.leastNonzeroMagnitude] {
                cap.setCapacitance(invalid)
                #expect(cap.value == 2.2)
            }
            cap.pins[1]!.receive(.high)
            cap.evaluate()
            #expect(cap.pins[2]!.driveState == .highImpedance)
            let symbol = try #require(KiCadSymbol.capacitors[kind])
            #expect(symbol.terminals.map(\.id).sorted() == [1, 2])
            #expect(symbol.markings.count >= 2)
        }
    }

    @Test("NE555 capacitor follows exponential RC charging and correct astable high/low times")
    func astableTiming() {
        let circuit = Circuit()
        #expect(circuit.timer.timingIssue == nil)
        #expect(circuit.out == .high)
        // Startup begins discharged: first pulse is ln(3)*(RA+RB)*C, not the steady-state ln(2).
        let tau = 30_000 * circuit.cap.farads
        let first = log(3.0) * tau
        circuit.advance(tau * 0.5)
        #expect(abs(circuit.cap.voltage - 5 * (1 - exp(-0.5))) < 1e-9)
        #expect(circuit.out == .high)
        circuit.advance(first - tau * 0.5 + 1e-10)
        #expect(circuit.out == .low)
        let low = log(2.0) * 20_000 * circuit.cap.farads
        circuit.advance(low - 1e-8)
        #expect(circuit.out == .low)
        circuit.advance(2e-8)
        #expect(circuit.out == .high)
        let high = log(2.0) * tau
        circuit.advance(high - 1e-7)
        #expect(circuit.out == .high)
        circuit.advance(2e-7)
        #expect(circuit.out == .low)
        // Several edges in one batch must reach downstream sequential logic individually.
        let batched = Circuit()
        batched.advance(first + low + 4 * (high + low) + 1e-8)
        #expect(batched.downstream.pins[1]!.driveState == .high) // Q5 after five rising edges.
    }

    @Test("Diode steering requires a charging path and produces separate high and low phases",
          arguments: [false, true])
    func diodeSteering(hasChargingPath: Bool) {
        let engine = SimulationEngine()
        let timer = NE555()
        let capacitor = Capacitor(.polarized)
        let ra = Resistor()
        let rb = Resistor()
        let charge = Diode1N4148()
        let discharge = Diode1N4148()
        let vcc = WorkbenchPower(.fiveVolts)
        let ground = WorkbenchPower(.ground)
        ra.setResistance(10, unit: .kilohms)
        rb.setResistance(100, unit: .kilohms)
        for part: any LogicComponent in [timer, capacitor, ra, rb, charge, discharge, vcc, ground] {
            engine.addComponent(part)
        }
        func wire(_ pins: Pin...) {
            let net = Net(name: "Test")
            for pin in pins { net.connect(pin) }
            engine.addNet(net)
        }
        wire(vcc.pins[1]!, timer.pins[4]!, timer.pins[8]!, ra.pins[1]!)
        wire(ground.pins[1]!, timer.pins[1]!, capacitor.pins[2]!)
        wire(timer.pins[2]!, timer.pins[6]!, capacitor.pins[1]!, charge.pins[1]!, rb.pins[2]!)
        wire(timer.pins[7]!, discharge.pins[1]!)
        wire(charge.pins[2]!, discharge.pins[2]!, rb.pins[1]!, hasChargingPath ? ra.pins[2]! : Pin(number: 1, name: "Open", direction: .input))
        #expect(engine.settle())
        let output = timer.pins[3]!
        if !hasChargingPath {
            #expect(timer.timingIssue?.contains("no charging path") == true)
            #expect(output.driveState == .undefined)
            return
        }
        #expect(timer.timingIssue == nil)
        #expect(charge.isTimingElement && discharge.isTimingElement)
        #expect(output.driveState == .high)
        _ = engine.advanceTime(by: 0.14)
        #expect(output.driveState == .high)
        _ = engine.advanceTime(by: 0.02)
        #expect(output.driveState == .low)
        _ = engine.advanceTime(by: 0.90)
        #expect(output.driveState == .low)
        _ = engine.advanceTime(by: 0.08)
        #expect(output.driveState == .high)
        _ = engine.advanceTime(by: 0.11)
        #expect(output.driveState == .low)
    }

    @Test("R and C values determine oscillation period; nF capacitor can be reversed")
    func valueScaling() {
        for kind in CapacitorKind.allCases {
            let circuit = Circuit(kind: kind, reverse: kind == .small)
            circuit.cap.setCapacitance(kind == .small ? 1000 : 1)
            circuit.ra.setResistance(0.1, unit: .megohms)
            circuit.rb.setResistance(100, unit: .kilohms)
            let first = log(3.0) * 200_000 * circuit.cap.farads
            circuit.advance(first + 1e-10)
            #expect(circuit.out == .low)
            circuit.advance(log(2.0) * 100_000 * circuit.cap.farads + 1e-10)
            #expect(circuit.out == .high)
            #expect(circuit.timer.timingIssue == nil)
        }
    }

    @Test("Monostable pulse is ln(3)*R*C and reset aborts/discharges it")
    func monostableTiming() {
        let circuit = Circuit(astable: false)
        circuit.reset.toggle()
        circuit.engine.settle()
        #expect(circuit.out == .low)
        circuit.reset.toggle()
        circuit.trigger.toggle()
        circuit.engine.settle()
        #expect(circuit.out == .high)
        circuit.trigger.toggle()
        circuit.engine.settle()
        let width = log(3.0) * 10_000 * circuit.cap.farads
        circuit.advance(width - 1e-8)
        #expect(circuit.out == .high)
        circuit.advance(2e-8)
        #expect(circuit.out == .low)
        #expect(circuit.cap.voltage == 0)
        circuit.trigger.toggle()
        circuit.engine.settle()
        circuit.advance(width * 2)
        #expect(circuit.out == .high) // Held trigger overrides threshold.
        circuit.trigger.toggle()
        circuit.engine.settle()
        #expect(circuit.out == .low)
        circuit.trigger.toggle()
        circuit.engine.settle()
        circuit.advance(width * 0.2)
        circuit.reset.toggle()
        circuit.engine.settle()
        #expect(circuit.out == .low)
        #expect(circuit.cap.voltage == 0)
    }

    @Test("Bad polarity, unsupported timing load, and power loss do not silently oscillate")
    func invalidAndPower() {
        let reversed = Circuit(reverse: true)
        #expect(reversed.timer.timingIssue != nil)
        #expect(reversed.out == .undefined)
        #expect(!reversed.engine.hasTimingNetworks)
        let circuit = Circuit()
        circuit.advance(0.1)
        circuit.supply.drive(.highImpedance)
        circuit.engine.settle()
        #expect(circuit.out == .undefined)
        #expect(!circuit.engine.hasTimingNetworks)
        circuit.supply.drive(.high)
        circuit.engine.settle()
        #expect(circuit.out == .high) // Discharged capacitor is a valid trigger on restart.
        #expect(circuit.cap.voltage == 0)
        let extra = Capacitor(.small)
        circuit.engine.addComponent(extra)
        circuit.engine.nets.first { $0.pins.contains { $0 === circuit.timer.pins[6]! } }!.connect(extra.pins[1]!)
        circuit.engine.settle()
        #expect(circuit.timer.timingIssue != nil)
        #expect(circuit.out == .undefined)
    }

    @Test("Bounded timing batches retain elapsed time and produce the same final count")
    func boundedBatches() {
        let circuit = Circuit()
        let result = circuit.advance(2, events: 2)
        #expect(result.elapsed > 0 && result.elapsed < 2)
        #expect(result.stable)
        let rest = circuit.advance(2 - result.elapsed)
        #expect(abs(rest.elapsed + result.elapsed - 2) < 1e-10)
        let single = Circuit()
        single.advance(2)
        #expect(circuit.out == single.out)
        #expect(abs(circuit.cap.voltage - single.cap.voltage) < 1e-9)
        #expect(circuit.downstream.pins[5]!.driveState == single.downstream.pins[5]!.driveState)
    }

    @Test("Workbench RC oscillator starts automatically, schedules edges and reopens using saved R/C values")
    func workbenchOscillator() throws {
        let bench = Workbench()
        let timer = NE555()
        let cap = Capacitor(.polarized)
        let ra = Resistor()
        let rb = Resistor()
        ra.setResistance(10, unit: .kilohms)
        rb.setResistance(20, unit: .kilohms)
        bench.add("NE555", component: timer)
        bench.add("C_Polarized", component: cap)
        bench.add("RA", component: ra)
        bench.add("RB", component: rb)
        bench.add("+5V", component: WorkbenchPower(.fiveVolts))
        bench.add("GND", component: WorkbenchPower(.ground))
        func wire(_ a: Int, _ pa: Int, _ b: Int, _ pb: Int) {
            bench.select(WorkbenchTerminal(partID: a, pinNumber: pa))
            bench.select(WorkbenchTerminal(partID: b, pinNumber: pb))
        }
        wire(5, 1, 1, 8)
        wire(6, 1, 1, 1)
        wire(5, 1, 1, 4)
        wire(6, 1, 2, 2)
        wire(2, 1, 1, 6)
        wire(1, 6, 1, 2)
        wire(1, 6, 4, 2)
        wire(4, 1, 1, 7)
        wire(1, 7, 3, 2)
        wire(3, 1, 5, 1)
        bench.setPowerMode(.explicit)
        #expect(bench.timingIssues.isEmpty)
        #expect(bench.hasRunningClocks)
        #expect(timer.pins[3]!.driveState == .high)
        bench.serviceSimulation(until: bench.servicedTime + log(3.0) * 0.3 + 1e-8)
        #expect(timer.pins[3]!.driveState == .low)
        bench.setCapacitance(22, for: cap)
        bench.setResistance(30, unit: .kilohms, for: rb)
        var now = 0.0
        let restored = Workbench(timeSource: { now })
        try restored.open(JSONDecoder().decode(WorkbenchArchive.self, from: JSONEncoder().encode(WorkbenchArchive(bench: bench))))
        let reopenedTimer = try #require(restored.parts[0].component as? NE555)
        #expect(restored.hasRunningClocks)
        #expect(restored.timingIssues.isEmpty)
        #expect(reopenedTimer.pins[3]!.driveState == .high)
        let startup = log(3.0) * 40_000 * 22e-6
        now += startup + 1e-8
        restored.serviceClocks()
        #expect(reopenedTimer.pins[3]!.driveState == .low)
        // An independent manual clock shares the elapsed-time scheduler with the oscillator.
        let clock = WorkbenchClock()
        restored.add("Clock", component: clock)
        restored.runClock(clock, hertz: 2)
        now += 0.26
        restored.serviceClocks()
        #expect(clock.phase == .high)
        now += 0.25
        restored.serviceClocks()
        #expect(clock.phase == .low)
        #expect(reopenedTimer.timingIssue == nil)
        restored.stopClock(clock)
        #expect(restored.hasRunningClocks) // RC oscillator continues after manual clock stops.
        restored.clear()
        #expect(!restored.hasRunningClocks)
        restored.add("Clock", component: clock)
        restored.runClock(clock, hertz: 2)
        now += 0.26
        restored.serviceClocks()
        #expect(clock.phase == .high) // Clock-only path retains the original behaviour.
        restored.stopClock(clock)
        #expect(!restored.hasRunningClocks)
    }

    @Test("Capacitance edits Undo/Redo and save/reopen with kind, values, rotation and wires")
    func archiveAndUndo() throws {
        let bench = Workbench()
        let cap = Capacitor(.polarized)
        bench.add("C_Polarized", component: cap)
        bench.add("C_Small", component: Capacitor(.small))
        bench.setCapacitance(47, for: cap)
        bench.undo()
        #expect(cap.value == 10)
        bench.redo()
        #expect(cap.value == 47)
        bench.rotatePart(1, by: 1)
        bench.select(WorkbenchTerminal(partID: 1, pinNumber: 2))
        bench.select(WorkbenchTerminal(partID: 2, pinNumber: 1))
        let data = try JSONEncoder().encode(WorkbenchArchive(bench: bench))
        let restored = Workbench()
        try restored.open(JSONDecoder().decode(WorkbenchArchive.self, from: data))
        let opened = try #require(restored.parts[0].component as? Capacitor)
        #expect(opened.kind == .polarized && opened.value == 47)
        #expect(restored.parts[0].reference == "C1")
        #expect(restored.rotations[1] == 1)
        #expect(restored.wires.count == 1)
        let bad = String(decoding: data, as: UTF8.self).replacingOccurrences(of: "47", with: "-47")
        #expect(throws: (any Error).self) {
            try restored.open(JSONDecoder().decode(WorkbenchArchive.self, from: Data(bad.utf8)))
        }
        #expect(restored.parts.count == 2)
    }
}
