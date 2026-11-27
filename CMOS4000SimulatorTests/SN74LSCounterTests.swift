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

extension SN74LSCounterTests {
    private struct Circuit {
        let engine = SimulationEngine()
        let chip: SN74LSCounter
        let supply = WorkbenchPower(.fiveVolts).pins[1]!
        let ground = WorkbenchPower(.ground).pins[1]!
        let clockA = driver("CKA")
        let clockB = driver("CKB")
        let resetA = driver("R0(1)")
        let resetB = driver("R0(2)")
        let presetA = driver("R9(1)")
        let presetB = driver("R9(2)")
        let weakResetB = driver("Weak reset", weak: true)
        let competingResetB = driver("Competing reset")
        let wrongSupply = WorkbenchPower(.ground).pins[1]!

        init(_ kind: CounterChip, automatic: Bool, downstream: SN74LSCounter? = nil,
             downstreamFirst: Bool = false) {
            chip = SN74LSCounter(kind)
            engine.automaticallyPowerChips = automatic
            if downstreamFirst, let downstream { engine.addComponent(downstream) }
            engine.addComponent(chip)
            if !downstreamFirst, let downstream { engine.addComponent(downstream) }

            let packages = [chip] + [downstream].compactMap { $0 }
            wire([supply, wrongSupply] + packages.map { $0.pins[5]! })
            wire([ground] + packages.map { $0.pins[10]! })
            let reset = kind == .ls92 ? (6, 7) : (2, 3)
            wire([resetA] + packages.map { $0.pins[reset.0]! })
            wire([resetB, weakResetB, competingResetB] + packages.map { $0.pins[reset.1]! })
            wire([clockA, chip.pins[14]!])
            if let downstream {
                for package in packages { wire([package.pins[12]!, package.pins[1]!]) }
                let qd = kind == .ls92 ? 8 : 11
                wire([chip.pins[qd]!, downstream.pins[14]!])
            } else {
                wire([clockB, chip.pins[1]!])
            }
            if kind == .ls90 {
                wire([presetA] + packages.map { $0.pins[6]! })
                wire([presetB] + packages.map { $0.pins[7]! })
            }

            wrongSupply.drive(.highImpedance)
            if automatic { supply.drive(.highImpedance) }
            for driver in [clockA, clockB, resetA, resetB, presetA, presetB] {
                driver.drive(.low)
            }
        }

        private static func driver(_ name: String, weak: Bool = false) -> Pin {
            Pin(number: 1, name: name, direction: .output, isWeakDriver: weak)
        }

        private func wire(_ pins: [Pin]) {
            let net = Net(name: pins[0].name)
            pins.forEach { net.connect($0) }
            engine.addNet(net)
        }

        func settle() throws { try #require(engine.settle()) }

        func drive(_ pin: Pin, _ state: LogicState) throws {
            pin.drive(state)
            try settle()
        }

        func pulse(_ pin: Pin) throws {
            try drive(pin, .high)
            try drive(pin, .low)
        }

        func expectWord(_ word: String, on package: SN74LSCounter? = nil) {
            let package = package ?? chip
            let pins = package.kind == .ls92 ? [8, 9, 11, 12] : [11, 8, 9, 12]
            let levels: [Character: LogicState] = ["0": .low, "1": .high, "X": .undefined]
            let actual = pins.map { package.pins[$0]!.driveState }
            #expect(actual == word.map { levels[$0]! }, "Expected QD–QA = \(word)")
        }
    }

    @Test(arguments: [false, true], [LogicState.undefined, .highImpedance])
    func ls90AmbiguousPresetWithReset(automatic: Bool, uncertain: LogicState) throws {
        let c = Circuit(.ls90, automatic: automatic)
        c.resetA.drive(.high)
        c.resetB.drive(.high)
        c.presetA.drive(.high)
        try c.drive(c.presetB, uncertain)
        c.expectWord("X00X")
        try c.pulse(c.clockA)
        try c.pulse(c.clockB)
        try c.settle()
        c.expectWord("X00X") // Both control outcomes suppress both clocks.

        c.resetA.drive(.low)
        try c.drive(c.presetA, .low) // Mask the uncertain R9 partner.
        c.expectWord("X00X")
        try c.pulse(c.clockB) // {0,9} → {2,1}
        c.expectWord("00XX")
        try c.settle()
        try c.settle()
        c.expectWord("00XX")
        try c.pulse(c.clockB) // {2,1} → {4,3}
        c.expectWord("0XXX")
        try c.pulse(c.clockA) // {4,3} → {5,2}
        c.expectWord("0XXX")

        c.resetA.drive(.high)
        try c.drive(c.presetA, .high)
        try c.drive(c.presetB, .high)
        c.expectWord("1001")
        try c.drive(c.presetB, .low)
        c.expectWord("0000")

        try c.drive(c.resetA, .low)
        try c.drive(c.presetB, uncertain)
        try c.pulse(c.clockB) // Preset adds nine to the two clocked candidates.
        c.expectWord("X0XX")
        try c.settle()
        c.expectWord("X0XX")
    }

    @Test(arguments: [CounterChip.ls92, .ls93], [false, true])
    func ambiguousResetAndReceiverResolution(kind: CounterChip, automatic: Bool) throws {
        let c = Circuit(kind, automatic: automatic)
        let bResetPin = kind == .ls92 ? 7 : 3
        let counted = kind == .ls92 ? "0010" : "0001"
        let ambiguous = kind == .ls92 ? "00X0" : "000X"
        let clock = kind == .ls92 ? c.clockB : c.clockA

        for uncertain in [LogicState.undefined, .highImpedance] {
            c.resetA.drive(.high)
            try c.drive(c.resetB, .high)
            try c.drive(c.resetA, .low)
            try c.pulse(clock)
            c.expectWord(counted)
            try c.drive(c.resetB, uncertain)
            c.expectWord(counted) // Known LOW masks X/Z before the reset can branch.
            try c.drive(c.resetA, .high)
            #expect(c.chip.pins[bResetPin]!.state == uncertain)
            c.expectWord(ambiguous)
            try c.settle()
            c.expectWord(ambiguous)

            try c.drive(c.resetA, .low)
            try c.pulse(kind == .ls92 ? c.clockA : c.clockB)
            c.expectWord(kind == .ls92 ? "00X1" : "001X")
            try c.settle()
            c.expectWord(kind == .ls92 ? "00X1" : "001X")
        }

        try c.drive(c.weakResetB, .high)
        #expect(c.chip.pins[bResetPin]!.state == .high)
        try c.drive(c.resetA, .high)
        c.expectWord("0000")
        try c.drive(c.resetB, .low) // Strong LOW wins over the weak pull-up.
        try c.pulse(clock)
        c.expectWord(counted)
        try c.drive(c.competingResetB, .high)
        #expect(c.chip.pins[bResetPin]!.state == .undefined)
        c.expectWord(ambiguous)
        try c.drive(c.resetB, .high)
        c.expectWord("0000")
    }

    @Test(arguments: kinds, [false, true])
    func restorationWithClockChangesWhileRailsAreInvalid(kind: CounterChip, automatic: Bool) throws {
        let c = Circuit(kind, automatic: automatic)
        c.resetA.drive(.high)
        try c.drive(c.resetB, .high)
        try c.drive(c.resetA, .low)
        try c.pulse(c.clockA)
        c.expectWord("0001")
        try c.drive(c.clockB, .high)

        try c.drive(c.supply, .highImpedance)
        c.expectWord(automatic ? "0001" : "XXXX")
        try c.drive(c.wrongSupply, .low)
        #expect(c.chip.powerState == .incorrect)
        c.expectWord(automatic ? "0001" : "XXXX")
        try c.drive(c.clockB, .low)
        c.expectWord(automatic ? "0011" : "XXXX")
        c.wrongSupply.drive(.highImpedance)
        try c.drive(c.supply, .high)
        c.expectWord(automatic ? "0011" : "XXXX")
        try c.drive(c.resetA, .high)
        c.expectWord("0000")
        try c.drive(c.resetA, .low)
        try c.settle()
        c.expectWord("0000")
        try c.pulse(c.clockB)
        c.expectWord("0010")
    }

    @Test(arguments: kinds, [false, true])
    func cascadedPackagesSettleInEitherRegistrationOrder(kind: CounterChip, downstreamFirst: Bool) throws {
        let downstream = SN74LSCounter(kind)
        let c = Circuit(kind, automatic: false, downstream: downstream, downstreamFirst: downstreamFirst)
        c.resetA.drive(.high)
        try c.drive(c.resetB, .high)
        try c.drive(c.resetA, .low)

        let sequence = kind == .ls92 ? [0, 1, 2, 3, 4, 5, 8, 9, 10, 11, 12, 13] :
            Array(0..<(kind == .ls90 ? 10 : 16))
        for step in 1...(2 * sequence.count) {
            try c.pulse(c.clockA)
            let value = sequence[step % sequence.count]
            c.expectWord((0..<4).reversed().map { value & (1 << $0) == 0 ? "0" : "1" }.joined())
            let downstreamWord = ["0000", "0001", "0010"][step / sequence.count]
            c.expectWord(downstreamWord, on: downstream)
            try c.settle()
            c.expectWord(downstreamWord, on: downstream)
        }
    }
}
