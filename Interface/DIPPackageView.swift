import SwiftUI

enum ComponentAppearance: String, CaseIterable {
    case schematic = "Schematic"
    case physicalDIP = "Physical DIP"

    var defaultWireColour: WireColour { self == .schematic ? .green : .black }
}

struct DIPPackage {
    let size: CGSize
    let pins: [Pin]
    let endpoints: [Int: CGPoint]
    let body: CGRect
    let usesCD4070Artwork: Bool
    let analogSwitchKind: AnalogSwitchKind?
    let displayDriverKind: SevenSegmentDriverKind?
    let isCD4518: Bool

    init?(part: WorkbenchPart) {
        // An imported drawing or an individual schematic unit does not own a
        // complete package at this placement. Keep its existing geometry.
        guard part.importedSymbol == nil, part.unitPlacement == nil else { return nil }
        analogSwitchKind = (part.component as? AnalogSwitch)?.kind
        displayDriverKind = (part.component as? SevenSegmentDriver)?.kind
        isCD4518 = (part.component as? DualCounter)?.kind == .bcd
        let count: Int
        switch part.component {
        case is CD4011, is CD4070, is CD4081, is CD40106: count = 14
        case is CD4017, is CD4026, is CD4027, is CD4029, is CD4060, is CD4510, is CD4516: count = 16
        case is DualCounter where isCD4518: count = 16
        case is AnalogSwitch: count = 16
        case is SevenSegmentDriver: count = 16
        case is NE555: count = 8
        default: return nil
        }
        let pins = part.pins
        guard pins.count == count,
              (1...count).allSatisfy({ pins[$0]?.number == $0 }) else { return nil }

        let rows = count / 2
        let step = WorkbenchWire.gridSpacing
        usesCD4070Artwork = part.component is CD4011 || part.component is CD4070 || part.component is CD4081
            || part.component is CD40106 || count == 16
        size = CGSize(width: 18 * step, height: CGFloat(2 * rows + 6) * step)
        let rightEndpoint = size.width - 2 * step
        body = CGRect(x: 40, y: 16, width: 100, height: size.height - 24)
        self.pins = pins.values.sorted { $0.number < $1.number }
        endpoints = Dictionary(uniqueKeysWithValues: (1...count).map { number in
            let left = number <= rows
            let row = left ? number - 1 : count - number
            return (number, CGPoint(x: left ? 2 * step : rightEndpoint, y: CGFloat(5 + 2 * row) * step))
        })
    }

    func isLeft(_ number: Int) -> Bool { number <= pins.count / 2 }
}

struct DIPPackageView: View {
    let package: DIPPackage
    let part: WorkbenchPart
    let bench: Workbench
    let isSelected: Bool
    let select: () -> Void
    let rotate: (Int) -> Void

    var body: some View {
        ZStack(alignment: .topLeading) {
            Canvas { context, _ in drawPackage(in: context) }
                .frame(width: package.size.width, height: package.size.height)
                .allowsHitTesting(false)
                .accessibilityHidden(true)

            Color.clear
                .frame(width: package.body.width, height: package.body.height)
                .contentShape(Rectangle())
                .onTapGesture(perform: select)
                .contextMenu {
                    PartRotationCommands(rotate: rotate)
                    Button("Remove Part", role: .destructive) { bench.removePart(part.id) }
                }
                .position(x: package.body.midX, y: package.body.midY)
                .accessibilityLabel(part.label)

            ForEach(package.pins) { pin in
                SchematicPinButton(terminal: WorkbenchTerminal(partID: part.id, pinNumber: pin.number), bench: bench)
                    .position(package.endpoints[pin.number]!)
            }
        }
        .frame(width: package.size.width, height: package.size.height)
    }

    private func drawPackage(in context: GraphicsContext) {
        let body = package.body
        let usesCD4070Artwork = package.usesCD4070Artwork
        let isCD4510 = part.component is CD4510
        let isCD4516 = part.component is CD4516
        let isNE555 = part.component is NE555
        let usesCompactTabs = isCD4516 || package.isCD4518 || package.displayDriverKind == .cd4543 || isNE555
        let isCD4029 = part.component is CD4029
        let isCD4017 = part.component is CD4017
        let usesDIP16Artwork = package.pins.count == 16
        let outline = Path { path in
            let radius: CGFloat = usesCD4070Artwork ? 8 : 5
            let notch: CGFloat = usesCD4070Artwork ? 10 : 8
            path.move(to: CGPoint(x: body.minX + radius, y: body.minY))
            path.addLine(to: CGPoint(x: body.midX - notch, y: body.minY))
            path.addRelativeArc(center: CGPoint(x: body.midX, y: body.minY),
                                radius: notch, startAngle: .degrees(180), delta: .degrees(-180))
            path.addLine(to: CGPoint(x: body.maxX - radius, y: body.minY))
            path.addQuadCurve(to: CGPoint(x: body.maxX, y: body.minY + radius),
                              control: CGPoint(x: body.maxX, y: body.minY))
            path.addLine(to: CGPoint(x: body.maxX, y: body.maxY - radius))
            path.addQuadCurve(to: CGPoint(x: body.maxX - radius, y: body.maxY),
                              control: CGPoint(x: body.maxX, y: body.maxY))
            path.addLine(to: CGPoint(x: body.minX + radius, y: body.maxY))
            path.addQuadCurve(to: CGPoint(x: body.minX, y: body.maxY - radius),
                              control: CGPoint(x: body.minX, y: body.maxY))
            path.addLine(to: CGPoint(x: body.minX, y: body.minY + radius))
            path.addQuadCurve(to: CGPoint(x: body.minX + radius, y: body.minY),
                              control: CGPoint(x: body.minX, y: body.minY))
            path.closeSubpath()
        }
        if isSelected {
            context.stroke(outline, with: .color(.accentColor), lineWidth: 7)
        }
        let cream = usesDIP16Artwork ? Color(red: 1, green: 0.96, blue: 0.86)
                            : usesCD4070Artwork ? Color(red: 1, green: 0.98, blue: 0.91)
                            : Color(red: 1, green: 0.97, blue: 0.86)
        context.fill(outline, with: .color(cream))
        context.stroke(outline, with: .color(.black),
                       style: StrokeStyle(lineWidth: usesCD4070Artwork ? 3.5 : 3, lineJoin: .round))
        context.fill(Path(ellipseIn: CGRect(x: body.minX + (usesCD4070Artwork ? 9 : 5), y: body.minY + (usesCD4070Artwork ? 8 : 5), width: 8, height: 8)),
                     with: .color(.black))
        let marking = package.analogSwitchKind?.rawValue ?? package.displayDriverKind?.rawValue
                    ?? (part.component is CD4011 ? "CD4011"
                    : part.component is CD4070 ? "CD4070" : part.component is CD40106 ? "CD40106"
                    : part.component is CD4026 ? "CD4026"
                    : part.component is CD4027 ? "CD4027"
                    : part.component is CD4060 ? "CD4060"
                    : part.component is CD4081 ? "CD4081"
                    : isCD4029 ? "CD4029"
                    : package.isCD4518 ? DualCounterKind.bcd.rawValue
                    : isNE555 ? "NE555"
                    : isCD4017 ? "CD4017" : isCD4510 ? "CD4510" : isCD4516 ? "CD4516" : part.name)
        context.draw(Text(marking).font(.system(size: isCD4510 || usesCompactTabs ? 12 : 11, weight: .bold)).foregroundStyle(Color.black),
                     at: CGPoint(x: body.midX, y: body.minY + (usesCD4070Artwork ? 21 : 19)))

        for pin in package.pins {
            let point = package.endpoints[pin.number]!
            let left = package.isLeft(pin.number)
            let edge = left ? body.minX : body.maxX
            let tabHeight: CGFloat = usesCompactTabs ? 12 : (usesDIP16Artwork ? 16 : 15)
            let tab = CGRect(x: left ? point.x : edge, y: point.y - tabHeight / 2,
                             width: abs(edge - point.x), height: tabHeight)
            let colour: Color = switch pin.direction {
            case .input: Color(red: 0.68, green: 0.92, blue: 0.48)
            case .output: Color(red: 0.59, green: 0.84, blue: 0.96)
            case .power: Color(red: 1, green: 0.45, blue: 0.38)
            case .bidirectional: .purple
            }
            let face = Path(roundedRect: tab, cornerRadius: 3)
            context.fill(face, with: .color(colour))
            context.stroke(face, with: .color(.black), lineWidth: 1.8)
            if usesDIP16Artwork || !usesCD4070Artwork {
                let lead = Path { path in
                    path.move(to: CGPoint(x: edge, y: point.y))
                    path.addLine(to: CGPoint(x: edge + (left ? 4 : -4), y: point.y))
                }
                context.stroke(lead, with: .color(.black), style: StrokeStyle(lineWidth: 1.8, lineCap: .round))
            }
            context.draw(Text(String(pin.number)).font(.system(size: usesCompactTabs ? 9 : 11, weight: .bold)).foregroundStyle(Color.black),
                         at: CGPoint(x: tab.midX, y: point.y))
            let labelPoint = CGPoint(x: edge + (left ? 9 : -9), y: point.y)
            let label = context.resolve(pinLabel(pin).foregroundStyle(Color.black))
            context.draw(label, at: labelPoint, anchor: left ? .leading : .trailing)
            let hasOverbar = ((isCD4510 || isCD4516 || isCD4029) && [5, 7].contains(pin.number))
                || (package.displayDriverKind == .cd4511 && [3, 4].contains(pin.number))
            if hasOverbar {
                let width = label.measure(in: package.size).width
                let bar = Path { path in
                    path.move(to: CGPoint(x: labelPoint.x, y: labelPoint.y - 6))
                    path.addLine(to: CGPoint(x: labelPoint.x + width, y: labelPoint.y - 6))
                }
                context.stroke(bar, with: .color(.black), lineWidth: 1)
            }
        }
    }

    private func pinLabel(_ pin: Pin) -> Text {
        let font = Font.system(size: 10, weight: .bold)
        if part.component is NE555 {
            switch pin.number {
            case 5: return Text("CV").font(font)
            case 6: return Text("THRESH").font(font)
            default: return Text(pin.name).font(font)
            }
        }
        if let kind = package.analogSwitchKind {
            let name = kind == .cd4051 && pin.direction == .bidirectional && pin.number != 3
                ? "CH" + pin.name : pin.name
            return Text(name).font(font)
        }
        if part.component is CD4027, pin.direction != .power {
            // The datasheet numbers the low-pin bank as channel 2.
            return subscriptedLabel(pin.name, suffix: package.isLeft(pin.number) ? "2" : "1", font: font)
        }
        if part.component is CD4017, pin.number == 13 {
            return Text("CLK INH").font(font)
        }
        if part.component is CD4026 {
            switch pin.number {
            case 2: return Text("CLK INH").font(font)
            case 3: return Text("DE IN").font(font)
            case 4: return Text("DE OUT").font(font)
            case 14: return Text("c UNG.").font(font)
            default: return Text(pin.name).font(font)
            }
        }
        if part.component is CD4060 {
            switch pin.number {
            case 9: return subscriptedLabel("C", suffix: "EXT", font: font)
            case 10: return subscriptedLabel("R", suffix: "EXT", font: font)
            default: break
            }
        }
        if part.component is CD4029 {
            switch pin.number {
            case 3, 4, 12, 13:
                return subscriptedLabel("JAM", suffix: String(pin.name.suffix(1)), font: font)
            case 5: return subscriptedLabel("C", suffix: "IN", font: font)
            case 7: return subscriptedLabel("C", suffix: "OUT", font: font)
            case 9: return Text("B/D").font(font)
            case 10: return Text("U/D").font(font)
            default: break
            }
        }
        if part.component is CD40106, pin.number == 7 {
            return Text("GND").font(font)
        }
        if package.isCD4518 {
            switch pin.number {
            case 2: return Text("EN A").font(font)
            case 7: return Text("RST A").font(font)
            case 10: return Text("EN B").font(font)
            case 15: return Text("RST B").font(font)
            case 3...6: return Text(pin.name + "A").font(font)
            case 11...14: return Text(pin.name + "B").font(font)
            default: return Text(pin.name).font(font)
            }
        }
        if part.component is CD4516 {
            // The datasheet labels preset and output bits starting at 1.
            let names = ["PE", "Q4", "P4", "P1", "CI", "Q1", "CO", "VSS",
                         "RST", "U/D", "Q2", "P2", "P3", "Q3", "CLK", "VDD"]
            return Text(names[pin.number - 1]).font(font)
        }
        if part.component is CD4510 {
            switch pin.number {
            case 1: return Text("PRESET").font(font)
            case 5: return subscriptedLabel("C", suffix: "IN", font: font)
            case 7: return subscriptedLabel("C", suffix: "OUT", font: font)
            case 8: return Text("GND").font(font)
            case 10: return Text("U/D").font(font)
            case 15: return Text("CLK").font(font)
            default: return Text(pin.name).font(font)
            }
        }
        if package.displayDriverKind == .cd4543, pin.number == 6 {
            return Text("PHASE").font(font)
        }
        if package.displayDriverKind == .cd4511, pin.number == 3 || pin.number == 4 {
            return Text(String(pin.name.prefix(while: { $0 != " " }))).font(font)
        }
        guard package.usesCD4070Artwork, pin.name.last?.isNumber == true else { return Text(pin.name).font(font) }
        return subscriptedLabel(String(pin.name.prefix(1)), suffix: String(pin.name.dropFirst()), font: font)
    }

    private func subscriptedLabel(_ name: String, suffix: String, font: Font) -> Text {
        let head = Text(name).font(font)
        let subscriptLabel = Text(suffix).font(.system(size: 7, weight: .bold)).baselineOffset(-2)
        return Text("\(head)\(subscriptLabel)")
    }
}
