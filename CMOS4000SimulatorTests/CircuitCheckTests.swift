import Testing
@testable import CMOS4000Simulator

@MainActor
struct CircuitCheckTests {
    private func pin(_ part: Int, _ number: Int = 1) -> WorkbenchTerminal {
        WorkbenchTerminal(partID: part, pinNumber: number)
    }

    private func wire(_ bench: Workbench, _ first: WorkbenchTerminal, _ second: WorkbenchTerminal) {
        bench.select(first)
        bench.select(second)
    }

    @Test func reportsLiveCounterProblemsWithoutEditingAndClearsWhenCorrected() throws {
        let bench = Workbench()
        let reset = WorkbenchSwitch(showsValue: true)
        let stray = WorkbenchSwitch(showsValue: true)
        bench.add("CD4026", component: CD4026())
        bench.add("MAN74A", component: MAN74A())
        bench.add("Reset", component: reset)
        bench.add("Stray input", component: stray)
        bench.add("Clock", component: WorkbenchClock())
        bench.add("Ground", component: WorkbenchPower(.ground))
        bench.add("+5 V", component: WorkbenchPower(.fiveVolts))
        bench.toggle(reset)
        bench.toggle(stray)
        wire(bench, pin(5), pin(1, 1))
        wire(bench, pin(6), pin(1, 2))
        wire(bench, pin(3), pin(1, 15))
        wire(bench, pin(1, 3), pin(1, 16))
        for (output, input) in zip(CD4026.segmentPins.dropFirst(), MAN74A.segmentPins.dropFirst()) {
            wire(bench, pin(1, output), pin(2, input))
        }
        for common in MAN74A.commonPins { wire(bench, pin(6), pin(2, common)) }
        wire(bench, pin(4), pin(2, MAN74A.segmentPins[0]))

        let revision = bench.circuitRevision
        let before = try WorkbenchArchive(bench: bench).encoded()
        let findings = bench.checkCircuit()
        #expect(findings.count == 3)
        #expect(findings.contains { $0.target == .pin(pin(1, 15)) && $0.state == .high && $0.title.contains("reset") })
        #expect(findings.contains { $0.target == .pin(pin(1, 3)) && $0.state == .highImpedance })
        #expect(findings.contains {
            $0.target == .pin(pin(2, 14)) && $0.state == .high && $0.suggestion.contains("a (10)")
        })
        #expect(bench.circuitRevision == revision)
        #expect(try WorkbenchArchive(bench: bench).encoded() == before)

        bench.toggle(reset)
        let resetFinding = try #require(findings.first { $0.target == .pin(pin(1, 15)) })
        #expect(bench.currentState(for: resetFinding) == .low)
        wire(bench, pin(7), pin(1, 16))
        let wrongSegment = try #require(bench.wires.first { $0.first == pin(4) && $0.second == pin(2, 14) })
        bench.removeWire(wrongSegment.id)
        wire(bench, pin(1, 10), pin(2, 14))
        #expect(bench.checkCircuit().isEmpty)
    }

    @Test func separatesStrongOutputContentionFromFloatingExplicitPower() throws {
        let bench = Workbench()
        bench.setPowerMode(.explicit)
        bench.add("CD4026", component: CD4026())
        bench.add("+5 V", component: WorkbenchPower(.fiveVolts))
        bench.add("Ground", component: WorkbenchPower(.ground))
        wire(bench, pin(2), pin(3))
        wire(bench, pin(2), pin(1, 16))

        let findings = bench.checkCircuit()
        let conflict = try #require(findings.first { $0.id.rule == "contention" })
        #expect(findings.filter { $0.id.rule == "contention" }.count == 1)
        #expect(conflict.target == .wire(bench.wires[0].id))
        #expect(conflict.state == .undefined)
        #expect(findings.contains { $0.target == .pin(pin(1, 8)) && $0.title == "Supply pin needs GND" })
        #expect(findings.contains { $0.target == .pin(pin(1, 16)) && $0.title == "Supply pin needs +5 V" })

        bench.removeWire(bench.wires[0].id)
        wire(bench, pin(3), pin(1, 8))
        #expect(bench.checkCircuit().allSatisfy { $0.id.rule != "contention" && $0.id.rule != "supply" })
    }
}
