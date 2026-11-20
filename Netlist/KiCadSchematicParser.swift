import Foundation

struct KiCadSchematic {
    typealias Terminal = ImportedCircuit.Terminal

    // KiCad coordinates are quantized to nanometres. This makes quarter-turns
    // and equality at wire endpoints exact, including after adding pin offsets.
    struct Point: Hashable {
        let x: Int64
        let y: Int64

        init(x: Int64, y: Int64) {
            self.x = x
            self.y = y
        }

        init?(_ expression: KiCadExpression?) {
            guard let x = expression?[1].flatMap(Double.init), let y = expression?[2].flatMap(Double.init),
                  abs(x) < 10_000, abs(y) < 10_000 else { return nil }
            self.init(x: Int64((x * 1_000_000).rounded()), y: Int64((y * 1_000_000).rounded()))
        }

        var millimetres: CGPoint { CGPoint(x: Double(x) / 1e6, y: Double(y) / 1e6) }

        func offset(by local: Point, turns: Int, mirror: String?) -> Point {
            var dx = local.x
            var dy = -local.y // Embedded library coordinates are Y-up.
            for _ in 0..<turns { (dx, dy) = (dy, -dx) }
            if mirror == "x" { dy = -dy }
            if mirror == "y" { dx = -dx }
            return Point(x: x + dx, y: y + dy)
        }
    }

    struct Instance {
        let reference: String
        let unit: Int
        let origin: Point
        let turns: Int
        let mirror: String?
        let drawing: ImportedSymbol
        let pins: [String: Point]
        let rail: PowerRail?
    }

    struct Edge {
        let first: Point
        let second: Point
        var isAlias = false

        func contains(_ point: Point) -> Bool {
            guard (min(first.x, second.x)...max(first.x, second.x)).contains(point.x),
                  (min(first.y, second.y)...max(first.y, second.y)).contains(point.y) else { return false }
            if first.x == second.x || first.y == second.y { return true }
            return (point.x - first.x).multipliedFullWidth(by: second.y - first.y) ==
                (point.y - first.y).multipliedFullWidth(by: second.x - first.x)
        }
    }

    let circuit: ImportedCircuit
    let instances: [Instance]
    let edges: [Edge]
    let junctions: Set<Point>
    let labels: [Point: [String]]
    let noConnects: Set<Point>
    let names: [Point: String]
    let warnings: [String]
}

enum KiCadSchematicParser {
    private typealias Point = KiCadSchematic.Point
    private typealias Edge = KiCadSchematic.Edge
    private typealias Instance = KiCadSchematic.Instance

    enum ParseError: LocalizedError {
        case invalid(String)
        var errorDescription: String? {
            switch self {
            case .invalid(let detail): "Invalid KiCad schematic — \(detail)"
            }
        }
    }

    static func parse(_ text: String) throws -> KiCadSchematic {
        guard let root = KiCadExpression.parse(text), root[0] == "kicad_sch",
              let library = root.child("lib_symbols") else {
            throw ParseError.invalid("Expected a modern schematic with embedded symbols.")
        }
        let definitions = Dictionary(library.children.compactMap { node in
            node[0] == "symbol" ? node[1].map { ($0, node) } : nil
        }, uniquingKeysWith: { first, _ in first })
        func nodes(_ name: String) -> [KiCadExpression] { root.children.filter { $0[0] == name } }
        func location(_ node: KiCadExpression) throws -> Point {
            guard let point = Point(node.child("at")) else { throw ParseError.invalid("Invalid \(node[0] ?? "item") position.") }
            return point
        }

        var warnings: [String] = []
        for (tag, description) in [
            ("sheet", "hierarchical sheets"), ("hierarchical_label", "hierarchical labels"),
            ("bus", "buses"), ("bus_entry", "bus entries"), ("bus_alias", "bus aliases"),
            ("image", "images"), ("text", "free text"), ("text_box", "text boxes"),
            ("polyline", "sheet graphics"), ("group", "groups")
        ] where !nodes(tag).isEmpty {
            warnings.append("Unsupported \(description) were omitted. Check the original sheet before simulating.")
        }

        let junctions = Set(try nodes("junction").map(location))
        let noConnects = Set(try nodes("no_connect").map(location))
        var labels: [Point: [String]] = [:]
        var globalNames: Set<String> = []
        for tag in ["label", "global_label", "hierarchical_label"] {
            for node in nodes(tag) where tag != "hierarchical_label" {
                guard let name = node[1], !name.isEmpty else { throw ParseError.invalid("Missing label name.") }
                labels[try location(node), default: []].append(name)
                if tag == "global_label" { globalNames.insert(name) }
            }
        }
        var parts: [ImportedCircuit.Part] = []
        var instanceKeys: [String: Set<Int>] = [:]
        var instances: [Instance] = []
        var excluded: Set<String> = []
        var namesAt = labels
        for node in nodes("symbol") {
            let properties = Dictionary(node.children.compactMap { property -> (String, String)? in
                guard property[0] == "property", let key = property[1], let value = property[2] else { return nil }
                return (key, value)
            }, uniquingKeysWith: { first, _ in first })
            guard let reference = properties["Reference"], !reference.isEmpty,
                  let id = node.child("lib_id")?[1], let unit = node.child("unit")?[1].flatMap(Int.init), unit > 0,
                  let angle = node.child("at")?[3].flatMap(Double.init), angle.isFinite,
                  angle.truncatingRemainder(dividingBy: 90) == 0 else {
                throw ParseError.invalid("A symbol has an invalid reference, unit, or rotation.")
            }
            let origin = try location(node)
            let turns = (Int(angle.truncatingRemainder(dividingBy: 360) / 90) + 4) % 4
            let mirror = node.child("mirror")?[1]
            guard mirror == nil || mirror == "x" || mirror == "y" else {
                throw ParseError.invalid("\(reference) has an unsupported mirror axis.")
            }
            let value = properties["Value"] ?? ""
            let identity = id.split(separator: ":", maxSplits: 1).map(String.init)
            let lib = identity.count == 2 ? identity[0] : ""
            let symbol = identity.last ?? ""
            let definition = definitions[node.child("lib_name")?[1] ?? id]
            let isPower = lib == "power" || definition?.child("power") != nil
            let rail = node.child("exclude_from_sim")?[1] != "yes" && lib == "power" && value == symbol ? PowerRail(rawValue: symbol) : nil
            let firstUnit = instanceKeys[reference] == nil
            guard instanceKeys[reference, default: []].insert(unit).inserted else {
                throw ParseError.invalid("Duplicate placement of \(reference) unit \(unit).")
            }
            if firstUnit && (!isPower || rail != nil) {
                parts.append(.init(reference: reference, library: lib, symbol: symbol, value: value,
                                   footprint: properties["Footprint"]))
            } else if !firstUnit, let part = parts.first(where: { $0.reference == reference }),
                      (part.library != lib || part.symbol != symbol || part.value != value || part.footprint != properties["Footprint"]) {
                throw ParseError.invalid("Units of \(reference) disagree about their symbol or value.")
            }
            if node.child("exclude_from_sim")?[1] == "yes" {
                warnings.append("\(reference): marked Exclude from Simulation in KiCad. Entire part omitted.")
                excluded.insert(reference)
            }
            let style = (node.child("body_style") ?? node.child("convert"))?[1].flatMap(Int.init) ?? 1
            guard let definition, definition.child("extends") == nil else {
                warnings.append("\(reference): missing or unresolved embedded symbol \(id).")
                continue
            }
            let elements = definition.children.filter { child in
                guard child[0] == "symbol", let name = child[1] else { return false }
                let suffix = name.split(separator: "_").suffix(2).compactMap { Int($0) }
                return suffix.count == 2 && [0, unit].contains(suffix[0]) && [0, style].contains(suffix[1])
            }.flatMap { $0.children.dropFirst(2) }
            var pins: [String: Point] = [:]
            for pin in elements where pin[0] == "pin" {
                guard let local = Point(pin.child("at")), let number = pin.child("number")?[1], !number.isEmpty else {
                    throw ParseError.invalid("Invalid embedded pin on \(reference).")
                }
                let point = origin.offset(by: local, turns: turns, mirror: mirror)
                if !isPower && pin[1] == "power_in",
                   pin.child("hide")?[1] == "yes" || pin.children.indices.contains(where: { pin[$0] == "hide" }) {
                    warnings.append("\(reference).\(number): implicit hidden power pin connections are unsupported.")
                }
                if let previous = pins.updateValue(point, forKey: number), previous != point {
                    throw ParseError.invalid("\(reference) pin \(number) has multiple positions.")
                }
            }
            if elements.contains(where: { !["pin", "rectangle", "polyline", "arc", "circle"].contains($0[0]) }) {
                warnings.append("\(reference): some embedded symbol graphics were omitted.")
            }
            if isPower {
                if symbol == "PWR_FLAG" {
                    warnings.append("\(reference): PWR_FLAG is an ERC annotation and was omitted.")
                    continue
                }
                if rail == nil { warnings.append("\(reference): \(value) retains its net name without a simulated supply.") }
                if !value.isEmpty {
                    for point in Set(pins.values) { namesAt[point, default: []].append(value) }
                    globalNames.insert(value)
                }
                if rail == nil { continue }
            }
            let fields = node.children.compactMap { field -> ImportedSymbol.Field? in
                guard field[0] == "property", let key = field[1], ["Reference", "Value"].contains(key),
                      field.child("hide")?[1] != "yes",
                      let at = field.child("at"), let position = Point(at),
                      let angle = at[3].flatMap(Double.init), angle.isFinite else { return nil }
                let effects = field.child("effects")
                if let effects, effects.child("hide")?[1] != "no",
                   effects.child("hide") != nil || effects.children.indices.contains(where: { effects[$0] == "hide" }) {
                    return nil
                }
                let size = effects?.child("font")?.child("size")?[2].flatMap(Double.init) ?? 1.27
                var offset = CGPoint(x: position.millimetres.x - origin.millimetres.x, y: position.millimetres.y - origin.millimetres.y)
                for _ in 0..<turns { offset = CGPoint(x: -offset.y, y: offset.x) }
                return .init(key: key, offset: offset, angle: Double(turns * 90) - angle,
                             size: size, justify: effects?.child("justify")?[1])
            }
            instances.append(Instance(reference: reference, unit: unit, origin: origin, turns: turns, mirror: mirror,
                                      drawing: ImportedSymbol(elements: elements, value: value, fields: fields), pins: pins, rail: rail))
        }

        instances.removeAll { excluded.contains($0.reference) }
        var sourceEdges: [Edge] = []
        for wire in nodes("wire") {
            guard let points = wire.child("pts")?.children.filter({ $0[0] == "xy" }), points.count == 2,
                  let first = Point(points[0]), let second = Point(points[1]), first != second else {
                throw ParseError.invalid("A wire must have two distinct endpoints.")
            }
            sourceEdges.append(Edge(first: first, second: second))
        }
        if sourceEdges.contains(where: { $0.first.x != $0.second.x && $0.first.y != $0.second.y }) {
            warnings.append("Diagonal wires are displayed with right-angle bends. Original electrical connections are preserved. Review the rerouted lines against the source schematic.")
        }
        var terminalsAt: [Point: [KiCadSchematic.Terminal]] = [:]
        for instance in instances {
            for (number, point) in instance.pins {
                if noConnects.contains(point) {
                    if namesAt[point] != nil || sourceEdges.contains(where: { $0.contains(point) }) {
                        warnings.append("\(instance.reference).\(number): no-connect marker overlaps wiring.")
                    } else {
                        continue
                    }
                }
                terminalsAt[point, default: []].append(.init(reference: instance.reference, pin: number))
            }
        }
        let anchors = Set(namesAt.keys).union(terminalsAt.keys)
        // A wire's own endpoints, explicit junctions and actual label anchors
        // connect it. A different wire or pin touching its interior does not.
        let splitPoints = junctions.union(labels.keys)

        var edges: [Edge] = []
        var neighbours: [Point: [Point]] = [:]
        func connect(_ edge: Edge) {
            edges.append(edge)
            neighbours[edge.first, default: []].append(edge.second)
            neighbours[edge.second, default: []].append(edge.first)
        }
        for wire in sourceEdges {
            let points = splitPoints.filter { wire.contains($0) }.union([wire.first, wire.second])
                .sorted(by: pointOrder)
            for (first, second) in zip(points, points.dropFirst()) { connect(Edge(first: first, second: second)) }
        }
        var firstByName: [String: Point] = [:]
        // Connect remote labels logically, leaving the drawn routes in their original locations.
        for point in namesAt.keys.sorted(by: pointOrder) {
            for name in Set(namesAt[point, default: []]).sorted() {
                if let first = firstByName[name], first != point {
                    connect(Edge(first: first, second: point, isAlias: true))
                } else {
                    firstByName[name] = point
                }
            }
        }

        var visited: Set<Point> = []
        var names: [Point: String] = [:]
        var nets: [ImportedCircuit.Net] = []
        var assigned: Set<KiCadSchematic.Terminal> = []
        for point in Set(neighbours.keys).union(anchors).sorted(by: pointOrder) where visited.insert(point).inserted {
            var connected: [Point] = [point]
            var index = 0
            while index < connected.count {
                for next in neighbours[connected[index], default: []] where visited.insert(next).inserted {
                    connected.append(next)
                }
                index += 1
            }
            let named = Set(connected.flatMap { namesAt[$0, default: []] }).sorted {
                if globalNames.contains($0) != globalNames.contains($1) { return globalNames.contains($0) }
                return $0 < $1
            }
            var terminals = Array(Set(connected.flatMap { terminalsAt[$0, default: []] })).sorted {
                ($0.reference, $0.pin) < ($1.reference, $1.pin)
            }
            if !assigned.isDisjoint(with: terminals) {
                warnings.append("Repeated physical pins on separate nets were omitted. Check multi-unit pin assignments.")
                terminals.removeAll { assigned.contains($0) }
            }
            assigned.formUnion(terminals)
            let name = named.first ?? terminals.first.map { "Net-(\($0.reference)-Pad\($0.pin))" } ?? "Wire \(nets.count + 1)"
            if named.count > 1 { warnings.append("Connected labels share one net: \(named.joined(separator: ", ")).") }
            for point in connected { names[point] = name }
            nets.append(.init(id: String(nets.count + 1), name: name, terminals: terminals))
        }
        return KiCadSchematic(circuit: ImportedCircuit(parts: parts, nets: nets), instances: instances, edges: edges,
                              junctions: junctions, labels: labels, noConnects: noConnects, names: names, warnings: warnings)
    }

    private static func pointOrder(_ a: Point, _ b: Point) -> Bool {
        (a.x, a.y) < (b.x, b.y)
    }
}
