import Foundation
import Testing
@testable import CMOS4000Simulator

private func readBits(_ chip: any LogicComponent, _ numbers: [Int]) -> Int? {
    var value = 0
    for (bit, number) in numbers.enumerated() {
        switch chip.pins[number]!.driveState {
        case .high: value |= 1 << bit
        case .low: break
        default: return nil
        }
    }
    return value
}

struct AdditionalCounterTests {
    @Test("CD4017 decodes one of ten outputs, inhibits, resets, and supplies divide-by-ten carry")
    func decade() {
        let chip = CD4017()
        chip.pins[13]!.receive(.low)
        chip.pins[14]!.receive(.low)
        chip.pins[15]!.receive(.high)
        chip.evaluate()
        chip.pins[15]!.receive(.low)
        for step in 0..<21 {
            let digit = step % 10
            for (index, number) in CD4017.outputPins.enumerated() {
                #expect(chip.pins[number]!.driveState == (index == digit ? .high : .low))
            }
            #expect(chip.pins[12]!.driveState == (digit < 5 ? .high : .low))
            chip.pins[14]!.receive(.low)
            chip.evaluate()
            chip.pins[14]!.receive(.high)
            chip.evaluate()
        }
        chip.pins[13]!.receive(.high)
        chip.evaluate()
        for _ in 0..<3 {
            chip.pins[14]!.receive(.low)
            chip.evaluate()
            chip.pins[14]!.receive(.high)
            chip.evaluate()
        }
        #expect(chip.pins[2]!.driveState == .high) // Stays at 1.
        chip.pins[15]!.receive(.high)
        chip.evaluate()
        #expect(chip.pins[3]!.driveState == .high)
    }

    @Test("CD4026 produces all digit patterns, display enable, carry, and ungated c")
    func sevenSegmentCounter() {
        let chip = CD4026()
        chip.pins[1]!.receive(.low)
        chip.pins[2]!.receive(.low)
        chip.pins[3]!.receive(.high)
        chip.pins[15]!.receive(.high)
        chip.evaluate()
        chip.pins[15]!.receive(.low)
        let masks = [0x3f, 0x06, 0x5b, 0x4f, 0x66, 0x6d, 0x7d, 0x07, 0x7f, 0x6f]
        for step in 0..<20 {
            let digit = step % 10
            #expect(readBits(chip, CD4026.segmentPins) == masks[digit])
            #expect(chip.pins[5]!.driveState == (digit < 5 ? .high : .low))
            chip.pins[3]!.receive(.low)
            chip.evaluate()
            #expect(readBits(chip, CD4026.segmentPins) == 0)
            #expect(chip.pins[4]!.driveState == .low)
            #expect(chip.pins[14]!.driveState == (digit == 2 ? .low : .high))
            chip.pins[3]!.receive(.high)
            chip.evaluate()
            #expect(chip.pins[4]!.driveState == .high)
            chip.pins[1]!.receive(.low)
            chip.evaluate()
            chip.pins[1]!.receive(.high)
            chip.evaluate()
        }
        chip.pins[2]!.receive(.high)
        chip.evaluate()
        chip.pins[1]!.receive(.low)
        chip.evaluate()
        chip.pins[1]!.receive(.high)
        chip.evaluate()
        #expect(readBits(chip, CD4026.segmentPins) == masks[0])
    }

    @Test("CD4516 supports all presets, binary up/down rollover, inhibit, reset and carry")
    func binaryUpDown() {
        let chip = CD4516()
        chip.pins[9]!.receive(.low)
        chip.pins[5]!.receive(.low)
        chip.pins[10]!.receive(.high)
        chip.pins[15]!.receive(.low)
        for value in 0..<16 {
            chip.pins[1]!.receive(.high)
            for (bit, number) in CD4516.presetPins.enumerated() {
                chip.pins[number]!.receive(value & (1 << bit) == 0 ? .low : .high)
            }
            chip.evaluate()
            #expect(readBits(chip, CD4516.outputPins) == value)
        }
        chip.pins[1]!.receive(.low)
        chip.evaluate()
        #expect(chip.pins[7]!.driveState == .low)
        chip.pins[15]!.receive(.high)
        chip.evaluate()
        #expect(readBits(chip, CD4516.outputPins) == 0)
        chip.pins[10]!.receive(.low)
        chip.evaluate()
        #expect(chip.pins[7]!.driveState == .low)
        chip.pins[15]!.receive(.low)
        chip.evaluate()
        chip.pins[15]!.receive(.high)
        chip.evaluate()
        #expect(readBits(chip, CD4516.outputPins) == 15)
        chip.pins[5]!.receive(.high)
        chip.pins[15]!.receive(.low)
        chip.evaluate()
        chip.pins[15]!.receive(.high)
        chip.evaluate()
        #expect(readBits(chip, CD4516.outputPins) == 15)
        #expect(chip.pins[7]!.driveState == .high)
        chip.pins[9]!.receive(.high)
        chip.evaluate()
        #expect(readBits(chip, CD4516.outputPins) == 0)
    }

    @Test("CD4518 and CD4520 have independent units and count from both clocking inputs",
           arguments: DualCounterKind.allCases)
    func dualCounters(kind: DualCounterKind) {
        let chip = DualCounter(kind)
        for offset in [0, 8] {
            chip.pins[1 + offset]!.receive(.low)
            chip.pins[2 + offset]!.receive(.high)
            chip.pins[7 + offset]!.receive(.high)
        }
        chip.evaluate()
        chip.pins[7]!.receive(.low)
        chip.pins[15]!.receive(.low)
        for count in 1...kind.modulus * 2 {
            chip.pins[1]!.receive(.high)
            chip.evaluate()
            #expect(readBits(chip, [3, 4, 5, 6]) == count % kind.modulus)
            #expect(readBits(chip, [11, 12, 13, 14]) == 0)
            chip.pins[1]!.receive(.low)
            chip.evaluate()
        }
        chip.pins[10]!.receive(.low)
        chip.evaluate()
        #expect(readBits(chip, [11, 12, 13, 14]) == 1) // ENABLE falling with CLK low.
        chip.pins[9]!.receive(.high)
        chip.evaluate()
        #expect(readBits(chip, [11, 12, 13, 14]) == 1) // Inhibited.
        chip.pins[10]!.receive(.high)
        chip.evaluate()
        chip.pins[10]!.receive(.low)
        chip.evaluate()
        #expect(readBits(chip, [11, 12, 13, 14]) == 1) // ENABLE falling with CLK high holds.
        chip.pins[15]!.receive(.high)
        chip.evaluate()
        #expect(readBits(chip, [11, 12, 13, 14]) == 0)
    }

    @Test("New chips have symbols, correct package allocation, and save/reopen support")
    func integration() throws {
        let bench = Workbench()
        for kind in CounterChip.allCases {
            bench.add(kind.rawValue, component: kind.makeComponent())
            #expect(KiCadSymbol.additionalCounters[kind]?.terminals.map(\.id).sorted() == Array(1...16))
        }
        for kind in [MultiUnitChip.dualBCD, .dualBinary] {
            bench.addNextUnit(for: kind)
            let first = try #require(bench.parts.last)
            bench.addNextUnit(for: kind)
            #expect(bench.parts.last?.component === first.component)
            #expect(bench.parts.last?.reference == first.reference?.replacingOccurrences(of: "A", with: "B"))
            bench.addUnit(kind.powerUnit, kind: kind, to: first.unitPlacement!.packageID)
            #expect(bench.parts.last?.component === first.component)
            #expect(KiCadSymbol.chipUnits[kind]?[1]?.terminals.count == 7)
            #expect(KiCadSymbol.chipUnits[kind]?[2]?.terminals.count == 7)
            #expect(KiCadSymbol.chipUnits[kind]?[3]?.terminals.count == 2)
        }
        let data = try JSONEncoder().encode(WorkbenchArchive(bench: bench))
        let restored = Workbench()
        try restored.open(JSONDecoder().decode(WorkbenchArchive.self, from: data))
        #expect(restored.parts.map(\.name) == bench.parts.map(\.name))
        #expect(restored.parts.map(\.reference) == bench.parts.map(\.reference))
        #expect(restored.parts[3].component === restored.parts[4].component)
    }

    @Test("New counters lose stored state on supply loss and reset recovers them")
    func powerLoss() {
        let chips: [(any PoweredChip, [Int])] = [
            (CD4017(), [15]), (CD4026(), [15]), (CD4516(), [9]),
            (DualCounter(.bcd), [7, 15]), (DualCounter(.binary), [7, 15])
        ]
        for (chip, resets) in chips {
            let engine = SimulationEngine()
            engine.addComponent(chip)
            for number in resets { chip.pins[number]!.receive(.high) }
            let vdd = Pin(number: 1, name: "VDD", direction: .power)
            let vss = Pin(number: 2, name: "VSS", direction: .power)
            vdd.drivenSupplyRail = .fiveVolts
            vdd.drive(.high)
            vss.drivenSupplyRail = .ground
            vss.drive(.low)
            for (source, number) in [(vdd, 16), (vss, 8)] {
                let net = Net(name: source.name)
                net.connect(source)
                net.connect(chip.pins[number]!)
                engine.addNet(net)
            }
            #expect(engine.settle())
            for number in resets { chip.pins[number]!.receive(.low) }
            vdd.drive(.highImpedance)
            #expect(engine.settle())
            #expect(chip.pins.values.filter { $0.direction == .output }.allSatisfy { $0.driveState == .undefined })
            vdd.drive(.high)
            #expect(engine.settle())
            for number in resets { chip.pins[number]!.receive(.high) }
            #expect(engine.settle())
            #expect(chip.powerState == .powered)
        }
    }

    @Test("CD4017 carry clocks the next decade after ten input cycles")
    func decadeCascade() {
        let engine = SimulationEngine()
        engine.automaticallyPowerChips = true
        let first = CD4017()
        let second = CD4017()
        for chip in [first, second] {
            engine.addComponent(chip)
            chip.pins[13]!.receive(.low)
            chip.pins[15]!.receive(.high)
        }
        let carry = Net(name: "Carry")
        carry.connect(first.pins[12]!)
        carry.connect(second.pins[14]!)
        engine.addNet(carry)
        first.pins[14]!.receive(.low)
        #expect(engine.settle())
        for chip in [first, second] { chip.pins[15]!.receive(.low) }
        #expect(engine.settle())
        for step in 1...100 {
            first.pins[14]!.receive(.high)
            #expect(engine.settle())
            first.pins[14]!.receive(.low)
            #expect(engine.settle())
            #expect(first.pins[CD4017.outputPins[step % 10]]!.driveState == .high)
            #expect(second.pins[CD4017.outputPins[(step / 10) % 10]]!.driveState == .high)
        }
    }
}
