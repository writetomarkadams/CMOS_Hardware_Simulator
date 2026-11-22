import Foundation
import Testing
@testable import CMOS4000Simulator

struct KiCadSchematicTests {
    private let resistor = """
        (symbol "Device:R"
          (symbol "R_0_1" (rectangle (start -0.5 0.5) (end 0.5 -0.5) (fill (type none))))
          (symbol "R_1_1"
            (pin passive line (at -2 0 0) (length 1.5) (name "~") (number "1"))
            (pin passive line (at 2 0 180) (length 1.5) (name "~") (number "2"))))
        """

    private func placed(_ reference: String, at: String, lib: String = "Device:R", unit: Int = 1,
                        value: String = "4k7", mirror: String = "") -> String {
        """
        (symbol (lib_id "\(lib)") (at \(at)) (unit \(unit)) \(mirror)
          (property "Reference" "\(reference)") (property "Value" "\(value)"))
        """
    }

    private func wire(_ a: String, _ b: String) -> String { "(wire (pts (xy \(a)) (xy \(b))))" }

    private func sheet(_ body: String, symbols: String? = nil) -> String {
        "(kicad_sch (version 20260306) (lib_symbols \(symbols ?? resistor)) \(body))"
    }

    private func net(_ reference: String, _ pin: String, in schematic: KiCadSchematic) -> ImportedCircuit.Net? {
        schematic.circuit.nets.first { $0.terminals.contains(.init(reference: reference, pin: pin)) }
    }

    @Test("Unmarked crossings stay separate and only a marked junction joins both routes")
    func crossings() throws {
        let symbols = """
        \(placed("R1", at: "8 20 0")) \(placed("R2", at: "32 20 0"))
        \(placed("R3", at: "20 8 90")) \(placed("R4", at: "20 32 90"))
        \(wire("10 20", "30 20")) \(wire("20 10", "20 30"))
        """
        let crossing = try KiCadSchematicParser.parse(sheet(symbols))
        #expect(crossing.edges.count == 2)
        #expect(net("R1", "2", in: crossing)?.id == net("R2", "1", in: crossing)?.id)
        #expect(net("R3", "1", in: crossing)?.id == net("R4", "2", in: crossing)?.id)
        #expect(net("R1", "2", in: crossing)?.id != net("R3", "1", in: crossing)?.id)
        let junction = try KiCadSchematicParser.parse(sheet(symbols + "(junction (at 20 20))"))
        #expect(junction.edges.count == 4)
        let common = try #require(net("R1", "2", in: junction))
        #expect(Set(common.terminals) == [.init(reference: "R1", pin: "2"), .init(reference: "R2", pin: "1"),
                                          .init(reference: "R3", pin: "1"), .init(reference: "R4", pin: "2")])
    }

    @Test func dotTracksConnectedBranchesAfterDeletionAndUndo() throws {
        let schematic = try KiCadSchematicParser.parse(sheet("""
        \(placed("R1", at: "8 20 0"))
        \(placed("R2", at: "32 20 0"))
        \(placed("R3", at: "20 32 90"))
        \(wire("10 20", "30 20")) \(wire("20 20", "20 30"))
        (junction (at 20 20))
        """))
        let bench = Workbench()
        bench.importCircuit(CircuitImportPreview(schematic.circuit, schematic: schematic), replacing: true)
        func dots() -> [CGPoint] { bench.junctionDots(visible: bench.wires, pinContacts: []) }
        #expect(dots().count == 1)
        bench.removeWire(try #require(bench.wires.last).id)
        #expect(dots().isEmpty)
        bench.undo()
        #expect(dots().count == 1)
    }

    @Test func importedPinContactBecomesAnOrthogonalLeadWhenMoved() throws {
        let schematic = try KiCadSchematicParser.parse(sheet("""
        \(placed("R1", at: "8 20 0"))
        \(placed("R2", at: "32 20 0"))
        \(wire("10 20", "30 20"))
        (junction (at 10 20))
        """))
        let bench = Workbench()
        bench.importCircuit(CircuitImportPreview(schematic.circuit, schematic: schematic), replacing: true)
        let wire = try #require(bench.wires.first { $0.sourceRoute == .pinAttachment })
        let contact = try #require(bench.junctions[wire.second.pinNumber])
        let origin = try #require(bench.positions[wire.first.partID])
        let part = try #require(bench.parts.first { $0.id == wire.first.partID })
        let geometry = SchematicPartGeometry(part: part, turns: 0)
        #expect(geometry.location(of: wire.first.pinNumber, at: origin, turns: 0, imported: true) == contact)
        #expect(!bench.showsOpenPinMarker(wire.first))
        let moved = CGPoint(x: contact.x + 30, y: contact.y + 20)
        #expect(!wire.isDrawn(from: contact, to: contact))
        let archive = try JSONEncoder().encode(WorkbenchArchive(bench: bench))
        let legacy = String(decoding: archive, as: UTF8.self).replacingOccurrences(of: "\"pinAttachment\"", with: "\"alias\"")
        let legacyBench = Workbench()
        try legacyBench.open(JSONDecoder().decode(WorkbenchArchive.self, from: Data(legacy.utf8)))
        #expect(legacyBench.wires.first { $0.id == wire.id }?.sourceRoute == .pinAttachment)
        bench.movePart(wire.first.partID, from: origin, to: CGPoint(x: origin.x + 30, y: origin.y + 20))
        #expect(wire.isDrawn(from: moved, to: contact))
        let route = wire.route(from: moved, to: contact)
        #expect(route.first == moved)
        #expect(route.last == contact)
        #expect(zip(route, route.dropFirst()).allSatisfy { $0.x == $1.x || $0.y == $1.y })
        let saved = try WorkbenchArchive(bench: bench)
        #expect(saved.wires.contains { $0.id == wire.id && $0.first == wire.first && $0.second == wire.second })
        let reopened = Workbench()
        try reopened.open(JSONDecoder().decode(WorkbenchArchive.self, from: JSONEncoder().encode(saved)))
        #expect(reopened.wires.first { $0.id == wire.id }?.sourceRoute == .pinAttachment)
    }

    @Test("A split crossing stays separate until a junction or label connects both routes")
    func splitCrossing() throws {
        let body = """
        \(placed("R1", at: "8 20 0")) \(placed("R2", at: "20 32 90"))
        \(wire("10 20", "20 20")) \(wire("20 20", "30 20"))
        \(wire("20 10", "20 30"))
        """
        let split = try KiCadSchematicParser.parse(sheet(body))
        #expect(split.edges.count == 3)
        #expect(net("R1", "2", in: split)?.id != net("R2", "2", in: split)?.id)
        let label = try KiCadSchematicParser.parse(sheet(body + "(label CROSS (at 20 20 0))"))
        #expect(net("R1", "2", in: label)?.id == net("R2", "2", in: label)?.id)
        #expect(net("R1", "2", in: label)?.name == "CROSS")
    }

    @Test("T junctions, diagonal routes, transformed physical pins and deliberate no-connects")
    func geometry() throws {
        let schematic = try KiCadSchematicParser.parse(sheet("""
        \(placed("R1", at: "8 20 0"))
        \(placed("R2", at: "22 30 90", mirror: "(mirror x)"))
        \(wire("10 20", "30 20"))
        \(wire("20 20", "22 28"))
        (junction (at 20 20))
        (no_connect (at 22 32))
        """))
        let rotated = try #require(schematic.instances.last)
        #expect(rotated.pins["2"]?.millimetres == CGPoint(x: 22, y: 32))
        #expect(rotated.pins["1"]?.millimetres == CGPoint(x: 22, y: 28))
        #expect(net("R2", "2", in: schematic) == nil)
        #expect(net("R1", "2", in: schematic)?.id == net("R2", "1", in: schematic)?.id)
        #expect(schematic.edges.count == 3)
        let bench = Workbench()
        bench.importCircuit(CircuitImportPreview(schematic.circuit, schematic: schematic), replacing: false)
        let first = try #require(bench.parts.first)
        let second = try #require(bench.parts.last)
        let a = try #require(bench.positions[first.id])
        let b = try #require(bench.positions[second.id])
        #expect(a == WorkbenchWire.snap(a))
        #expect(b == WorkbenchWire.snap(b))
        #expect(abs((b.x - a.x) - 14 * SchematicSymbolGeometry.scale) <= WorkbenchWire.gridSpacing)
        #expect(abs((b.y - a.y) - 10 * SchematicSymbolGeometry.scale) <= WorkbenchWire.gridSpacing)
        let geometry = SchematicPartGeometry(part: second, turns: 3)
        let upper = try #require(geometry.location(of: 1, at: b, turns: 3, imported: true))
        let lower = try #require(geometry.location(of: 2, at: b, turns: 3, imported: true))
        #expect(upper == WorkbenchWire.snap(upper))
        #expect(lower == WorkbenchWire.snap(lower))
        #expect(lower.x == upper.x && lower.y > upper.y)
        #expect(bench.rotations[second.id] == 3)
        #expect(second.importedSymbol?.mirror == "x")
        #expect(second.importedSymbol?.noConnectPins == [2])
        let drawn = bench.wires.filter { $0.sourceRoute == .straight }
        #expect(drawn.count == 3)
        #expect(drawn.filter { !$0.bends.isEmpty }.count == 1)
        #expect(schematic.warnings.contains { $0.contains("Diagonal wires") })
        let loaded = Workbench()
        let data = try JSONEncoder().encode(WorkbenchArchive(bench: bench))
        try loaded.open(JSONDecoder().decode(WorkbenchArchive.self, from: data))
        #expect(loaded.wires.map(\.bends) == bench.wires.map(\.bends))
    }

    @Test("Remote labels and schematic power connect editable wires and scope probes after reopening")
    func workbenchAndArchive() throws {
        let ground = """
        (symbol "power:GND" (power)
          (symbol "GND_1_1" (pin power_in line (at 0 0 0) (length 0) (name "GND") (number "1"))))
        """
        let content = sheet("""
        \(placed("R1", at: "12 10 0"))
        \(placed("#PWR01", at: "30 30 0", lib: "power:GND", value: "GND"))
        \(wire("5 10", "10 10")) (label "return" (at 5 10 0))
        \(wire("30 30", "35 30")) (global_label "return" (at 35 30 0))
        (no_connect (at 14 10))
        """, symbols: resistor + ground)
        let preview = try CircuitImportPreview.read(content, filenameExtension: "KICAD_SCH")
        let bench = Workbench(timeSource: { 0 })
        let r = try #require(bench.importCircuit(preview, replacing: true))
        let pin = WorkbenchTerminal(partID: r.id, pinNumber: 1)
        let wire = try #require(bench.wires.first { $0.sourceRoute == .straight })
        #expect((r.component as? Resistor)?.value == 4.7)
        #expect(r.component.pins[1]?.supplyRail == .ground)
        #expect(bench.wires.filter { $0.sourceRoute == .alias }.count == 1)
        #expect(bench.schematicMarks.count == 2)
        bench.assignScopeProbe(.pin(pin), to: 0)
        bench.assignScopeProbe(.wire(wire.id), to: 1)
        #expect(bench.scope.samples(channel: 0, in: 0...1).last?.value == .logic(.low))
        #expect(bench.scope.samples(channel: 1, in: 0...1).last?.value == .logic(.low))

        let data = try JSONEncoder().encode(WorkbenchArchive(bench: bench))
        let reopened = Workbench(timeSource: { 0 })
        try reopened.open(JSONDecoder().decode(WorkbenchArchive.self, from: data))
        let restored = try #require(reopened.parts.first)
        #expect(restored.importedSymbol?.value == "4k7")
        #expect(restored.importedSymbol?.noConnectPins == [2])
        #expect(restored.component.pins[1]?.supplyRail == .ground)
        #expect(reopened.scopeProbes == [0: .pin(pin), 1: .wire(wire.id)])
        #expect(reopened.schematicMarks.map(\.text) == bench.schematicMarks.map(\.text))
        reopened.removeWire(wire.id)
        #expect(restored.component.pins[1]?.supplyRail == nil)
        reopened.undo()
        #expect(restored.component.pins[1]?.supplyRail == .ground)
        reopened.clear()
        #expect(reopened.schematicMarks.isEmpty)
        reopened.undo()
        #expect(reopened.schematicMarks.count == 2)
    }

    @Test("Only placed CMOS units import and unsupported circuitry is reported")
    func supportedModels() throws {
        func definition(_ identifier: String, _ unit: Int, _ pins: [Int]) -> String {
            let declarations = pins.enumerated().map { index, pin in
                "(pin passive line (at -2 \(index) 0) (length 1) (name ~) (number \(pin)))"
            }.joined(separator: " ")
            return "(symbol \(identifier)_\(unit)_1 \(declarations))"
        }
        let defs = """
        (symbol "4xxx:4011" \(definition("4011", 1, [1, 2, 3])) \(definition("4011", 5, [7, 14])))
        (symbol "Timer:NE555" \(definition("NE555", 1, Array(1...8))))
        (symbol "Device:C_Polarized" \(definition("C_Polarized", 1, [1, 2])))
        (symbol "custom:Unknown" \(definition("Unknown", 1, [1, 2])))
        """
        let content = sheet("""
        \(placed("U1", at: "10 10 0", lib: "4xxx:4011", value: "4011"))
        \(placed("U1", at: "20 10 0", lib: "4xxx:4011", unit: 5, value: "4011"))
        \(placed("U2", at: "30 10 0", lib: "Timer:NE555", value: "NE555"))
        \(placed("C1", at: "40 10 0", lib: "Device:C_Polarized", value: "10 µF"))
        \(placed("U3", at: "50 10 0", lib: "custom:Unknown", value: "NE555"))
        (sheet (at 0 0)) (bus (pts (xy 10 10) (xy 20 10)))
        """, symbols: defs)
        let preview = try CircuitImportPreview.read(content, filenameExtension: "kicad_sch")
        #expect(preview.supportedCount == 3)
        #expect(preview.warnings.contains { $0.contains("hierarchical sheets") })
        #expect(preview.warnings.contains { $0.contains("Unsupported buses") })
        #expect(preview.warnings.contains { $0.contains("custom:Unknown") })
        let bench = Workbench()
        bench.importCircuit(preview, replacing: false)
        #expect(bench.parts.map(\.reference) == ["U1A", "U1E", "U2", "C1"])
        #expect(bench.parts[0].component === bench.parts[1].component)
        #expect(bench.parts[2].component is NE555)
        #expect((bench.parts[3].component as? Capacitor)?.value == 10)
    }

    @Test("Malformed native schematics fail before replacing the workbench")
    func malformed() {
        for text in ["(kicad_sch (lib_symbols)", sheet("(wire (pts (xy 0 0)))"),
                     sheet(placed("R1", at: "0 0 45")), sheet(placed("R1", at: "nan 0 0")),
                     sheet(placed("R1", at: "0 0 0") + placed("R1", at: "10 10 0"))] {
            #expect(throws: KiCadSchematicParser.ParseError.self) { try KiCadSchematicParser.parse(text) }
        }
    }
}
