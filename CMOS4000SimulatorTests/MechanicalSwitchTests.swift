import CoreGraphics
import Foundation
import Testing
@testable import CMOS4000Simulator

@MainActor
struct MechanicalSwitchTests {
    private func pin(_ part: Int, _ number: Int = 1) -> WorkbenchTerminal {
        WorkbenchTerminal(partID: part, pinNumber: number)
    }

    private func connect(_ bench: Workbench, _ first: WorkbenchTerminal, _ second: WorkbenchTerminal) {
        bench.select(first)
        bench.select(second)
    }

    @Test(arguments: [1, 2])
    func pushButtonIsOpenAtRestAndWorksInBothDirections(sourcePin: Int) {
        let bench = Workbench()
        let contact = MechanicalSwitch()
        bench.add("Switch", component: contact)
        bench.add("+5V", component: WorkbenchPower(.fiveVolts))
        let output = pin(1, 3 - sourcePin)
        #expect(bench.readings[output] == .highImpedance)
        connect(bench, pin(2), pin(1, sourcePin))
        #expect(bench.readings[output] == .highImpedance)

        bench.setPressed(true, for: contact)
        #expect(bench.readings[output] == .high)
        #expect(contact.pins.values.allSatisfy { $0.driveState == .highImpedance })
        bench.setPressed(false, for: contact)
        #expect(bench.readings[output] == .highImpedance)

        bench.setPressed(true, for: contact)
        #expect(bench.releasePressedSwitches())
        #expect(bench.readings[output] == .highImpedance)
        #expect(!bench.releasePressedSwitches())
    }

    @Test(arguments: [false, true])
    func externalResistorSetsTheOpenState(pullUp: Bool) {
        let bench = Workbench()
        let contact = MechanicalSwitch()
        bench.add("Switch", component: contact)
        bench.add("Resistor", component: Resistor())
        bench.add("+5V", component: WorkbenchPower(.fiveVolts))
        bench.add("GND", component: WorkbenchPower(.ground))
        let output = pin(1, 2)
        connect(bench, pin(pullUp ? 3 : 4), pin(2))
        connect(bench, pin(2, 2), output)
        connect(bench, pin(pullUp ? 4 : 3), pin(1))
        #expect(bench.readings[output] == (pullUp ? .high : .low))
        bench.setPressed(true, for: contact)
        #expect(bench.readings[output] == (pullUp ? .low : .high))
        bench.setPressed(false, for: contact)
        #expect(bench.readings[output] == (pullUp ? .high : .low))
    }

    @Test func maintainedContactRoutesOnlyOneThrowAndPreservesContention() {
        let bench = Workbench()
        let contact = MechanicalSwitch(.spdt)
        bench.add("Switch", component: contact)
        bench.add("VCC", component: WorkbenchPower(.fiveVolts))
        bench.add("GND", component: WorkbenchPower(.ground))
        #expect(contact.pins[2]?.name == "Common")
        connect(bench, pin(2), pin(1, 2))
        #expect(bench.readings[pin(1, 1)] == .high)
        #expect(bench.readings[pin(1, 3)] == .highImpedance)
        connect(bench, pin(3), pin(1, 3))
        #expect(bench.readings[pin(1, 2)] == .high)
        bench.toggleContact(contact)
        #expect(bench.readings[pin(1, 2)] == .undefined)
        #expect(bench.readings[pin(1, 3)] == .undefined)
        #expect(bench.readings[pin(1, 1)] == .highImpedance)
        bench.toggleContact(contact)
        #expect(bench.readings[pin(1, 2)] == .high)
        #expect(bench.readings[pin(1, 3)] == .low)
    }

    @Test func preservesMaintainedPositionWiresAndRotationAcrossArchiveAndPaste() throws {
        let bench = Workbench()
        bench.add("Switch", component: MechanicalSwitch())
        bench.setSwitchDesignation(.spdt, for: 1)
        let contact = try #require(bench.parts.first?.component as? MechanicalSwitch)
        #expect(contact.designation == .spdt)
        bench.add("GND", component: WorkbenchPower(.ground))
        connect(bench, pin(1, 3), pin(2))
        bench.rotatePart(1, by: 1)
        bench.toggleContact(contact)
        #expect(!bench.canSetSwitchDesignation(.pushButton, for: 1))
        bench.setSwitchDesignation(.pushButton, for: 1)
        #expect(bench.parts[0].component === contact)
        #expect(bench.readings[pin(1, 2)] == .low)

        let data = try WorkbenchArchive(bench: bench).encoded()
        let reopened = Workbench()
        try reopened.open(JSONDecoder().decode(WorkbenchArchive.self, from: data))
        let restored = try #require(reopened.parts.first?.component as? MechanicalSwitch)
        #expect(restored.designation == .spdt && restored.selectsThrow3)
        #expect(reopened.rotations[1] == 1)
        #expect(reopened.readings[pin(1, 2)] == .low)

        let copy = try reopened.copyParts([1, 2])
        let ids = try reopened.pasteParts(copy, by: CGSize(width: 100, height: 100))
        let duplicate = try #require(reopened.parts.first { ids.contains($0.id) && $0.component is MechanicalSwitch })
        let duplicatedSwitch = try #require(duplicate.component as? MechanicalSwitch)
        #expect(duplicatedSwitch !== restored && duplicatedSwitch.selectsThrow3)
        #expect(reopened.rotations[duplicate.id] == 1)
        #expect(reopened.readings[pin(duplicate.id, 2)] == .low)
    }

    @Test func momentaryPressDoesNotPersistAndLegacySourcesStillReopen() throws {
        let bench = Workbench()
        let contact = MechanicalSwitch()
        bench.add("Switch", component: contact)
        bench.add("Pull-up", component: WorkbenchPullUp())
        bench.add("Logic Input", component: WorkbenchSwitch(showsValue: true))
        bench.add("Clock", component: WorkbenchClock())
        bench.setPressed(true, for: contact)
        let data = try WorkbenchArchive(bench: bench).encoded()
        let reopened = Workbench()
        try reopened.open(JSONDecoder().decode(WorkbenchArchive.self, from: data))
        let restored = try #require(reopened.parts.first?.component as? MechanicalSwitch)
        #expect(!restored.isPressed && restored.closedConnections.isEmpty)
        #expect(reopened.parts[1].component is WorkbenchPullUp)
        #expect(reopened.parts[2].component is WorkbenchSwitch)
        #expect(reopened.parts[3].component is WorkbenchClock)
        let copy = try bench.copyParts([1])
        let ids = try bench.pasteParts(copy, by: .zero)
        let duplicate = try #require(bench.parts.first { ids.contains($0.id) }?.component as? MechanicalSwitch)
        #expect(!duplicate.isPressed)
    }

    @Test(arguments: SwitchDesignation.allCases)
    func bothAppearancesShareGridAlignedTerminalsAtEveryRotation(designation: SwitchDesignation) throws {
        let bench = Workbench()
        bench.add("Switch", component: MechanicalSwitch(designation))
        let part = try #require(bench.parts.first)
        let position = CGPoint(x: 37, y: 114)
        for turns in 0..<4 {
            let schematic = SchematicPartGeometry(part: part, turns: turns)
            let physical = SchematicPartGeometry(part: part, turns: turns, appearance: .physicalDIP)
            #expect(Set(schematic.pins.keys) == Set(part.pins.keys))
            for number in part.pins.keys {
                let location = try #require(schematic.location(of: number, at: position, turns: turns, imported: false))
                #expect(location == physical.location(of: number, at: position, turns: turns, imported: false))
                #expect(location == WorkbenchWire.snap(location))
            }
        }
    }

    @Test func importsKiCadSwitchesWithTheirOriginalPinRoles() throws {
        let input = """
        (export (components
          (comp (ref SW1) (value SW_Push) (libsource (lib Switch) (part SW_Push)))
          (comp (ref SW2) (value SW_SPDT) (libsource (lib Switch) (part SW_SPDT))))
          (nets
            (net (code 1) (name +5V) (node (ref SW2) (pin 1)))
            (net (code 2) (name GND) (node (ref SW2) (pin 3)))
            (net (code 3) (name Output) (node (ref SW2) (pin 2)) (node (ref SW1) (pin 2)))
            (net (code 4) (name Unconnected) (node (ref SW1) (pin 1)))))
        """
        let bench = Workbench()
        let preview = try CircuitImportPreview.read(input, filenameExtension: "net")
        #expect(preview.supportedCount == 2)
        bench.importCircuit(preview, replacing: true)
        let push = try #require(bench.parts.first { $0.reference == "SW1" })
        let spdt = try #require(bench.parts.first { $0.reference == "SW2" })
        let momentary = try #require(push.component as? MechanicalSwitch)
        let maintained = try #require(spdt.component as? MechanicalSwitch)
        #expect(momentary.designation == .pushButton && maintained.designation == .spdt)
        #expect(bench.readings[pin(push.id, 1)] == .highImpedance)
        #expect(bench.readings[pin(push.id, 2)] == .high)
        bench.toggleContact(maintained)
        #expect(bench.readings[pin(push.id, 2)] == .low)
        bench.setPressed(true, for: momentary)
        #expect(bench.readings[pin(push.id, 1)] == .low)
    }

    @Test func unrelatedDiscreteLEDStillUsesDCWithMechanicalSwitchPresent() {
        let bench = Workbench()
        bench.add("LED", component: LED3mm())
        bench.add("Resistor", component: Resistor())
        bench.add("+5V", component: WorkbenchPower(.fiveVolts))
        bench.add("GND", component: WorkbenchPower(.ground))
        let contact = MechanicalSwitch()
        bench.add("Switch", component: contact)
        connect(bench, pin(3), pin(2))
        connect(bench, pin(2, 2), pin(1, 2))
        connect(bench, pin(4), pin(1))
        #expect(bench.illuminatedLEDs == [1])
        bench.setPressed(true, for: contact)
        #expect(bench.illuminatedLEDs == [1])
        #expect(bench.circuitNet(at: pin(1, 2))?.dcVoltage != nil)
    }
}
