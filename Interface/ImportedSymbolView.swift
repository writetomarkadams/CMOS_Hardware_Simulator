import SwiftUI

struct ImportedSymbolView: View {
    let drawing: ImportedSymbol
    let part: WorkbenchPart
    let bench: Workbench
    let isSelected: Bool
    let select: () -> Void
    let rotate: (Int) -> Void
    let editResistance: () -> Void
    let editCapacitance: () -> Void
    var editProperties: (() -> Void)? = nil

    private let ink = Color(red: 0.65, green: 0, blue: 0)
    private let textInk = Color(red: 0, green: 0.35, blue: 0.36)
    private var rotation: Double { Double(bench.rotations[part.id, default: 0] * 90) }
    private var bounds: CGRect { drawing.bounds }

    private func point(_ local: CGPoint) -> CGPoint {
        let offset = drawing.localReflection(CGPoint(x: local.x * drawing.drawingScale,
                                                       y: local.y * drawing.drawingScale), turns: turns)
        return viewPoint(offset)
    }

    private var turns: Int { bench.rotations[part.id, default: 0] }

    private func viewPoint(_ offset: CGPoint) -> CGPoint {
        CGPoint(x: offset.x - bounds.minX, y: offset.y - bounds.minY)
    }

    private func endpoint(_ pin: ImportedSymbol.Pin) -> CGPoint {
        viewPoint(drawing.pinOffset(pin, turns: turns))
    }

    private var value: String {
        if let resistor = part.component as? Resistor {
            return "\(resistor.value.formatted()) \(resistor.unit.rawValue)"
        }
        if let capacitor = part.component as? Capacitor {
            return "\(capacitor.value.formatted()) \(capacitor.kind.unit)"
        }
        if let transistor = part.component as? Transistor { return transistor.designation.rawValue }
        return drawing.value
    }

    private var axialPins: (first: CGPoint, second: CGPoint)? {
        guard let firstPin = drawing.pins.first(where: { $0.id == 1 }),
              let secondPin = drawing.pins.first(where: { $0.id == 2 }) else { return nil }
        let first = endpoint(firstPin)
        let second = endpoint(secondPin)
        return first == second ? nil : (first, second)
    }

    private var schematicDisplay: SevenSegmentDisplay? {
        bench.componentAppearance == .schematic ? part.component as? SevenSegmentDisplay : nil
    }

    private var displayBody: CGRect? {
        guard schematicDisplay != nil,
              let background = drawing.graphics.first(where: { $0.fill == "background" }) else { return nil }
        return background.points.reduce(CGRect.null) { $0.union(CGRect(origin: $1, size: .zero)) }
    }

    var body: some View {
        let contact = part.component as? MechanicalSwitch
        let actuated = contact.map { $0.isPressed || $0.selectsThrow3 } ?? false
        let artwork = AxialArtwork(part: part, appearance: bench.componentAppearance)
        let axialPins = artwork == nil ? nil : self.axialPins
        ZStack(alignment: .topLeading) {
            Canvas { context, _ in
                if let artwork, let axialPins {
                    artwork.draw(in: context, first: axialPins.first, second: axialPins.second,
                                 bench: bench, partID: part.id, isSelected: isSelected,
                                 noConnectPins: drawing.noConnectPins)
                }
                if let contact {
                    drawMechanicalSwitch(contact.designation, actuated: actuated, physical: bench.componentAppearance == .physicalDIP,
                                         point: point, ink: isSelected ? .schematicSelectionInk : ink, in: context)
                }
                for graphic in drawing.graphics
                where contact == nil && axialPins == nil && (displayBody == nil || graphic.fill == "background") {
                    let points = graphic.points.map(point)
                    let path = Path { path in
                        switch graphic.kind {
                        case .line: path.addLines(points)
                        case .circle: path.addEllipse(in: CGRect(origin: points[0], size: .zero)
                            .union(CGRect(origin: points[1], size: .zero)))
                        case .arc:
                            path.addLines(arc(through: points))
                        }
                    }
                    if graphic.fill == "background" {
                        context.fill(path, with: .color(isSelected ? .schematicSelectionFill : Color(red: 1, green: 1, blue: 0.76)))
                    } else if graphic.fill == "outline" {
                        context.fill(path, with: .color(ink))
                    }
                    if bench.illuminatedLEDs.contains(part.id) {
                        context.stroke(path, with: .color(.red.opacity(0.30)), lineWidth: 7)
                        context.stroke(path, with: .color(.red), lineWidth: 2)
                    } else {
                        context.stroke(path, with: .color(isSelected ? .schematicSelectionInk : ink), lineWidth: 1.2)
                    }
                }
                if let display = part.component as? SevenSegmentDisplay {
                    func reading(_ pin: Int) -> LogicState {
                        bench.readings[WorkbenchTerminal(partID: part.id, pinNumber: pin)] ?? .highImpedance
                    }
                    if bench.componentAppearance == .physicalDIP {
                        drawSevenSegmentFace(display, in: context, point: point, state: reading)
                    } else if let displayBody {
                        drawSevenSegmentSchematic(display, body: displayBody, in: context, point: point, state: reading)
                    }
                }
                for field in drawing.fields ?? [] {
                    if field.key == "Reference" && part.component is WorkbenchPower { continue }
                    if axialPins != nil, case .diode? = artwork, field.key == "Value" { continue }
                    let offset = CGPoint(x: field.offset.x * drawing.drawingScale - bounds.minX,
                                         y: field.offset.y * drawing.drawingScale - bounds.minY)
                    let text = field.key == "Reference" ? part.reference ?? part.name : value
                    var labelContext = context
                    labelContext.translateBy(x: offset.x, y: offset.y)
                    labelContext.rotate(by: .degrees(field.angle))
                    let anchor: UnitPoint = field.justify == "left" ? .leading : field.justify == "right" ? .trailing : .center
                    labelContext.draw(Text(text).font(.system(size: field.size * drawing.drawingScale, design: .monospaced))
                        .foregroundStyle(textInk), at: .zero, anchor: anchor)
                }
                for pin in drawing.pins where part.pins[pin.id] != nil {
                    let start = endpoint(pin)
                    let end = point(pin.end)
                    let original = point(pin.position)
                    let length = hypot(end.x - original.x, end.y - original.y)
                    let dx = length > 0 ? (end.x - original.x) / length : 0
                    let dy = length > 0 ? (end.y - original.y) / length : 0
                    let terminal = WorkbenchTerminal(partID: part.id, pinNumber: pin.id)
                    let noConnect = drawing.noConnectPins.contains(pin.id) && !bench.isTerminalConnected(terminal)
                    if axialPins != nil {
                        if noConnect {
                            context.stroke(schematicCross(at: start), with: .color(.blue), lineWidth: 1.3)
                        }
                        continue
                    }
                    let inverted = pin.style.hasPrefix("inverted")
                    let lineEnd = CGPoint(x: end.x - (inverted ? 6 * dx : 0), y: end.y - (inverted ? 6 * dy : 0))
                    var path = Path()
                    if length > 0 {
                        path.addLines(schematicPinLead(from: start, toward: original,
                                                      trim: bench.showsOpenPinMarker(terminal, explicitNoConnect: noConnect) ? 2.5 : 0,
                                                      inward: CGVector(dx: dx, dy: dy)))
                        path.addLine(to: lineEnd)
                    }
                    if inverted {
                        path.addEllipse(in: CGRect(x: end.x - 3 * dx - 3, y: end.y - 3 * dy - 3, width: 6, height: 6))
                    }
                    if pin.style.hasSuffix("clock") {
                        path.addLines([CGPoint(x: end.x - 4 * dy, y: end.y + 4 * dx),
                                       CGPoint(x: end.x + 6 * dx, y: end.y + 6 * dy),
                                       CGPoint(x: end.x + 4 * dy, y: end.y - 4 * dx)])
                    }
                    context.stroke(path, with: .color(ink), lineWidth: 1)
                    if noConnect {
                        context.stroke(schematicCross(at: start), with: .color(.blue), lineWidth: 1.3)
                    }
                }
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)

            let graphicBounds = drawing.graphics.flatMap(\.points).map(point).reduce(CGRect.null) {
                $0.union(CGRect(origin: $1, size: .zero))
            }
            let target = graphicBounds.isNull ? CGRect(x: bounds.midX + bounds.width / 2 - 10,
                                                        y: bounds.midY + bounds.height / 2 - 10,
                                                        width: 20, height: 20) : graphicBounds
            Group {
                if let contact {
                    SwitchActuator(part: part, contact: contact, bench: bench, select: select, rotate: rotate,
                                   size: CGSize(width: max(24, target.width), height: max(24, target.height)))
                } else {
                    Rectangle().fill(.clear)
                        .frame(width: max(14, target.width), height: max(14, target.height))
                        .contentShape(Rectangle())
                        .onTapGesture(perform: select)
                        .help("\(part.reference ?? part.name) · \(value)")
                        .accessibilityLabel("\(part.reference ?? part.name) · \(value)")
                        .contextMenu {
                            PartRotationCommands(rotate: rotate)
                            if part.component is Resistor { Button("Set Resistance…", action: editResistance) }
                            if part.component is Capacitor { Button("Set Capacitance…", action: editCapacitance) }
                            if let editProperties { Button("Properties…", action: editProperties) }
                            Button("Remove Part", role: .destructive) { bench.removePart(part.id) }
                        }
                }
            }
                .transformAnchorPreference(key: CanvasBounds.self, value: .bounds) { anchors, anchor in
                    anchors[.part(part.id)] = anchor
                }
                .position(x: target.midX, y: target.midY)

            let power = part.component is WorkbenchPower
            let discrete = part.component is Resistor || part.component is Capacitor
            if let warning = bench.powerStates[part.id]?.warning ?? bench.timingIssues[part.id] {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .help(warning)
                    .accessibilityLabel(warning)
                    .rotationEffect(.degrees(-rotation))
                    .position(x: target.maxX + 8, y: target.minY)
            }
            ForEach(drawing.pins.filter { part.pins[$0.id] != nil }) { pin in
                terminal(pin, showLabel: !power && !discrete && axialPins == nil)
            }
        }
        .frame(width: bounds.width, height: bounds.height)
    }

    private func terminal(_ pin: ImportedSymbol.Pin, showLabel: Bool) -> some View {
        let terminal = WorkbenchTerminal(partID: part.id, pinNumber: pin.id)
        let start = endpoint(pin)
        let end = point(pin.end)
        return ZStack {
            if showLabel {
                Text(String(pin.id))
                    .font(.system(size: 7, design: .monospaced))
                    .foregroundStyle(ink)
                    .rotationEffect(.degrees(-rotation))
                    .position(x: (start.x + end.x) / 2 + (start.x == end.x ? 7 : 0),
                              y: (start.y + end.y) / 2 - (start.y == end.y ? 6 : 0))
                    .allowsHitTesting(false)
            }
            if let name = schematicDisplay?.pins[pin.id]?.name {
                let lead = point(pin.position)
                let length = hypot(end.x - lead.x, end.y - lead.y)
                if length > 0 {
                    let fontSize = drawing.drawingScale * 1.4
                    let label = name == "DP" ? "D.P." : name
                    let inset = 7 + CGFloat(label.count) * fontSize * 0.3
                    Text(label)
                        .font(.system(size: fontSize, design: .monospaced))
                        .foregroundStyle(textInk)
                        .position(x: end.x + (end.x - lead.x) / length * inset,
                                  y: end.y + (end.y - lead.y) / length * 10)
                        .allowsHitTesting(false)
                }
            }
            SchematicPinButton(terminal: terminal, bench: bench,
                               spacing: schematicPinSpacing(at: start, among: drawing.pins.map(endpoint)))
                .position(start)
        }
    }

    private func arc(through points: [CGPoint]) -> [CGPoint] {
        let a = points[0], m = points[1], b = points[2]
        let dx = m.x - a.x, dy = m.y - a.y
        let ex = b.x - a.x, ey = b.y - a.y
        let determinant = 2 * (dx * ey - dy * ex)
        guard abs(determinant) > 0.0001 else { return points }
        let d = dx * dx + dy * dy, e = ex * ex + ey * ey
        let center = CGPoint(x: a.x + (d * ey - e * dy) / determinant,
                             y: a.y + (dx * e - ex * d) / determinant)
        let start = atan2(a.y - center.y, a.x - center.x)
        let radius = hypot(a.x - center.x, a.y - center.y)
        func sweep(to point: CGPoint) -> CGFloat {
            let angle = atan2(point.y - center.y, point.x - center.x) - start
            return angle < 0 ? angle + 2 * .pi : angle
        }
        let end = sweep(to: b)
        let sweep = sweep(to: m) <= end ? end : end - 2 * .pi
        return (0...32).map {
            let angle = start + sweep * CGFloat($0) / 32
            return CGPoint(x: center.x + radius * cos(angle), y: center.y + radius * sin(angle))
        }
    }
}

func schematicCross(at point: CGPoint) -> Path {
    Path { path in
        path.addLines([CGPoint(x: point.x - 4, y: point.y - 4), CGPoint(x: point.x + 4, y: point.y + 4)])
        path.move(to: CGPoint(x: point.x - 4, y: point.y + 4))
        path.addLine(to: CGPoint(x: point.x + 4, y: point.y - 4))
    }
}

func schematicJunction(at point: CGPoint) -> Path {
    Path(ellipseIn: CGRect(x: point.x - 3.5, y: point.y - 3.5, width: 7, height: 7))
}
