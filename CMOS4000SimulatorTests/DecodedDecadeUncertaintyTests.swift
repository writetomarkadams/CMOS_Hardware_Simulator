import Testing
@testable import CMOS4000Simulator

struct DecodedDecadeUncertaintyTests {
    private struct Circuit {
        let engine = SimulationEngine()
        let decoded = CD4017()
        let displayDriver = CD4026()
        let supply = WorkbenchPower(.fiveVolts).pins[1]!
        let ground = WorkbenchPower(.ground).pins[1]!
        let clock = Pin(number: 1, name: "Clock", direction: .output)
        let inhibit = Pin(number: 1, name: "Inhibit", direction: .output)
        let reset = Pin(number: 1, name: "Reset", direction: .output)
        let enable = Pin(number: 1, name: "Display enable", direction: .output)
        let resetNet: Net

        init(automatic: Bool) {
            engine.automaticallyPowerChips = automatic
            engine.addComponent(decoded)
            engine.addComponent(displayDriver)
            resetNet = Net(name: "Reset")
            for pin in [reset, decoded.pins[15]!, displayDriver.pins[15]!] { resetNet.connect(pin) }
            engine.addNet(resetNet)
            wire(clock, decoded.pins[14]!, displayDriver.pins[1]!)
            wire(inhibit, decoded.pins[13]!, displayDriver.pins[2]!)
            wire(enable, displayDriver.pins[3]!)
            wire(supply, decoded.pins[16]!, displayDriver.pins[16]!)
            wire(ground, decoded.pins[8]!, displayDriver.pins[8]!)
            if automatic { supply.drive(.highImpedance) }
            clock.drive(.low)
            inhibit.drive(.low)
            enable.drive(.high)
        }

        func wire(_ source: Pin, _ receivers: Pin...) {
            let net = Net(name: source.name)
            net.connect(source)
            for pin in receivers { net.connect(pin) }
            engine.addNet(net)
        }

        func drive(_ pin: Pin, _ level: LogicState) throws {
            pin.drive(level)
            try #require(engine.settle())
        }

        func pulse() throws {
            try drive(clock, .high)
            try drive(clock, .low)
        }

        var segments: [LogicState] {
            [10, 12, 13, 9, 11, 6, 7].map { displayDriver.pins[$0]!.driveState }
        }

        func expectCounts(_ counts: Set<Int>) {
            let outputs = [3, 2, 4, 7, 10, 1, 5, 6, 9, 11]
            for (digit, pin) in outputs.enumerated() {
                let expected: LogicState = counts.contains(digit) ? (counts.count == 1 ? .high : .undefined) : .low
                #expect(decoded.pins[pin]!.driveState == expected, "Q\(digit) with candidates \(counts.sorted())")
            }
            let carry: LogicState = counts.allSatisfy { $0 < 5 } ? .high :
                (counts.allSatisfy { $0 >= 5 } ? .low : .undefined)
            #expect(decoded.pins[12]!.driveState == carry)
            #expect(displayDriver.pins[5]!.driveState == carry)
        }
    }

    @Test(arguments: [false, true])
    func resolvedResetAndDisplay(automatic: Bool) throws {
        let c = Circuit(automatic: automatic)
        let display = MAN74A()
        c.engine.addComponent(display)
        for (driver, segment) in zip([10, 12, 13, 9, 11, 6, 7], MAN74A.segmentPins) {
            c.wire(c.displayDriver.pins[driver]!, display.pins[segment]!)
        }
        // Add the display common to the existing ground net.
        let groundNet = try #require(c.engine.nets.first { $0.pins.contains { $0 === c.ground } })
        for pin in MAN74A.commonPins { groundNet.connect(display.pins[pin]!) }

        let pull = Pin(number: 1, name: "Weak reset", direction: .output, isWeakDriver: true)
        let opposing = Pin(number: 1, name: "Strong reset", direction: .output)
        for pin in [pull, opposing] { c.resetNet.connect(pin) }

        try #require(c.engine.settle())
        c.expectCounts(Set(0..<10))
        #expect(c.segments.allSatisfy { $0 == .undefined })
        try c.drive(pull, .high)
        c.expectCounts([0])
        try c.drive(c.reset, .low)
        try c.pulse()
        c.expectCounts([1])

        try c.drive(opposing, .high)
        #expect(c.decoded.pins[15]!.state == .undefined)
        c.expectCounts([0, 1])
        #expect(c.segments == [.undefined, .high, .high, .undefined, .undefined, .undefined, .low])
        #expect(MAN74A.segmentPins.filter { number in
            display.isLit(number) { display.pins[$0]!.state }
        } == [13, 8])

        try c.drive(opposing, .highImpedance)
        try c.drive(pull, .highImpedance)
        try c.drive(c.reset, .highImpedance)
        #expect(c.decoded.pins[15]!.state == .highImpedance)
        c.expectCounts([0, 1])
        #expect(c.segments == [.undefined, .high, .high, .undefined, .undefined, .undefined, .low])
        for enable in [LogicState.undefined, .highImpedance] {
            try c.drive(c.enable, enable)
            #expect(c.segments == Array(repeating: .undefined, count: 6) + [.low])
            #expect(c.displayDriver.pins[4]!.driveState == .undefined)
            #expect(c.displayDriver.pins[14]!.driveState == .high)
        }
        try c.drive(c.enable, .low)
        #expect(c.segments.allSatisfy { $0 == .low })
        #expect(c.displayDriver.pins[4]!.driveState == .low)
        #expect(c.displayDriver.pins[14]!.driveState == .high)
        c.expectCounts([0, 1])
        try c.drive(c.reset, .low)
        try c.pulse()
        c.expectCounts([1, 2])
        #expect(c.displayDriver.pins[14]!.driveState == .undefined)
        c.reset.drive(.highImpedance)
        try c.drive(pull, .high)
        c.expectCounts([0])
        #expect(c.segments.allSatisfy { $0 == .low })
    }

    @Test(arguments: [false, true])
    func clockAndInhibit(automatic: Bool) throws {
        let c = Circuit(automatic: automatic)
        try c.drive(c.reset, .high)
        try c.drive(c.reset, .low)
        try c.drive(c.inhibit, .high)
        try c.drive(c.clock, .high)
        c.expectCounts([0])
        try c.drive(c.inhibit, .low)
        c.expectCounts([1])
        try c.drive(c.clock, .low)

        for (level, counts): (LogicState, Set<Int>) in [(.undefined, [1, 2]), (.highImpedance, [1, 2, 3])] {
            try c.drive(c.inhibit, level)
            try c.drive(c.clock, .high)
            for _ in 0..<3 {
                try #require(c.engine.settle())
                c.expectCounts(counts)
            }
            try c.drive(c.inhibit, .low)
            c.expectCounts(counts)
            try c.drive(c.clock, .low)
        }

        for (level, counts): (LogicState, Set<Int>) in [(.undefined, [2, 3, 4]), (.highImpedance, [3, 4, 5])] {
            try c.drive(c.clock, level)
            try c.drive(c.clock, .high)
            try c.drive(c.clock, .low)
            try c.pulse()
            c.expectCounts(counts)
        }
        try c.drive(c.reset, .high)
        try c.drive(c.clock, .high)
        c.expectCounts([0])
        try c.drive(c.reset, .low)
        c.expectCounts([0])
        try c.drive(c.clock, .low)
        for count in 1...19 {
            try c.pulse()
            c.expectCounts([count % 10])
        }
        try c.drive(c.reset, .undefined)
        c.expectCounts([0, 9])
        try c.drive(c.clock, .high)
        c.expectCounts([0, 1])
        try c.drive(c.reset, .low)
        try c.drive(c.clock, .low)
        try c.pulse()
        c.expectCounts([1, 2])
    }

    @Test(arguments: [false, true])
    func invalidSupplyAndRestoration(incorrectGround: Bool) throws {
        let c = Circuit(automatic: false)
        try c.drive(c.reset, .high)
        try c.drive(c.reset, .low)
        try c.pulse()
        if incorrectGround {
            c.ground.drivenSupplyRail = nil
            try #require(c.engine.settle())
        } else {
            try c.drive(c.supply, .highImpedance)
        }
        for chip in [c.decoded as any PoweredChip, c.displayDriver] {
            #expect(chip.powerState == (incorrectGround ? .incorrect : .disconnected))
            #expect(chip.pins.values.filter { $0.direction == .output }.allSatisfy { $0.driveState == .undefined })
        }
        try c.drive(c.clock, .high)
        c.ground.drivenSupplyRail = .ground
        try c.drive(c.supply, .high)
        c.expectCounts(Set(0..<10))
        #expect(c.displayDriver.pins[4]!.driveState == .high)
        try c.drive(c.reset, .high)
        try c.drive(c.reset, .low)
        c.expectCounts([0])
        try c.drive(c.clock, .low)
        try c.pulse()
        c.expectCounts([1])
    }

    @Test(arguments: [false, true], [false, true])
    func carryCascade(automatic: Bool, downstreamFirst: Bool) throws {
        let engine = SimulationEngine()
        engine.automaticallyPowerChips = automatic
        let first = CD4017()
        let second = CD4026()
        if downstreamFirst {
            engine.addComponent(second)
            engine.addComponent(first)
        } else {
            engine.addComponent(first)
            engine.addComponent(second)
        }
        let pairs: [(Pin, [Pin])] = [
            (first.pins[12]!, [second.pins[1]!]),
            (WorkbenchPower(.fiveVolts).pins[1]!, [first.pins[16]!, second.pins[16]!, second.pins[3]!]),
            (WorkbenchPower(.ground).pins[1]!, [first.pins[8]!, second.pins[8]!, first.pins[13]!, second.pins[2]!])
        ]
        for (driver, receivers) in pairs {
            let net = Net(name: driver.name)
            for pin in [driver] + receivers { net.connect(pin) }
            engine.addNet(net)
        }
        for pin in [first.pins[15]!, second.pins[15]!] { pin.receive(.high) }
        first.pins[14]!.receive(.low)
        try #require(engine.settle())
        for pin in [first.pins[15]!, second.pins[15]!] { pin.receive(.low) }
        for step in 1...20 {
            first.pins[14]!.receive(.high)
            try #require(engine.settle())
            try #require(engine.settle())
            first.pins[14]!.receive(.low)
            try #require(engine.settle())
            let patterns: [[LogicState]] = [
                [.high, .high, .high, .high, .high, .high, .low],
                [.low, .high, .high, .low, .low, .low, .low],
                [.high, .high, .low, .high, .high, .low, .high]
            ]
            #expect(CD4026.segmentPins.map { second.pins[$0]!.driveState } == patterns[step / 10])
        }
    }
}
