import Testing
@testable import CMOS4000Simulator

struct CD4060PowerTests {
    private struct Circuit {
        static let dividerPins: [(pin: Int, ratio: Int)] = [
            (7, 16), (5, 32), (4, 64), (6, 128), (14, 256),
            (13, 512), (15, 1024), (1, 4096), (2, 8192), (3, 16384)
        ]

        let engine = SimulationEngine()
        let chip = CD4060()
        let supply = WorkbenchPower(.fiveVolts).pins[1]!
        let ground = WorkbenchPower(.ground).pins[1]!
        var clock: Pin { chip.pins[11]! }
        var reset: Pin { chip.pins[12]! }

        init(automaticPower: Bool = false) {
            engine.automaticallyPowerChips = automaticPower
            engine.addComponent(chip)
            let vdd = Net(name: "VDD")
            vdd.connect(supply)
            vdd.connect(chip.pins[16]!)
            engine.addNet(vdd)
            let vss = Net(name: "VSS")
            vss.connect(ground)
            vss.connect(chip.pins[8]!)
            engine.addNet(vss)
        }

        var outputs: [LogicState] {
            Self.dividerPins.map { chip.pins[$0.pin]!.driveState }
        }

        func driveClock(_ level: LogicState) throws {
            clock.receive(level)
            try #require(engine.settle())
        }

        func pulse() throws {
            try driveClock(.high)
            try driveClock(.low)
        }
    }

    @Test("CD4060 loses state on invalid rails and needs powered reset at either clock level",
          arguments: [LogicState.low, .high], [ChipPowerState.disconnected, .incorrect])
    func powerLoss(restoredClock: LogicState, fault: ChipPowerState) throws {
        let circuit = Circuit()
        circuit.reset.receive(.high)
        try circuit.driveClock(.low)
        circuit.reset.receive(.low)
        for _ in 0..<8 { try circuit.pulse() }
        #expect(circuit.outputs.first == .high)

        try circuit.driveClock(.high)
        // A plain logic LOW on VSS has the expected level but lacks ground provenance.
        let faultyRail = fault == .disconnected ? circuit.supply : circuit.ground
        faultyRail.drive(fault == .disconnected ? .highImpedance : .low)
        if fault == .incorrect { faultyRail.drivenSupplyRail = nil }
        circuit.reset.receive(.high)
        try #require(circuit.engine.settle())
        #expect(circuit.chip.powerState == fault)
        #expect(circuit.outputs.allSatisfy { $0 == .undefined })
        try circuit.driveClock(restoredClock)

        circuit.reset.receive(.low)
        circuit.supply.drive(.high)
        circuit.ground.drivenSupplyRail = .ground
        try #require(circuit.engine.settle())
        #expect(circuit.chip.powerState == .powered)
        #expect(circuit.outputs.allSatisfy { $0 == .undefined })
        for _ in 0..<8 { try circuit.pulse() }
        #expect(circuit.outputs.allSatisfy { $0 == .undefined })

        try circuit.driveClock(restoredClock)
        circuit.reset.receive(.high)
        try #require(circuit.engine.settle())
        #expect(circuit.outputs.allSatisfy { $0 == .low })
        circuit.reset.receive(.low)
        try #require(circuit.engine.settle())
        if restoredClock == .high {
            for _ in 0..<3 {
                try circuit.driveClock(.high)
                #expect(circuit.outputs.first == .low)
            }
        }
        for _ in 0..<7 { try circuit.pulse() }
        #expect(circuit.outputs.allSatisfy { $0 == .low })
        try circuit.pulse()
        #expect(circuit.outputs.first == .high)
    }

    @Test("CD4060 uses all ten divider ratios and rolls over in both power modes",
          arguments: [false, true])
    func dividerRatios(automaticPower: Bool) throws {
        let circuit = Circuit(automaticPower: automaticPower)
        if automaticPower {
            circuit.supply.drive(.highImpedance)
            circuit.ground.drive(.highImpedance)
        }
        circuit.reset.receive(.low)
        try circuit.driveClock(.low)
        #expect(circuit.outputs.allSatisfy { $0 == .undefined })
        for _ in 0..<8 { try circuit.pulse() }
        #expect(circuit.outputs.allSatisfy { $0 == .undefined })

        circuit.reset.receive(.high)
        try #require(circuit.engine.settle())
        #expect(circuit.outputs.allSatisfy { $0 == .low })
        circuit.reset.receive(.low)

        // Check every transition through one complete 14-bit cycle and into the next.
        for count in 1...(16_384 + 8) {
            try circuit.driveClock(.high)
            let before = circuit.outputs
            try circuit.driveClock(.low)
            let after = circuit.outputs
            for (index, divider) in Circuit.dividerPins.enumerated() {
                let halfPeriod = divider.ratio / 2
                #expect(before[index] == ((count - 1) & halfPeriod == 0 ? .low : .high))
                #expect(after[index] == (count & halfPeriod == 0 ? .low : .high))
            }
        }
    }

    @Test("CD4060 X/Z reset preserves stationary consensus and advances exact candidates",
          arguments: [LogicState.undefined, .highImpedance], [false, true])
    func uncertainReset(resetLevel: LogicState, automaticPower: Bool) throws {
        let circuit = Circuit(automaticPower: automaticPower)
        if automaticPower {
            circuit.supply.drive(.highImpedance)
            circuit.ground.drive(.highImpedance)
        }

        func expectOutputs(_ first: LogicState, _ second: LogicState = .low) {
            #expect(circuit.outputs == [first, second] + Array(repeating: .low, count: 8))
        }

        circuit.reset.receive(.high)
        try circuit.driveClock(.low)
        circuit.reset.receive(resetLevel)
        try circuit.driveClock(.low)
        expectOutputs(.low)

        circuit.reset.receive(.low)
        for _ in 0..<8 { try circuit.pulse() }
        circuit.reset.receive(resetLevel)
        try circuit.driveClock(.low)
        expectOutputs(.undefined) // {0, 8}

        // Start a separate sequence to exercise a simultaneous reset/edge
        // and a sparse set whose Q4 consensus differs from its bounding range.
        circuit.reset.receive(.high)
        try circuit.driveClock(.low)
        circuit.reset.receive(.low)
        for _ in 0..<15 { try circuit.pulse() }
        try circuit.driveClock(.high)
        circuit.reset.receive(resetLevel)
        try circuit.driveClock(.low)
        expectOutputs(.low, .undefined) // {0, 16}

        for _ in 0..<3 {
            try circuit.driveClock(.low)
            expectOutputs(.low, .undefined)
        }
        try circuit.pulse()
        expectOutputs(.low, .undefined) // {0, 1, 17}

        circuit.reset.receive(.low)
        for _ in 0..<6 {
            try circuit.pulse()
            expectOutputs(.low, .undefined)
        }
        try circuit.pulse()
        expectOutputs(.undefined, .undefined) // {7, 8, 24}
        try circuit.pulse()
        expectOutputs(.high, .undefined) // {8, 9, 25}

        try circuit.driveClock(.high)
        circuit.reset.receive(.high)
        try circuit.driveClock(.low)
        expectOutputs(.low)
        circuit.reset.receive(.low)
        for _ in 0..<7 { try circuit.pulse() }
        expectOutputs(.low)
        try circuit.driveClock(.high)
        try circuit.driveClock(resetLevel)
        try circuit.driveClock(.low)
        expectOutputs(.high) // Either possible falling boundary advances from 7 to 8.
        try circuit.pulse()
        expectOutputs(.high)
    }

    @Test("CD4060 candidate ranges wrap and merge across the 14-bit boundary")
    func candidateRollover() throws {
        let circuit = Circuit()
        circuit.reset.receive(.high)
        try circuit.driveClock(.low)
        circuit.reset.receive(.low)
        for _ in 0..<16_382 { try circuit.pulse() }

        circuit.reset.receive(.undefined)
        try circuit.driveClock(.low)
        #expect(circuit.outputs.allSatisfy { $0 == .undefined }) // {0, 16382}
        try circuit.pulse()
        #expect(circuit.outputs.allSatisfy { $0 == .undefined }) // {0, 1, 16383}
        circuit.reset.receive(.low)
        try circuit.pulse()
        #expect(circuit.outputs.allSatisfy { $0 == .low }) // {0, 1, 2}
        for _ in 0..<5 { try circuit.pulse() }
        #expect(circuit.outputs.allSatisfy { $0 == .low }) // {5, 6, 7}
        try circuit.pulse()
        #expect(circuit.outputs.first == .undefined) // {6, 7, 8}
        try circuit.pulse()
        try circuit.pulse()
        #expect(circuit.outputs.first == .high) // {8, 9, 10}
    }

    @Test("CD4060 consumes resolved RESET with weak pulls and strong contention",
          arguments: [false, true])
    func resolvedReset(automaticPower: Bool) throws {
        let circuit = Circuit(automaticPower: automaticPower)
        if automaticPower {
            circuit.supply.drive(.highImpedance)
            circuit.ground.drive(.highImpedance)
        }
        let resetNet = Net(name: "RESET")
        let pull = Pin(number: 1, name: "Weak reset", direction: .output, isWeakDriver: true)
        let low = Pin(number: 1, name: "Strong low", direction: .output)
        let high = Pin(number: 1, name: "Strong high", direction: .output)
        for pin in [circuit.reset, pull, low, high] { resetNet.connect(pin) }
        circuit.engine.addNet(resetNet)

        pull.drive(.high)
        try circuit.driveClock(.low)
        #expect(circuit.reset.state == .high)
        #expect(circuit.outputs.allSatisfy { $0 == .low })
        pull.drive(.low)
        for _ in 0..<8 { try circuit.pulse() }
        #expect(circuit.reset.state == .low)
        #expect(circuit.outputs.first == .high)

        pull.drive(.high)
        low.drive(.low)
        try circuit.driveClock(.low)
        #expect(circuit.reset.state == .low)
        #expect(circuit.outputs.first == .high)
        high.drive(.high)
        try circuit.driveClock(.low)
        #expect(circuit.reset.state == .undefined)
        #expect(circuit.outputs.first == .undefined)
        #expect(circuit.outputs.dropFirst().allSatisfy { $0 == .low })

        low.drive(.highImpedance)
        try circuit.driveClock(.low)
        #expect(circuit.reset.state == .high)
        #expect(circuit.outputs.allSatisfy { $0 == .low })
    }

    private struct WiredClock {
        let circuit: Circuit
        let driver = Pin(number: 1, name: "Clock drive", direction: .output)
        let net = Net(name: "Clock")

        init(automaticPower: Bool) {
            circuit = Circuit(automaticPower: automaticPower)
            if automaticPower {
                circuit.supply.drive(.highImpedance)
                circuit.ground.drive(.highImpedance)
            }
            net.connect(driver)
            net.connect(circuit.clock)
            circuit.engine.addNet(net)
        }

        func settle() throws {
            try #require(circuit.engine.settle())
        }

        func drive(_ level: LogicState) throws {
            driver.drive(level)
            try settle()
        }

        func pulse(_ count: Int) throws {
            for _ in 0..<count {
                try drive(.high)
                try drive(.low)
            }
        }

        func initialize() throws {
            circuit.reset.receive(.high)
            try drive(.low)
            circuit.reset.receive(.low)
            try settle()
        }

        func expectCounts(_ counts: [Int]) {
            let expected: [LogicState] = Circuit.dividerPins.map { divider in
                let mask = divider.ratio / 2
                let high = counts.first! & mask != 0
                return counts.allSatisfy { ($0 & mask != 0) == high }
                    ? (high ? .high : .low) : .undefined
            }
            #expect(circuit.outputs == expected)
        }
    }

    @Test("CD4060 correlates uncertain falling bridges and returns",
          arguments: [false, true], [LogicState.undefined, .highImpedance])
    func correlatedClock(automaticPower: Bool, unknown: LogicState) throws {
        let clock = WiredClock(automaticPower: automaticPower)
        try clock.initialize()
        try clock.pulse(7)
        try clock.drive(.high)
        try clock.drive(unknown)
        clock.expectCounts([7, 8])
        for _ in 0..<3 { try clock.settle() }
        try clock.drive(.low)
        clock.expectCounts([8])

        try clock.initialize()
        try clock.pulse(7)
        try clock.drive(.high)
        try clock.drive(unknown)
        try clock.drive(.high)
        clock.expectCounts([7, 8])
        try clock.drive(.low)
        clock.expectCounts([8, 9])
    }

    @Test("CD4060 distinguishes published clock events and keeps phase during reset",
          arguments: [false, true], [LogicState.undefined, .highImpedance])
    func sameSymbolAndReset(automaticPower: Bool, unknown: LogicState) throws {
        let clock = WiredClock(automaticPower: automaticPower)
        try clock.initialize()
        try clock.pulse(14)
        try clock.drive(.high)
        try clock.drive(unknown)
        try clock.drive(unknown)
        clock.expectCounts([14, 15])
        clock.driver.publishClockDrive(unknown)
        try clock.settle()
        try clock.drive(.low)
        clock.expectCounts([15, 16])

        try clock.drive(unknown)
        clock.circuit.reset.receive(.high)
        try clock.settle()
        clock.expectCounts([0])
        clock.circuit.reset.receive(.low)
        try clock.settle()
        clock.expectCounts([0])
        try clock.drive(.low)
        try clock.pulse(7)
        clock.expectCounts([7, 8])
    }

    @Test("CD4060 correlates a contended clock and ignores masked weak drive changes",
          arguments: [false, true])
    func resolvedClock(automaticPower: Bool) throws {
        let clock = WiredClock(automaticPower: automaticPower)
        let pull = Pin(number: 2, name: "Weak clock pull", direction: .output, isWeakDriver: true)
        let opposing = Pin(number: 3, name: "Opposing clock", direction: .output)
        clock.net.connect(pull)
        clock.net.connect(opposing)
        pull.drive(.low)
        try clock.initialize()
        try clock.pulse(7)
        try clock.drive(.highImpedance)
        #expect(clock.circuit.clock.state == .low)
        try clock.drive(.high)
        opposing.drive(.low)
        try clock.settle()
        #expect(clock.circuit.clock.state == .undefined)
        clock.expectCounts([7, 8])
        pull.publishClockDrive(.high)
        try clock.settle()
        pull.drive(.low)
        clock.driver.drive(.highImpedance)
        try clock.settle()
        clock.expectCounts([8])
        opposing.drive(.highImpedance)
        try clock.settle()
        #expect(clock.circuit.clock.state == .low)
        clock.expectCounts([8])
    }

    @Test("CD4060 seeds all clock levels at startup and power restoration",
          arguments: [false, true], [LogicState.low, .high, .undefined, .highImpedance])
    func startupAndRestore(automaticPower: Bool, initial: LogicState) throws {
        let clock = WiredClock(automaticPower: automaticPower)
        clock.circuit.reset.receive(.low)
        try clock.drive(initial)
        #expect(clock.circuit.outputs.allSatisfy { $0 == .undefined })
        try clock.initialize()
        try clock.pulse(8)
        clock.expectCounts([8])

        clock.circuit.engine.automaticallyPowerChips = false
        clock.circuit.supply.drive(.highImpedance)
        clock.circuit.reset.receive(.high)
        try clock.drive(initial)
        #expect(clock.circuit.outputs.allSatisfy { $0 == .undefined })
        clock.circuit.engine.automaticallyPowerChips = automaticPower
        if !automaticPower { clock.circuit.supply.drive(.high) }
        try clock.settle()
        clock.expectCounts([0])
        clock.circuit.reset.receive(.low)
        try clock.settle()
        try clock.pulse(7)
        clock.expectCounts([7])
        try clock.pulse(1)
        clock.expectCounts([8])
    }

    @Test("CD4060 pin 3 clocks a CD4027 to produce 1 Hz from 32,768 Hz")
    func timebase() throws {
        let bench = Workbench(timeSource: { 0 })
        let clock = WorkbenchClock()
        let reset = WorkbenchSwitch()
        let supply = WorkbenchPower(.fiveVolts)
        let ground = WorkbenchPower(.ground)
        let counter = CD4060()
        let flipFlop = CD4027()
        bench.add("Clock", component: clock)
        bench.add("Reset", component: reset)
        bench.add("+5V", component: supply)
        bench.add("GND", component: ground)
        bench.add("CD4060", component: counter)
        bench.add("CD4027", component: flipFlop)

        func wire(_ a: Int, _ pinA: Int, _ b: Int, _ pinB: Int) {
            bench.select(WorkbenchTerminal(partID: bench.parts[a].id, pinNumber: pinA))
            bench.select(WorkbenchTerminal(partID: bench.parts[b].id, pinNumber: pinB))
        }
        wire(0, 1, 4, 11)
        wire(1, 1, 4, 12)
        wire(1, 1, 5, 4)
        wire(4, 3, 5, 3)
        for chip in [4, 5] {
            wire(2, 1, chip, 16)
            wire(3, 1, chip, 8)
        }
        wire(2, 1, 5, 5)
        wire(2, 1, 5, 6)
        wire(3, 1, 5, 7)

        bench.setPowerMode(.explicit)
        bench.toggle(reset)
        #expect(counter.pins[3]?.driveState == .low)
        #expect(flipFlop.pins[1]?.driveState == .low)
        bench.toggle(reset)

        let frequency = 32_768.0
        let halfPeriod = 0.5 / frequency
        bench.runClock(clock, hertz: frequency)
        func advance(to time: Double) throws {
            while bench.servicedTime < time {
                let previousTime = bench.servicedTime
                bench.serviceSimulation(until: time)
                try #require(bench.servicedTime > previousTime)
                try #require(bench.isStable)
            }
        }

        // Check both outputs immediately before and at each expected transition.
        let transitions: [(time: Double, q14: LogicState, q: LogicState)] = [
            (0.25, .high, .high), (0.5, .low, .high),
            (0.75, .high, .low), (1, .low, .low),
            (1.25, .high, .high), (1.5, .low, .high),
            (1.75, .high, .low), (2, .low, .low), (2.25, .high, .high)
        ]
        var previousQ14 = LogicState.low
        var previousQ = LogicState.low
        for transition in transitions {
            try advance(to: transition.time - halfPeriod)
            #expect(counter.pins[3]?.driveState == previousQ14)
            #expect(flipFlop.pins[1]?.driveState == previousQ)
            try advance(to: transition.time)
            #expect(counter.pins[3]?.driveState == transition.q14)
            #expect(flipFlop.pins[1]?.driveState == transition.q)
            previousQ14 = transition.q14
            previousQ = transition.q
        }
    }
}

extension CD4060PowerTests {
    private func exactCounts(_ bucket: CD4060.Candidates) -> Set<Int> {
        Set((0..<bucket.rangeCount).flatMap { bucket[$0] })
    }

    @Test("CD4060 inline and fragmented buckets match exact 14-bit set operations")
    func intervalStorage() throws {
        typealias Bucket = CD4060.Candidates
        let mask = 0x3FFF
        let buckets: [Bucket] = [
            .single(0), .single(1), .single(7), .single(mask),
            .interval(0...9), .interval(2...12), .interval(8...14),
            .interval(0...(mask - 1)), .interval(1...mask),
            .interval((mask - 3)...mask),
            .ranges([0...0, 3...5, mask...mask]), .ranges([1...3, 6...8]),
            .unknown
        ]

        func verify(_ actual: Bucket, equals expected: Set<Int>) {
            #expect(exactCounts(actual) == expected)
            let ordered = expected.sorted()
            let first = ordered.first!
            let last = ordered.last!
            switch actual {
            case .single: #expect(ordered.count == 1)
            case .interval: #expect(ordered.count > 1 && ordered.count < mask + 1 && ordered.count == last - first + 1)
            case .ranges(let ranges):
                #expect(ranges.count > 1)
                #expect(zip(ranges, ranges.dropFirst()).allSatisfy { $0.upperBound + 1 < $1.lowerBound })
            case .unknown: #expect(ordered.count == mask + 1)
            }
            let allHigh = ordered.reduce(mask, &)
            let anyHigh = ordered.reduce(0, |)
            #expect(actual.outputBits.high == allHigh)
            #expect(actual.outputBits.ambiguous == allHigh ^ anyHigh)
        }

        let references = buckets.map(exactCounts)
        for (index, original) in buckets.enumerated() {
            let reference = references[index]
            for falling in [false, true] {
                for mayReset in [false, true] {
                    var next = original
                    next.transition(falling: falling, mayReset: mayReset)
                    var expected = falling ? Set(reference.map { ($0 + 1) & mask }) : reference
                    if mayReset { expected.insert(0) }
                    verify(next, equals: expected)
                }
            }
            for (other, expected) in zip(buckets, references) {
                verify(original.union(other), equals: reference.union(expected))
            }
        }
    }

    @Test("CD4060 X/Z clock and reset histories match exact correlated buckets",
          arguments: [false, true], [LogicState.undefined, .highImpedance])
    func exactClockHistory(automaticPower: Bool, uncertain: LogicState) throws {
        let clock = WiredClock(automaticPower: automaticPower)
        try clock.initialize()
        let other: LogicState = uncertain == .undefined ? .highImpedance : .undefined
        var history: [LogicState: Set<Int>] = [.low: [0]]
        var previous = LogicState.low

        func step(_ level: LogicState, reset: LogicState = .low, publish: Bool = false) throws {
            let levels: [LogicState] = level == .low || level == .high ? [level] : [.low, .high]
            var next: [LogicState: Set<Int>] = [:]
            for (prior, counts) in history {
                for current in levels where level != previous || publish || current == prior {
                    for count in counts {
                        if reset != .high {
                            let advance = prior == .high && current == .low ? 1 : 0
                            next[current, default: []].insert((count + advance) & 0x3FFF)
                        }
                        if reset != .low { next[current, default: []].insert(0) }
                    }
                }
            }
            clock.circuit.reset.receive(reset)
            if publish {
                clock.driver.publishClockDrive(level)
                try clock.settle()
            } else {
                try clock.drive(level)
            }
            let chip = clock.circuit.chip
            #expect(exactCounts(chip.candidates) == next[levels[0]])
            if levels.count == 2 {
                let high = try #require(chip.highCandidates)
                #expect(exactCounts(high) == next[.high])
            } else {
                #expect(chip.highCandidates == nil)
            }
            clock.expectCounts(Array(next.values.reduce(into: Set<Int>()) { $0.formUnion($1) }))
            history = next
            previous = level
        }

        try clock.pulse(16_380)
        history = [.low: [16_380]]
        try step(.high)
        try step(uncertain)
        try step(uncertain)
        try step(uncertain, reset: other)
        try step(uncertain, publish: true)
        try step(other)
        try step(other, publish: true)
        try step(.low)
        try step(.high)
        try step(.low)
        try step(other, reset: .high)
        try step(other)
        try step(.low)
        try step(.high)
        try step(.low)
    }
}
