import CoreGraphics
import Foundation
import Testing
@testable import CMOS4000Simulator

@MainActor
struct TransistorTests {
    @Test(arguments: TransistorDesignation.allCases)
    func physicalLeadsAndRotationKeepElectricalPinNumbers(designation: TransistorDesignation) throws {
        let bench = Workbench()
        bench.add("Transistor", component: Transistor())
        bench.setTransistorDesignation(designation, for: 1)
        let part = try #require(bench.parts.first)
        let device = try #require(part.component as? Transistor)
        #expect(device.designation == designation)
        let position = CGPoint(x: 47.3, y: 112.8)
        for turns in 0..<4 {
            let schematic = SchematicPartGeometry(part: part, turns: turns)
            let physical = SchematicPartGeometry(part: part, turns: turns, appearance: .physicalDIP)
            let package = try #require(physical.to92Package)
            #expect(package.leads.map(\.number) == [1, 2, 3])
            let names = designation == .bc547B ? ["C", "B", "E"] : ["E", "B", "C"]
            #expect(package.leads.map(\.name) == names)
            let symbol = try #require(part.librarySymbol)
            #expect(symbol.isCircular)
            #expect(symbol.terminals.sorted { $0.id < $1.id }.map(\.name) == names)
            #expect(Set(schematic.pins.keys) == Set(physical.pins.keys))
            let pivot = physical.canvasOrigin(at: position, imported: false)
            #expect(pivot == schematic.canvasOrigin(at: position, imported: false))
            for number in 1...3 {
                let lead = try #require(package.endpoints[number])
                #expect(package.body.insetBy(dx: 4, dy: 4).contains(lead))
                let offset = CGPoint(x: CGFloat(number - 2) * 20, y: 30).schematicRotated(turns)
                let location = try #require(physical.location(of: number, at: position, turns: turns, imported: false))
                #expect(location == CGPoint(x: pivot.x + offset.x, y: pivot.y + offset.y))
                #expect(location == WorkbenchWire.snap(location))
            }
        }
    }

    @Test(arguments: [false, true])
    func savesOrRestoresLegacyWiringAndCopiesRotatedTransistor(legacy: Bool) throws {
        let bench = Workbench()
        bench.add("Transistor", component: Transistor())
        bench.add("Ground", component: WorkbenchPower(.ground))
        bench.placeNewPart(1, at: CGPoint(x: 40, y: 50))
        bench.rotatePart(1, by: 1)
        let emitter = WorkbenchTerminal(partID: 1, pinNumber: 1)
        let ground = WorkbenchTerminal(partID: 2, pinNumber: 1)
        bench.select(emitter)
        bench.select(ground)

        var data = try WorkbenchArchive(bench: bench).encoded()
        var json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        var parts = try #require(json["parts"] as? [[String: Any]])
        #expect(parts[0]["transistorDesignation"] as? String == "2N3904")
        if legacy {
            parts[0].removeValue(forKey: "transistorDesignation")
            parts[0]["name"] = "2N3904"
            json["parts"] = parts
            data = try JSONSerialization.data(withJSONObject: json)
        }
        let reopened = Workbench()
        try reopened.open(JSONDecoder().decode(WorkbenchArchive.self, from: data))
        let device = try #require(reopened.parts[0].component as? Transistor)
        #expect(device.designation == .twoN3904)
        #expect(reopened.positions[1] == CGPoint(x: 40, y: 50))
        #expect(reopened.rotations[1] == 1)
        let net = try #require(reopened.circuitNet(at: emitter))
        #expect(net === reopened.circuitNet(at: ground))
        #expect(net.pins.contains { $0 === device.pin(.emitter) })

        reopened.setTransistorDesignation(.twoN3904, for: 1)
        #expect(!reopened.isDirty)
        #expect(reopened.circuitNet(at: emitter) === net)

        let copy = try reopened.copyParts([1, 2])
        let pasted = try reopened.pasteParts(copy, by: CGSize(width: 100, height: 100))
        let duplicate = try #require(reopened.parts.first { pasted.contains($0.id) && $0.component is Transistor })
        let copiedDevice = try #require(duplicate.component as? Transistor)
        #expect(copiedDevice.designation == device.designation)
        #expect(copiedDevice.pin(.emitter) !== device.pin(.emitter))
        #expect(reopened.rotations[duplicate.id] == 1)
        let copiedEmitter = WorkbenchTerminal(partID: duplicate.id, pinNumber: 1)
        let copiedNet = try #require(reopened.circuitNet(at: copiedEmitter))
        #expect(copiedNet !== net)
        #expect(copiedNet.pins.contains { $0 === copiedDevice.pin(.emitter) })
        #expect(reopened.wires.contains { $0.first == copiedEmitter && pasted.contains($0.second.partID) })
    }

    @Test func bc547BImportsSwitchesAndReopensWithWiring() throws {
        let input = """
        (export (components
          (comp (ref Q1) (value BC547) (footprint Package_TO_SOT_THT:TO-92_Inline)
            (libsource (lib Transistor_BJT) (part BC547))))
          (nets (net (code 1) (name GND) (node (ref Q1) (pin 3)))))
        """
        let bench = Workbench()
        let preview = try CircuitImportPreview.read(input, filenameExtension: "net")
        #expect(preview.supportedCount == 1)
        bench.importCircuit(preview, replacing: true)
        let part = try #require(bench.parts.first { $0.reference == "Q1" })
        let device = try #require(part.component as? Transistor)
        #expect(device.designation == .bc547B)
        #expect(device.pin(.collector).number == 1)
        #expect(device.pin(.base).number == 2)
        #expect(device.pin(.emitter).number == 3)
        let emitter = WorkbenchTerminal(partID: part.id, pinNumber: 3)
        let ground = try #require(bench.circuitNet(at: emitter))
        #expect(ground.pins.contains { $0.drivenSupplyRail == .ground })
        bench.setTransistorDesignation(.twoN3904, for: part.id)
        #expect(bench.parts.first { $0.id == part.id }?.component === device)
        #expect(bench.circuitNet(at: emitter) === ground)

        bench.rotatePart(part.id, by: 1)
        let reopened = Workbench()
        let data = try WorkbenchArchive(bench: bench).encoded()
        try reopened.open(JSONDecoder().decode(WorkbenchArchive.self, from: data))
        let restored = try #require(reopened.parts.first { $0.id == part.id }?.component as? Transistor)
        #expect(restored.designation == .bc547B)
        #expect(reopened.rotations[part.id] == 1)
        #expect(reopened.circuitNet(at: emitter)?.pins.contains { $0 === restored.pin(.emitter) } == true)

        let switchingDevice = Transistor(.bc547B)
        let engine = SimulationEngine()
        let drive = WorkbenchSwitch()
        let low = WorkbenchPower(.ground)
        let pullUp = Resistor()
        let high = WorkbenchPower(.fiveVolts)
        let parts: [any LogicComponent] = [drive, low, pullUp, high, switchingDevice]
        for component in parts { engine.addComponent(component) }
        func wire(_ name: String, _ pins: Pin...) -> Net {
            let net = Net(name: name)
            for pin in pins { net.connect(pin) }
            engine.addNet(net)
            return net
        }
        _ = wire("Emitter", switchingDevice.pin(.emitter), low.pins[1]!)
        _ = wire("Base", switchingDevice.pin(.base), drive.pins[1]!)
        _ = wire("Supply", pullUp.pins[1]!, high.pins[1]!)
        let output = wire("Collector", switchingDevice.pin(.collector), pullUp.pins[2]!)
        #expect(engine.settle())
        #expect(output.state == .high)
        drive.toggle()
        #expect(engine.settle())
        #expect(output.state == .low)
        #expect(output.dcVoltage == nil)
        drive.toggle()
        #expect(engine.settle())
        #expect(output.state == .high)
    }

    @Test func pnpSymbolArrowPointsInwardOnEmitter() throws {
        let symbol = try #require(KiCadSymbol.pnp2N3906)
        let emitter = try #require(symbol.terminals.first { $0.id == 1 })
        let arrow = try #require(symbol.markings.first { $0.count == 4 && $0.first == $0.last })
        let tip = arrow[2]
        #expect(tip.x < arrow[0].x && tip.x < arrow[1].x)
        #expect(arrow.allSatisfy { $0.y * emitter.position.y > 0 })
        #expect(abs(tip.y) < abs(arrow[0].y) && abs(tip.y) < abs(arrow[1].y))
    }

    @Test func pnpImportPreservesHighSideWiringThroughArchive() throws {
        let input = """
        (export (components
          (comp (ref Q1) (value 2N3906) (footprint Package_TO_SOT_THT:TO-92_Inline)
            (libsource (lib Transistor_BJT) (part 2N3906))))
          (nets (net (code 1) (name +5V) (node (ref Q1) (pin 1)))))
        """
        let bench = Workbench()
        let preview = try CircuitImportPreview.read(input, filenameExtension: "net")
        #expect(preview.supportedCount == 1)
        bench.importCircuit(preview, replacing: true)
        let part = try #require(bench.parts.first { $0.reference == "Q1" })
        let transistor = try #require(part.component as? Transistor)
        #expect(transistor.designation == .twoN3906)
        let emitter = WorkbenchTerminal(partID: part.id, pinNumber: 1)
        let supply = try #require(bench.circuitNet(at: emitter))
        #expect(supply.pins.contains { $0.drivenSupplyRail == .fiveVolts })
        #expect(!bench.canSetTransistorDesignation(.twoN3904, for: part.id))
        bench.rotatePart(part.id, by: 1)

        let reopened = Workbench()
        let data = try WorkbenchArchive(bench: bench).encoded()
        try reopened.open(JSONDecoder().decode(WorkbenchArchive.self, from: data))
        let restored = try #require(reopened.parts.first { $0.id == part.id }?.component as? Transistor)
        #expect(restored.designation == .twoN3906)
        #expect(reopened.rotations[part.id] == 1)
        let restoredSupply = try #require(reopened.circuitNet(at: emitter))
        #expect(restoredSupply.pins.contains { $0 === restored.pin(.emitter) })
        #expect(restoredSupply.pins.contains { $0.drivenSupplyRail == .fiveVolts })
    }

    @Test(arguments: [false, true])
    func pnpSourcesAndReleasesPulledDownCollector(withPhysicalLED: Bool) {
        let transistor = Transistor(.twoN3906)
        let engine = SimulationEngine()
        let base = WorkbenchSwitch()
        let high = WorkbenchPower(.fiveVolts)
        let ground = WorkbenchPower(.ground)
        let pullDown = Resistor()
        let led = LED3mm()
        let parts: [any LogicComponent] = [transistor, base, high, ground, pullDown]
        for part in parts { engine.addComponent(part) }
        func wire(_ name: String, _ pins: [Pin]) -> Net {
            let net = Net(name: name)
            for pin in pins { net.connect(pin) }
            engine.addNet(net)
            return net
        }

        _ = wire("Emitter", [transistor.pin(.emitter), high.pins[1]!])
        let baseNet = wire("Base", [transistor.pin(.base), base.pins[1]!])
        let output = wire("Collector", [transistor.pin(.collector), pullDown.pins[1]!])
        let returnNet = wire("Return", [ground.pins[1]!, pullDown.pins[2]!])
        if withPhysicalLED {
            engine.addComponent(led)
            output.connect(led.pins[2]!)
            returnNet.connect(led.pins[1]!)
        }

        #expect(engine.settle())
        #expect(baseNet.state == .low)
        #expect(output.state == .high)
        #expect(output.dcVoltage == nil)

        base.toggle()
        #expect(engine.settle())
        #expect(baseNet.state == .high)
        #expect(transistor.pin(.collector).driveState == .highImpedance)
        #expect(output.state == .low)
        #expect(output.dcVoltage == nil)

        base.toggle()
        #expect(engine.settle())
        #expect(output.state == .high)
    }

    @Test(arguments: [false, true])
    func pnpWithMissingInputIsUndefined(connectEmitter: Bool) {
        let engine = SimulationEngine()
        let transistor = Transistor(.twoN3906)
        let source = WorkbenchPower(connectEmitter ? .fiveVolts : .ground)
        engine.addComponent(transistor)
        engine.addComponent(source)
        let input = Net(name: "Only connected input")
        input.connect(source.pins[1]!)
        input.connect(transistor.pin(connectEmitter ? .emitter : .base))
        engine.addNet(input)
        let output = Net(name: "Collector")
        output.connect(transistor.pin(.collector))
        engine.addNet(output)
        #expect(engine.settle())
        #expect(output.state == .undefined)
    }

    @Test func reversedLeadOrderIsIncompatibleWithExistingConnections() {
        let original = TransistorDesignation.defaultDevice.definition
        let reversed = TransistorDefinition(package: original.package, leads: Array(original.leads.reversed()),
                                            symbol: original.symbol, model: original.model)
        #expect(original.preservesConnections(of: original))
        #expect(!reversed.preservesConnections(of: original))
    }
}
