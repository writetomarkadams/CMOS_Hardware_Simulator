import CoreGraphics
import Foundation
import Testing
@testable import CMOS4000Simulator

@MainActor
struct SN74LSCounterTests {
    private nonisolated static let kinds: [CounterChip] = [.ls90, .ls92, .ls93]

    private func terminal(_ part: Int, _ pin: Int = 1) -> WorkbenchTerminal {
        WorkbenchTerminal(partID: part, pinNumber: pin)
    }

    private func connect(_ bench: Workbench, _ first: WorkbenchTerminal, _ second: WorkbenchTerminal) {
        bench.select(first)
        bench.select(second)
    }

    private func outputPins(_ kind: CounterChip) -> [Int] {
        kind == .ls92 ? [12, 11, 9, 8] : [12, 9, 8, 11]
    }

    private func resetPins(_ kind: CounterChip) -> [Int] { kind == .ls92 ? [6, 7] : [2, 3] }

    private func expectOutput(_ bench: Workbench, _ kind: CounterChip, _ pattern: Int?) {
        for (bit, pin) in outputPins(kind).enumerated() {
            let expected: LogicState = pattern.map { $0 & (1 << bit) == 0 ? .low : .high } ?? .undefined
            #expect(bench.readings[terminal(1, pin)] == expected, "Physical pin \(pin), pattern \(String(describing: pattern))")
        }
    }

    private func addInput(_ bench: Workbench, pins: [Int]) -> WorkbenchSwitch {
        let source = WorkbenchSwitch()
        bench.add("Input", component: source)
        let id = bench.parts.last!.id
        for pin in pins { connect(bench, terminal(id), terminal(1, pin)) }
        return source
    }

    @Test(arguments: kinds)
    func independentlyClockedSections(kind: CounterChip) {
        let bench = Workbench()
        bench.add(kind.rawValue, component: kind.makeComponent())
        let reset = addInput(bench, pins: resetPins(kind))
        if kind == .ls90 { _ = addInput(bench, pins: [6]) }
        expectOutput(bench, kind, nil)
        bench.toggle(reset)
        expectOutput(bench, kind, 0)
        bench.toggle(reset)

        let a = addInput(bench, pins: [14])
        let b = addInput(bench, pins: [1])
        for expected in [1, 0, 1] {
            expectOutput(bench, kind, 1 - expected)
            bench.toggle(a)
            expectOutput(bench, kind, 1 - expected)
            bench.toggle(a)
            expectOutput(bench, kind, expected)
        }

        let patterns = kind == .ls90 ? [0, 2, 4, 6, 8] :
            kind == .ls92 ? [0, 2, 4, 8, 10, 12] : [0, 2, 4, 6, 8, 10, 12, 14]
        for (current, next) in zip(patterns, patterns.dropFirst() + [0]) {
            bench.toggle(b)
            expectOutput(bench, kind, current | 1)
            bench.toggle(b)
            expectOutput(bench, kind, next | 1)
        }
        bench.toggle(a)
        bench.toggle(reset)
        bench.toggle(a) // Falling edge during asynchronous reset.
        expectOutput(bench, kind, 0)
        bench.toggle(reset)
        expectOutput(bench, kind, 0)
    }

    @Test(arguments: kinds)
    func cascadedCountSequence(kind: CounterChip) {
        let bench = Workbench()
        bench.add(kind.rawValue, component: kind.makeComponent())
        let reset = addInput(bench, pins: resetPins(kind))
        if kind == .ls90 { _ = addInput(bench, pins: [6, 7]) }
        let clock = WorkbenchClock()
        bench.add("Clock Source", component: clock)
        connect(bench, terminal(bench.parts.last!.id), terminal(1, 14))
        connect(bench, terminal(1, 12), terminal(1, 1))
        bench.toggle(reset)
        bench.toggle(reset)
        let patterns = kind == .ls92 ? [0, 1, 2, 3, 4, 5, 8, 9, 10, 11, 12, 13] :
            Array(0..<(kind == .ls90 ? 10 : 16))
        for (current, next) in zip(patterns + patterns, (patterns + patterns).dropFirst() + [0]) {
            bench.advanceClock(clock)
            expectOutput(bench, kind, current)
            bench.advanceClock(clock)
            expectOutput(bench, kind, next)
        }
    }

    @Test func ls90BiQuinaryCount() {
        let bench = Workbench()
        bench.add("SN74LS90", component: CounterChip.ls90.makeComponent())
        let reset = addInput(bench, pins: [2, 3])
        _ = addInput(bench, pins: [7])
        let clock = addInput(bench, pins: [1])
        connect(bench, terminal(1, 11), terminal(1, 14))
        bench.toggle(reset)
        bench.toggle(reset)
        for pattern in [2, 4, 6, 8, 1, 3, 5, 7, 9, 0] {
            bench.toggle(clock)
            bench.toggle(clock)
            expectOutput(bench, .ls90, pattern)
        }
    }

    @Test(arguments: Array(0..<16))
    func ls90ResetPresetTruthTable(controlBits: Int) {
        let bench = Workbench()
        bench.add("SN74LS90", component: CounterChip.ls90.makeComponent())
        let controls = [2, 3, 6, 7].map { addInput(bench, pins: [$0]) }
        let clock = addInput(bench, pins: [14])
        connect(bench, terminal(1, 12), terminal(1, 1))
        for (index, control) in controls.enumerated() where controlBits & (1 << index) != 0 {
            bench.toggle(control)
        }
        if controlBits & 12 == 12 {
            expectOutput(bench, .ls90, 9)
            for control in controls.prefix(2).enumerated() where controlBits & (1 << control.offset) != 0 {
                bench.toggle(control.element)
            }
            bench.toggle(controls[2])
            expectOutput(bench, .ls90, 9)
            bench.toggle(clock)
            bench.toggle(clock)
            expectOutput(bench, .ls90, 0)
        } else if controlBits & 3 == 3 {
            expectOutput(bench, .ls90, 0)
            bench.toggle(clock)
            bench.toggle(clock)
            expectOutput(bench, .ls90, 0)
        } else {
            expectOutput(bench, .ls90, nil)
            // Set to nine, then restore this combination and verify counting resumes.
            for index in 2...3 where controlBits & (1 << index) == 0 { bench.toggle(controls[index]) }
            for index in 2...3 where controlBits & (1 << index) == 0 { bench.toggle(controls[index]) }
            bench.toggle(clock)
            bench.toggle(clock)
            expectOutput(bench, .ls90, 0)
        }
    }

    @Test(arguments: kinds)
    func explicitPowerAndNoConnectPins(kind: CounterChip) throws {
        let bench = Workbench()
        let chip = SN74LSCounter(kind)
        bench.add(kind.rawValue, component: chip)
        let reset = addInput(bench, pins: resetPins(kind))
        if kind == .ls90 { _ = addInput(bench, pins: [6]) }
        let nc = chip.pins.values.filter { $0.direction == .noConnect }.map(\.number).sorted()
        #expect(nc == (kind == .ls90 ? [4, 13] : kind == .ls92 ? [2, 3, 4, 13] : [4, 6, 7, 13]))
        _ = addInput(bench, pins: nc)
        #expect(nc.allSatisfy { chip.pins[$0]?.driveState == .highImpedance })
        bench.toggle(reset)
        expectOutput(bench, kind, 0)

        bench.setPowerMode(.explicit)
        expectOutput(bench, kind, nil)
        bench.add("+5V", component: WorkbenchPower(.fiveVolts))
        let vcc = terminal(bench.parts.last!.id)
        bench.add("GND", component: WorkbenchPower(.ground))
        let ground = terminal(bench.parts.last!.id)
        connect(bench, ground, terminal(1, 10))
        connect(bench, ground, terminal(1, 5))
        #expect(chip.powerState == .incorrect)
        expectOutput(bench, kind, nil)
        bench.removeWire(try #require(bench.wires.last).id)
        connect(bench, vcc, terminal(1, 5))
        #expect(chip.powerState == .powered)
        expectOutput(bench, kind, 0)
        bench.toggle(reset)
        bench.removeWire(try #require(bench.wires.last).id)
        expectOutput(bench, kind, nil)
        connect(bench, vcc, terminal(1, 5))
        expectOutput(bench, kind, nil)
        bench.toggle(reset)
        expectOutput(bench, kind, 0)
    }

    @Test(arguments: [0.79, 0.81, 1.99, 2.01])
    func classifiesSolvedClockVoltage(target: Double) throws {
        let bench = Workbench()
        let upper = Resistor()
        let lower = Resistor()
        upper.setResistance(5 - target, unit: .kilohms)
        lower.setResistance(target, unit: .kilohms)
        bench.add("SN74LS93", component: CounterChip.ls93.makeComponent())
        bench.add("+5V", component: WorkbenchPower(.fiveVolts))
        bench.add("GND", component: WorkbenchPower(.ground))
        bench.add("Upper", component: upper)
        bench.add("Lower", component: lower)
        bench.add("LED", component: LED3mm())
        // A reverse-biased LED makes this net eligible for the existing DC solver.
        connect(bench, terminal(2), terminal(4))
        connect(bench, terminal(3), terminal(5, 2))
        connect(bench, terminal(3), terminal(6, 2))
        connect(bench, terminal(4, 2), terminal(5))
        connect(bench, terminal(6), terminal(5))

        let reset = addInput(bench, pins: [2, 3])
        bench.toggle(reset)
        bench.toggle(reset)
        connect(bench, terminal(1, 14), terminal(5))
        let voltage = try #require(bench.circuitNet(at: terminal(1, 14))?.dcVoltage)
        #expect(abs(voltage - target) < 1e-6)
        let expected: LogicState = target < 0.8 ? .low : target > 2 ? .high : .undefined
        #expect(bench.readings[terminal(1, 14)] == expected)
        expectOutput(bench, .ls93, 0)
        bench.removeWire(try #require(bench.wires.last).id)
        #expect(bench.readings[terminal(1, 14)] == .highImpedance)
        connect(bench, terminal(1, 14), terminal(3))
        expectOutput(bench, .ls93, 0) // Open to LOW is not a falling edge.
    }

    @Test(arguments: kinds)
    func kiCadGeometryAndArchive(kind: CounterChip) throws {
        let reset = resetPins(kind)
        let symbol = kind.rawValue.dropFirst(2)
        let preset = kind == .ls90 ? "(node (ref U1) (pin 6))" : ""
        let input = """
        (export (components
          (comp (ref U1) (value \(kind.rawValue)) (libsource (lib 74xx) (part \(symbol)))))
          (nets
            (net (code 1) (name +5V) (node (ref U1) (pin 5))
              (node (ref U1) (pin \(reset[0]))) (node (ref U1) (pin \(reset[1]))))
            (net (code 2) (name GND) (node (ref U1) (pin 10)) \(preset))))
        """
        let bench = Workbench()
        let preview = try CircuitImportPreview.read(input, filenameExtension: "net")
        #expect(preview.supportedCount == 1)
        bench.importCircuit(preview, replacing: true)
        bench.setPowerMode(.explicit)
        let part = try #require(bench.parts.first)
        let dip = try #require(DIPPackage(part: part))
        #expect(dip.pins.map(\.number) == Array(1...14))
        let pinouts: [CounterChip: [String]] = [
            .ls90: ["CKB", "R0(1)", "R0(2)", "NC", "VCC", "R9(1)", "R9(2)", "QC", "QB", "GND", "QD", "QA", "NC", "CKA"],
            .ls92: ["CKB", "NC", "NC", "NC", "VCC", "R0(1)", "R0(2)", "QD", "QC", "GND", "QB", "QA", "NC", "CKA"],
            .ls93: ["CKB", "R0(1)", "R0(2)", "NC", "VCC", "NC", "NC", "QC", "QB", "GND", "QD", "QA", "NC", "CKA"]
        ]
        #expect(dip.pins.map(\.name) == pinouts[kind])
        #expect(dip.endpoints[1]?.y == dip.endpoints[14]?.y)
        #expect(dip.endpoints[7]?.y == dip.endpoints[8]?.y)
        for turns in 0...3 {
            for appearance in ComponentAppearance.allCases {
                let geometry = SchematicPartGeometry(part: part, turns: turns, appearance: appearance)
                let endpoints = try (1...14).map { pin in
                    try #require(geometry.location(of: pin, at: .zero, turns: turns, imported: false))
                }
                #expect(Set(endpoints).count == 14)
                #expect(endpoints.allSatisfy { WorkbenchWire.snap($0) == $0 })
            }
        }
        expectOutput(bench, kind, 0)
        bench.componentAppearance = .physicalDIP
        bench.rotatePart(part.id, by: 1)
        let data = try WorkbenchArchive(bench: bench).encoded()
        let reopened = Workbench()
        try reopened.open(JSONDecoder().decode(WorkbenchArchive.self, from: data))
        #expect((reopened.parts.first?.component as? SN74LSCounter)?.kind == kind)
        #expect(reopened.componentAppearance == .physicalDIP)
        #expect(reopened.rotations[part.id] == 1)
        #expect(reopened.powerMode == .explicit)
        expectOutput(reopened, kind, 0)
    }
}
