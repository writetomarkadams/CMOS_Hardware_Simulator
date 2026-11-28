import Testing
@testable import CMOS4000Simulator

@MainActor
struct CD4029UncertaintyTests {
    nonisolated private static let uncertain: [LogicState] = [.undefined, .highImpedance]
    nonisolated private static let powerModes: [PowerMode] = [.automatic, .explicit]

    @MainActor
    private struct Fixture {
        let engine = SimulationEngine()
        let chip = CD4029()
        let supply = WorkbenchPower(.fiveVolts)
        let inputs: [Int: Pin]

        init(mode: PowerMode) {
            engine.automaticallyPowerChips = mode == .automatic
            engine.addComponent(chip)
            let ground = WorkbenchPower(.ground)
            connect(supply.pins[1]!, to: [chip.pins[16]!], on: engine)
            connect(ground.pins[1]!, to: [chip.pins[8]!], on: engine)
            var drivers: [Int: Pin] = [:]
            for number in [1, 5, 9, 10, 15] + CD4029.jamPins {
                let driver = Pin(number: number, name: "Input \(number)", direction: .output)
                driver.drive(number == 10 ? .high : .low)
                connect(driver, to: [chip.pins[number]!], on: engine)
                drivers[number] = driver
            }
            inputs = drivers
        }

        func drive(_ pin: Int, _ state: LogicState) { inputs[pin]!.drive(state) }
        func settle() { #expect(engine.settle()) }

        func jam(_ count: Int) {
            for (bit, pin) in CD4029.jamPins.enumerated() {
                drive(pin, count & (1 << bit) == 0 ? .low : .high)
            }
        }

        func load(_ count: Int) {
            jam(count)
            drive(1, .high)
            settle()
            drive(1, .low)
            settle()
        }

        func pulse() {
            drive(15, .low)
            settle()
            drive(15, .high)
            settle()
        }

        var q: String { bits(chip) }
        var carry: LogicState { chip.pins[7]!.driveState }
    }

    private static func connect(_ source: Pin, to inputs: [Pin], on engine: SimulationEngine) {
        let net = Net(name: source.name)
        for pin in [source] + inputs { net.connect(pin) }
        engine.addNet(net)
    }

    private static func bits(_ chip: CD4029) -> String {
        CD4029.outputPins.reversed().map {
            switch chip.pins[$0]!.driveState {
            case .low: "0"
            case .high: "1"
            case .undefined: "X"
            case .highImpedance: "Z"
            }
        }.joined()
    }

    @Test(arguments: uncertain, powerModes)
    func ambiguousModeAndRecovery(unknown: LogicState, power: PowerMode) {
        let f = Fixture(mode: power)
        f.load(4)
        f.drive(9, unknown)
        f.pulse()
        #expect(f.q == "0101")

        f.load(9)
        #expect(f.carry == .undefined)
        f.pulse()
        #expect(f.q == "X0X0") // {0, 10}
        #expect(f.carry == .high)
        for _ in 0..<3 { f.settle() }
        #expect(f.q == "X0X0")
        #expect(f.carry == .high)
        f.drive(9, .high)
        f.pulse()
        #expect(f.q == "X0X1") // {1, 11}

        f.load(0)
        f.drive(9, unknown)
        f.drive(10, .low)
        f.settle()
        #expect(f.carry == .low)
        f.pulse()
        #expect(f.q == "1XX1") // {9, 15}
        #expect(f.carry == .high)
    }

    @Test(arguments: uncertain, powerModes)
    func ambiguousCarryAndDirection(unknown: LogicState, power: PowerMode) {
        let f = Fixture(mode: power)
        f.load(4)
        f.drive(5, unknown)
        f.pulse()
        #expect(f.q == "010X")
        #expect(f.carry == .high)

        f.drive(9, .high)
        f.load(15)
        #expect(f.carry == .undefined)
        f.pulse()
        // Hold at 15 with CI high, or wrap to zero with CI low.
        f.jam(6) // JAM edits with PE low must leave the carry consensus intact.
        for _ in 0..<3 {
            f.settle()
            #expect(f.q == "XXXX")
            #expect(f.carry == .high)
        }
        f.drive(5, .low)
        f.settle()
        #expect(f.carry == .undefined)
        f.drive(5, .high)
        f.settle()
        #expect(f.carry == .high)

        f.drive(9, .low)
        f.drive(5, .low)
        f.load(0)
        f.drive(10, unknown)
        f.settle()
        #expect(f.carry == .undefined)
        f.pulse()
        #expect(f.q == "X001") // Up to 1, or down to 9.
        f.settle()
        #expect(f.carry == .high) // Neither result is terminal in its own direction.
        f.load(4)
        f.pulse()
        #expect(f.q == "0XX1") // {3, 5}
        f.drive(10, .high)
        f.pulse()
        #expect(f.q == "01X0") // {4, 6}
    }

    @Test(arguments: uncertain, powerModes)
    func asynchronousJamAndAmbiguousPreset(unknown: LogicState, power: PowerMode) {
        let f = Fixture(mode: power)
        f.load(4)
        f.jam(4)
        f.drive(4, unknown)
        f.drive(1, .high)
        f.settle()
        #expect(f.q == "010X")
        f.pulse()
        #expect(f.q == "010X")
        f.jam(6)
        f.drive(1, unknown)
        f.settle()
        #expect(f.q == "01XX") // {4, 5, 6}
        f.load(4)
        f.drive(15, .low)
        f.settle()
        f.jam(7)
        f.drive(1, unknown)
        f.drive(15, .high)
        f.settle()
        #expect(f.q == "01X1") // Jam 7 or advance to 5.
        f.load(9)
        #expect(f.carry == .low)
        f.drive(1, .high)
        f.settle()
        #expect(f.carry == .low)
        f.drive(5, .high)
        f.settle()
        #expect(f.carry == .high)
    }

    @Test(arguments: uncertain)
    func invalidDecadeTransitions(unknown: LogicState) {
        let f = Fixture(mode: .automatic)
        f.load(12)
        #expect(f.q == "1100")
        #expect(f.carry == .undefined)
        f.pulse()
        #expect(f.q == "XXXX")
        #expect(f.carry == .undefined)

        f.jam(8)
        f.drive(12, unknown) // JAM 8 or 10.
        f.drive(1, .high)
        f.settle()
        #expect(f.q == "10X0")
        f.drive(1, .low)
        f.drive(5, .high)
        f.pulse()
        #expect(f.q == "10X0")
        #expect(f.carry == .high)
        f.drive(5, .low)
        f.drive(9, unknown)
        f.pulse() // Includes an enabled decade transition from 10.
        #expect(f.q == "XXXX")
        #expect(f.carry == .undefined)
        f.load(4)
        f.pulse()
        #expect(f.q == "0101")
    }

    @Test(arguments: powerModes)
    func resolvedPullsAndContention(power: PowerMode) {
        let f = Fixture(mode: power)
        f.load(9)
        let modeNet = f.engine.nets.first { net in net.pins.contains { $0 === f.inputs[9]! } }!
        let pull = Pin(number: 1, name: "Weak binary select", direction: .output, isWeakDriver: true)
        pull.drive(.high)
        modeNet.connect(pull)
        f.drive(9, .highImpedance)
        f.pulse()
        #expect(f.chip.pins[9]!.state == .high)
        #expect(f.q == "1010")

        f.load(9)
        f.drive(9, .low)
        f.pulse()
        #expect(f.chip.pins[9]!.state == .low)
        #expect(f.q == "0000")

        let contender = Pin(number: 1, name: "Strong binary select", direction: .output)
        contender.drive(.high)
        modeNet.connect(contender)
        f.load(9)
        f.pulse()
        #expect(f.chip.pins[9]!.state == .undefined)
        #expect(f.q == "X0X0")
    }

    @Test(arguments: powerModes)
    func freshStateAndPowerLifecycle(power: PowerMode) {
        let f = Fixture(mode: power)
        f.settle()
        #expect(f.q == "XXXX")
        f.load(4)
        f.pulse()
        #expect(f.q == "0101")
        for invalidSupply: LogicState in [.highImpedance, .low] {
            f.supply.pins[1]!.drive(invalidSupply)
            f.drive(5, .high)
            f.settle()
            #expect(f.q == (power == .explicit ? "XXXX" : "0101"))
            #expect(f.carry == (power == .explicit ? .undefined : .high))
            f.supply.pins[1]!.drive(.high)
            f.drive(5, .low)
            f.settle() // Clock is already high when power returns.
            #expect(f.q == (power == .explicit ? "XXXX" : "0101"))
            f.load(4)
            f.pulse()
            #expect(f.q == "0101")
        }
    }

    @Test(arguments: [true, false], powerModes)
    func commonClockCascade(lowFirst: Bool, power: PowerMode) {
        let engine = SimulationEngine()
        engine.automaticallyPowerChips = power == .automatic
        let low = CD4029()
        let high = CD4029()
        for chip in lowFirst ? [low, high] : [high, low] { engine.addComponent(chip) }
        let supply = WorkbenchPower(.fiveVolts)
        let ground = WorkbenchPower(.ground)
        let clock = Pin(number: 15, name: "Shared clock", direction: .output)
        Self.connect(supply.pins[1]!, to: [low.pins[16]!, high.pins[16]!], on: engine)
        Self.connect(ground.pins[1]!, to: [low.pins[8]!, high.pins[8]!], on: engine)
        Self.connect(clock, to: [low.pins[15]!, high.pins[15]!], on: engine)
        Self.connect(low.pins[7]!, to: [high.pins[5]!], on: engine)
        low.pins[5]!.receive(.low)

        for modulus in [10, 16] {
            for up in [true, false] {
                clock.drive(.low)
                for chip in [low, high] {
                    chip.pins[1]!.receive(.high)
                    chip.pins[9]!.receive(modulus == 16 ? .high : .low)
                    chip.pins[10]!.receive(up ? .high : .low)
                    for pin in CD4029.jamPins { chip.pins[pin]!.receive(.low) }
                }
                #expect(engine.settle())
                for chip in [low, high] { chip.pins[1]!.receive(.low) }
                #expect(engine.settle())

                for step in 1...(2 * modulus + 1) {
                    clock.drive(.high)
                    #expect(engine.settle())
                    #expect(engine.settle())
                    let expected = up ? step : modulus * modulus - step
                    #expect(Int(Self.bits(low), radix: 2) == expected % modulus)
                    #expect(Int(Self.bits(high), radix: 2) == expected / modulus)
                    clock.drive(.low)
                    #expect(engine.settle())
                }
            }
        }
    }

    @Test(arguments: uncertain, powerModes)
    func correlatedClockBridgesAndReturns(unknown: LogicState, power: PowerMode) {
        let f = Fixture(mode: power)
        f.load(4)
        f.drive(15, unknown)
        f.settle()
        #expect(f.q == "010X")
        let unrelated = Pin(number: 1, name: "Unrelated", direction: .output)
        Self.connect(unrelated, to: [], on: f.engine)
        for level: LogicState in [.high, .low, .undefined] {
            unrelated.drive(level)
            f.settle()
            f.settle()
            #expect(f.q == "010X")
        }
        f.drive(15, .high)
        f.settle()
        #expect(f.q == "0101")

        f.drive(15, .low)
        f.load(4)
        f.drive(15, unknown)
        f.settle()
        f.drive(15, .low)
        f.settle()
        #expect(f.q == "010X")
        f.pulse()
        #expect(f.q == "01XX") // {5, 6}, including the earlier possible pulse.
    }

    @Test(arguments: uncertain, powerModes)
    func distinctSameSymbolClockEvents(unknown: LogicState, power: PowerMode) {
        let f = Fixture(mode: power)
        f.load(4)
        let clock = f.inputs[15]!
        clock.drive(unknown)
        f.settle()
        clock.drive(unknown)
        f.settle()
        #expect(f.q == "010X")
        clock.publishClockDrive(unknown)
        f.settle()
        #expect(f.chip.pins[15]!.state == unknown)
        #expect(f.q == "010X") // Two uncertain samples still allow at most one rise.
        clock.drive(.high)
        f.settle()
        #expect(f.q == "01XX") // {5, 6}, since X/Z can now include HIGH then LOW.

        clock.drive(.low)
        f.load(4)
        clock.drive(unknown)
        f.settle()
        let net = f.engine.nets.first { $0.pins.contains { $0 === clock } }!
        let extra = Pin(number: 1, name: "Additional clock driver", direction: .output)
        extra.drive(unknown)
        net.connect(extra)
        f.settle()
        #expect(f.chip.pins[15]!.state == unknown)
        extra.drive(.highImpedance)
        clock.drive(.high)
        f.settle()
        #expect(f.q == "01XX") // A changed driver set also distinguishes X or Z.
    }

    @Test(arguments: uncertain, powerModes)
    func controlsAtClockBoundaries(unknown: LogicState, power: PowerMode) {
        let f = Fixture(mode: power)
        f.load(9)
        f.drive(9, .high)
        f.drive(15, unknown)
        f.settle()
        f.drive(9, .low)
        f.drive(15, .high)
        f.settle()
        #expect(f.q == "X0X0") // Early binary rise to 10, or late decade rise to 0.
        #expect(f.carry == .undefined) // 10 is invalid under the new decade mode.

        f.drive(15, .low)
        f.load(4)
        f.drive(5, .high)
        f.drive(15, unknown)
        f.settle()
        f.drive(5, .low)
        f.drive(10, .low)
        f.drive(15, .high)
        f.settle()
        #expect(f.q == "0XXX") // Early rise inhibited, or late rise down to 3.

        f.drive(15, .low)
        f.load(4)
        f.jam(8)
        f.drive(1, .high)
        f.drive(15, unknown)
        f.settle()
        #expect(f.q == "1000")
        f.drive(1, .low)
        f.drive(15, .high)
        f.settle()
        #expect(f.q == "XXXX") // JAM 8, or count down to 7 on the late rise.
    }

    @Test(arguments: powerModes)
    func clockPullsAndContention(power: PowerMode) {
        let f = Fixture(mode: power)
        f.load(4)
        let driver = f.inputs[15]!
        let net = f.engine.nets.first { $0.pins.contains { $0 === driver } }!
        let pull = Pin(number: 1, name: "Clock pull-up", direction: .output, isWeakDriver: true)
        pull.drive(.high)
        net.connect(pull)
        let contender = Pin(number: 1, name: "Contending clock", direction: .output)
        contender.drive(.high)
        net.connect(contender)
        f.settle()
        #expect(f.chip.pins[15]!.state == .undefined)
        #expect(f.q == "010X")
        pull.drive(.low)
        f.settle() // The change in the shadowed pull cannot resample X.
        pull.drive(.high)
        f.settle()
        contender.drive(.highImpedance)
        driver.drive(.highImpedance)
        f.settle()
        #expect(f.chip.pins[15]!.state == .high)
        #expect(f.q == "0101")
    }

    @Test(arguments: [LogicState.low, .high, .undefined, .highImpedance], powerModes)
    func clockAtStartupAndPowerRestoration(level: LogicState, power: PowerMode) {
        let f = Fixture(mode: power)
        f.drive(15, level)
        f.load(4)
        f.drive(15, .high)
        f.settle()
        let afterHigh: String
        switch level {
        case .low: afterHigh = "0101"
        case .high: afterHigh = "0100"
        case .undefined, .highImpedance: afterHigh = "010X"
        }
        #expect(f.q == afterHigh)

        f.supply.pins[1]!.drive(.low)
        f.settle()
        #expect(f.q == (power == .explicit ? "XXXX" : afterHigh))
        f.drive(15, level)
        f.drive(1, .high)
        f.jam(4)
        f.settle()
        f.supply.pins[1]!.drive(.high)
        f.settle()
        #expect(f.q == "0100")
        f.drive(1, .low)
        f.settle()
        f.drive(15, .high)
        f.settle()
        #expect(f.q == afterHigh)
        f.load(4)
        f.pulse()
        #expect(f.q == "0101")
    }
}
