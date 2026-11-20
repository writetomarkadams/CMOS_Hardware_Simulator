import Foundation
import Testing
@testable import CMOS4000Simulator

struct NE555Tests {
    @Test("NE555 digital function table, latch, reset priority and unknown inputs")
    func functionTable() {
        let states: [LogicState] = [.low, .high, .undefined, .highImpedance]
        for reset in states {
            for trigger in states {
                for threshold in states {
                    let chip = NE555()
                    chip.pins[4]!.receive(reset)
                    chip.pins[2]!.receive(trigger)
                    chip.pins[6]!.receive(threshold)
                    chip.evaluate()
                    let expected: LogicState
                    if reset == .low { expected = .low }
                    else if reset != .high { expected = .undefined }
                    else if trigger == .low { expected = .high }
                    else if trigger == .high && threshold == .high { expected = .low }
                    else { expected = .undefined }
                    #expect(chip.pins[3]!.driveState == expected)
                    #expect(chip.pins[7]!.driveState == (expected == .low ? .low : expected == .high ? .highImpedance : .undefined))
                }
            }
        }
        let chip = NE555()
        chip.pins[4]!.receive(.high)
        chip.pins[2]!.receive(.low)
        chip.pins[6]!.receive(.high)
        chip.evaluate()
        chip.pins[2]!.receive(.high)
        chip.pins[6]!.receive(.low)
        chip.evaluate()
        #expect(chip.pins[3]!.driveState == .high)
        chip.pins[6]!.receive(.high)
        chip.evaluate()
        chip.pins[6]!.receive(.low)
        chip.evaluate()
        #expect(chip.pins[3]!.driveState == .low)
        for control in states where control != .highImpedance {
            chip.pins[5]!.receive(control)
            chip.evaluate()
            #expect(chip.pins[3]!.driveState == .undefined)
            chip.pins[4]!.receive(.low)
            chip.evaluate()
            #expect(chip.pins[3]!.driveState == .low)
            chip.pins[4]!.receive(.high)
        }
    }

    @Test("NE555 power loss clears latch, restoration needs valid control, discharge needs pull-up")
    func powerAndWiring() throws {
        let engine = SimulationEngine()
        let chip = NE555()
        let inverter = CD40106()
        let vcc = WorkbenchPower(.fiveVolts)
        let ground = WorkbenchPower(.ground)
        let reset = WorkbenchSwitch()
        let trigger = WorkbenchSwitch()
        let threshold = WorkbenchSwitch()
        let pullUp = WorkbenchPullUp()
        reset.toggle()
        for component: any LogicComponent in [chip, inverter, vcc, ground, reset, trigger, threshold, pullUp] {
            engine.addComponent(component)
        }
        func wire(_ pins: [Pin]) {
            let net = Net(name: "test")
            for pin in pins { net.connect(pin) }
            engine.addNet(net)
        }
        let timerSupply = Pin(number: 1, name: "Supply", direction: .output)
        timerSupply.drivenSupplyRail = .fiveVolts
        timerSupply.drive(.high)
        wire([timerSupply, chip.pins[8]!])
        wire([vcc.pins[1]!, inverter.pins[14]!])
        wire([ground.pins[1]!, chip.pins[1]!, inverter.pins[7]!])
        wire([reset.pins[1]!, chip.pins[4]!])
        wire([trigger.pins[1]!, chip.pins[2]!])
        wire([threshold.pins[1]!, chip.pins[6]!])
        wire([chip.pins[3]!, inverter.pins[1]!])
        wire([chip.pins[7]!, pullUp.pins[1]!])
        #expect(engine.settle())
        #expect(chip.pins[3]!.driveState == .high)
        #expect(chip.pins[7]!.state == .high)
        #expect(chip.pins[7]!.supplyRail == nil)
        trigger.toggle()
        #expect(engine.settle())
        timerSupply.drive(.highImpedance)
        #expect(engine.settle())
        #expect(chip.pins[3]!.driveState == .undefined)
        #expect(chip.pins[7]!.state == .undefined)
        #expect(inverter.pins[2]!.driveState == .undefined)
        timerSupply.drive(.high)
        #expect(engine.settle())
        #expect(chip.pins[3]!.driveState == .undefined)
        threshold.toggle()
        #expect(engine.settle())
        #expect(chip.pins[3]!.driveState == .low)
        #expect(chip.pins[7]!.state == .low)
        #expect(inverter.pins[2]!.driveState == .high)
        timerSupply.drivenSupplyRail = nil
        #expect(engine.settle())
        #expect(chip.powerState == .incorrect)
        #expect(chip.pins[3]!.driveState == .undefined)
        engine.automaticallyPowerChips = true
        #expect(engine.settle())
        #expect(chip.pins[3]!.driveState == .low)
    }

    @Test("NE555 symbol pin mapping, Automatic Power and saved circuit round-trip")
    func workbenchIntegration() throws {
        let symbol = try #require(KiCadSymbol.ne555)
        #expect(symbol.terminals.map(\.id).sorted() == Array(1...8))
        let bench = Workbench()
        bench.add("NE555", component: NE555())
        bench.add("GND", component: WorkbenchPower(.ground))
        bench.select(WorkbenchTerminal(partID: 2, pinNumber: 1))
        bench.select(WorkbenchTerminal(partID: 1, pinNumber: 4))
        #expect(bench.parts[0].reference == "U1")
        #expect(bench.readings[WorkbenchTerminal(partID: 1, pinNumber: 3)] == .low)
        let archive = try JSONDecoder().decode(WorkbenchArchive.self, from: JSONEncoder().encode(WorkbenchArchive(bench: bench)))
        let restored = Workbench()
        try restored.open(archive)
        #expect(restored.parts[0].component is NE555)
        #expect(restored.wires.count == 1)
        #expect(restored.readings[WorkbenchTerminal(partID: 1, pinNumber: 3)] == .low)
        restored.setPowerMode(.explicit)
        #expect(restored.readings[WorkbenchTerminal(partID: 1, pinNumber: 3)] == .undefined)
    }
}
