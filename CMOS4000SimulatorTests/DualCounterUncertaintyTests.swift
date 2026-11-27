import Testing
@testable import CMOS4000Simulator

struct DualCounterUncertaintyTests {
    private struct Circuit {
        let engine = SimulationEngine()
        let chip: DualCounter
        let downstream: DualCounter?
        let supply = WorkbenchPower(.fiveVolts).pins[1]!
        let ground = WorkbenchPower(.ground).pins[1]!
        let clocks = [driver("CLOCK A"), driver("CLOCK B")]
        let enables = [driver("ENABLE A"), driver("ENABLE B")]
        let resets = [driver("RESET A"), driver("RESET B")]

        init(_ kind: DualCounterKind, automatic: Bool, downstreamFirst: Bool? = nil) {
            chip = DualCounter(kind)
            downstream = downstreamFirst.map { _ in DualCounter(kind) }
            engine.automaticallyPowerChips = automatic
            if downstreamFirst == true, let downstream { engine.addComponent(downstream) }
            engine.addComponent(chip)
            if downstreamFirst == false, let downstream { engine.addComponent(downstream) }

            let packages = [chip] + [downstream].compactMap { $0 }
            wire([supply] + packages.map { $0.pins[16]! })
            wire([ground] + packages.map { $0.pins[8]! } + [downstream?.pins[1]].compactMap { $0 })
            if automatic { supply.drive(.highImpedance) }
            for unit in 0..<2 {
                let offset = unit * 8
                wire([clocks[unit], chip.pins[1 + offset]!])
                wire([enables[unit], chip.pins[2 + offset]!])
                let resetReceivers = unit == 0 ? [downstream?.pins[7]].compactMap { $0 } : []
                wire([resets[unit], chip.pins[7 + offset]!] + resetReceivers)
                clocks[unit].drive(.low)
                enables[unit].drive(.high)
                resets[unit].drive(.low)
            }
            if let downstream { wire([chip.pins[6]!, downstream.pins[2]!]) }
        }

        private func wire(_ pins: [Pin]) {
            let net = Net(name: pins[0].name)
            for pin in pins { net.connect(pin) }
            engine.addNet(net)
        }

        func settle() throws {
            try #require(engine.settle())
        }

        func drive(_ pin: Pin, _ state: LogicState) throws {
            pin.drive(state)
            try settle()
        }

        func reset(_ unit: Int) throws {
            try drive(resets[unit], .high)
            try drive(resets[unit], .low)
        }

        func pulse(_ unit: Int) throws {
            try drive(clocks[unit], .high)
            try drive(clocks[unit], .low)
        }

        func expect(_ counts: Set<Int>, unit: Int, downstream: Bool = false) {
            let package = downstream ? self.downstream! : chip
            let pins = unit == 0 ? [6, 5, 4, 3] : [14, 13, 12, 11]
            let expected: [LogicState] = (0..<4).reversed().map { bit in
                let levels = Set(counts.map { ($0 >> bit) & 1 })
                if levels == [0] { return .low }
                if levels == [1] { return .high }
                return .undefined
            }
            #expect(pins.map { package.pins[$0]!.driveState } == expected, "Unit \(unit), candidates \(counts.sorted())")
        }
    }

    private static func driver(_ name: String, weak: Bool = false) -> Pin {
        Pin(number: 1, name: name, direction: .output, isWeakDriver: weak)
    }

    @Test(arguments: DualCounterKind.allCases, [false, true])
    func resetConsensusAndIndependentRollover(kind: DualCounterKind, automatic: Bool) throws {
        let c = Circuit(kind, automatic: automatic)
        try c.settle()
        for unit in 0..<2 {
            c.expect(Set(0..<kind.modulus), unit: unit)
            try c.reset(unit)
        }

        let stationary = kind == .bcd ? 8 : 15
        for unit in 0..<2 {
            let other = 1 - unit
            try c.pulse(other)
            for level in [LogicState.undefined, .highImpedance] {
                try c.reset(unit)
                for _ in 0..<stationary { try c.pulse(unit) }
                try c.drive(c.resets[unit], level)
                c.expect([0, stationary], unit: unit)
                c.expect([1], unit: other)
                try c.drive(c.resets[unit], .low)
                try c.pulse(unit)
                c.expect([1, (stationary + 1) % kind.modulus], unit: unit)
            }

            try c.drive(c.resets[unit], .high)
            try c.drive(c.clocks[unit], .high)
            c.expect([0], unit: unit)
            try c.drive(c.resets[unit], .low)
            c.expect([0], unit: unit)
            try c.drive(c.clocks[unit], .low)
            for count in 1...kind.modulus {
                try c.pulse(unit)
                c.expect([count % kind.modulus], unit: unit)
            }
            c.expect([1], unit: other)
            try c.reset(other)
        }
    }

    @Test(arguments: DualCounterKind.allCases, [false, true])
    func resolvedGatingAndEdgeHistory(kind: DualCounterKind, automatic: Bool) throws {
        let c = Circuit(kind, automatic: automatic)
        let pull = Self.driver("Weak enable", weak: true)
        let opposing = Self.driver("Opposing enable")
        let enableNet = try #require(c.engine.nets.first { $0.pins.contains { $0 === c.enables[0] } })
        enableNet.connect(pull)
        enableNet.connect(opposing)

        try c.reset(0)
        try c.reset(1)
        c.enables[0].drive(.highImpedance)
        try c.drive(pull, .high)
        try c.pulse(0)
        c.expect([1], unit: 0)
        c.enables[0].drive(.low)
        try c.drive(opposing, .high)
        #expect(c.chip.pins[2]!.state == .undefined)
        try c.pulse(0)
        c.expect([1, 2], unit: 0)
        c.enables[0].drive(.highImpedance)
        opposing.drive(.highImpedance)
        try c.drive(pull, .highImpedance)
        #expect(c.chip.pins[2]!.state == .highImpedance)
        try c.drive(c.clocks[0], .high)
        for _ in 0..<3 {
            try c.settle()
            c.expect([1, 2, 3], unit: 0)
        }
        try c.drive(c.enables[0], .high)
        c.expect([1, 2, 3], unit: 0)

        for level in [LogicState.undefined, .highImpedance] {
            try c.reset(1)
            try c.drive(c.clocks[1], level)
            try c.drive(c.enables[1], .high)
            try c.drive(c.enables[1], .low)
            c.expect([0, 1], unit: 1)
            try c.settle()
            c.expect([0, 1], unit: 1)
            try c.drive(c.enables[1], .high)
            try c.drive(c.clocks[1], .high)
            c.expect([0, 1], unit: 1)
            try c.drive(c.clocks[1], .low)
            try c.drive(c.enables[1], level)
            try c.drive(c.enables[1], .low)
            c.expect([0, 1], unit: 1)
            try c.drive(c.enables[1], .high)
            try c.drive(c.enables[1], .low)
            c.expect([1, 2], unit: 1)
        }

        try c.reset(1)
        try c.drive(c.enables[1], .high)
        c.clocks[1].drive(.high)
        try c.drive(c.enables[1], .low)
        c.expect([0], unit: 1)
        c.expect([1, 2, 3], unit: 0)
    }

    @Test(arguments: DualCounterKind.allCases, [false, true])
    func invalidPowerAndRestoration(kind: DualCounterKind, restoreHigh: Bool) throws {
        let c = Circuit(kind, automatic: false)
        for unit in 0..<2 {
            try c.reset(unit)
            try c.pulse(unit)
            c.expect([1], unit: unit)
        }
        if restoreHigh {
            c.ground.drivenSupplyRail = nil
            try c.settle()
            #expect(c.chip.powerState == .incorrect)
        } else {
            try c.drive(c.supply, .highImpedance)
            #expect(c.chip.powerState == .disconnected)
        }
        let allCounts = Set(0..<kind.modulus)
        for unit in 0..<2 {
            c.expect(allCounts, unit: unit)
            c.clocks[unit].drive(restoreHigh ? .high : .low)
        }
        try c.settle()
        c.ground.drivenSupplyRail = .ground
        try c.drive(c.supply, .high)
        #expect(c.chip.powerState == .powered)
        for unit in 0..<2 { c.expect(allCounts, unit: unit) }

        for unit in 0..<2 {
            try c.reset(unit)
            c.expect([0], unit: unit)
            try c.drive(c.clocks[unit], .low)
            try c.pulse(unit)
            c.expect([1], unit: unit)
        }
    }

    @Test(arguments: [false, true], [false, true])
    func rippleCascade(automatic: Bool, downstreamFirst: Bool) throws {
        for kind in DualCounterKind.allCases {
            let c = Circuit(kind, automatic: automatic, downstreamFirst: downstreamFirst)
            try c.reset(0)
            try c.reset(1)
            for step in 1...kind.modulus * 2 {
                try c.pulse(0)
                try c.settle()
                c.expect([step % kind.modulus], unit: 0)
                c.expect([step / kind.modulus], unit: 0, downstream: true)
            }
            try c.drive(c.resets[0], .high)
            try c.drive(c.resets[0], .low)
            for _ in 0..<8 { try c.pulse(0) }
            try c.drive(c.resets[0], .undefined)
            c.expect([0, 8], unit: 0)
            #expect(c.downstream?.pins[2]!.state == .undefined)
            c.expect([0], unit: 0, downstream: true)
        }
    }
}
