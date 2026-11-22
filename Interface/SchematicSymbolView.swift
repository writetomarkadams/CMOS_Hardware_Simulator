import SwiftUI

extension Color {
    static let schematicSelectionFill = Color(red: 0.88, green: 1, blue: 1)
    static let schematicSelectionInk = Color(red: 0, green: 0.48, blue: 0.58)
}

struct SchematicSymbolView: View {
    let symbol: KiCadSymbol
    let part: WorkbenchPart

    private var partID: Int { part.id }
    let bench: Workbench
    let isSelected: Bool
    let select: () -> Void
    let rotate: (Int) -> Void
    var editResistance: (() -> Void)? = nil
    var editCapacitance: (() -> Void)? = nil
    var editFrequency: (() -> Void)? = nil
    private var capacitor: Capacitor? { part.component as? Capacitor }

    private var resistor: Resistor? { part.component as? Resistor }
    private var display: SevenSegmentDisplay? { part.component as? SevenSegmentDisplay }
    private var usesMAN74AFace: Bool {
        bench.componentAppearance == .physicalDIP && part.component is MAN74A
    }
    private var isPinHeader: Bool { part.component is PinHeader }
    private var isDiode: Bool { part.component is Diode1N4148 || part.component is LED3mm }
    private var isXORGate: Bool {
        part.unitPlacement?.kind == .xor && part.unitPlacement?.isPowerUnit == false
    }

    private var isDiscrete: Bool { symbol.isCircular || resistor != nil || capacitor != nil || isDiode }

    private var valueLabel: String {
        if let capacitor { return "\(capacitor.value.formatted()) \(capacitor.kind.unit)" }
        if let resistor {
            return "\(resistor.value.formatted()) \(resistor.unit.rawValue)"
        }
        if part.component is NE555 || part.component is AnalogSwitch || CounterChip.kind(of: part.component) != nil || part.component is CD4060 || part.component is SevenSegmentDriver || display != nil {
            return part.name
        }
        return part.unitPlacement?.kind.rawValue ?? part.name
    }

    private var labelPosition: CGPoint {
        if isPinHeader {
            return point(CGPoint(x: symbol.body.minX, y: symbol.body.minY))
        }
        if resistor != nil || capacitor != nil || symbol.isCircular {
            return CGPoint(x: bodyCenter.x + 42, y: bodyCenter.y)
        }
        if usesMAN74AFace {
            return CGPoint(x: bodyCenter.x, y: point(symbol.body.origin).y + bodySize.height - 23)
        }
        if bench.componentAppearance == .schematic && part.component is MAN74A {
            return CGPoint(x: bodyCenter.x, y: point(symbol.body.origin).y - 13)
        }
        if isDiode || display != nil || !symbol.polygon.isEmpty {
            return CGPoint(x: bodyCenter.x, y: point(symbol.body.origin).y + bodySize.height + 14)
        }
        return bodyCenter
    }

    private let scale = SchematicSymbolGeometry.scale
    private var geometry: SchematicSymbolGeometry { SchematicSymbolGeometry(symbol: symbol, part: part) }
    private let bodyFill = Color(red: 1, green: 1, blue: 0.76)
    private let outline = Color(red: 0.65, green: 0, blue: 0)
    private let labelInk = Color(red: 0, green: 0.35, blue: 0.36)

    private var bodySize: CGSize {
        CGSize(width: symbol.body.width * scale, height: symbol.body.height * scale)
    }

    private var bodyCenter: CGPoint {
        point(CGPoint(x: symbol.body.midX, y: symbol.body.midY))
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            Canvas { context, _ in
                let outlinePath = symbolOutline()
                if isSelected && !isPinHeader && !usesMAN74AFace {
                    context.fill(outlinePath, with: .color(.schematicSelectionFill))
                    context.stroke(outlinePath, with: .color(.cyan.opacity(0.3)), lineWidth: 4)
                } else if !isDiscrete && !isPinHeader && !usesMAN74AFace {
                    context.fill(outlinePath, with: .color(bodyFill))
                }
                if capacitor == nil && !isPinHeader && !usesMAN74AFace {
                    context.stroke(outlinePath, with: .color(outline), lineWidth: 1.2)
                }
                if let display {
                    if usesMAN74AFace {
                        drawMAN74AFace(display, in: context)
                        if isSelected {
                            context.stroke(outlinePath, with: .color(.cyan), lineWidth: 2)
                        }
                    } else if bench.componentAppearance == .physicalDIP {
                        drawSevenSegmentFace(display, in: context, point: point, state: displayReading)
                    } else {
                        drawSevenSegmentSchematic(display, body: symbol.body, in: context, point: point, state: displayReading)
                    }
                }
                for marking in symbol.filledMarkings {
                    var path = Path()
                    path.addLines(marking.map(point))
                    path.closeSubpath()
                    context.fill(path, with: .color(isDiscrete ? outline : labelInk))
                }
                for marking in display == nil ? symbol.markings : [] {
                    var path = Path()
                    path.addLines(marking.map(point))
                    if isSelected {
                        context.stroke(path, with: .color(.cyan.opacity(0.35)), lineWidth: 4)
                    }
                    if bench.illuminatedLEDs.contains(partID) {
                        context.stroke(path, with: .color(.red.opacity(0.30)), lineWidth: 7)
                        context.stroke(path, with: .color(.red), lineWidth: 2)
                    } else {
                        context.stroke(path, with: .color(isDiscrete || isXORGate ? outline : labelInk), lineWidth: 1)
                    }
                }
                for pin in symbol.terminals {
                    draw(pin, in: context)
                }
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)

            Rectangle()
                .fill(.clear)
                .frame(width: bodySize.width, height: bodySize.height)
                .contentShape(Rectangle())
                .onTapGesture(perform: select)
                .contextMenu {
                    PartRotationCommands(rotate: rotate)
                    if let editCapacitance {
                        Button("Set Capacitance…", action: editCapacitance)
                    }
                    if let editResistance {
                        Button("Set Resistance…", action: editResistance)
                    }
                    if let editFrequency { Button("Set Frequency…", action: editFrequency) }
                    Button("Remove Part", role: .destructive) { bench.removePart(partID) }
                }
                .position(bodyCenter)

            if isXORGate {
                Text(valueLabel)
                    .font(.system(size: 15, design: .monospaced))
                    .foregroundStyle(labelInk)
                    .position(x: bodyCenter.x + 3, y: bodyCenter.y)
                    .allowsHitTesting(false)
            }

            VStack(spacing: 1) {
                Text(part.reference ?? "U\(partID)")
                    .fontWeight(.semibold)
                if !isPinHeader && !isXORGate { Text(valueLabel) }
                if let oscillator = part.component as? CXO_DIP8 {
                    Text(bench.clockFrequency(for: partID, source: oscillator).label)
                }
            }
            .font(.system(size: 10, design: .monospaced))
            .foregroundStyle(usesMAN74AFace ? Color(white: 0.85) : labelInk)
            .position(labelPosition)
            .allowsHitTesting(false)

            ForEach(symbol.terminals) { pin in
                terminal(pin)
            }
        }
        .frame(width: geometry.size.width, height: geometry.size.height)
    }

    private func displayReading(_ pin: Int) -> LogicState {
        bench.readings[WorkbenchTerminal(partID: partID, pinNumber: pin)] ?? .highImpedance
    }

    private func drawMAN74AFace(_ display: SevenSegmentDisplay, in context: GraphicsContext) {
        let face = symbol.body
        func position(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            point(CGPoint(x: face.minX + x * face.width, y: face.minY + y * face.height))
        }
        func color(_ pin: Int) -> Color {
            display.isLit(pin, reading: displayReading)
                ? Color(red: 1, green: 0.23, blue: 0.11)
                : Color(red: 0.32, green: 0.22, blue: 0.21)
        }

        let outline = symbolOutline()
        context.fill(outline, with: .color(Color(white: 0.20)))
        context.stroke(outline, with: .color(Color(white: 0.10)), lineWidth: 1)

        // Slanted bars follow the front-face reference in A–G order.
        let segments: [[(CGFloat, CGFloat)]] = [
            [(0.43, 0.29), (0.71, 0.29), (0.69, 0.34), (0.41, 0.34)],
            [(0.73, 0.30), (0.83, 0.30), (0.76, 0.49), (0.66, 0.49)],
            [(0.66, 0.51), (0.76, 0.51), (0.69, 0.70), (0.59, 0.70)],
            [(0.31, 0.66), (0.58, 0.66), (0.56, 0.71), (0.29, 0.71)],
            [(0.23, 0.51), (0.33, 0.51), (0.26, 0.70), (0.16, 0.70)],
            [(0.30, 0.30), (0.40, 0.30), (0.33, 0.49), (0.23, 0.49)],
            [(0.37, 0.475), (0.64, 0.475), (0.62, 0.525), (0.35, 0.525)]
        ]
        for (pin, corners) in zip(display.segmentNumbers, segments) {
            let segment = Path { path in
                path.addLines(corners.map { position($0.0, $0.1) })
                path.closeSubpath()
            }
            context.fill(segment, with: .color(color(pin)))
        }

        let dot = position(0.82, 0.71)
        let radius = bodySize.width * 0.06
        let dotPath = Path(ellipseIn: CGRect(x: dot.x - radius, y: dot.y - radius,
                                            width: 2 * radius, height: 2 * radius))
        context.fill(dotPath, with: .color(color(display.segmentNumbers[7])))
    }

    private func symbolOutline() -> Path {
        if isDiode { return Path() }
        if symbol.isCircular {
            return Path(ellipseIn: CGRect(origin: point(symbol.body.origin), size: bodySize))
        }

        if !symbol.polygon.isEmpty {
            var path = Path()
            path.addLines(symbol.polygon.map(point))
            path.closeSubpath()
            return path
        }

        guard let gate = symbol.gateOutline else {
            return Path(CGRect(origin: point(symbol.body.origin), size: bodySize))
        }

        var path = Path()
        path.addLines(gate.points.map(point))
        let start = point(gate.start)
        let end = point(gate.end)
        let middle = point(gate.middle)
        let controlX = start.x + (middle.x - start.x) * 4 / 3
        path.addCurve(to: start, control1: CGPoint(x: controlX, y: end.y),
                      control2: CGPoint(x: controlX, y: start.y))
        path.closeSubpath()
        return path
    }

    private func terminal(_ pin: KiCadSymbol.Terminal) -> some View {
        let endpoint = geometry.endpoint(pin)
        let inner = point(pin.bodyEnd)
        let terminal = WorkbenchTerminal(partID: partID, pinNumber: pin.id)

        let schematicDisplay = display != nil && bench.componentAppearance == .schematic
        let labelInset: CGFloat
        if schematicDisplay && pin.inward.dx > 0 {
            labelInset = pin.name == "DP" || pin.name == "D.P." ? 22 : 14
        } else {
            labelInset = usesMAN74AFace ? 10 : (pin.style.hasSuffix("clock") ? 19 : 13)
        }

        return ZStack {
            Text(isDiscrete ? "" : schematicDisplay && pin.name == "DP" ? "D.P." : pin.name)
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(usesMAN74AFace ? Color(white: 0.85) : labelInk)
                .allowsHitTesting(false)
                .position(x: inner.x + pin.inward.dx * labelInset,
                          y: inner.y + pin.inward.dy * 9)
                .accessibilityHidden(true)

            Text(resistor == nil && capacitor == nil ? pin.id.formatted() : "")
                .font(.system(size: 8, design: .monospaced))
                .foregroundStyle(outline)
                .allowsHitTesting(false)
                .rotationEffect(.degrees(isPinHeader ? -90 : 0))
                .position(x: (endpoint.x + inner.x) / 2 + (isPinHeader ? -7 : pin.inward.dx == 0 ? 10 : 0),
                          y: (endpoint.y + inner.y) / 2 - (pin.inward.dy == 0 ? 7 : 0))
                .accessibilityHidden(true)

            SchematicPinButton(terminal: terminal, bench: bench,
                               spacing: schematicPinSpacing(at: endpoint, among: symbol.terminals.map(geometry.endpoint)))
                .position(endpoint)
        }
    }

    private func point(_ position: CGPoint) -> CGPoint {
        geometry.point(position)
    }

    private func draw(_ pin: KiCadSymbol.Terminal, in context: GraphicsContext) {
        let inner = point(pin.bodyEnd)
        let bubbles = pin.style.hasPrefix("inverted")
        let radius: CGFloat = 3
        let inward = pin.inward
        var path = Path()
        let endpoint = geometry.endpoint(pin)
        let terminal = WorkbenchTerminal(partID: partID, pinNumber: pin.id)
        path.addLines(schematicPinLead(from: endpoint, toward: point(pin.position),
                                      trim: bench.showsOpenPinMarker(terminal) ? 2.5 : 0,
                                      inward: inward))
        path.addLine(to: CGPoint(x: inner.x - (bubbles ? 2 * radius * inward.dx : 0),
                                 y: inner.y - (bubbles ? 2 * radius * inward.dy : 0)))
        if bubbles {
            let center = CGPoint(x: inner.x - radius * inward.dx, y: inner.y - radius * inward.dy)
            path.addEllipse(in: CGRect(x: center.x - radius, y: center.y - radius,
                                       width: radius * 2, height: radius * 2))
        }
        if pin.style.hasSuffix("clock") {
            path.move(to: CGPoint(x: inner.x, y: inner.y - 4))
            path.addLine(to: CGPoint(x: inner.x + 7 * inward.dx, y: inner.y))
            path.addLine(to: CGPoint(x: inner.x, y: inner.y + 4))
        }
        if isSelected {
            context.stroke(path, with: .color(.cyan.opacity(0.35)), lineWidth: 4)
        }
        context.stroke(path, with: .color(outline), lineWidth: 1)
        if isPinHeader {
            let contact = CGRect(x: inner.x - 1.5, y: inner.y - 3, width: 3, height: 6)
            context.fill(Path(contact), with: .color(isSelected ? .schematicSelectionInk : outline))
        }
    }

}

func drawSevenSegmentFace(_ display: SevenSegmentDisplay, in context: GraphicsContext,
                             point: (CGPoint) -> CGPoint, state: (Int) -> LogicState) {
    // Place the face in the free space beside the KiCad pin labels.
    // All artwork uses symbol coordinates so imported flips and workbench zoom apply together.
    let face = CGRect(x: -1.95, y: -12.35, width: 6.65, height: 11.4)
    func position(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
        point(CGPoint(x: face.minX + x * face.width, y: face.minY + y * face.height))
    }

    let facePath = Path { path in
        path.addLines([position(0, 0), position(1, 0), position(1, 1), position(0, 1)])
        path.closeSubpath()
    }
    context.fill(facePath, with: .color(Color(red: 0.14, green: 0.14, blue: 0.15)))
    context.stroke(facePath, with: .color(Color(white: 0.30)), lineWidth: 1)

    let left: CGFloat = display.commonAnode ? 0.34 : 0.17
    let right = left + 0.49
    let upper: CGFloat = 0.17
    let middle: CGFloat = 0.49
    let lower: CGFloat = 0.81
    let segments = [
        (left, upper, right, upper),
        (right, upper, right, middle),
        (right, middle, right, lower),
        (left, lower, right, lower),
        (left, middle, left, lower),
        (left, upper, left, middle),
        (left, middle, right, middle)
    ]

    func color(for pin: Int) -> Color {
        display.isLit(pin, reading: state)
            ? Color(red: 1, green: 0.13, blue: 0.16)
            : Color(red: 0.32, green: 0.20, blue: 0.22)
    }

    for (pin, segment) in zip(display.segmentNumbers, segments) {
        let (x1, y1, x2, y2) = segment
        let horizontal = y1 == y2
        let tipX: CGFloat = horizontal ? 0.047 : 0
        let tipY: CGFloat = horizontal ? 0 : 0.027
        let halfWidth: CGFloat = horizontal ? 0 : 0.061
        let halfHeight: CGFloat = horizontal ? 0.036 : 0
        let path = Path { path in
            path.addLines([
                position(x1 + tipX, y1 + tipY),
                position(x1 + 2 * tipX + halfWidth, y1 + 2 * tipY + halfHeight),
                position(x2 - 2 * tipX + halfWidth, y2 - 2 * tipY + halfHeight),
                position(x2 - tipX, y2 - tipY),
                position(x2 - 2 * tipX - halfWidth, y2 - 2 * tipY - halfHeight),
                position(x1 + 2 * tipX - halfWidth, y1 + 2 * tipY - halfHeight)
            ])
            path.closeSubpath()
        }
        context.fill(path, with: .color(color(for: pin)))
    }

    let dot = position(display.commonAnode ? 0.15 : 0.85, lower)
    let edge = position(1, 0)
    let origin = position(0, 0)
    let radius = hypot(edge.x - origin.x, edge.y - origin.y) * 0.056
    context.fill(Path(ellipseIn: CGRect(x: dot.x - radius, y: dot.y - radius,
                                       width: 2 * radius, height: 2 * radius)),
                 with: .color(color(for: display.segmentNumbers[7])))
}

func drawSevenSegmentSchematic(_ display: SevenSegmentDisplay, body: CGRect, in context: GraphicsContext,
                               point: (CGPoint) -> CGPoint, state: (Int) -> LogicState) {
    let centerX = body.midX + (display.commonAnode ? 1.6 : 0.25)
    let top = body.minY + 1.2
    func position(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
        point(CGPoint(x: centerX + x, y: top + y))
    }

    let segments: [(start: CGPoint, end: CGPoint, label: CGPoint)] = [
        (.init(x: -0.8, y: 0), .init(x: 1.2, y: 0), .init(x: 0.2, y: 0.8)),
        (.init(x: 1.7, y: 0.5), .init(x: 1.4, y: 2.6), .init(x: 2.5, y: 1.5)),
        (.init(x: 1.4, y: 3.6), .init(x: 1.1, y: 5.7), .init(x: 2.2, y: 4.6)),
        (.init(x: -1.4, y: 6.2), .init(x: 0.6, y: 6.2), .init(x: -0.4, y: 5.4)),
        (.init(x: -1.7, y: 3.6), .init(x: -2, y: 5.7), .init(x: -2.8, y: 4.6)),
        (.init(x: -1.3, y: 0.5), .init(x: -1.6, y: 2.6), .init(x: -2.4, y: 1.5)),
        (.init(x: -1, y: 3.1), .init(x: 0.9, y: 3.1), .init(x: 0, y: 2.3))
    ]
    let ink = Color(red: 0.52, green: 0.06, blue: 0)
    let scale = abs(point(CGPoint(x: 1, y: 0)).x - point(.zero).x)
    func color(for pin: Int) -> Color {
        display.isLit(pin, reading: state) ? .red : ink
    }
    func label(_ text: String, at location: CGPoint) {
        context.draw(Text(text).font(.system(size: scale * 0.75, weight: .medium, design: .monospaced))
            .foregroundStyle(ink), at: location)
    }
    for (pin, segment) in zip(display.segmentNumbers, segments) {
        let path = Path { path in
            path.addLines([position(segment.start.x, segment.start.y), position(segment.end.x, segment.end.y)])
        }
        context.stroke(path, with: .color(color(for: pin)),
                       style: StrokeStyle(lineWidth: scale * 0.48, lineCap: .round))
        label(display.pins[pin]!.name, at: position(segment.label.x, segment.label.y))
    }

    let dotX: CGFloat = display.commonAnode ? -2.9 : 2.55
    let dot = position(dotX, 6.2)
    let radius = scale * 0.22
    context.fill(Path(ellipseIn: CGRect(x: dot.x - radius, y: dot.y - radius,
                                       width: 2 * radius, height: 2 * radius)),
                 with: .color(color(for: display.segmentNumbers[7])))
    label("DP", at: position(dotX + (display.commonAnode ? -0.55 : 0.95), 7.05))
}
