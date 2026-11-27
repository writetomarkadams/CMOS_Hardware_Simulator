import Testing
@testable import CMOS4000Simulator

struct SevenSegmentPowerTests {
    private struct Circuit {
        let engine = SimulationEngine()
        let chip: SevenSegmentDriver
        let display: SevenSegmentDisplay
        let inverter = CD40106()
        let supply = WorkbenchPower(.fiveVolts).pins[1]!
        let ground = WorkbenchPower(.ground).pins[1]!
        let vdd = WorkbenchPower(.fiveVolts).pins[1]!
        let vss = WorkbenchPower(.ground).pins[1]!
        let phase: LogicState
        var is4511: Bool { chip.kind == .cd4511 }

        init(kind: SevenSegmentDriverKind, phase: LogicState = .low, automatic: Bool = false) {
            precondition(kind == .cd4543 || phase == .low)
            self.phase = phase
            chip = SevenSegmentDriver(kind)
            display = phase == .high ? MAN72A() : MAN74A()
            engine.automaticallyPowerChips = automatic
            engine.addComponent(chip)
            engine.addComponent(display)
            engine.addComponent(inverter)
            connect([vdd, chip.pins[16]!])
            connect([vss, chip.pins[8]!])
            connect([supply, inverter.pins[14]!] + (phase == .high ? commons : []))
            connect([ground, inverter.pins[7]!] + (phase == .low ? commons : []))
            for (index, output) in chip.kind.outputs.enumerated() {
                let pins = [chip.pins[output]!, display.pins[display.segmentNumbers[index]]!]
                connect(index == 0 ? pins + [inverter.pins[1]!] : pins)
            }
            if automatic {
                vdd.drive(.highImpedance)
                vss.drive(.highImpedance)
            }
            if is4511 {
                lamp(false)
            } else {
                chip.pins[6]!.receive(phase)
            }
            blank(false)
        }

        private var commons: [Pin] { display.commonNumbers.map { display.pins[$0]! } }

        private func connect(_ pins: [Pin]) {
            let net = Net(name: "Fixture")
            for pin in pins { net.connect(pin) }
            engine.addNet(net)
        }

        func hold(_ enabled: Bool) {
            chip.pins[is4511 ? 5 : 1]!.receive(enabled == is4511 ? .high : .low)
        }

        func blank(_ enabled: Bool) {
            chip.pins[is4511 ? 4 : 7]!.receive(enabled != is4511 ? .high : .low)
        }

        func lamp(_ enabled: Bool) {
            chip.pins[3]!.receive(enabled ? .low : .high)
        }

        func code(_ value: Int) {
            for (bit, pin) in chip.kind.inputs.enumerated() {
                chip.pins[pin]!.receive(value & (1 << bit) == 0 ? .low : .high)
            }
        }

        func connectInput(_ number: Int, to drivers: [Pin]) {
            connect([chip.pins[number]!] + drivers)
        }

        // Letters specify raw output levels in segment a–g order.
        func expectLevels(_ levels: String, sourceLocation: SourceLocation = #_sourceLocation) throws {
            try #require(engine.settle(), sourceLocation: sourceLocation)
            for (index, level) in levels.enumerated() {
                let expected: LogicState = level == "H" ? .high : (level == "L" ? .low : .undefined)
                let segment = display.segmentNumbers[index]
                #expect(chip.pins[chip.kind.outputs[index]]!.driveState == expected,
                        sourceLocation: sourceLocation)
                #expect(display.pins[segment]!.state == expected, sourceLocation: sourceLocation)
                #expect(display.isLit(segment) { display.pins[$0]!.state } == (expected == phase.inverted),
                        sourceLocation: sourceLocation)
                if index == 0 {
                    #expect(inverter.pins[2]!.driveState == expected.inverted, sourceLocation: sourceLocation)
                }
            }
        }

        // nil represents X on every segment. An empty string represents definite blanking.
        func expectSegments(_ lit: String?, sourceLocation: SourceLocation = #_sourceLocation) throws {
            let levels = lit.map { glyph in
                String("abcdefg".map { glyph.contains($0) == (phase == .low) ? "H" : "L" })
            } ?? "XXXXXXX"
            try expectLevels(levels, sourceLocation: sourceLocation)
        }
    }

    @Test(arguments: SevenSegmentDriverKind.allCases, [false, true])
    func datasheetGlyphs(kind: SevenSegmentDriverKind, automatic: Bool) throws {
        let glyphs = kind == .cd4511
            ? ["abcdef", "bc", "abdeg", "abcdg", "bcfg", "acdfg", "cdefg", "abc", "abcdefg", "abcfg"]
            : ["abcdef", "bc", "abdeg", "abcdg", "bcfg", "acdfg", "acdefg", "abc", "abcdefg", "abcdfg"]
        for phase: LogicState in kind == .cd4511 ? [.low] : [.low, .high] {
            let circuit = Circuit(kind: kind, phase: phase, automatic: automatic)
            circuit.hold(false)
            for code in 0...15 {
                circuit.code(code)
                try circuit.expectSegments(code < glyphs.count ? glyphs[code] : "")
            }
        }
    }

    @Test(arguments: SevenSegmentDriverKind.allCases, [LogicState.undefined, .highImpedance])
    func partialInputsAndAmbiguousLatch(kind: SevenSegmentDriverKind, uncertain: LogicState) throws {
        for automatic in [false, true] {
            let circuit = Circuit(kind: kind, automatic: automatic)
            let latch = circuit.chip.pins[circuit.is4511 ? 5 : 1]!
            let a = circuit.chip.pins[circuit.chip.kind.inputs[0]]!
            circuit.hold(false)
            circuit.code(0)
            a.receive(uncertain)
            try circuit.expectLevels("XHHXXXL")
            circuit.hold(true)
            circuit.code(8)
            try circuit.expectLevels("XHHXXXL")

            circuit.hold(false)
            circuit.code(1)
            try circuit.expectSegments("bc")
            latch.receive(uncertain)
            try circuit.expectSegments("bc")
            circuit.code(2)
            for _ in 0..<3 {
                // Candidates are 1 and 2. Expanding uncertain bits independently
                // would also admit 0 and 3 and lose certainty on segment f.
                try circuit.expectLevels("XHXXXLX")
            }
            circuit.hold(true)
            circuit.code(8)
            try circuit.expectLevels("XHXXXLX")
            circuit.hold(false)
            try circuit.expectSegments("abcdefg")
        }
    }

    @Test(arguments: [LogicState.undefined, .highImpedance])
    func cd4511LampAndBlankBranches(uncertain: LogicState) throws {
        let circuit = Circuit(kind: .cd4511)
        circuit.hold(false)
        circuit.code(8)
        try circuit.expectSegments("abcdefg")
        circuit.hold(true)
        circuit.code(1)
        circuit.chip.pins[3]!.receive(uncertain)
        try circuit.expectSegments("abcdefg")
        circuit.blank(true)
        try circuit.expectSegments(nil)
        circuit.lamp(true)
        try circuit.expectSegments("abcdefg")
        circuit.lamp(false)
        try circuit.expectSegments("")
        circuit.blank(false)
        try circuit.expectSegments("abcdefg")

        circuit.hold(false)
        circuit.chip.pins[4]!.receive(uncertain)
        try circuit.expectLevels("LXXLLLL")
        circuit.lamp(true)
        circuit.code(2)
        try circuit.expectSegments("abcdefg")
        circuit.hold(true)
        circuit.code(8)
        circuit.lamp(false)
        circuit.blank(false)
        try circuit.expectSegments("abdeg")

        circuit.hold(false)
        circuit.blank(true)
        circuit.code(6)
        try circuit.expectSegments("")
        circuit.hold(true)
        circuit.code(8)
        circuit.blank(false)
        try circuit.expectSegments("cdefg")
    }

    @Test(arguments: [LogicState.undefined, .highImpedance])
    func cd4543BlankAndPhaseBranches(uncertain: LogicState) throws {
        for phase: LogicState in [.low, .high] {
            let circuit = Circuit(kind: .cd4543, phase: phase)
            circuit.hold(false)
            circuit.code(10)
            try circuit.expectSegments("")
            circuit.hold(true)
            circuit.code(8)
            circuit.chip.pins[7]!.receive(uncertain)
            try circuit.expectSegments("")
            circuit.blank(true)
            circuit.chip.pins[6]!.receive(uncertain)
            try circuit.expectSegments(nil)
            circuit.chip.pins[6]!.receive(phase)
            circuit.blank(false)
            try circuit.expectSegments("")

            circuit.hold(false)
            circuit.blank(true)
            circuit.code(9)
            try circuit.expectSegments("")
            circuit.hold(true)
            circuit.code(8)
            circuit.blank(false)
            try circuit.expectSegments("abcdfg")
        }
    }

    @Test(arguments: SevenSegmentDriverKind.allCases, [false, true])
    func resolvedDataPullAndContention(kind: SevenSegmentDriverKind, automatic: Bool) throws {
        let circuit = Circuit(kind: kind, phase: kind == .cd4543 ? .high : .low, automatic: automatic)
        let a = circuit.chip.kind.inputs[0]
        let pull = Pin(number: 1, name: "Weak pull", direction: .output, isWeakDriver: true)
        let first = Pin(number: 1, name: "First source", direction: .output)
        let second = Pin(number: 1, name: "Second source", direction: .output)
        circuit.code(0)
        circuit.connectInput(a, to: [pull, first, second])
        circuit.hold(false)
        let partial = kind == .cd4511 ? "XHHXXXL" : "XLLXXXH"
        try circuit.expectLevels(partial)
        #expect(circuit.chip.pins[a]!.state == .highImpedance)
        pull.drive(.high)
        try circuit.expectSegments("bc")
        first.drive(.low)
        try circuit.expectSegments("abcdef")
        second.drive(.high)
        try circuit.expectLevels(partial)
        #expect(circuit.chip.pins[a]!.state == .undefined)
        circuit.hold(true)
        second.drive(.highImpedance)
        try circuit.expectLevels(partial)
        #expect(circuit.chip.pins[a]!.state == .low)
        circuit.hold(false)
        try circuit.expectSegments("abcdef")
    }

    @Test(arguments: SevenSegmentDriverKind.allCases, [false, true])
    func captureHoldAndInvalidBCD(kind: SevenSegmentDriverKind, automatic: Bool) throws {
        for phase: LogicState in kind == .cd4511 ? [.low] : [.low, .high] {
            let circuit = Circuit(kind: kind, phase: phase, automatic: automatic)
            circuit.hold(true)
            circuit.code(2)
            try circuit.expectSegments(nil)
            circuit.hold(false)
            try circuit.expectSegments("abdeg")
            circuit.hold(true)
            circuit.code(5)
            try circuit.expectSegments("abdeg")
            circuit.hold(false)
            try circuit.expectSegments("acdfg")

            for invalid in 10...15 {
                circuit.hold(false)
                circuit.code(invalid)
                try circuit.expectSegments("")
                circuit.hold(true)
                circuit.code(1)
                try circuit.expectSegments("")
            }
            circuit.hold(false)
            try circuit.expectSegments("bc")
        }
    }

    @Test(arguments: SevenSegmentDriverKind.allCases, [ChipPowerState.disconnected, .incorrect])
    func powerLossAndRecovery(kind: SevenSegmentDriverKind, fault: ChipPowerState) throws {
        for phase: LogicState in kind == .cd4511 ? [.low] : [.low, .high] {
            let circuit = Circuit(kind: kind, phase: phase)
            circuit.hold(false)
            circuit.code(8)
            try circuit.expectSegments("abcdefg")
            circuit.hold(true)
            let rail = fault == .disconnected ? circuit.vdd : circuit.vss
            if fault == .disconnected {
                rail.drive(.highImpedance)
            } else {
                // A logic LOW without the ground rail identity is an incorrect VSS.
                rail.drivenSupplyRail = nil
            }
            circuit.code(2)
            circuit.blank(true)
            if circuit.is4511 { circuit.lamp(true) }
            try circuit.expectSegments(nil)
            #expect(circuit.chip.powerState == fault)

            circuit.vdd.drive(.high)
            circuit.vss.drivenSupplyRail = .ground
            try circuit.expectSegments(circuit.is4511 ? "abcdefg" : "")
            if circuit.is4511 {
                circuit.lamp(false)
                try circuit.expectSegments("")
            }
            circuit.blank(false)
            try circuit.expectSegments(nil)
            #expect(circuit.chip.powerState == .powered)
            circuit.hold(false)
            try circuit.expectSegments("abdeg")
            circuit.hold(true)
            circuit.code(5)
            try circuit.expectSegments("abdeg")

            // Transparent restoration captures current data, including after an
            // outage with different BCD inputs. Try both ways to restore power.
            circuit.vdd.drive(.highImpedance)
            try circuit.expectSegments(nil)
            circuit.hold(false)
            circuit.code(1)
            try circuit.expectSegments(nil)
            if fault == .disconnected {
                circuit.vdd.drive(.high)
            } else {
                circuit.engine.automaticallyPowerChips = true
            }
            try circuit.expectSegments("bc")
            circuit.hold(true)
            circuit.code(8)
            try circuit.expectSegments("bc")
        }
    }

    @Test
    func enteringAutomaticPowerInHoldDoesNotRestoreTheDigit() throws {
        for kind in SevenSegmentDriverKind.allCases {
            let circuit = Circuit(kind: kind)
            circuit.hold(false)
            circuit.code(8)
            try circuit.expectSegments("abcdefg")
            circuit.hold(true)
            circuit.vss.drive(.highImpedance)
            try circuit.expectSegments(nil)
            circuit.engine.automaticallyPowerChips = true
            try circuit.expectSegments(nil)
            circuit.code(2)
            circuit.hold(false)
            try circuit.expectSegments("abdeg")
        }
    }
}
