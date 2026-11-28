import Testing
@testable import CMOS4000Simulator

struct CD4060FinalVerificationTests {
    private static let outputPins: [(pin: Int, stage: Int)] = [
        (7, 4), (5, 5), (4, 6), (6, 7), (14, 8), (13, 9),
        (15, 10), (1, 12), (2, 13), (3, 14)
    ]

    // Enumerate individual physical states. nil means no prior clock sample.
    private struct State: Hashable {
        let count: Int
        let clock: Bool?
    }

    private struct Oracle {
        static let modulus = 16_384
        var states = initial
        var symbol: LogicState?

        static var initial: Set<State> {
            Set((0..<modulus).map { State(count: $0, clock: nil) })
        }

        mutating func step(_ level: LogicState, reset: LogicState, published: Bool) {
            let levels = level == .low ? [false] : level == .high ? [true] : [false, true]
            var next = Set<State>()
            for state in states {
                for high in levels where level != symbol || published || high == state.clock {
                    if reset != .high {
                        let count = (state.count + (state.clock == true && !high ? 1 : 0)) % Self.modulus
                        next.insert(State(count: count, clock: high))
                    }
                    if reset != .low { next.insert(State(count: 0, clock: high)) }
                }
            }
            states = next
            symbol = level
        }
    }

    private struct Fixture {
        let chip = CD4060()
        let engine = SimulationEngine()
        let clock = Pin(number: 1, name: "Clock", direction: .output)
        let supply = WorkbenchPower(.fiveVolts).pins[1]!
        let ground = WorkbenchPower(.ground).pins[1]!
        let clockNet = Net(name: "Clock")

        init(_ automatic: Bool) {
            engine.automaticallyPowerChips = automatic
            engine.addComponent(chip)
            clockNet.connect(clock)
            clockNet.connect(chip.pins[11]!)
            engine.addNet(clockNet)
            for (pin, rail) in [(16, supply), (8, ground)] {
                let net = Net(name: "Rail \(pin)")
                net.connect(rail)
                net.connect(chip.pins[pin]!)
                engine.addNet(net)
                if automatic { rail.drive(.highImpedance) }
            }
        }

        func verify(_ oracle: Oracle, step: Int, powered: Bool = true) throws {
            func check(_ bucket: CD4060.Candidates, counts: Set<Int>) throws {
                let actual = Set((0..<bucket.rangeCount).flatMap { bucket[$0] })
                try #require(actual == counts, "State set differs at step \(step)")
                let bits = bucket.outputBits
                for bit in 0..<14 {
                    let mask = 1 << bit
                    let high = counts.contains { $0 & mask != 0 }
                    let low = counts.contains { $0 & mask == 0 }
                    try #require((bits.high & mask != 0) == (high && !low), "HIGH bit \(bit), step \(step)")
                    try #require((bits.ambiguous & mask != 0) == (high && low), "X bit \(bit), step \(step)")
                }
            }
            if oracle.symbol == .undefined || oracle.symbol == .highImpedance {
                try check(chip.candidates, counts: Set(oracle.states.filter { $0.clock == false }.map(\.count)))
                let high = try #require(chip.highCandidates)
                try check(high, counts: Set(oracle.states.filter { $0.clock == true }.map(\.count)))
            } else {
                try #require(chip.highCandidates == nil)
                try check(chip.candidates, counts: Set(oracle.states.map(\.count)))
            }
            for (pin, stage) in CD4060FinalVerificationTests.outputPins {
                let values = Set(oracle.states.map { ($0.count >> (stage - 1)) & 1 })
                let expected: LogicState = !powered || values.count != 1 ? .undefined : values.contains(1) ? .high : .low
                try #require(chip.pins[pin]!.driveState == expected, "Pin \(pin), step \(step)")
            }
        }
    }

    @Test("Exact CD4060 buckets, all bits and pins across rollover, uncertainty and power",
          arguments: [false, true])
    func exactStateTrace(automatic: Bool) throws {
        let fixture = Fixture(automatic)
        var oracle = Oracle()
        var index = 0
        func check(_ level: LogicState, _ reset: LogicState = .low, publish: Bool = false,
                   drive: Bool = true, powered: Bool = true) throws {
            index += 1
            fixture.chip.pins[12]!.receive(reset)
            if drive {
                if publish { fixture.clock.publishClockDrive(level) }
                else { fixture.clock.drive(level) }
            }
            try #require(fixture.engine.settle(), "Step \(index)")
            try #require(fixture.chip.pins[11]!.state == level)
            if powered { oracle.step(level, reset: reset, published: publish) }
            else { oracle = Oracle() }
            try fixture.verify(oracle, step: index, powered: powered)
        }

        try check(.highImpedance)
        try check(.high)
        try check(.high, .high, drive: false)
        try check(.high, drive: false)
        for _ in 0..<16_384 {
            try check(.low)
            try check(.high)
        }
        try #require(oracle.states == [State(count: 0, clock: true)])

        // Establish separated counts near the top of the domain and advance them through wrap.
        for _ in 0..<16_380 {
            fixture.clock.drive(.low)
            try #require(fixture.engine.settle())
            fixture.clock.drive(.high)
            try #require(fixture.engine.settle())
        }
        oracle.states = [State(count: 16_380, clock: true)]
        try fixture.verify(oracle, step: index)
        try check(.undefined, .highImpedance)
        try check(.undefined, .undefined, drive: false)
        try check(.undefined)
        try check(.undefined, publish: true)
        try check(.highImpedance)
        try check(.highImpedance, publish: true)
        try check(.low)
        try check(.high)
        try check(.low)
        try check(.high)
        try check(.low)

        // Exercise masked publications, contention, and release through resolved nets.
        let weak = Pin(number: 2, name: "Weak", direction: .output, isWeakDriver: true)
        let opposing = Pin(number: 3, name: "Opposing", direction: .output)
        fixture.clockNet.connect(weak)
        fixture.clockNet.connect(opposing)
        weak.drive(.low)
        try check(.high)
        opposing.drive(.low)
        try check(.undefined, drive: false)
        weak.publishClockDrive(.high)
        try check(.undefined, drive: false)
        try check(.undefined, .high, drive: false)
        try check(.undefined, drive: false)
        try check(.undefined, drive: false)
        fixture.clock.drive(.highImpedance)
        try check(.low, drive: false)
        opposing.drive(.highImpedance)
        try check(.high, drive: false)
        weak.drive(.highImpedance)
        try check(.highImpedance, drive: false)

        // A distinct repeatable sequence combines all clock and RESET symbols.
        let symbols: [LogicState] = [.low, .high, .undefined, .highImpedance]
        var random: UInt64 = 0x4060_5B5C
        for step in 0..<512 {
            random = random &* 6364136223846793005 &+ 1
            let level = symbols[Int((random >> 32) & 3)]
            let reset = step.isMultiple(of: 13) ? symbols[Int((random >> 48) & 3)] : .low
            try check(level, reset, publish: step.isMultiple(of: 3))
        }

        fixture.engine.automaticallyPowerChips = false
        fixture.supply.drive(.highImpedance)
        try check(.high, .high, powered: false)
        try check(.highImpedance, powered: false)
        fixture.engine.automaticallyPowerChips = automatic
        if !automatic { fixture.supply.drive(.high) }
        try check(.highImpedance)
        try check(.highImpedance, .high, drive: false)
        try check(.highImpedance, drive: false)
        try check(.low)
        try check(.high)
        try check(.low)
    }

    @Test("Exact scope edge timestamps for the wired 32,768 Hz, CD4060, CD4027 and CD4017 chain",
          arguments: [false, true])
    func wiredTimebase(automatic: Bool) throws {
        let bench = Workbench(timeSource: { 0 })
        let clock = WorkbenchClock()
        let reset = WorkbenchSwitch()
        let supply = WorkbenchPower(.fiveVolts)
        let ground = WorkbenchPower(.ground)
        let divider = CD4060()
        let flipFlop = CD4027()
        let decade = CD4017()
        bench.add("Clock", component: clock)
        bench.add("RESET", component: reset)
        bench.add("+5V", component: supply)
        bench.add("GND", component: ground)
        bench.add("CD4060", component: divider)
        bench.add("CD4027", component: flipFlop)
        bench.add("CD4017", component: decade)
        func terminal(_ part: Int, _ pin: Int) -> WorkbenchTerminal {
            WorkbenchTerminal(partID: bench.parts[part].id, pinNumber: pin)
        }
        func wire(_ a: Int, _ pinA: Int, _ b: Int, _ pinB: Int) {
            bench.select(terminal(a, pinA))
            bench.select(terminal(b, pinB))
        }

        wire(0, 1, 4, 11)
        wire(1, 1, 4, 12)
        wire(1, 1, 5, 4)
        wire(1, 1, 6, 15)
        wire(4, 3, 5, 3)
        wire(5, 1, 6, 14)
        wire(2, 1, 5, 5)
        wire(2, 1, 5, 6)
        wire(3, 1, 5, 7)
        wire(3, 1, 6, 13)
        if !automatic {
            for chip in [4, 5, 6] {
                wire(2, 1, chip, 16)
                wire(3, 1, chip, 8)
            }
        }
        bench.setPowerMode(automatic ? .automatic : .explicit)
        bench.toggle(reset)
        try #require(bench.isStable)
        try #require(decade.pins[CD4017.outputPins[0]]!.driveState == .high)
        bench.toggle(reset)

        for (channel, point) in [terminal(0, 1), terminal(4, 3), terminal(5, 1),
                                 terminal(6, CD4017.outputPins[1])].enumerated() {
            bench.assignScopeProbe(.pin(point), to: channel)
        }
        bench.runClock(clock, hertz: 32_768)
        let tick = 1.0 / 65_536
        let blockSize = 4096
        let end = 163_840 // 2.5 s, three downstream rising edges.
        for last in stride(from: blockSize, through: end, by: blockSize) {
            let target = Double(last) * tick
            while bench.servicedTime < target {
                let previous = bench.servicedTime
                bench.serviceSimulation(until: target)
                try #require(bench.isStable && bench.servicedTime > previous)
            }
            try #require(bench.servicedTime == target)
            let first = last - blockSize + 1
            let range = (Double(first) * tick)...target
            let input = bench.scope.samples(channel: 0, in: range).filter { range.contains($0.time) }
            let expected = (first...last).map {
                ScopeSample(time: Double($0) * tick, value: .logic($0.isMultiple(of: 2) ? .low : .high))
            }
            try #require(input == expected, "Input half-cycle ticks \(first)...\(last)")
            let expectedDigit = [16_384, 81_920, 147_456].filter { $0 <= last }.count
            for (digit, pin) in CD4017.outputPins.enumerated() {
                try #require(decade.pins[pin]!.driveState == (digit == expectedDigit ? .high : .low))
            }
        }
        let window = tick...(Double(end) * tick)
        func edges(_ channel: Int) -> [ScopeSample] {
            bench.scope.samples(channel: channel, in: window).filter { window.contains($0.time) }
        }
        func sample(_ time: Double, _ level: LogicState) -> ScopeSample {
            ScopeSample(time: time, value: .logic(level))
        }
        try #require(edges(1) == (1...10).map { sample(Double($0) / 4, $0.isMultiple(of: 2) ? .low : .high) })
        try #require(edges(2) == (0..<5).map { sample(0.25 + Double($0) / 2, $0.isMultiple(of: 2) ? .high : .low) })
        try #require(edges(3) == [sample(0.25, .high), sample(1.25, .low)])
    }
}
