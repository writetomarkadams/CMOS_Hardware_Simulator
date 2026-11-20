import Foundation
import Testing
@testable import CMOS4000Simulator

struct CD4071Tests {
    @Test("All physical OR gates implement the four-state truth table")
    func truthTable() {
        let chip = CD4071()
        let gates = [(1, 2, 3), (5, 6, 4), (8, 9, 10), (12, 13, 11)]
        let states: [LogicState] = [.low, .high, .undefined, .highImpedance]
        #expect(chip.pins[14]?.name == "VDD")
        #expect(chip.pins[7]?.name == "VSS")
        for (a, b, output) in gates {
            for first in states {
                for second in states {
                    chip.pins[a]!.receive(first)
                    chip.pins[b]!.receive(second)
                    chip.evaluate()
                    let expected: LogicState
                    if first == .high || second == .high {
                        expected = .high
                    } else if first == .low && second == .low {
                        expected = .low
                    } else {
                        expected = .undefined
                    }
                    #expect(chip.pins[output]!.driveState == expected)
                }
            }
        }
    }

    @Test("Shared CD4071 units, symbols, supply loss, and archived wires work together")
    func workbenchIntegration() throws {
        let bench = Workbench()
        bench.setPowerMode(.explicit)
        bench.addNextUnit(for: .or)
        bench.addNextUnit(for: .or)
        #expect(bench.parts[0].component === bench.parts[1].component)
        bench.addUnit(MultiUnitChip.or.powerUnit, kind: .or, to: 1)
        bench.addUnit(MultiUnitChip.or.powerUnit, kind: .or, to: 1)
        #expect(bench.parts.count == 3)
        #expect(bench.parts[2].reference == "U1E")
        for unit in MultiUnitChip.or.allUnits {
            let symbol = try #require(KiCadSymbol.chipUnits[.or]?[unit.id])
            #expect(symbol.terminals.map(\.id).sorted() == unit.pinNumbers)
        }
        bench.add("+5V", component: WorkbenchPower(.fiveVolts))
        bench.add("GND", component: WorkbenchPower(.ground))
        bench.add("LED", component: WorkbenchLED())
        func wire(_ a: Int, _ pa: Int, _ b: Int, _ pb: Int) {
            bench.select(WorkbenchTerminal(partID: a, pinNumber: pa))
            bench.select(WorkbenchTerminal(partID: b, pinNumber: pb))
        }
        wire(4, 1, 3, 14)
        let supplyWire = try #require(bench.wires.last?.id)
        wire(5, 1, 3, 7)
        wire(5, 1, 1, 1)
        wire(4, 1, 1, 2)
        wire(1, 3, 2, 5)
        wire(5, 1, 2, 6)
        wire(2, 4, 6, 1)
        let output = WorkbenchTerminal(partID: 6, pinNumber: 1)
        #expect(bench.readings[output] == .high)

        let restored = Workbench()
        try restored.open(JSONDecoder().decode(WorkbenchArchive.self, from: JSONEncoder().encode(WorkbenchArchive(bench: bench))))
        #expect(restored.parts[0].component is CD4071)
        #expect(restored.parts[0].component === restored.parts[2].component)
        #expect(restored.readings[output] == .high)
        restored.removeWire(supplyWire)
        #expect(restored.readings[output] == .undefined)
        restored.undo()
        #expect(restored.readings[output] == .high)
        restored.removeWire(supplyWire)
        restored.setPowerMode(.automatic)
        #expect(restored.readings[output] == .high)
    }
}
