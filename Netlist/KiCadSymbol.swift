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
    let filledMarkings: [[CGPoint]]
    let terminals: [Terminal]

    private static let installedLibrary: KiCadExpression? = {
        let path = "/Applications/KiCad/KiCad.app/Contents/SharedSupport/symbols/4xxx.kicad_sym"
        guard let text = try? String(contentsOfFile: path, encoding: .utf8),
              let root = KiCadExpression.parse(text), root[0] == "kicad_symbol_lib" else { return nil }
        return root
    }()

    static let npn2N3904 = transistorSymbol("2N3904")
    static let bc547 = transistorSymbol("BC547")
    static let pnp2N3906 = transistorSymbol("2N3906")

    private static func transistorSymbol(_ name: String) -> Self? {
        guard let elements = deviceElements(name, library: "Transistor_BJT"),
              let circle = elements.first(where: { $0[0] == "circle" }),
              let center = circle.child("center")?.point,
              let radius = circle.child("radius")?[1].flatMap(Double.init) else { return nil }

        let markings = elements.filter { $0[0] == "polyline" }.compactMap {
            $0.child("pts")?.children.compactMap(\.point)
        }
        let body = CGRect(x: center.x - radius, y: center.y - radius,
                          width: radius * 2, height: radius * 2)
        return Self(pins: elements, body: body, isCircular: true, markings: markings,
                    pinNumbers: [1, 2, 3])
    }

    static let capacitors: [CapacitorKind: Self] = Dictionary(uniqueKeysWithValues:
        CapacitorKind.allCases.compactMap { kind -> (CapacitorKind, Self)? in
            guard let elements = deviceElements(kind.rawValue, library: "Device") else { return nil }
            var markings = elements.filter { $0[0] == "polyline" }.compactMap {
                $0.child("pts")?.children.compactMap(\.point)
            }
            var filledMarkings: [[CGPoint]] = []
            for rectangle in elements where rectangle[0] == "rectangle" {
                if let a = rectangle.child("start")?.point, let b = rectangle.child("end")?.point {
                    let plate = [a, CGPoint(x: b.x, y: a.y), b, CGPoint(x: a.x, y: b.y), a]
                    markings.append(plate)
                    if rectangle.child("fill")?.child("type")?[1] == "outline" {
                        filledMarkings.append(plate)
                    }
                }
            }
            let points = markings.flatMap { $0 }
            guard let left = points.map(\.x).min(), let right = points.map(\.x).max(),
                  let top = points.map(\.y).min(), let bottom = points.map(\.y).max(),
                  let symbol = Self(pins: elements, body: CGRect(x: left, y: top, width: right-left, height: bottom-top),
                                    markings: markings, filledMarkings: filledMarkings, pinNumbers: [1, 2]) else { return nil }
            return (kind, symbol)
        })

    static let smallResistor: Self? = {
        guard let elements = deviceElements("R_Small", library: "Device"),
              let rectangle = elements.first(where: { $0[0] == "rectangle" }),
              let start = rectangle.child("start")?.point,
              let end = rectangle.child("end")?.point else { return nil }

        let body = CGRect(x: min(start.x, end.x), y: min(start.y, end.y),
                          width: abs(end.x - start.x), height: abs(end.y - start.y))
        return Self(pins: elements, body: body, pinNumbers: [1, 2])
    }()

    static let axialResistor = axialPackage(halfBodyWidth: 2.413)
    static let axialSmallCapacitor = axialPackage(halfBodyWidth: 1.651)

    static let axialPolarizedCapacitor = axialPackage(halfBodyWidth: 2.667, halfBodyHeight: 1.27)

    private static func axialPackage(halfBodyWidth: CGFloat, halfBodyHeight: CGFloat = 1.016) -> Self {
        let halfSpan: CGFloat = 3.81
        let leadLength = halfSpan - halfBodyWidth
        return Self(
            body: CGRect(x: -halfBodyWidth, y: -halfBodyHeight, width: 2 * halfBodyWidth, height: 2 * halfBodyHeight),
            terminals: [
                Terminal(id: 1, name: "", style: "line", position: CGPoint(x: -halfSpan, y: 0),
                         inward: CGVector(dx: 1, dy: 0), length: leadLength),
                Terminal(id: 2, name: "", style: "line", position: CGPoint(x: halfSpan, y: 0),
                         inward: CGVector(dx: -1, dy: 0), length: leadLength)
            ]
        )
    }

    static let led3mm = Self(
        body: CGRect(x: -2.54, y: -5.08, width: 5.08, height: 7.62),
        markings: [
            [CGPoint(x: -2.54, y: -2.54), CGPoint(x: -2.54, y: 2.54)],
            [CGPoint(x: -2.54, y: 0), CGPoint(x: 2.54, y: -2.54),
             CGPoint(x: 2.54, y: 2.54), CGPoint(x: -2.54, y: 0)],
            [CGPoint(x: -1.27, y: -3.18), CGPoint(x: -3.81, y: -5.72),
             CGPoint(x: -2.54, y: -5.72), CGPoint(x: -3.81, y: -5.72), CGPoint(x: -3.81, y: -4.45)],
            [CGPoint(x: 1.27, y: -3.18), CGPoint(x: -1.27, y: -5.72),
             CGPoint(x: 0, y: -5.72), CGPoint(x: -1.27, y: -5.72), CGPoint(x: -1.27, y: -4.45)]
        ],
        terminals: [
            Terminal(id: 1, name: "K", style: "line", position: CGPoint(x: -7.62, y: 0),
                     inward: CGVector(dx: 1, dy: 0), length: 5.08),
            Terminal(id: 2, name: "A", style: "line", position: CGPoint(x: 7.62, y: 0),
                     inward: CGVector(dx: -1, dy: 0), length: 5.08)
        ]
    )

    static let diode1N4148: Self = {
        if let elements = deviceElements("1N4148", library: "Diode"),
           let symbol = diodeSymbol(elements) {
            return symbol
        }

        // Mirror the library symbol when KiCad is unavailable so both appearances share the same pins.
        return Self(
            body: CGRect(x: -1.27, y: -1.27, width: 2.54, height: 2.54),
            markings: [
                [CGPoint(x: -1.27, y: -1.27), CGPoint(x: -1.27, y: 1.27)],
                [CGPoint(x: 1.27, y: -1.27), CGPoint(x: 1.27, y: 1.27),
                 CGPoint(x: -1.27, y: 0), CGPoint(x: 1.27, y: -1.27)],
                [CGPoint(x: 1.27, y: 0), CGPoint(x: -1.27, y: 0)]
            ],
            terminals: [
                Terminal(id: 1, name: "K", style: "line", position: CGPoint(x: -3.81, y: 0),
                         inward: CGVector(dx: 1, dy: 0), length: 2.54),
                Terminal(id: 2, name: "A", style: "line", position: CGPoint(x: 3.81, y: 0),
                         inward: CGVector(dx: -1, dy: 0), length: 2.54)
            ]
        )
    }()

    private static func diodeSymbol(_ elements: [KiCadExpression]) -> Self? {
        let markings = elements.filter { $0[0] == "polyline" }.compactMap {
            $0.child("pts")?.children.compactMap(\.point)
        }
        let points = markings.flatMap { $0 }
        guard let left = points.map(\.x).min(), let right = points.map(\.x).max(),
              let top = points.map(\.y).min(), let bottom = points.map(\.y).max() else { return nil }

        let body = CGRect(x: left, y: top, width: right - left, height: bottom - top)
        return Self(pins: elements, body: body, markings: markings, pinNumbers: [1, 2])
    }

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
            if kind.isTTL { return (kind, counterSymbol(kind.makeComponent())) }
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

    private init(body: CGRect, gateOutline: GateOutline? = nil, polygon: [CGPoint] = [], markings: [[CGPoint]] = [], terminals: [Terminal]) {
        self.body = body
        self.terminals = terminals
        isCircular = false
        self.gateOutline = gateOutline
        self.polygon = polygon
        self.markings = markings
        filledMarkings = []
    }

    static let mechanicalSwitches: [SwitchDesignation: Self] = Dictionary(uniqueKeysWithValues:
        SwitchDesignation.allCases.map { designation in
            func terminal(_ id: Int, x: CGFloat, y: CGFloat) -> Terminal {
                Terminal(id: id, name: "", style: "line", position: CGPoint(x: x, y: y),
                         inward: CGVector(dx: x < 0 ? 1 : -1, dy: 0), length: 2.54)
            }
            let pins = designation == .pushButton
                ? [terminal(1, x: -5.08, y: 0), terminal(2, x: 5.08, y: 0)]
                : [terminal(1, x: 5.08, y: -2.54), terminal(2, x: -5.08, y: 0),
                   terminal(3, x: 5.08, y: 2.54)]
            return (designation, Self(body: CGRect(x: -3.81, y: -3.81, width: 7.62, height: 7.62),
                                      terminals: pins))
        })

    static let pinHeaders: [PinHeaderKind: Self] = Dictionary(uniqueKeysWithValues:
        PinHeaderKind.allCases.map { kind in
            let pitch = 2.54
            let terminals = kind.pinNumbers.map { number in
                Terminal(id: number, name: "", style: "line",
                         position: CGPoint(x: Double(number - 1) * pitch, y: -5.08),
                         inward: CGVector(dx: 0, dy: 1), length: 5.08)
            }
            let body = CGRect(x: -5.08, y: -2.54, width: Double(kind.rawValue + 1) * pitch, height: 3.81)
            return (kind, Self(body: body, terminals: terminals))
        }
    )

    static func fallback(pins: [Pin]) -> Self {
        let left = pins.filter { $0.direction != .output }
        let right = pins.filter { $0.direction == .output }
        let rowCount = max(left.count, right.count)
        let body = CGRect(x: -12.7, y: -2.54, width: 25.4, height: Double(rowCount + 1) * 2.54)
        let terminals = [(left, -17.78, 1.0), (right, 17.78, -1.0)].flatMap { pins, x, direction in
            pins.enumerated().map { row, pin in
                Terminal(id: pin.number, name: pin.name, style: "line",
                         position: CGPoint(x: x, y: Double(row) * 2.54),
                         inward: CGVector(dx: direction, dy: 0), length: 5.08)
            }
        }
        return Self(body: body, terminals: terminals)
    }

    private static func counterSymbol(_ chip: any PoweredChip) -> Self {
        let inputs = chip.pins.values.filter { $0.direction == .input }.sorted { $0.number < $1.number }
        let outputs = chip.pins.values.filter { $0.direction == .output }.sorted { $0.number < $1.number }
        let unconnected = chip.pins.values.filter { $0.direction == .noConnect }.sorted { $0.number < $1.number }
        var terminals: [Terminal] = []
        for (pins, x, direction) in [(inputs, -12.7, 1.0), (outputs + unconnected, 12.7, -1.0)] {
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
                let style = label == "CKA" || label == "CKB" ? "inverted_clock" : "line"
                terminals.append(Terminal(id: pin.number, name: label, style: style,
                                          position: CGPoint(x: x, y: -11.43 + Double(row) * 2.54),
                                          inward: CGVector(dx: direction, dy: 0), length: 5.08))
            }
        }
        terminals.append(Terminal(id: chip.supplyPins.vdd, name: chip.pins[chip.supplyPins.vdd]!.name, style: "line",
                                  position: CGPoint(x: 0, y: -20.32), inward: CGVector(dx: 0, dy: 1), length: 5.08))
        terminals.append(Terminal(id: chip.supplyPins.vss, name: chip.pins[chip.supplyPins.vss]!.name, style: "line",
                                  position: CGPoint(x: 0, y: 20.32), inward: CGVector(dx: 0, dy: -1), length: 5.08))
        return Self(body: CGRect(x: -7.62, y: -15.24, width: 15.24, height: 30.48), terminals: terminals)
    }

    static let oscillatorDIP8 = Self(
        body: CGRect(x: -7.62, y: -5.08, width: 15.24, height: 10.16),
        terminals: [
            Terminal(id: 1, name: "EN", style: "line", position: CGPoint(x: -12.7, y: 0),
                     inward: CGVector(dx: 1, dy: 0), length: 5.08),
            Terminal(id: 4, name: "GND", style: "line", position: CGPoint(x: 0, y: 10.16),
                     inward: CGVector(dx: 0, dy: -1), length: 5.08),
            Terminal(id: 5, name: "OUT", style: "line", position: CGPoint(x: 12.7, y: 0),
                     inward: CGVector(dx: -1, dy: 0), length: 5.08),
            Terminal(id: 8, name: "VCC", style: "line", position: CGPoint(x: 0, y: -10.16),
                     inward: CGVector(dx: 0, dy: 1), length: 5.08)
        ]
    )

    static let ne555 = rectangularSymbol(
        elements: deviceElements("NE555P", library: "Timer"), pinNumbers: Array(1...8)
    )

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

    static let man74a: Self = {
        let display = MAN74A()
        let step: CGFloat = 1.27
        let body = CGRect(x: -4 * step, y: -10 * step, width: 10 * step, height: 20 * step)
        let rows: [CGFloat] = [-8, -6, -4, -2, 0, 2, 4, 8]
        let segments = zip(display.segmentNumbers, rows).map { number, row in
            Terminal(id: number, name: display.pins[number]!.name, style: "line",
                     position: CGPoint(x: -6 * step, y: row * step),
                     inward: CGVector(dx: 1, dy: 0), length: 2 * step)
        }
        let commons = zip(display.commonNumbers, [-2 * step, 4 * step]).map { number, x in
            Terminal(id: number, name: display.pins[number]!.name, style: "line",
                     position: CGPoint(x: x, y: 12 * step),
                     inward: CGVector(dx: 0, dy: -1), length: 2 * step)
        }
        return Self(body: body, terminals: segments + commons)
    }()

    static let man74aSchematic: Self = {
        let step: CGFloat = 1.27
        let body = man74a.body.insetBy(dx: step, dy: 0).offsetBy(dx: -step, dy: 0)
        let segments = man74a.terminals.filter { MAN74A.segmentPins.contains($0.id) }
        let commonPins = man74a.terminals.filter { MAN74A.commonPins.contains($0.id) }
        let commons = zip(commonPins.reversed(), [6, 8]).map { pin, row in
            Terminal(id: pin.id, name: pin.name, style: pin.style,
                     position: CGPoint(x: body.maxX + 2 * step, y: CGFloat(row) * step),
                     inward: CGVector(dx: -1, dy: 0), length: 2 * step)
        }
        return Self(body: body, terminals: segments + commons)
    }()

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
        if kind == .xor { return xorUnits() }
        if kind == .hc08 { return hc08Units() }
        if let package = kind.hcPackage { return hcUnits(package) }
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
            units[unit.id] = kind == .or
                ? loadORUnit(expression, pinNumbers: unit.pinNumbers)
                : loadUnit(expression, pinNumbers: unit.pinNumbers)
        }
        return units
    }

    private static func hc08Units() -> [Int: Self] {
        let step = 1.27
        let outline = GateOutline(
            points: [CGPoint(x: 0, y: -3 * step), CGPoint(x: -3 * step, y: -3 * step),
                     CGPoint(x: -3 * step, y: 3 * step), CGPoint(x: 0, y: 3 * step)],
            start: CGPoint(x: 0, y: -3 * step), middle: CGPoint(x: 3 * step, y: 0),
            end: CGPoint(x: 0, y: 3 * step))
        var symbols = Dictionary(uniqueKeysWithValues: QuadGate.allCases.map { gate in
            let pins = SN74HC08.terminals(gate)
            let terminals = [
                Terminal(id: pins.inputA, name: "", style: "line", position: CGPoint(x: -7 * step, y: -2 * step),
                         inward: CGVector(dx: 1, dy: 0), length: 4 * step),
                Terminal(id: pins.inputB, name: "", style: "line", position: CGPoint(x: -7 * step, y: 2 * step),
                         inward: CGVector(dx: 1, dy: 0), length: 4 * step),
                Terminal(id: pins.output, name: "", style: "line", position: CGPoint(x: 7 * step, y: 0),
                         inward: CGVector(dx: -1, dy: 0), length: 4 * step)
            ]
            return (gate.rawValue, Self(body: CGRect(x: -3 * step, y: -3 * step, width: 6 * step, height: 6 * step),
                                        gateOutline: outline, terminals: terminals))
        })
        let chip = SN74HC08()
        symbols[5] = Self(
            body: CGRect(x: -5 * step, y: -2 * step, width: 10 * step, height: 4 * step),
            terminals: [
                Terminal(id: 14, name: chip.pins[14]!.name, style: "line", position: CGPoint(x: -7 * step, y: 0),
                         inward: CGVector(dx: 1, dy: 0), length: 2 * step),
                Terminal(id: 7, name: chip.pins[7]!.name, style: "line", position: CGPoint(x: 7 * step, y: 0),
                         inward: CGVector(dx: -1, dy: 0), length: 2 * step)
            ])
        return symbols
    }

    private static func hcUnits(_ package: HCGatePackage) -> [Int: Self] {
        let step = 1.27
        func point(_ x: Double, _ y: Double) -> CGPoint {
            CGPoint(x: x * step, y: y * step)
        }

        let templates: [Int: Self]
        let inputsAndOutput: [[Int]]
        if package.quadKind != nil {
            templates = package == .hc00 ? hc08Units() : xorUnits()
            inputsAndOutput = QuadGate.allCases.map { gate in
                let pins = package.quadTerminals(gate)
                return [pins.inputA, pins.inputB, pins.output]
            }
        } else {
            let inverter = Self(
                body: CGRect(x: -3 * step, y: -3 * step, width: 6 * step, height: 6 * step),
                polygon: [point(-3, -3), point(3, 0), point(-3, 3)],
                markings: package == .hc14
                    ? [[point(-2, 1), point(-1, 1), point(-1, -1), point(0.5, -1)],
                       [point(-1.5, 1), point(-0.5, 1), point(-0.5, -1)]] : [],
                terminals: [
                    Terminal(id: 1, name: "", style: "line", position: point(-7, 0),
                             inward: CGVector(dx: 1, dy: 0), length: 4 * step),
                    Terminal(id: 2, name: "", style: "inverted", position: point(7, 0),
                             inward: CGVector(dx: -1, dy: 0), length: 4 * step)
                ])
            inputsAndOutput = HCGatePackage.inverterTerminals.map { [$0.input, $0.output] }
            templates = Dictionary(uniqueKeysWithValues: (1...inputsAndOutput.count).map { ($0, inverter) })
        }
        var symbols = Dictionary(uniqueKeysWithValues: inputsAndOutput.enumerated().map { index, numbers in
            let template = templates[index + 1]!
            let terminals = zip(numbers, template.terminals).map { number, pin in
                let invert = number == numbers.last && (package == .hc00 || package == .hc02)
                return Terminal(id: number, name: "", style: invert ? "inverted" : pin.style,
                                position: pin.position, inward: pin.inward, length: pin.length)
            }
            let markings = package == .hc02 || package == .hc32 ? [] : template.markings
            return (index + 1, Self(body: template.body, gateOutline: template.gateOutline,
                                    polygon: template.polygon, markings: markings, terminals: terminals))
        })
        symbols[inputsAndOutput.count + 1] = hc08Units()[5]
        return symbols
    }

    private static func xorUnits() -> [Int: Self] {
        let step = 1.27
        func point(_ x: Double, _ y: Double) -> CGPoint {
            CGPoint(x: x * step, y: y * step)
        }

        func inputFace(at y: Double) -> Double {
            return -3.5 + 1.6 * (1 - y * y / 9)
        }
        let face = (0...24).map { index -> CGPoint in
            let y = Double(index) / 4 - 3
            return point(inputFace(at: y), y)
        }
        // The reference has flat shoulders and two arcs meeting at the output.
        let lowerArc = (0...12).map { index -> CGPoint in
            let t = Double(index) / 12
            let u = 1 - t
            return point(-u * u + 4.4 * u * t + 3.5 * t * t, 3 * (1 - t * t))
        }
        let upperArc = lowerArc.reversed().dropFirst().map { CGPoint(x: $0.x, y: -$0.y) }
        let extraCurve = face.map { CGPoint(x: $0.x - step / 2, y: $0.y) }
        var symbols = Dictionary(uniqueKeysWithValues: QuadGate.allCases.map { gate in
            let pins = gate.terminals
            return (gate.rawValue, Self(
                body: CGRect(x: -4 * step, y: -3 * step, width: 7.5 * step, height: 6 * step),
                polygon: face + lowerArc + upperArc,
                markings: [extraCurve],
                terminals: [
                    Terminal(id: pins.inputA, name: "", style: "line", position: point(-7, -2),
                             inward: CGVector(dx: 1, dy: 0), length: (7 + inputFace(at: 2)) * step),
                    Terminal(id: pins.inputB, name: "", style: "line", position: point(-7, 2),
                             inward: CGVector(dx: 1, dy: 0), length: (7 + inputFace(at: 2)) * step),
                    Terminal(id: pins.output, name: "", style: "line", position: point(7, 0),
                             inward: CGVector(dx: -1, dy: 0), length: 3.5 * step)
                ]))
        })
        let supplyPins = MultiUnitChip.xor.powerUnit
        symbols[supplyPins.id] = Self(
            body: CGRect(x: -5 * step, y: -2 * step, width: 10 * step, height: 4 * step),
            terminals: [
                Terminal(id: 14, name: "VDD", style: "line", position: point(-7, 0),
                         inward: CGVector(dx: 1, dy: 0), length: 2 * step),
                Terminal(id: 7, name: "GND", style: "line", position: point(7, 0),
                         inward: CGVector(dx: -1, dy: 0), length: 2 * step)
            ])
        return symbols
    }

    private static func loadORUnit(_ expression: KiCadExpression, pinNumbers: [Int]) -> Self? {
        // KiCad supplies the concave input face as a polyline and the output face as two arcs.
        let polylines = expression.children.filter { $0[0] == "polyline" }.compactMap {
            $0.child("pts")?.children.compactMap(\.point)
        }
        guard var outline = polylines.max(by: { $0.count < $1.count }) else { return nil }
        for arc in expression.children.filter({ $0[0] == "arc" }).dropFirst() {
            guard let start = arc.child("end")?.point,
                  let mid = arc.child("mid")?.point,
                  let end = arc.child("start")?.point else { return nil }
            let control = CGPoint(x: 2 * mid.x - (start.x + end.x) / 2,
                                  y: 2 * mid.y - (start.y + end.y) / 2)
            for step in 0...24 {
                let t = CGFloat(step) / 24
                let u = 1 - t
                outline.append(CGPoint(x: u * u * start.x + 2 * u * t * control.x + t * t * end.x,
                                       y: u * u * start.y + 2 * u * t * control.y + t * t * end.y))
            }
        }
        guard let left = outline.map(\.x).min(), let right = outline.map(\.x).max(),
              let top = outline.map(\.y).min(), let bottom = outline.map(\.y).max() else { return nil }
        return Self(pins: expression.children,
                    body: CGRect(x: left, y: top, width: right - left, height: bottom - top),
                    polygon: outline, pinNumbers: pinNumbers)
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
                  polygon: [CGPoint] = [], markings: [[CGPoint]] = [], filledMarkings: [[CGPoint]] = [], pinNumbers: [Int]) {
        self.body = body
        self.isCircular = isCircular
        self.gateOutline = gateOutline
        self.polygon = polygon
        self.markings = markings
        self.filledMarkings = filledMarkings
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

enum KiCadExpression {
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
        let textRange = NSRange(text.startIndex..., in: text)
        var offset = 0
        let source = text as NSString
        var stack: [[Self]] = [[]]
        for match in lexer.matches(in: text, range: textRange) {
            let skipped = NSRange(location: offset, length: match.range.location - offset)
            guard source.substring(with: skipped).allSatisfy(\.isWhitespace) else { return nil }
            offset = NSMaxRange(match.range)
            guard let range = Range(match.range, in: text) else { return nil }
            let token = text[range]
            switch token {
            case "(":
                guard stack.count < 256 else { return nil }
                stack.append([])
            case ")":
                guard stack.count > 1, let expressions = stack.popLast() else { return nil }
                stack[stack.count - 1].append(.list(expressions))
            default:
                let value = token.first == "\"" ? unquote(token.dropFirst().dropLast()) : String(token)
                stack[stack.count - 1].append(.atom(value))
            }
        }
        let trailing = NSRange(location: offset, length: textRange.length - offset)
        guard source.substring(with: trailing).allSatisfy(\.isWhitespace),
              stack.count == 1, stack[0].count == 1 else { return nil }
        return stack[0].first
    }

    private static func unquote(_ token: Substring) -> String {
        var result = ""
        var escaped = false
        for character in token {
            if escaped {
                switch character {
                case "\"": result.append("\"")
                case "\\": result.append("\\")
                case "n": result.append("\n")
                case "r": result.append("\r")
                case "t": result.append("\t")
                default:
                    result.append("\\")
                    result.append(character)
                }
                escaped = false
            } else if character == "\\" {
                escaped = true
            } else {
                result.append(character)
            }
        }
        return result
    }
}
