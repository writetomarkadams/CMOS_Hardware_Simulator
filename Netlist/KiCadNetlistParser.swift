import Foundation

/// Source-neutral topology. A net's identity is independent of its display name.
struct ImportedCircuit {
    struct Part {
        let reference: String
        let library: String
        let symbol: String
        let value: String
        let footprint: String?
    }

    struct Terminal: Hashable {
        let reference: String
        let pin: String
    }

    struct Net {
        let id: String
        let name: String
        let terminals: [Terminal]
    }

    let parts: [Part]
    let nets: [Net]
}

enum KiCadNetlistParser {
    enum ImportError: LocalizedError {
        case unsupported, malformed(String)

        var errorDescription: String? {
            switch self {
            case .unsupported:
                "Choose a KiCad native S-expression netlist exported from the schematic."
            case .malformed(let context):
                "Invalid KiCad netlist — \(context)"
            }
        }
    }

    static func parse(_ text: String) throws -> ImportedCircuit {
        guard let root = KiCadExpression.parse(text), root[0] == "export" else {
            throw ImportError.unsupported
        }
        guard let components = root.child("components"), let nets = root.child("nets") else {
            throw ImportError.malformed("Missing components or nets section.")
        }

        var references: Set<String> = []
        let parts = try components.children.filter { $0[0] == "comp" }.map { part in
            guard let reference = part.child("ref")?[1], !reference.isEmpty,
                  references.insert(reference).inserted else {
                throw ImportError.malformed("Missing or duplicate component reference.")
            }
            let source = part.child("libsource")
            return ImportedCircuit.Part(reference: reference, library: source?.child("lib")?[1] ?? "",
                                        symbol: source?.child("part")?[1] ?? "", value: part.child("value")?[1] ?? "",
                                        footprint: part.child("footprint")?[1])
        }

        var ids: Set<String> = []
        var assigned: [ImportedCircuit.Terminal: String] = [:]
        let connections = try nets.children.filter { $0[0] == "net" }.map { net in
            guard let id = net.child("code")?[1], !id.isEmpty, ids.insert(id).inserted,
                  let name = net.child("name")?[1] else {
                throw ImportError.malformed("Missing net name or missing/duplicate net code.")
            }
            var terminals: [ImportedCircuit.Terminal] = []
            for node in net.children where node[0] == "node" {
                guard let reference = node.child("ref")?[1], references.contains(reference),
                      let pin = node.child("pin")?[1], !pin.isEmpty else {
                    throw ImportError.malformed("Missing pin or unknown component reference in \(name).")
                }
                let terminal = ImportedCircuit.Terminal(reference: reference, pin: pin)
                if let previous = assigned[terminal] {
                    guard previous == id else {
                        throw ImportError.malformed("\(reference) pin \(pin) appears in multiple nets.")
                    }
                } else {
                    assigned[terminal] = id
                    terminals.append(terminal)
                }
            }
            return ImportedCircuit.Net(id: id, name: name, terminals: terminals)
        }
        return ImportedCircuit(parts: parts, nets: connections)
    }
}
