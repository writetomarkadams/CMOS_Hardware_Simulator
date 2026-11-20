import Foundation
import Testing
@testable import CMOS4000Simulator

struct PinHeaderTests {
    @Test("Each header imports numbered, independent contacts and survives Save/Open", arguments: PinHeaderKind.allCases)
    func importAndRestore(_ kind: PinHeaderKind) throws {
        let (library, symbol) = switch kind {
        case .two: ("Connector", "Conn_01x02_Pin")
        case .three: ("Connector_Generic", "Conn_01x03")
        case .eight: ("Connector", "Conn_01x08_Pin")
        }
        let source = """
        (export (version "E")
          (components
            (comp (ref "J20") (value "\(symbol)")
              (footprint "\(kind.footprint)")
              (libsource (lib "\(library)") (part "\(symbol)"))))
          (nets
            (net (code 1) (name "+5V") (node (ref "J20") (pin "1")))
            (net (code 2) (name "GND") (node (ref "J20") (pin "\(kind.rawValue)")))))
        """
        let parsed = try KiCadNetlistParser.parse(source)
        #expect(parsed.parts.first?.footprint == kind.footprint)

        let bench = Workbench()
        bench.importCircuit(CircuitImportPreview(parsed), replacing: false)
        let archive = try JSONEncoder().encode(WorkbenchArchive(bench: bench))
        let reopened = Workbench()
        try reopened.open(JSONDecoder().decode(WorkbenchArchive.self, from: archive))

        for circuit in [bench, reopened] {
            let part = try #require(circuit.parts.first { $0.reference == "J20" })
            #expect((part.component as? PinHeader)?.kind == kind)
            #expect(part.pins.keys.sorted() == Array(kind.pinNumbers))
            #expect(part.pins[1]?.state == .high)
            #expect(part.pins[kind.rawValue]?.state == .low)
            #expect(part.pins.values.allSatisfy { $0.driveState == .highImpedance })
            if kind != .two {
                let unused = WorkbenchTerminal(partID: part.id, pinNumber: 2)
                #expect(circuit.readings[unused] == .highImpedance)
            }
        }
        let terminals = try #require(KiCadSymbol.pinHeaders[kind]?.terminals)
        #expect(terminals.map(\.id) == Array(kind.pinNumbers))
        #expect(terminals.map(\.position.x) == terminals.map(\.position.x).sorted())
        #expect(Set(terminals.map(\.position.y)).count == 1)
        #expect(terminals.allSatisfy { $0.bodyEnd.y > $0.position.y })
    }

    @Test("A header footprint alone cannot override the schematic pin map")
    func mismatchedFootprint() throws {
        let source = """
        (export (version "E")
          (components
            (comp (ref "J1") (value "Conn_01x03_Pin")
              (footprint "\(PinHeaderKind.two.footprint)")
              (libsource (lib "Connector") (part "Conn_01x03_Pin"))))
          (nets))
        """
        let preview = CircuitImportPreview(try KiCadNetlistParser.parse(source))
        #expect(!preview.canImport)
        #expect(preview.warnings.contains { $0.contains("J1") })
    }
}
