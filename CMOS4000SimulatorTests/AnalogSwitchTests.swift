import Foundation
import Testing
@testable import CMOS4000Simulator

struct AnalogSwitchTests {
    private func connect(_ engine: SimulationEngine, _ pins: Pin...) -> Net {
        let net = Net(name: "Test")
        for pin in pins { net.connect(pin) }
        engine.addNet(net)
        return net
    }

    private func checkRouting(_ kind: AnalogSwitchKind, selectors: [Int], banks: [(Int, [Int])]) {
        let engine = SimulationEngine()
        engine.automaticallyPowerChips = true
        let chip = AnalogSwitch(kind)
        engine.addComponent(chip)
        chip.pins[6]!.receive(.low)
        let commons = banks.map { common, _ in Pin(number: common, name: "Common source", direction: .output) }
        let channels = banks.map { _, numbers in
            numbers.map { Pin(number: $0, name: "Channel source", direction: .output) }
        }
        for sources in channels {
            for source in sources { _ = connect(engine, source, chip.pins[source.number]!) }
        }
        for source in commons { _ = connect(engine, source, chip.pins[source.number]!) }

        for address in 0..<(1 << selectors.count) {
            for (bit, number) in selectors.enumerated() {
                chip.pins[number]!.receive(address & (1 << bit) == 0 ? .low : .high)
            }
            let selected = banks.indices.map { kind == .cd4053 ? (address >> $0) & 1 : address }
            for (index, sources) in channels.enumerated() {
                for (channel, source) in sources.enumerated() {
                    source.drive(channel == selected[index] ? (index == 1 ? .low : .high) : .highImpedance)
                }
            }
            #expect(engine.settle())
            for (index, common) in commons.enumerated() {
                #expect(common.state == (index == 1 ? .low : .high))
                common.drive(index == 1 ? .high : .low)
            }
            for source in channels.joined() { source.drive(.highImpedance) }
            #expect(engine.settle())
            for (index, sources) in channels.enumerated() {
                for (channel, source) in sources.enumerated() {
                    #expect(source.state == (channel == selected[index] ? (index == 1 ? .high : .low) : .highImpedance))
                }
                commons[index].drive(.highImpedance)
            }
        }

        for inhibit in [LogicState.high, .highImpedance, .undefined] {
            chip.pins[6]!.receive(inhibit)
            for common in commons { common.drive(.high) }
            #expect(engine.settle())
            #expect(channels.joined().allSatisfy { $0.state == .highImpedance })
        }

        chip.pins[6]!.receive(.low)
        for unknown in [LogicState.undefined, .highImpedance] {
            chip.pins[selectors[0]]!.receive(unknown)
            #expect(engine.settle())
            for (index, sources) in channels.enumerated() {
                let expected: LogicState = kind == .cd4053 && index > 0 ? .high : .highImpedance
                #expect(sources.last!.state == expected)
                #expect(sources.dropLast().allSatisfy { $0.state == .highImpedance })
            }
        }
    }

    @Test func cd4051TruthTable() {
        checkRouting(.cd4051, selectors: [11, 10, 9], banks: [(3, [13, 14, 15, 12, 1, 5, 2, 4])])
    }

    @Test func cd4052TruthTable() {
        checkRouting(.cd4052, selectors: [10, 9], banks: [(13, [12, 14, 15, 11]), (3, [1, 5, 2, 4])])
    }

    @Test func cd4053TruthTable() {
        checkRouting(.cd4053, selectors: [11, 10, 9], banks: [(14, [12, 13]), (15, [2, 1]), (4, [5, 3])])
    }

    @Test func cascadedSwitchesResolveStrengthContentionAndRelease() {
        let engine = SimulationEngine()
        engine.automaticallyPowerChips = true
        let first = AnalogSwitch(.cd4051)
        let second = AnalogSwitch(.cd4053)
        for chip in [first, second] {
            engine.addComponent(chip)
            for number in [6, 9, 10, 11] { chip.pins[number]!.receive(.low) }
        }
        let pull = WorkbenchPullUp()
        let source = Pin(number: 1, name: "Source", direction: .output)
        let opposing = Pin(number: 2, name: "Opposing", direction: .output)
        let common = connect(engine, first.pins[3]!, pull.pins[1]!, opposing)
        let middle = connect(engine, first.pins[13]!, second.pins[14]!)
        let end = connect(engine, second.pins[12]!, source)

        source.drive(.low)
        #expect(engine.settle())
        #expect([common, middle, end].allSatisfy { $0.state == .low })
        opposing.drive(.high)
        #expect(engine.settle())
        #expect([common, middle, end].allSatisfy { $0.state == .undefined })
        opposing.drive(.highImpedance)
        source.drive(.highImpedance)
        #expect(engine.settle())
        #expect(source.state == .high)
        #expect(source.strongState == .highImpedance)
        second.pins[6]!.receive(.high)
        #expect(engine.settle())
        #expect(end.state == .highImpedance)
        #expect(middle.state == .high)
    }

    @Test func explicitSuppliesAndPowerLoss() {
        let engine = SimulationEngine()
        let chip = AnalogSwitch(.cd4053)
        engine.addComponent(chip)
        chip.pins[11]!.receive(.low)
        chip.pins[6]!.receive(.low)
        let vdd = WorkbenchPower(.fiveVolts).pins[1]!
        let vss = WorkbenchPower(.ground).pins[1]!
        let vee = WorkbenchPower(.ground).pins[1]!
        let signal = WorkbenchSwitch()
        signal.toggle()
        _ = connect(engine, vdd, chip.pins[16]!)
        _ = connect(engine, vss, chip.pins[8]!)
        _ = connect(engine, vee, chip.pins[7]!)
        _ = connect(engine, signal.pins[1]!, chip.pins[12]!)

        #expect(engine.settle())
        #expect(chip.powerState == .powered)
        #expect(chip.pins[14]!.state == .high)

        vee.drive(.highImpedance)
        #expect(engine.settle())
        #expect(chip.powerState == .disconnected)
        #expect(chip.pins[14]!.state == .highImpedance)
        #expect(chip.pins[12]!.state == .high)
        vee.drivenSupplyRail = nil
        vee.drive(.low)
        #expect(engine.settle())
        #expect(chip.powerState == .incorrect)
        #expect(chip.pins[14]!.state == .highImpedance)
        vee.drivenSupplyRail = .ground
        #expect(engine.settle())
        #expect(chip.pins[14]!.state == .high)
    }

    @Test(arguments: AnalogSwitchKind.allCases)
    func symbolAndWiringRoundTrip(kind: AnalogSwitchKind) throws {
        let bench = Workbench()
        let chip = AnalogSwitch(kind)
        let symbol = try #require(KiCadSymbol.analogSwitches[kind])
        #expect(symbol.terminals.map(\.id) == Array(1...16))
        #expect(symbol.terminals.allSatisfy { chip.pins[$0.id]?.name == $0.name })
        #expect(Set(chip.pins.filter { $0.value.direction == .power }.keys) == [7, 8, 16])
        bench.add(kind.rawValue, component: chip)
        bench.add("Ground", component: WorkbenchPower(.ground))
        bench.add("Input", component: WorkbenchSwitch())
        bench.add("LED", component: WorkbenchLED())
        let parts = bench.parts
        let route: (Int, Int, [Int]) = switch kind {
        case .cd4051: (13, 3, [6, 9, 10, 11])
        case .cd4052: (12, 13, [6, 9, 10])
        case .cd4053: (12, 14, [6, 11])
        }
        func wire(_ a: Int, _ ap: Int, _ b: Int, _ bp: Int) {
            bench.select(WorkbenchTerminal(partID: parts[a].id, pinNumber: ap))
            bench.select(WorkbenchTerminal(partID: parts[b].id, pinNumber: bp))
        }
        for control in route.2 { wire(1, 1, 0, control) }
        wire(2, 1, 0, route.0)
        wire(0, route.1, 3, 1)
        let led = WorkbenchTerminal(partID: parts[3].id, pinNumber: 1)
        #expect(bench.readings[led] == .low)

        let data = try JSONEncoder().encode(WorkbenchArchive(bench: bench))
        let reopened = Workbench()
        try reopened.open(JSONDecoder().decode(WorkbenchArchive.self, from: data))
        #expect(reopened.parts.first?.reference == parts.first?.reference)
        #expect((reopened.parts.first?.component as? AnalogSwitch)?.kind == kind)
        #expect(reopened.wires.count == route.2.count + 2)
        #expect(reopened.readings[led] == .low)
        let reloadedSource = try #require(reopened.parts[2].component as? WorkbenchSwitch)
        reopened.toggle(reloadedSource)
        #expect(reopened.readings[led] == .high)
    }
}
