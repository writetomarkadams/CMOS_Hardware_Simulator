import CoreGraphics
import Foundation
import Testing
@testable import CMOS4000Simulator

@MainActor
struct SN74HC08Tests {
    private func terminal(_ part: Int, _ pin: Int = 1) -> WorkbenchTerminal {
        WorkbenchTerminal(partID: part, pinNumber: pin)
    }

    private func connect(_ bench: Workbench, _ first: WorkbenchTerminal, _ second: WorkbenchTerminal) {
        bench.select(first)
        bench.select(second)
    }

    @Test(arguments: [[1, 2, 3], [4, 5, 6], [9, 10, 8], [12, 13, 11]])
    func truthTableAndSupplyRecovery(pins: [Int]) throws {
        let bench = Workbench()
        let chip = SN74HC08()
        let a = WorkbenchSwitch()
        let b = WorkbenchSwitch()
        bench.add("74HC08", component: chip)
        bench.add("A", component: a)
        bench.add("B", component: b)
        bench.add("+5V", component: WorkbenchPower(.fiveVolts))
        bench.add("GND", component: WorkbenchPower(.ground))
        let output = terminal(1, pins[2])
        #expect(bench.readings[output] == .undefined)

        connect(bench, terminal(2), terminal(1, pins[0]))
        #expect(bench.readings[output] == .low)
        bench.toggle(a)
        #expect(bench.readings[output] == .undefined)
        connect(bench, terminal(3), terminal(1, pins[1]))
        #expect(bench.readings[output] == .low)
        bench.toggle(a)
        #expect(bench.readings[output] == .low)
        bench.toggle(b)
        #expect(bench.readings[output] == .low)
        bench.toggle(a)
        #expect(bench.readings[output] == .high)
        for other in [3, 6, 8, 11] where other != pins[2] {
            #expect(bench.readings[terminal(1, other)] == .undefined)
        }

        bench.setPowerMode(.explicit)
        #expect(chip.powerState == .disconnected)
        #expect(bench.readings[output] == .undefined)
        connect(bench, terminal(5), terminal(1, 7))
        connect(bench, terminal(5), terminal(1, 14))
        #expect(chip.powerState == .incorrect)
        #expect(bench.readings[output] == .undefined)
        bench.removeWire(try #require(bench.wires.last).id)
        connect(bench, terminal(4), terminal(1, 14))
        #expect(chip.powerState == .powered)
        #expect(bench.readings[output] == .high)
        bench.removeWire(try #require(bench.wires.last).id)
        #expect(chip.powerState == .disconnected)
        #expect(bench.readings[output] == .undefined)
        bench.undo()
        #expect(bench.readings[output] == .high)
    }

    @Test(arguments: [1.4, 1.6, 3.4, 3.6])
    func classifiesSolvedDCAtFiveVolts(target: Double) throws {
        let bench = Workbench()
        let upper = Resistor()
        let lower = Resistor()
        upper.setResistance(5 - target, unit: .kilohms)
        lower.setResistance(target, unit: .kilohms)
        bench.add("74HC08", component: SN74HC08())
        bench.add("CD4081", component: CD4081())
        bench.add("+5V", component: WorkbenchPower(.fiveVolts))
        bench.add("GND", component: WorkbenchPower(.ground))
        bench.add("Upper", component: upper)
        bench.add("Lower", component: lower)
        bench.add("LED", component: LED3mm())
        // Reverse-bias the LED so this region qualifies for the existing DC solver.
        connect(bench, terminal(3), terminal(5))
        connect(bench, terminal(4), terminal(6, 2))
        connect(bench, terminal(4), terminal(7, 2))
        connect(bench, terminal(5, 2), terminal(6))
        connect(bench, terminal(7), terminal(6))
        connect(bench, terminal(1), terminal(6))
        connect(bench, terminal(2), terminal(6))
        connect(bench, terminal(1, 2), terminal(3))
        connect(bench, terminal(2, 2), terminal(3))
        let voltage = try #require(bench.circuitNet(at: terminal(1))?.dcVoltage)
        #expect(abs(voltage - target) < 1e-6)
        let hc: LogicState = target < 1.5 ? .low : target > 3.5 ? .high : .undefined
        #expect(bench.readings[terminal(1, 3)] == hc)
        #expect(bench.readings[terminal(2, 3)] == (target >= 2 ? .high : .undefined))
    }

    @Test func packageGeometryAndArchive() throws {
        let bench = Workbench()
        bench.add("74HC08", component: SN74HC08())
        bench.add("+5V", component: WorkbenchPower(.fiveVolts))
        let part = try #require(bench.parts.first)
        let dip = try #require(DIPPackage(part: part))
        #expect(dip.usesCD4070Artwork)
        #expect(dip.pins.map(\.name) == ["1A", "1B", "1Y", "2A", "2B", "2Y", "GND",
                                         "3Y", "3A", "3B", "4Y", "4A", "4B", "VCC"])
        #expect(dip.pins.filter { $0.direction == .output }.map(\.number) == [3, 6, 8, 11])
        #expect(dip.pins.filter { $0.direction == .power }.map(\.number) == [7, 14])
        let reference = WorkbenchPart(id: 1, name: "CD4081", component: CD4081(), unitPlacement: nil, chipNumber: 1)
        #expect(dip.endpoints == DIPPackage(part: reference)?.endpoints)

        for turns in 0...3 {
            let schematic = SchematicPartGeometry(part: part, turns: turns)
            let units = try #require(schematic.packageLayout).units
            #expect(units.map { $0.symbol.terminals.map(\.id).sorted() } == [[1, 2, 3], [4, 5, 6], [8, 9, 10], [11, 12, 13], [7, 14]])
            for appearance in ComponentAppearance.allCases {
                let geometry = SchematicPartGeometry(part: part, turns: turns, appearance: appearance)
                let endpoints = try (1...14).map { pin in
                    try #require(geometry.location(of: pin, at: .zero, turns: turns, imported: false))
                }
                #expect(Set(endpoints.map { "\($0.x),\($0.y)" }).count == 14)
                #expect(endpoints.allSatisfy { WorkbenchWire.snap($0) == $0 })
            }
        }
        connect(bench, terminal(1, 9), terminal(2))
        connect(bench, terminal(1, 10), terminal(2))
        bench.componentAppearance = .physicalDIP
        bench.rotatePart(1, by: 1)
        let reopened = Workbench()
        let data = try WorkbenchArchive(bench: bench).encoded()
        try reopened.open(JSONDecoder().decode(WorkbenchArchive.self, from: data))
        #expect(reopened.parts.first?.component is SN74HC08)
        #expect(reopened.componentAppearance == .physicalDIP)
        #expect(reopened.rotations[1] == 1)
        #expect(reopened.readings[terminal(1, 8)] == .high)
        reopened.componentAppearance = .schematic
        #expect(reopened.readings[terminal(1, 8)] == .high)
    }

    @Test(arguments: ["74HC08", "74LS08"])
    func importsKiCadUnitsAndRestoresSharedChip(symbol: String) throws {
        let input = """
        (export (components
          (comp (ref U1) (value 74HC08) (libsource (lib 74xx) (part \(symbol)))))
          (nets
            (net (code 1) (name +5V) (node (ref U1) (pin 14)) (node (ref U1) (pin 4)) (node (ref U1) (pin 5)))
            (net (code 2) (name GND) (node (ref U1) (pin 7)))))
        """
        let bench = Workbench()
        let preview = try CircuitImportPreview.read(input, filenameExtension: "net")
        #expect(preview.supportedCount == 1)
        bench.importCircuit(preview, replacing: true)
        bench.setPowerMode(.explicit)
        let reopened = Workbench()
        let data = try WorkbenchArchive(bench: bench).encoded()
        try reopened.open(JSONDecoder().decode(WorkbenchArchive.self, from: data))
        for workbench in [bench, reopened] {
            let parts = workbench.parts.filter { $0.component is SN74HC08 }
            #expect(parts.count == 5)
            let gate = try #require(parts.first { $0.reference == "U1B" })
            let chip = try #require(gate.component as? SN74HC08)
            #expect(parts.allSatisfy { $0.component === chip })
            #expect(chip.powerState == .powered)
            #expect(workbench.readings[terminal(gate.id, 6)] == .high)
        }
    }
}
