import Testing
@testable import CMOS4000Simulator

struct CD4027UncertaintyTests {
    private struct Circuit {
        let engine = SimulationEngine()
        let chip = CD4027()
        let inverter = CD40106()
        let supply = WorkbenchPower(.fiveVolts).pins[1]!
        let ground = WorkbenchPower(.ground).pins[1]!
        let unitPins = [
            (q: 1, qBar: 2, clock: 3, reset: 4, k: 5, j: 6, set: 7),
            (q: 15, qBar: 14, clock: 13, reset: 12, k: 11, j: 10, set: 9)
        ]
        private(set) var drivers: [Int: Pin] = [:]
        private(set) var nets: [Int: Net] = [:]

        init(automatic: Bool) {
            engine.automaticallyPowerChips = automatic
            engine.addComponent(chip)
            engine.addComponent(inverter)
            wire([supply, chip.pins[16]!, inverter.pins[14]!])
            wire([ground, chip.pins[8]!, inverter.pins[7]!])
            for unit in unitPins {
                for number in [unit.clock, unit.reset, unit.k, unit.j, unit.set] {
                    let input = chip.pins[number]!
                    let driver = Pin(number: number, name: input.name, direction: .output)
                    driver.drive(.low)
                    drivers[number] = driver
                    nets[number] = wire([driver, input])
                }
            }
            wire([chip.pins[1]!, inverter.pins[1]!])
            wire([chip.pins[2]!, inverter.pins[3]!])
            if automatic {
                supply.drive(.highImpedance)
                ground.drive(.highImpedance)
            }
        }

        @discardableResult
        private func wire(_ pins: [Pin]) -> Net {
            let net = Net(name: pins[0].name)
            for pin in pins { net.connect(pin) }
            engine.addNet(net)
            return net
        }

        func settle() throws {
            try #require(engine.settle())
        }

        func drive(_ changes: (Int, LogicState)...) throws {
            for (number, state) in changes { drivers[number]!.drive(state) }
            try settle()
        }

        func expect(_ unit: Int, _ q: LogicState, _ qBar: LogicState) {
            #expect(chip.pins[unitPins[unit].q]!.driveState == q)
            #expect(chip.pins[unitPins[unit].qBar]!.driveState == qBar)
        }
    }

    @Test("CD4027 definite JK truth table on both physical units", arguments: [false, true])
    func truthTable(automatic: Bool) throws {
        let c = Circuit(automatic: automatic)
        try c.settle()
        let rows: [(j: LogicState, k: LogicState, fromLow: LogicState, fromHigh: LogicState)] = [
            (.low, .low, .low, .high),
            (.low, .high, .low, .low),
            (.high, .low, .high, .high),
            (.high, .high, .high, .low)
        ]

        for (index, unit) in c.unitPins.enumerated() {
            c.expect(index, .undefined, .undefined)
            for row in rows {
                for start in [LogicState.low, .high] {
                    let initialise = start == .low ? unit.reset : unit.set
                    try c.drive((initialise, .high))
                    try c.drive((initialise, .low), (unit.j, row.j), (unit.k, row.k))
                    c.expect(index, start, start.inverted)
                    try c.drive((unit.clock, .high))
                    let expected = start == .low ? row.fromLow : row.fromHigh
                    c.expect(index, expected, expected.inverted)
                    try c.settle()
                    try c.drive((unit.clock, .low))
                    c.expect(index, expected, expected.inverted)
                }
            }
        }
    }

    @Test("CD4027 asynchronous priority, partial consensus and release", arguments: [false, true])
    func asynchronousControls(automatic: Bool) throws {
        let c = Circuit(automatic: automatic)
        for (index, unit) in c.unitPins.enumerated() {
            for unknown in [LogicState.undefined, .highImpedance] {
                try c.drive((unit.set, .high), (unit.reset, unknown))
                c.expect(index, .high, .undefined)
                try c.drive((unit.set, unknown), (unit.reset, .high))
                c.expect(index, .undefined, .high)

                try c.drive((unit.set, .low))
                c.expect(index, .low, .high)
                try c.drive((unit.reset, unknown))
                c.expect(index, .low, .high)
                try c.drive((unit.set, .high), (unit.reset, .low))
                c.expect(index, .high, .low)
                try c.drive((unit.set, unknown))
                c.expect(index, .high, .low)
            }

            try c.drive((unit.set, .high), (unit.reset, .high), (unit.j, .high))
            c.expect(index, .high, .high)
            try c.drive((unit.clock, .high), (unit.set, .low))
            c.expect(index, .low, .high)
            try c.drive((unit.reset, .low))
            c.expect(index, .low, .high)
            try c.drive((unit.set, .high), (unit.reset, .high), (unit.clock, .low))
            try c.drive((unit.reset, .low))
            c.expect(index, .high, .low)
            try c.drive((unit.reset, .high))
            try c.drive((unit.set, .low), (unit.reset, .low), (unit.clock, .high))
            c.expect(index, .undefined, .undefined)
            try c.settle()
            c.expect(index, .undefined, .undefined)
            try c.drive((unit.clock, .low))
            try c.drive((unit.clock, .high))
            c.expect(index, .high, .low)
        }
    }

    @Test("CD4027 samples uncertain data once on a definite rising edge", arguments: [false, true])
    func clockedControls(automatic: Bool) throws {
        let c = Circuit(automatic: automatic)
        for (index, unit) in c.unitPins.enumerated() {
            try c.drive((unit.j, .high), (unit.k, .high))
            try c.drive((unit.clock, .high))
            c.expect(index, .undefined, .undefined)
            for unknown in [LogicState.undefined, .highImpedance] {
                try c.drive((unit.reset, .high), (unit.clock, .low))
                try c.drive((unit.reset, .low), (unit.j, .low), (unit.k, unknown))
                try c.drive((unit.clock, .high))
                c.expect(index, .low, .high)

                try c.drive((unit.set, .high), (unit.clock, .low))
                try c.drive((unit.set, .low), (unit.j, unknown), (unit.k, .low))
                try c.drive((unit.clock, .high))
                c.expect(index, .high, .low)

                try c.drive((unit.clock, .low), (unit.k, unknown))
                try c.drive((unit.clock, .high))
                c.expect(index, .undefined, .undefined)
                try c.drive((unit.j, .low), (unit.k, .high))
                c.expect(index, .undefined, .undefined)
                try c.drive((unit.clock, .low))
                try c.drive((unit.clock, unknown))
                c.expect(index, .undefined, .undefined)
                // Both possible rising boundaries sample the same reset row.
                try c.drive((unit.clock, .high))
                c.expect(index, .low, .high)
                try c.drive((unit.clock, .low))
                try c.drive((unit.clock, .high))
                c.expect(index, .low, .high)

                // Reset and a clocked set are both possible on this edge.
                try c.drive((unit.clock, .low), (unit.j, .high), (unit.k, .low))
                try c.drive((unit.reset, unknown), (unit.clock, .high))
                c.expect(index, .undefined, .undefined)
                try c.drive((unit.reset, .low))
                c.expect(index, .undefined, .undefined)
            }
        }
    }

    @Test("CD4027 resolves pulls and contention before propagating each output", arguments: [false, true])
    func resolvedInputs(automatic: Bool) throws {
        let c = Circuit(automatic: automatic)
        let pull = Pin(number: 1, name: "Weak LOW", direction: .output, isWeakDriver: true)
        let opposing = Pin(number: 2, name: "Strong LOW", direction: .output)
        c.nets[4]!.connect(pull)
        c.nets[4]!.connect(opposing)
        pull.drive(.low)
        try c.drive((7, .high), (4, .highImpedance))
        #expect(c.chip.pins[4]!.state == .low)
        c.expect(0, .high, .low)
        #expect(c.inverter.pins[4]!.driveState == .high)

        opposing.drive(.low)
        try c.drive((4, .high))
        #expect(c.chip.pins[4]!.state == .undefined)
        c.expect(0, .high, .undefined)
        #expect(c.inverter.pins[2]!.driveState == .low)
        #expect(c.inverter.pins[4]!.driveState == .undefined)

        opposing.drive(.highImpedance)
        try c.settle()
        #expect(c.chip.pins[4]!.state == .high)
        c.expect(0, .high, .high)
        #expect(c.inverter.pins[4]!.driveState == .low)
    }

    @Test("CD4027 shared power faults invalidate both units without a false restore edge", arguments: [false, true])
    func packagePower(missing: Bool) throws {
        let c = Circuit(automatic: false)
        try c.drive((7, .high), (9, .high))
        c.expect(0, .high, .low)
        c.expect(1, .high, .low)

        if missing {
            c.supply.drive(.highImpedance)
        } else {
            c.ground.drivenSupplyRail = nil
        }
        try c.drive((7, .low), (9, .low), (6, .high), (10, .high), (3, .high))
        c.expect(0, .undefined, .undefined)
        c.expect(1, .undefined, .undefined)
        #expect(c.inverter.pins[2]!.driveState == .undefined)

        c.supply.drive(.high)
        c.ground.drivenSupplyRail = .ground
        try c.settle()
        c.expect(0, .undefined, .undefined)
        c.expect(1, .undefined, .undefined)
        try c.drive((13, .high))
        c.expect(0, .undefined, .undefined)
        c.expect(1, .high, .low)
        try c.drive((3, .low))
        try c.drive((3, .high))
        c.expect(0, .high, .low)
    }

    @Test("CD4027 toggle selects complementary minutes and hours signals")
    func minutesHoursSelection() throws {
        let c = Circuit(automatic: true)
        try c.drive((4, .high), (12, .high), (6, .high), (5, .high), (10, .high), (11, .high))
        try c.drive((4, .low), (12, .low))
        c.expect(0, .low, .high)
        for selectedHours in [LogicState.high, .low, .high] {
            try c.drive((3, .high))
            c.expect(0, selectedHours, selectedHours.inverted)
            try c.settle()
            try c.drive((3, .low))
            c.expect(0, selectedHours, selectedHours.inverted)
            c.expect(1, .low, .high)
        }
        try c.drive((13, .high))
        c.expect(0, .high, .low)
        c.expect(1, .high, .low)
    }

    @Test("CD4027 correlates bridges and returns independently on both clocks",
          arguments: [false, true], [LogicState.undefined, .highImpedance])
    func correlatedClocks(automatic: Bool, unknown: LogicState) throws {
        let c = Circuit(automatic: automatic)
        try c.drive((4, .high), (12, .high), (5, .high), (6, .high), (10, .high), (11, .high))
        try c.drive((4, .low), (12, .low))
        try c.drive((3, unknown), (13, unknown))
        c.expect(0, .undefined, .undefined)
        c.expect(1, .undefined, .undefined)
        for _ in 0..<3 { try c.settle() }
        try c.drive((3, .high), (13, .low))
        c.expect(0, .high, .low)
        c.expect(1, .undefined, .undefined)

        try c.drive((3, .low), (12, .high))
        try c.drive((12, .low), (3, unknown))
        try c.drive((3, .low), (13, .high))
        c.expect(0, .undefined, .undefined)
        c.expect(1, .high, .low)
    }

    @Test("CD4027 samples J and K at each clock boundary and honors asynchronous overrides",
          arguments: [false, true], [LogicState.undefined, .highImpedance])
    func boundaryControls(automatic: Bool, unknown: LogicState) throws {
        let c = Circuit(automatic: automatic)
        try c.drive((4, .high), (9, .high))
        try c.drive((4, .low), (9, .low), (3, unknown), (13, unknown), (6, .high), (11, .high))
        c.expect(0, .undefined, .undefined)
        c.expect(1, .undefined, .undefined)
        // Change controls only. Each history must keep its previous clock.
        try c.drive((6, .low), (11, .low))
        try c.settle()
        try c.drive((3, .high), (13, .high), (6, .high), (11, .high))
        c.expect(0, .high, .low)
        c.expect(1, .low, .high)

        try c.drive((3, .low), (13, .low))
        // The two possible rising boundaries now see different controls.
        try c.drive((3, unknown), (13, unknown), (5, .high), (10, .high))
        try c.drive((3, .high), (13, .high), (5, .low), (10, .low))
        c.expect(0, .undefined, .undefined)
        c.expect(1, .undefined, .undefined)

        try c.drive((3, unknown), (13, unknown), (4, .high), (9, .high))
        c.expect(0, .low, .high)
        c.expect(1, .high, .low)
        try c.drive((4, .low), (9, .low), (6, .high), (11, .high))
        c.expect(0, .low, .high)
        c.expect(1, .high, .low)
        try c.drive((3, .high), (13, .high))
        c.expect(0, .undefined, .undefined)
        c.expect(1, .undefined, .undefined)
    }

    @Test("CD4027 distinguishes published same-symbol clock samples",
          arguments: [false, true], [LogicState.undefined, .highImpedance])
    func sameSymbolClock(automatic: Bool, unknown: LogicState) throws {
        let c = Circuit(automatic: automatic)
        try c.drive((4, .high), (12, .high), (5, .high), (6, .high), (10, .high), (11, .high))
        try c.drive((4, .low), (12, .low))
        try c.drive((3, unknown), (13, unknown))
        c.drivers[3]!.publishClockDrive(unknown)
        try c.settle()
        // Activity on another net and an ordinary same-value drive leave the
        // second receiver's original sample intact.
        try c.drive((7, .low), (13, unknown), (11, .low))
        try c.drive((11, .high))
        try c.drive((3, .high), (13, .high))
        c.expect(0, .undefined, .undefined)
        c.expect(1, .high, .low)
    }

    @Test("CD4027 clock observes contention and resolved weak pulls", arguments: [false, true])
    func resolvedClock(automatic: Bool) throws {
        let c = Circuit(automatic: automatic)
        let pull = Pin(number: 1, name: "Weak LOW", direction: .output, isWeakDriver: true)
        let opposing = Pin(number: 2, name: "Strong LOW", direction: .output)
        c.nets[3]!.connect(pull)
        c.nets[3]!.connect(opposing)
        pull.drive(.low)
        try c.drive((3, .highImpedance), (4, .high), (5, .high), (6, .high))
        #expect(c.chip.pins[3]!.state == .low)
        try c.drive((4, .low))
        opposing.drive(.low)
        try c.drive((3, .high))
        #expect(c.chip.pins[3]!.state == .undefined)
        c.expect(0, .undefined, .undefined)
        pull.publishClockDrive(.high)
        try c.drive((10, .high))
        opposing.drive(.highImpedance)
        try c.settle()
        c.expect(0, .high, .low)

        pull.drive(.low)
        try c.drive((3, .highImpedance))
        #expect(c.chip.pins[3]!.state == .low)
        opposing.drive(.low)
        try c.drive((3, .high))
        // Replace the opposing driver while the resolved value stays X.
        let replacement = Pin(number: 3, name: "Replacement LOW", direction: .output)
        c.nets[3]!.connect(replacement)
        replacement.drive(.low)
        opposing.drive(.highImpedance)
        try c.settle()
        #expect(c.chip.pins[3]!.state == .undefined)
        replacement.drive(.highImpedance)
        try c.settle()
        c.expect(0, .undefined, .undefined)
    }

    @Test("CD4027 seeds history without a startup or restoration edge",
          arguments: [false, true], [LogicState.low, .high, .undefined, .highImpedance])
    func clockInitialization(automatic: Bool, initial: LogicState) throws {
        let c = Circuit(automatic: automatic)
        try c.drive((3, initial), (13, initial), (6, .high), (10, .high))
        for half in 0..<2 { c.expect(half, .undefined, .undefined) }
        try c.drive((3, .low), (13, .low))
        try c.drive((3, .high), (13, .high))
        for half in 0..<2 { c.expect(half, .high, .low) }

        // With invalid rails, Explicit Power exposes the package power loss.
        c.engine.automaticallyPowerChips = false
        c.supply.drive(.highImpedance)
        try c.drive((3, initial), (13, initial))
        for half in 0..<2 { c.expect(half, .undefined, .undefined) }

        c.engine.automaticallyPowerChips = automatic
        if !automatic { c.supply.drive(.high) }
        try c.settle()
        for half in 0..<2 { c.expect(half, .undefined, .undefined) }
        try c.settle()
        for half in 0..<2 { c.expect(half, .undefined, .undefined) }
        try c.drive((3, .low), (13, .low))
        try c.drive((3, .high), (13, .high))
        for half in 0..<2 { c.expect(half, .high, .low) }
    }
}
