import CoreGraphics
import Foundation

struct KiCadSymbol {
    struct Terminal: Identifiable {
        let id: Int
        let name: String
        let style: String
        let position: CGPoint
        let inward: CGVector
        let length: CGFloat

        var bodyEnd: CGPoint {
            CGPoint(x: position.x + inward.dx * length, y: position.y + inward.dy * length)
        }
    }

    struct GateOutline {
        let points: [CGPoint]
        let start: CGPoint
        let middle: CGPoint
        let end: CGPoint
    }

    let body: CGRect
    let isCircular: Bool
    let gateOutline: GateOutline?
    let polygon: [CGPoint]
    let markings: [[CGPoint]]
    let terminals: [Terminal]

    private static let installedLibrary: KiCadExpression? = {
        let path = "/Applications/KiCad/KiCad.app/Contents/SharedSupport/symbols/4xxx.kicad_sym"
        guard let text = try? String(contentsOfFile: path, encoding: .utf8),
              let root = KiCadExpression.parse(text), root[0] == "kicad_symbol_lib" else { return nil }
        return root
    }()

    static let npn2N3904: Self? = {
        let path = "/Applications/KiCad/KiCad.app/Contents/SharedSupport/symbols/Transistor_BJT.kicad_sym"
        guard let text = try? String(contentsOfFile: path, encoding: .utf8),
              let library = KiCadExpression.parse(text),
              let part = library.children.first(where: { $0[0] == "symbol" && $0[1] == "2N3904" }),
              let parentName = part.child("extends")?[1],
              let parent = library.children.first(where: { $0[0] == "symbol" && $0[1] == parentName }),
              let circle = parent.children.lazy.compactMap({ $0.child("circle") }).first,
              let center = circle.child("center")?.point,
              let radius = circle.child("radius")?[1].flatMap(Double.init) else { return nil }

        let elements = parent.children.flatMap(\.children)
        let markings = elements.filter { $0[0] == "polyline" }.compactMap {
            $0.child("pts")?.children.compactMap(\.point)
        }
        let body = CGRect(x: center.x - radius, y: center.y - radius,
                          width: radius * 2, height: radius * 2)
        return Self(pins: elements, body: body, isCircular: true, markings: markings,
                    pinNumbers: [1, 2, 3])
    }()

    static let smallResistor: Self? = {
        guard let elements = deviceElements("R_Small", library: "Device"),
              let rectangle = elements.first(where: { $0[0] == "rectangle" }),
              let start = rectangle.child("start")?.point,
              let end = rectangle.child("end")?.point else { return nil }

        let body = CGRect(x: min(start.x, end.x), y: min(start.y, end.y),
                          width: abs(end.x - start.x), height: abs(end.y - start.y))
        return Self(pins: elements, body: body, pinNumbers: [1, 2])
    }()

    static let diode1N4148: Self? = {
        guard let elements = deviceElements("1N4148", library: "Diode") else { return nil }
        let markings = elements.filter { $0[0] == "polyline" }.compactMap {
            $0.child("pts")?.children.compactMap(\.point)
        }
        let points = markings.flatMap { $0 }
        guard let left = points.map(\.x).min(), let right = points.map(\.x).max(),
              let top = points.map(\.y).min(), let bottom = points.map(\.y).max() else { return nil }

        let body = CGRect(x: left, y: top, width: right - left, height: bottom - top)
        return Self(pins: elements, body: body, markings: markings, pinNumbers: [1, 2])
    }()

    private static func deviceElements(_ name: String, library: String) -> [KiCadExpression]? {
        let path = "/Applications/KiCad/KiCad.app/Contents/SharedSupport/symbols/\(library).kicad_sym"
        guard let text = try? String(contentsOfFile: path, encoding: .utf8),
              let root = KiCadExpression.parse(text) else { return nil }

        let symbols = root.children.filter { $0[0] == "symbol" }
        var currentName = name
        var visited = Set<String>()
        while visited.insert(currentName).inserted,
              let symbol = symbols.first(where: { $0[1] == currentName }) {
            guard let parent = symbol.child("extends")?[1] else {
                return symbol.children.flatMap(\.children)
            }
            currentName = parent
        }
        return nil
    }

    static let additionalCounters: [CounterChip: Self] = Dictionary(
        uniqueKeysWithValues: CounterChip.allCases.map { kind in
            let imported = rectangularSymbol(elements: installedSymbol(String(kind.rawValue.dropFirst(2)))?.children.flatMap(\.children),
                                             pinNumbers: Array(1...16))
            return (kind, imported ?? counterSymbol(kind.makeComponent()))
        }
    )

    // Draw the physical DIP pin order and use exactly the labels from the model.
    static let analogSwitches: [AnalogSwitchKind: Self] = Dictionary(
        uniqueKeysWithValues: AnalogSwitchKind.allCases.map { kind in
            let chip = AnalogSwitch(kind)
            let terminals = (1...16).map { number in
                let left = number <= 8
                let row = left ? number - 1 : 16 - number
                return Terminal(id: number, name: chip.pins[number]!.name, style: "line",
                                position: CGPoint(x: left ? -20.32 : 20.32, y: -8.89 + Double(row) * 2.54),
                                inward: CGVector(dx: left ? 1 : -1, dy: 0), length: 5.08)
            }
            return (kind, Self(body: CGRect(x: -15.24, y: -11.43, width: 30.48, height: 22.86),
                               terminals: terminals))
        }
    )

    private init(body: CGRect, terminals: [Terminal]) {
        self.body = body
        self.terminals = terminals
        isCircular = false
        gateOutline = nil
        polygon = []
        markings = []
    }

    private static func counterSymbol(_ chip: any PoweredChip) -> Self {
        let inputs = chip.pins.values.filter { $0.direction == .input }.sorted { $0.number < $1.number }
        let outputs = chip.pins.values.filter { $0.direction == .output }.sorted { $0.number < $1.number }
        var terminals: [Terminal] = []
        for (pins, x, direction) in [(inputs, -12.7, 1.0), (outputs, 12.7, -1.0)] {
            for (row, pin) in pins.enumerated() {
                let label: String
                switch pin.name {
                case "CLOCK INHIBIT": label = "INH"
                case "DISPLAY ENABLE": label = "DEI"
                case "DISPLAY ENABLE OUT": label = "DEO"
                case "CARRY OUT": label = "CO"
                case "CARRY IN": label = "CI"
                case "UNGATED c": label = "Uc"
                case "UP/DOWN": label = "U/D"
                case "RESET": label = "RST"
                default: label = pin.name
                }
                terminals.append(Terminal(id: pin.number, name: label, style: "line",
                                          position: CGPoint(x: x, y: -11.43 + Double(row) * 2.54),
                                          inward: CGVector(dx: direction, dy: 0), length: 5.08))
            }
        }
        terminals.append(Terminal(id: chip.supplyPins.vdd, name: "VDD", style: "line",
                                  position: CGPoint(x: 0, y: -20.32), inward: CGVector(dx: 0, dy: 1), length: 5.08))
        terminals.append(Terminal(id: chip.supplyPins.vss, name: "VSS", style: "line",
                                  position: CGPoint(x: 0, y: 20.32), inward: CGVector(dx: 0, dy: -1), length: 5.08))
        return Self(body: CGRect(x: -7.62, y: -15.24, width: 15.24, height: 30.48), terminals: terminals)
    }

    static let counter = rectangularSymbol(
        elements: installedSymbol("4510")?.children.flatMap(\.children),
        pinNumbers: Array(1...16)
    )
    static let counter4060 = rectangularSymbol(
        elements: installedSymbol("4060")?.children.flatMap(\.children),
        pinNumbers: Array(1...16)
    )
    static let displayDrivers: [SevenSegmentDriverKind: Self] = [
        .cd4511: rectangularSymbol(elements: deviceElements("4511", library: "4xxx")
                                    ?? deviceElements("4511", library: "4xxx_IEEE"),
                                   pinNumbers: Array(1...16)),
        .cd4543: rectangularSymbol(elements: installedSymbol("4543")?.children.flatMap(\.children),
                                   pinNumbers: Array(1...16))
    ].compactMapValues { $0 }

    static let man72a = rectangularSymbol(
        elements: deviceElements("MAN72A", library: "Display_Character")?.filter { $0[1] != "no_connect" },
        pinNumbers: (MAN72A.segmentPins + MAN72A.commonPins).sorted()
    )

    static let man74a = rectangularSymbol(
        elements: deviceElements("MAN74A", library: "Display_Character")?.filter { $0[1] != "no_connect" },
        pinNumbers: (MAN74A.segmentPins + MAN74A.commonPins).sorted()
    )

    private static func rectangularSymbol(elements: [KiCadExpression]?, pinNumbers: [Int]) -> Self? {
        guard let elements, let rectangle = elements.first(where: { $0[0] == "rectangle" }),
              let start = rectangle.child("start")?.point,
              let end = rectangle.child("end")?.point else { return nil }

        let body = CGRect(x: min(start.x, end.x), y: min(start.y, end.y),
                          width: abs(end.x - start.x), height: abs(end.y - start.y))
        let markings = elements.filter { $0[0] == "polyline" }.compactMap {
            $0.child("pts")?.children.compactMap(\.point)
        }
        return Self(pins: elements, body: body, markings: markings, pinNumbers: pinNumbers)
    }

    static let chipUnits: [MultiUnitChip: [Int: Self]] = Dictionary(
        uniqueKeysWithValues: MultiUnitChip.allCases.map { ($0, loadUnits($0)) }
    )

    private static func loadUnits(_ kind: MultiUnitChip) -> [Int: Self] {
        guard let symbol = installedSymbol(kind.rawValue) else { return [:] }
        var units: [Int: Self] = [:]
        for unit in kind.allUnits {
            if unit.id == kind.powerUnit.id || kind == .dualBCD || kind == .dualBinary {
                let prefix = "\(kind.rawValue)_\(unit.id)_"
                let elements = symbol.children.filter { $0[0] == "symbol" && ($0[1]?.hasPrefix(prefix) ?? false) }.flatMap(\.children)
                units[unit.id] = rectangularSymbol(elements: elements, pinNumbers: unit.pinNumbers)
                continue
            }
            let style = kind == .inverter ? 0 : 1
            let name = "\(kind.rawValue)_\(unit.id)_\(style)"
            guard let expression = symbol.children.first(where: { $0[0] == "symbol" && $0[1] == name })
            else { continue }
            units[unit.id] = loadUnit(expression, pinNumbers: unit.pinNumbers)
        }
        return units
    }

    private static func loadUnit(_ expression: KiCadExpression, pinNumbers: [Int]) -> Self? {
        let pins = expression.children
        if let rectangle = expression.child("rectangle"),
           let start = rectangle.child("start")?.point, let end = rectangle.child("end")?.point {
            return Self(pins: pins, body: CGRect(x: min(start.x, end.x), y: min(start.y, end.y),
                                              width: abs(end.x - start.x), height: abs(end.y - start.y)),
                        pinNumbers: pinNumbers)
        }

        let polylines = expression.children.filter { $0[0] == "polyline" }.compactMap {
            $0.child("pts")?.children.compactMap(\.point)
        }
        guard let points = polylines.first, let left = points.map(\.x).min(), points.count >= 3
        else { return nil }

        if let arc = expression.child("arc"), let start = arc.child("start")?.point,
           let middle = arc.child("mid")?.point, let end = arc.child("end")?.point {
            let body = CGRect(x: left, y: min(start.y, end.y),
                              width: middle.x - left, height: abs(end.y - start.y))
            let outline = GateOutline(points: points, start: start, middle: middle, end: end)
            return Self(pins: pins, body: body, gateOutline: outline, pinNumbers: pinNumbers)
        }

        guard let right = points.map(\.x).max(), let top = points.map(\.y).min(),
              let bottom = points.map(\.y).max() else { return nil }
        let body = CGRect(x: left, y: top, width: right - left, height: bottom - top)
        return Self(pins: pins, body: body, polygon: points, markings: Array(polylines.dropFirst()),
                    pinNumbers: pinNumbers)
    }

    private static func installedSymbol(_ name: String) -> KiCadExpression? {
        installedLibrary?.children.first { $0[0] == "symbol" && $0[1] == name }
    }

    private init?(pins: [KiCadExpression], body: CGRect, isCircular: Bool = false, gateOutline: GateOutline? = nil,
                  polygon: [CGPoint] = [], markings: [[CGPoint]] = [], pinNumbers: [Int]) {
        self.body = body
        self.isCircular = isCircular
        self.gateOutline = gateOutline
        self.polygon = polygon
        self.markings = markings
        terminals = pins.filter { $0[0] == "pin" }.compactMap { pin in
            guard let number = pin.child("number")?[1].flatMap(Int.init),
                  let name = pin.child("name")?[1],
                  let style = pin[2], ["line", "inverted", "clock", "inverted_clock"].contains(style),
                  let at = pin.child("at"), let position = at.point,
                  let length = pin.child("length")?[1].flatMap(Double.init) else { return nil }

            let inward: CGVector
            switch at[3] {
            case "0": inward = CGVector(dx: 1, dy: 0)
            case "90": inward = CGVector(dx: 0, dy: -1)
            case "180": inward = CGVector(dx: -1, dy: 0)
            case "270": inward = CGVector(dx: 0, dy: 1)
            default: return nil
            }
            return Terminal(id: number, name: name == "~{Q}" ? "Q̅" : name.replacingOccurrences(of: "~{", with: "").replacingOccurrences(of: "}", with: ""), style: style, position: position,
                            inward: inward, length: length)
        }
        guard terminals.map(\.id).sorted() == pinNumbers else { return nil }
    }
}

private enum KiCadExpression {
    case atom(String)
    case list([KiCadExpression])

    var children: [KiCadExpression] {
        if case .list(let expressions) = self { return expressions }
        return []
    }

    subscript(index: Int) -> String? {
        let expressions = children
        guard expressions.indices.contains(index), case .atom(let value) = expressions[index] else {
            return nil
        }
        return value
    }

    func child(_ name: String) -> Self? {
        children.first { $0[0] == name }
    }

    var point: CGPoint? {
        guard let x = self[1].flatMap(Double.init), let y = self[2].flatMap(Double.init) else { return nil }
        return CGPoint(x: x, y: -y)
    }

    static func parse(_ text: String) -> Self? {
        let pattern = #""(?:\\.|[^"\\])*"|[()]|[^\s()"]+"#
        guard let lexer = try? NSRegularExpression(pattern: pattern) else { return nil }
        var stack: [[Self]] = [[]]
        for match in lexer.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
            guard let range = Range(match.range, in: text) else { return nil }
            let token = text[range]
            switch token {
            case "(":
                stack.append([])
            case ")":
                guard stack.count > 1, let expressions = stack.popLast() else { return nil }
                stack[stack.count - 1].append(.list(expressions))
            default:
                let value = token.first == "\"" ? token.dropFirst().dropLast() : token
                stack[stack.count - 1].append(.atom(String(value)))
            }
        }
        guard stack.count == 1, stack[0].count == 1 else { return nil }
        return stack[0].first
    }
}
