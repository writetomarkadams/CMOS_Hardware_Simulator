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
        expectOutputs(.low) // HIGH → X/Z → LOW is not a definite falling edge.
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
