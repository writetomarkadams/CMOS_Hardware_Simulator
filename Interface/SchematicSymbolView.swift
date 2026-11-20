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
    private var capacitor: Capacitor? { part.component as? Capacitor }

    private var resistor: Resistor? { part.component as? Resistor }
    private var display: SevenSegmentDisplay? { part.component as? SevenSegmentDisplay }
    private var isDiode: Bool { part.component is Diode1N4148 }
    private var isDiscrete: Bool { symbol.isCircular || resistor != nil || capacitor != nil || isDiode }

    private var valueLabel: String {
        if let capacitor { return "\(capacitor.value.formatted()) \(capacitor.kind.unit)" }
        if let resistor {
            return "\(resistor.value.formatted()) \(resistor.unit.rawValue)"
        }
        if part.component is NE555 || part.component is AnalogSwitch || CounterChip.kind(of: part.component) != nil || part.component is CD4060 || part.component is SevenSegmentDriver || display != nil {
            return part.name
        }
        return isDiscrete ? part.name : part.unitPlacement?.kind.rawValue ?? "4510"
    }

    private var labelPosition: CGPoint {
        if resistor != nil || capacitor != nil || symbol.isCircular {
            return CGPoint(x: bodyCenter.x + 42, y: bodyCenter.y)
        }
        if isDiode || display != nil || !symbol.polygon.isEmpty {
            return CGPoint(x: bodyCenter.x, y: point(symbol.body.origin).y + bodySize.height + 14)
        }
        return bodyCenter
    }

    private let scale: CGFloat = 6
    private var padding: CGFloat { symbol.polygon.isEmpty && !isDiode ? 18 : 28 }
    private let bodyFill = Color(red: 1, green: 1, blue: 0.76)
    private let outline = Color(red: 0.65, green: 0, blue: 0)
    private let labelInk = Color(red: 0, green: 0.35, blue: 0.36)

    private var bounds: CGRect {
        symbol.terminals.reduce(symbol.body) { rect, pin in
            rect.union(CGRect(origin: pin.position, size: .zero))
        }
    }

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
                if isSelected {
                    context.fill(outlinePath, with: .color(.schematicSelectionFill))
                    context.stroke(outlinePath, with: .color(.cyan.opacity(0.3)), lineWidth: 4)
                } else if !isDiscrete {
                    context.fill(outlinePath, with: .color(bodyFill))
                }
                if capacitor == nil { context.stroke(outlinePath, with: .color(outline), lineWidth: 1.2) }
                if let display {
                    drawSegments(of: display, in: context)
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
                    context.stroke(path, with: .color(isDiscrete ? outline : labelInk), lineWidth: 1)
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
                    Button("Remove Part", role: .destructive) { bench.removePart(partID) }
                }
                .position(bodyCenter)

            VStack(spacing: 1) {
                Text(part.reference ?? "U\(partID)")
                    .fontWeight(.semibold)
                Text(valueLabel)
            }
            .font(.system(size: 10, design: .monospaced))
            .foregroundStyle(labelInk)
            .position(labelPosition)
            .allowsHitTesting(false)

            ForEach(symbol.terminals) { pin in
                terminal(pin)
            }
        }
        .frame(width: bounds.width * scale + 2 * padding + (symbol.isCircular || resistor != nil || capacitor != nil ? 85 : 0),
               height: bounds.height * scale + 2 * padding)
    }

    private func drawSegments(of display: SevenSegmentDisplay, in context: GraphicsContext) {
        // MAN72A uses the same segment geometry shifted right, with a left decimal point.
        func segmentPoint(_ position: CGPoint) -> CGPoint {
            point(CGPoint(x: position.x + (display.commonAnode ? 1.778 : 0),
                          y: position.y - (display.commonAnode ? 0.254 : 0)))
        }
        let segments: [(CGPoint, CGPoint)] = [
            (CGPoint(x: -0.508, y: -11.43), CGPoint(x: 1.524, y: -11.43)),
            (CGPoint(x: 2.032, y: -10.922), CGPoint(x: 1.778, y: -8.89)),
            (CGPoint(x: 1.778, y: -7.874), CGPoint(x: 1.524, y: -5.842)),
            (CGPoint(x: -1.016, y: -5.334), CGPoint(x: 1.016, y: -5.334)),
            (CGPoint(x: -1.27, y: -7.874), CGPoint(x: -1.524, y: -5.842)),
            (CGPoint(x: -1.016, y: -10.922), CGPoint(x: -1.27, y: -8.89)),
            (CGPoint(x: -0.762, y: -8.382), CGPoint(x: 1.27, y: -8.382))
        ]
        func color(for number: Int) -> Color {
            let lit = display.isLit(number) {
                bench.readings[WorkbenchTerminal(partID: partID, pinNumber: $0)] ?? .highImpedance
            }
            return lit ? .red : outline.opacity(0.16)
        }
        for (number, segment) in zip(display.segmentNumbers, segments) {
            var path = Path()
            path.move(to: segmentPoint(segment.0))
            path.addLine(to: segmentPoint(segment.1))
            context.stroke(path, with: .color(color(for: number)), style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
        }
        let dot = point(display.commonAnode ? CGPoint(x: -0.762, y: -5.588) : CGPoint(x: 2.794, y: -5.334))
        context.fill(Path(ellipseIn: CGRect(x: dot.x - 1.5, y: dot.y - 1.5, width: 3, height: 3)),
                     with: .color(color(for: display.segmentNumbers[7])))
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
        let endpoint = point(pin.position)
        let inner = point(pin.bodyEnd)
        let terminal = WorkbenchTerminal(partID: partID, pinNumber: pin.id)
        let selected = bench.selectedTerminal == terminal
        let state = bench.readings[terminal] ?? .highImpedance
        let labelInset: CGFloat = pin.style.hasSuffix("clock") ? 19 : 13

        return ZStack {
            Text(isDiscrete ? "" : pin.name)
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(labelInk)
                .allowsHitTesting(false)
                .position(x: inner.x + pin.inward.dx * labelInset,
                          y: inner.y + pin.inward.dy * 9)
                .accessibilityHidden(true)

            Text(resistor == nil && capacitor == nil ? pin.id.formatted() : "")
                .font(.system(size: 8, design: .monospaced))
                .foregroundStyle(outline)
                .allowsHitTesting(false)
                .position(x: (endpoint.x + inner.x) / 2 + (pin.inward.dx == 0 ? 10 : 0),
                          y: (endpoint.y + inner.y) / 2 - (pin.inward.dy == 0 ? 7 : 0))
                .accessibilityHidden(true)

            Button {
                bench.select(terminal)
            } label: {
                Image(systemName: selected ? "circle.inset.filled" : "circle.fill")
                    .font(.system(size: selected ? 12 : 8))
                    .foregroundStyle(selected ? Color.accentColor : outline)
                    .frame(width: 15, height: 15)
                    .contentShape(Rectangle())
                    .anchorPreference(key: CanvasBounds.self, value: .bounds) { [.terminal(terminal): $0] }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(bench.label(for: terminal))
            .accessibilityValue(state.description)
            .accessibilityAddTraits(selected ? .isSelected : [])
            .help("\(bench.label(for: terminal)) · \(state.description)")
            .position(endpoint)
        }
    }

    private func point(_ position: CGPoint) -> CGPoint {
        CGPoint(x: (position.x - bounds.minX) * scale + padding,
                y: (position.y - bounds.minY) * scale + padding)
    }

    private func draw(_ pin: KiCadSymbol.Terminal, in context: GraphicsContext) {
        let inner = point(pin.bodyEnd)
        let bubbles = pin.style.hasPrefix("inverted")
        let radius: CGFloat = 3
        let inward = pin.inward
        var path = Path()
        path.move(to: point(pin.position))
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
    }

}
