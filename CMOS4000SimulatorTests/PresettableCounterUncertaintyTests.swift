import Testing
@testable import CMOS4000Simulator

@MainActor
struct PresettableCounterUncertaintyTests {
    private static let uncertain: [LogicState] = [.undefined, .highImpedance]
    private static let powerModes: [PowerMode] = [.automatic, .explicit]

    @MainActor
    private struct Fixture {
        let engine = SimulationEngine()
        let chip: any PoweredChip
        let supply = WorkbenchPower(.fiveVolts)
        let inputs: [Int: Pin]

        init(decimal: Bool, mode: PowerMode) {
            chip = decimal ? CD4510() : CD4516()
            engine.automaticallyPowerChips = mode == .automatic
            engine.addComponent(chip)
            let ground = WorkbenchPower(.ground)
            for (number, source) in [(8, ground), (16, supply)] {
                let net = Net(name: "Rail \(number)")
                net.connect(source.pins[1]!)
                net.connect(chip.pins[number]!)
                engine.addNet(net)
            }
            var sources: [Int: Pin] = [:]
            for number in [1, 3, 4, 5, 9, 10, 12, 13, 15] {
                let driver = Pin(number: number, name: "Input \(number)", direction: .output)
                driver.drive(number == 10 ? .high : .low)
                let net = Net(name: driver.name)
                net.connect(driver)
                net.connect(chip.pins[number]!)
                engine.addNet(net)
                sources[number] = driver
            }
            inputs = sources
        }

        func drive(_ number: Int, _ state: LogicState) {
            inputs[number]!.drive(state)
        }

        func settle() {
            #expect(engine.settle())
        }

        func setPreset(_ value: Int) {
            for (bit, pin) in [4, 12, 13, 3].enumerated() {
                drive(pin, value & (1 << bit) == 0 ? .low : .high)
            }
        }

        func load(_ value: Int) {
            setPreset(value)
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

        var q: String { PresettableCounterUncertaintyTests.q(chip) }
        var carry: LogicState { chip.pins[7]!.driveState }
    }

    private static func q(_ chip: any LogicComponent) -> String {
        [2, 14, 11, 6].map {
            switch chip.pins[$0]!.driveState {
            case .low: "0"
            case .high: "1"
            case .undefined: "X"
            case .highImpedance: "Z"
            }
        }.joined()
    }

    @Test(arguments: uncertain, powerModes)
    func decimalDirectionAndRecovery(unknown: LogicState, mode: PowerMode) {
        let f = Fixture(decimal: true, mode: mode)
        f.load(4)
        f.drive(10, unknown)
        f.pulse()
        #expect(f.q == "0XX1")
        #expect(f.carry == .high)
        for _ in 0..<3 { f.settle() }
        #expect(f.q == "0XX1")
        f.drive(10, .high)
        f.pulse()
        #expect(f.q == "01X0") // {4, 6}
        f.drive(9, .high)
        f.settle()
        #expect(f.q == "0000")
        f.drive(9, unknown)
        f.settle()
        #expect(f.q == "0000")
        f.pulse()
        #expect(f.q == "000X") // reset or count
    }

    @Test(arguments: uncertain, powerModes)
    func binaryCarryInAndBranchConsensus(unknown: LogicState, mode: PowerMode) {
        let f = Fixture(decimal: false, mode: mode)
        f.settle()
        #expect(f.q == "XXXX")
        f.load(4)
        f.drive(5, unknown)
        f.settle()
        #expect(f.q == "0100")
        #expect(f.carry == .high)
        f.pulse()
        #expect(f.q == "010X")
        #expect(f.carry == .high)
        f.drive(5, .low)
        f.pulse()
        #expect(f.q == "01XX") // {5, 6}
        f.pulse()
        #expect(f.q == "011X") // {6, 7}, recovers Q2

        f.load(15)
        f.drive(5, unknown)
        f.settle()
        #expect(f.carry == .undefined)
        f.pulse()
        // Enabled wraps to zero. Inhibited stays at 15 with carry high.
        for _ in 0..<4 {
            f.settle()
            #expect(f.q == "XXXX")
            #expect(f.carry == .high)
        }
        f.setPreset(9) // With PE low, changing JAM does not affect carry.
        f.settle()
        #expect(f.carry == .high)
        f.drive(5, .low)
        f.settle()
        #expect(f.carry == .undefined)
        f.load(6)
        #expect(f.q == "0110")
    }

    @Test(arguments: uncertain, powerModes)
    func partialPresetAndControlPriority(unknown: LogicState, mode: PowerMode) {
        for decimal in [true, false] {
            let f = Fixture(decimal: decimal, mode: mode)
            f.load(4)
            f.setPreset(2)
            f.drive(4, unknown)
            f.drive(1, .high)
            f.pulse()
            #expect(f.q == "001X")
            #expect(f.carry == .high)

            f.setPreset(6)
            f.drive(1, unknown)
            f.settle()
            #expect(f.q == "0X1X") // {2, 3, 6}
            f.drive(9, unknown)
            f.settle()
            #expect(f.q == "0XXX") // {0, 2, 3, 6}
            f.drive(1, .high)
            f.settle()
            #expect(f.q == "0XX0") // reset or preset
            f.drive(9, .high)
            f.pulse()
            #expect(f.q == "0000")
            f.drive(9, .low)
            f.settle()
            #expect(f.q == "0110")

            f.setPreset(4)
            f.drive(1, unknown)
            f.pulse()
            #expect(f.q == "01XX") // preset 4 or count from 6 to 7
            f.load(6)

            if decimal {
                f.setPreset(15)
                f.drive(1, .high)
                f.settle()
                #expect(f.q == "0110")
                f.setPreset(8)
                f.drive(12, unknown) // 8 or invalid 10 (hold 6).
                f.settle()
                #expect(f.q == "XXX0")
            }
        }
    }

    @Test(arguments: [true, false])
    func powerLossAndResolvedPulls(decimal: Bool) {
        let f = Fixture(decimal: decimal, mode: .explicit)
        f.settle()
        #expect(f.q == (decimal ? "0000" : "XXXX"))
        f.load(4)
        let pull = Pin(number: 1, name: "Pull-down", direction: .output, isWeakDriver: true)
        pull.drive(.low)
        let ciNet = f.engine.nets.first { $0.pins.contains { $0 === f.inputs[5]! } }!
        ciNet.connect(pull)
        f.drive(5, .highImpedance)
        f.pulse()
        #expect(f.q == "0101")

        f.supply.pins[1]!.drive(.highImpedance)
        f.settle()
        #expect(f.q == "XXXX")
        f.supply.pins[1]!.drive(.high)
        f.settle()
        #expect(f.q == "XXXX") // Restoration with clock high is not an edge.
        f.drive(9, .high)
        f.settle()
        #expect(f.q == "0000")
        f.drive(9, .low)
        f.settle()
        #expect(f.q == "0000")
        f.pulse()
        #expect(f.q == "0001")
    }

    @Test(arguments: [true, false], powerModes)
    func binaryCommonClockCascade(lowCounterFirst: Bool, mode: PowerMode) {
        let engine = SimulationEngine()
        engine.automaticallyPowerChips = mode == .automatic
        let low = CD4516()
        let high = CD4516()
        for chip in lowCounterFirst ? [low, high] : [high, low] {
            engine.addComponent(chip)
        }
        func connect(_ source: Pin, _ destinations: [Pin]) {
            let net = Net(name: source.name)
            for pin in [source] + destinations { net.connect(pin) }
            engine.addNet(net)
        }
        let vdd = WorkbenchPower(.fiveVolts)
        let ground = WorkbenchPower(.ground)
        connect(vdd.pins[1]!, [low.pins[16]!, high.pins[16]!])
        connect(ground.pins[1]!, [low.pins[8]!, high.pins[8]!])
        let clock = Pin(number: 15, name: "Shared clock", direction: .output)
        connect(clock, [low.pins[15]!, high.pins[15]!])
        connect(low.pins[7]!, [high.pins[5]!])
        low.pins[5]!.receive(.low)
        for chip in [low, high] {
            chip.pins[1]!.receive(.low)
        }
        for up in [true, false] {
            clock.drive(.low)
            for chip in [low, high] {
                chip.pins[9]!.receive(.high)
                chip.pins[10]!.receive(up ? .high : .low)
            }
            #expect(engine.settle())
            for chip in [low, high] { chip.pins[9]!.receive(.low) }
            #expect(engine.settle())
            for step in 1...32 {
                clock.drive(.high)
                #expect(engine.settle())
                let expected = (up ? step : -step) & 255
                #expect(Int(Self.q(low), radix: 2) == (expected & 15))
                #expect(Int(Self.q(high), radix: 2) == (expected >> 4))
                clock.drive(.low)
                #expect(engine.settle())
            }
        }
    }
}
