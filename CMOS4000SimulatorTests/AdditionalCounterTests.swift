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

    @Test("CD4029 wraps in binary and decade modes in both directions",
          arguments: [10, 16], [false, true])
    func presettableCounter(modulus: Int, up: Bool) {
        let chip = CD4029()
        #expect(chip.pins.keys.sorted() == Array(1...16))
        #expect(CD4029.outputPins == [6, 11, 14, 2])
        #expect(CD4029.jamPins == [4, 12, 13, 3])
        for number in CD4029.jamPins { chip.pins[number]!.receive(.low) }
        chip.pins[5]!.receive(.low)
        chip.pins[9]!.receive(modulus == 16 ? .high : .low)
        chip.pins[10]!.receive(up ? .high : .low)
        chip.pins[15]!.receive(.low)
        chip.pins[1]!.receive(.high)
        chip.evaluate()
        chip.pins[1]!.receive(.low)
        for step in 0...modulus {
            let value = (modulus + (up ? step : -step)) % modulus
            #expect(readBits(chip, CD4029.outputPins) == value)
            #expect(chip.pins[7]!.driveState == (value == (up ? modulus - 1 : 0) ? .low : .high))
            chip.pins[15]!.receive(.low)
            chip.evaluate()
            #expect(readBits(chip, CD4029.outputPins) == value)
            chip.pins[15]!.receive(.high)
            chip.evaluate()
        }
    }

    @Test("CD4029 JAM overrides the clock, carry-in inhibits count, and floating controls propagate X")
    func presetAndInhibit() {
        let chip = CD4029()
        chip.pins[9]!.receive(.high)
        chip.pins[10]!.receive(.high)
        chip.pins[5]!.receive(.high)
        chip.pins[15]!.receive(.high)
        chip.pins[1]!.receive(.high)
        for number in CD4029.jamPins { chip.pins[number]!.receive(.high) }
        chip.evaluate()
        #expect(readBits(chip, CD4029.outputPins) == 15)
        #expect(chip.pins[7]!.driveState == .high)
        chip.pins[1]!.receive(.low)
        chip.pins[15]!.receive(.low)
        chip.evaluate()
        chip.pins[15]!.receive(.high)
        chip.evaluate()
        #expect(readBits(chip, CD4029.outputPins) == 15)
        chip.pins[5]!.receive(.highImpedance)
        chip.evaluate()
        #expect(chip.pins[7]!.driveState == .undefined)
        chip.pins[15]!.receive(.low)
        chip.evaluate()
        chip.pins[15]!.receive(.high)
        chip.evaluate()
        #expect(readBits(chip, CD4029.outputPins) == nil)
        #expect(chip.pins[7]!.driveState == .high) // 0 with CI low, or 15 with CI high.
        chip.pins[1]!.receive(.high)
        chip.pins[3]!.receive(.low)
        chip.evaluate()
        #expect(readBits(chip, CD4029.outputPins) == 7)
    }

    @Test("CD4029 carries synchronously to the next decade on the common clock")
    func cd4029Cascade() {
        let engine = SimulationEngine()
        engine.automaticallyPowerChips = true
        let ones = CD4029()
        let tens = CD4029()
        ones.pins[5]!.receive(.low)
        let carry = Net(name: "Carry")
        carry.connect(ones.pins[7]!)
        carry.connect(tens.pins[5]!)
        engine.addNet(carry)
        for chip in [ones, tens] {
            engine.addComponent(chip)
            for pin in CD4029.jamPins { chip.pins[pin]!.receive(.low) }
            chip.pins[9]!.receive(.low)
            chip.pins[10]!.receive(.high)
            chip.pins[1]!.receive(.high)
            chip.pins[15]!.receive(.low)
        }
        #expect(engine.settle())
        for chip in [ones, tens] { chip.pins[1]!.receive(.low) }
        for count in 1...22 {
            for chip in [ones, tens] { chip.pins[15]!.receive(.low) }
            #expect(engine.settle())
            for chip in [ones, tens] { chip.pins[15]!.receive(.high) }
            #expect(engine.settle())
            #expect(readBits(ones, CD4029.outputPins) == count % 10)
            #expect(readBits(tens, CD4029.outputPins) == count / 10)
        }
    }

    @Test("CD4029 maps both verified KiCad library identities by physical pin number")
    func cd4029Imports() throws {
        let netlist = """
        (export (components
          (comp (ref U1) (value 4029) (libsource (lib 4xxx) (part 4029)))
          (comp (ref U2) (value 4029) (libsource (lib 4xxx_IEEE) (part 4029))))
          (nets (net (code 1) (name Carry) (node (ref U1) (pin 7)) (node (ref U2) (pin 5)))))
        """
        let bench = Workbench()
        bench.importCircuit(try CircuitImportPreview.read(netlist, filenameExtension: "net"), replacing: true)
        #expect(bench.parts.count == 2)
        #expect(bench.parts.allSatisfy { $0.component is CD4029 })
        let wire = try #require(bench.wires.first)
        #expect(wire.first == WorkbenchTerminal(partID: 1, pinNumber: 7))
        #expect(wire.second == WorkbenchTerminal(partID: 2, pinNumber: 5))

        let pins = (1...16).map {
            "(pin passive line (at -2 \($0) 0) (length 1) (name ~) (number \($0)))"
        }.joined(separator: "\n")
        let schematic = """
        (kicad_sch (lib_symbols (symbol "4xxx:4029" (symbol "4029_1_1" \(pins))))
          (symbol (lib_id "4xxx:4029") (at 20 30 0) (unit 1)
            (property "Reference" "U9") (property "Value" "4029")))
        """
        bench.importCircuit(try CircuitImportPreview.read(schematic, filenameExtension: "kicad_sch"), replacing: true)
        let imported = try #require(bench.parts.first)
        #expect(imported.component is CD4029)
        #expect(imported.reference == "U9")
        #expect(imported.importedSymbol?.pins.map(\.id).sorted() == Array(1...16))
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
            let pinCount = kind.isTTL ? 14 : 16
            #expect(KiCadSymbol.additionalCounters[kind]?.terminals.map(\.id).sorted() == Array(1...pinCount))
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
        #expect(restored.parts[CounterChip.allCases.count].component === restored.parts[CounterChip.allCases.count + 1].component)
    }

    @Test("New counters lose stored state on supply loss and reset recovers them")
    func powerLoss() {
        let chips: [(any PoweredChip, [Int])] = [
            (CD4017(), [15]), (CD4026(), [15]), (CD4029(), [1]), (CD4516(), [9]),
            (DualCounter(.bcd), [7, 15]), (DualCounter(.binary), [7, 15])
        ]
        for (chip, resets) in chips {
            let engine = SimulationEngine()
            engine.addComponent(chip)
            for number in resets { chip.pins[number]!.receive(.high) }
            if chip is CD4029 {
                for number in CD4029.jamPins { chip.pins[number]!.receive(.low) }
            }
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
            if chip is CD4029 { #expect(readBits(chip, CD4029.outputPins) == nil) }
            for number in resets { chip.pins[number]!.receive(.high) }
            #expect(engine.settle())
            #expect(chip.powerState == .powered)
            if chip is CD4029 { #expect(readBits(chip, CD4029.outputPins) == 0) }
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
