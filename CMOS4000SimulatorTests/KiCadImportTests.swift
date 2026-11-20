import Foundation
import Testing
@testable import CMOS4000Simulator

struct KiCadImportTests {
    private let example = #"""
    (export (version "E")
      (components
        (comp (ref "U7") (value "4011") (libsource (lib "4xxx") (part "4011")))
        (comp (ref "R12") (value "4k7") (libsource (lib "Device") (part "R")))
        (comp (ref "C9") (value "2.2 µF") (libsource (lib "Device") (part "C_Polarized")))
        (comp (ref "C10") (value "100nF") (libsource (lib "Device") (part "C"))))
      (nets
        (net (code "1") (name "+5V") (class "Default")
          (node (ref "U7") (pin "1") (pinfunction "A") (pintype "input"))
          (node (ref "U7") (pin "14"))
          (node (ref "C10") (pin "1")))
        (net (code "2") (name "GND")
          (node (ref "U7") (pin "7")) (node (ref "U7") (pin "2"))
          (node (ref "C9") (pin "2")) (node (ref "C10") (pin "2")))
        (net (code "3") (name "/CLK \"test\"")
          (node (ref "U7") (pin "3")) (node (ref "R12") (pin "1")))
        (net (code "4") (name "RC") (node (ref "R12") (pin "2")) (node (ref "C9") (pin "1")))
        (net (code "5") (name "unconnected-(U7B-Pad4)") (node (ref "U7") (pin "4")))))
    """#

    @Test("Reads quoted KiCad version E and unquoted version D fields")
    func nativeExports() throws {
        let circuit = try KiCadNetlistParser.parse(example)
        #expect(circuit.parts.map(\.reference) == ["U7", "R12", "C9", "C10"])
        #expect(circuit.parts[2].value == "2.2 µF")
        #expect(circuit.nets[2].name == #"/CLK "test""#)
        #expect(circuit.nets[0].terminals.map(\.pin) == ["1", "14", "1"])
        let legacy = try KiCadNetlistParser.parse("""
        (export (version D) (components (comp (ref U1) (value NE555) (libsource (lib Timer) (part NE555))))
          (nets (net (code 1) (name GND) (node (ref U1) (pin 1)))))
        """)
        #expect(CircuitImportPreview(legacy).supportedCount == 1)
        #expect(legacy.nets.first?.terminals.first?.pin == "1")
    }

    @Test("Rejects malformed exports and contradictory physical pin assignments")
    func invalidTopology() {
        for text in [
            "(export (components) (nets)",
            "(export (components) (nets))\"",
            "<export><components/></export>",
            example.replacingOccurrences(of: "(code \"5\")", with: "(code \"4\")"),
            example.replacingOccurrences(of: "(pin \"4\")", with: "(pin \"3\")"),
            example.replacingOccurrences(of: "(ref \"C10\") (pin \"2\")", with: "(ref \"unknown\") (pin \"2\")")
        ] {
            #expect(throws: KiCadNetlistParser.ImportError.self) {
                try KiCadNetlistParser.parse(text)
            }
        }
    }

    @Test("Preview reports unknown symbols, unsafe pin maps, invalid values and open nets")
    func warnings() throws {
        var source = example.replacingOccurrences(of: "(part \"C\")", with: "(part \"Crystal\")")
        source = source.replacingOccurrences(of: "(ref \"R12\") (pin \"2\")", with: "(ref \"R12\") (pin \"9\")")
        source = source.replacingOccurrences(of: "2.2 µF", with: "invalid")
        let preview = CircuitImportPreview(try KiCadNetlistParser.parse(source))
        #expect(preview.supportedCount == 1)
        for warning in ["unsupported symbol", "unsupported pin map", "unsupported value", "unconnected pin", "endpoint(s) omitted"] {
            #expect(preview.warnings.contains { $0.contains(warning) })
        }
        let floating = example.replacingOccurrences(of: #"(ref "R12") (pin "2")"#, with: #"(ref "U7") (pin "5")"#)
        #expect(CircuitImportPreview(try KiCadNetlistParser.parse(floating)).warnings.contains { $0.contains("potentially floating") })
    }

    @Test("Import settles real pin nets, preserves package sharing and round-trips archives")
    func connectivityAndArchive() throws {
        let bench = Workbench()
        let preview = CircuitImportPreview(try KiCadNetlistParser.parse(example))
        bench.importCircuit(preview, replacing: false)

        func verify(_ bench: Workbench) throws {
            let units = bench.parts.filter { $0.importedReference == "U7" }
            #expect(units.map(\.reference) == ["U7A", "U7B", "U7C", "U7D", "U7E"])
            let gate = try #require(units.first)
            let power = try #require(units.last)
            #expect(power.component === gate.component)
            #expect(power.pins.keys.sorted() == [7, 14])
            #expect(bench.powerMode == .explicit)
            #expect(bench.powerStates[gate.id] == .powered)
            #expect(bench.readings[WorkbenchTerminal(partID: gate.id, pinNumber: 3)] == .high)
            #expect(bench.readings[WorkbenchTerminal(partID: units[1].id, pinNumber: 4)] == .undefined)
            let resistor = try #require(bench.parts.first { $0.reference == "R12" }?.component as? Resistor)
            #expect(resistor.value * resistor.unit.multiplier == 4_700)
            #expect(resistor.pins[1]?.state == .high)
            let cap = try #require(bench.parts.first { $0.reference == "C9" }?.component as? Capacitor)
            #expect(cap.kind == .polarized)
            #expect(abs(cap.farads - 2.2e-6) < 1e-15)
            #expect(cap.pins[2]?.supplyRail == .ground)
            let cap2 = try #require(bench.parts.first { $0.reference == "C10" }?.component as? Capacitor)
            #expect(abs(cap2.farads - 100e-9) < 1e-15)
            #expect(bench.wires.contains { $0.netName == #"/CLK "test""# })
            #expect(!bench.junctions.isEmpty)
        }
        try verify(bench)
        let archive = try JSONEncoder().encode(WorkbenchArchive(bench: bench))
        let reopened = Workbench()
        try reopened.open(JSONDecoder().decode(WorkbenchArchive.self, from: archive))
        try verify(reopened)
        let gate = try #require(reopened.parts.first)
        let from = try #require(reopened.positions[gate.id])
        reopened.movePart(gate.id, from: from, to: CGPoint(x: from.x + 20, y: from.y + 20))
        #expect(reopened.positions[gate.id] != from)
        try verify(reopened)
    }

    @Test("Add stays separate and preserves existing IDs; replace and add undo in one step")
    func addReplaceUndo() throws {
        let bench = Workbench()
        let preview = CircuitImportPreview(try KiCadNetlistParser.parse(example))
        bench.importCircuit(preview, replacing: false)
        let originalParts = bench.parts
        let originalWires = bench.wires
        let first = try #require(bench.importCircuit(preview, replacing: false))
        #expect(first.reference == "U7 (2)A")
        #expect(bench.parts.count == originalParts.count * 2)
        #expect(bench.parts.first?.component === originalParts.first?.component)
        #expect(first.component !== originalParts.first?.component)
        #expect(Set(bench.wires.map(\.id)).count == bench.wires.count)
        let addedPartIDs = Set(bench.parts.dropFirst(originalParts.count).map(\.id))
        let addedJunctions = Set(bench.junctions.keys).subtracting(originalWires.flatMap { [$0.first, $0.second] }
            .filter(\.isJunction).map(\.pinNumber))
        for wire in bench.wires.dropFirst(originalWires.count) {
            for endpoint in [wire.first, wire.second] {
                #expect(endpoint.isJunction ? addedJunctions.contains(endpoint.pinNumber) : addedPartIDs.contains(endpoint.partID))
            }
        }
        bench.importCircuit(preview, replacing: true)
        #expect(bench.parts.count == originalParts.count)
        bench.undo()
        #expect(bench.parts.count == originalParts.count * 2)
        bench.undo()
        #expect(bench.parts.map(\.id) == originalParts.map(\.id))
        #expect(bench.wires.map(\.id) == originalWires.map(\.id))
        bench.redo()
        #expect(bench.parts.count == originalParts.count * 2)
    }

    @Test("Imported NE555 timing wiring runs with physical capacitor polarity and resistance")
    func importedAstable() throws {
        let netlist = """
        (export (version E)
          (components
            (comp (ref U1) (value NE555P) (libsource (lib Timer) (part NE555P)))
            (comp (ref R1) (value 100k) (libsource (lib Device) (part R)))
            (comp (ref R2) (value 100k) (libsource (lib Device) (part R)))
            (comp (ref C1) (value 1uF) (libsource (lib Device) (part C_Polarized))))
          (nets
            (net (code 1) (name +5V) (node (ref U1) (pin 4)) (node (ref U1) (pin 8)) (node (ref R1) (pin 1)))
            (net (code 2) (name GND) (node (ref U1) (pin 1)) (node (ref C1) (pin 2)))
            (net (code 3) (name Discharge) (node (ref U1) (pin 7)) (node (ref R1) (pin 2)) (node (ref R2) (pin 1)))
            (net (code 4) (name Timing) (node (ref U1) (pin 2)) (node (ref U1) (pin 6))
              (node (ref R2) (pin 2)) (node (ref C1) (pin 1)))))
        """
        let preview = CircuitImportPreview(try KiCadNetlistParser.parse(netlist))
        let bench = Workbench(timeSource: { 0 })
        let timer = try #require(bench.importCircuit(preview, replacing: true))
        let out = WorkbenchTerminal(partID: timer.id, pinNumber: 3)
        #expect(bench.timingIssues.isEmpty)
        #expect(bench.readings[out] == .high)
        bench.serviceSimulation(until: 0.21)
        #expect(bench.readings[out] == .high)
        bench.serviceSimulation(until: 0.23)
        #expect(bench.readings[out] == .low)
    }

    @Test("Equal net names never join distinct physical nets")
    func separateNetCodes() throws {
        let source = example.replacingOccurrences(of: "(name \"RC\")", with: #"(name "/CLK \"test\"")"#)
        let bench = Workbench()
        bench.importCircuit(CircuitImportPreview(try KiCadNetlistParser.parse(source)), replacing: false)
        let resistor = try #require(bench.parts.first { $0.reference == "R12" }?.component as? Resistor)
        #expect(resistor.pins[1]?.strongState == .high)
        #expect(resistor.pins[2]?.strongState == .highImpedance)
    }
}
