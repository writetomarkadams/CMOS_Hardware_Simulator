import SwiftUI

struct MechanicalSwitchSymbol: View {
    let symbol: KiCadSymbol
    let part: WorkbenchPart
    let contact: MechanicalSwitch
    let bench: Workbench
    let isSelected: Bool
    let select: () -> Void
    let rotate: (Int) -> Void

    var body: some View {
        let geometry = SchematicSymbolGeometry(symbol: symbol, part: part)
        let ink = isSelected ? Color.schematicSelectionInk : Color(red: 0.65, green: 0, blue: 0)
        let center = geometry.point(.zero)
        let actuated = contact.isPressed || contact.selectsThrow3
        ZStack(alignment: .topLeading) {
            Canvas { context, _ in
                for pin in symbol.terminals {
                    let terminal = WorkbenchTerminal(partID: part.id, pinNumber: pin.id)
                    let start = geometry.endpoint(pin)
                    let trim = bench.showsOpenPinMarker(terminal) ? 2.5 : 0
                    var lead = Path()
                    let end = geometry.point(pin.bodyEnd)
                    lead.addLines(schematicPinLead(from: start, toward: end, trim: trim, inward: pin.inward))
                    lead.addLine(to: end)
                    context.stroke(lead, with: .color(ink), lineWidth: 1.2)
                }
                drawMechanicalSwitch(contact.designation, actuated: actuated, physical: bench.componentAppearance == .physicalDIP,
                                     point: geometry.point, ink: ink, in: context)
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)

            Text("\(part.reference ?? part.name) · \(contact.designation.rawValue)")
                .font(.system(size: 9, design: .monospaced))
                .rotationEffect(.degrees(-Double(bench.rotations[part.id, default: 0] * 90)))
                .position(x: center.x, y: center.y + 38)
                .allowsHitTesting(false)

            SwitchActuator(part: part, contact: contact, bench: bench, select: select, rotate: rotate,
                           size: CGSize(width: 58, height: 58))
                .position(center)

            ForEach(symbol.terminals) { pin in
                SchematicPinButton(terminal: WorkbenchTerminal(partID: part.id, pinNumber: pin.id), bench: bench)
                    .position(geometry.endpoint(pin))
            }
        }
        .frame(width: geometry.size.width, height: geometry.size.height)
    }
}

/// The physical view is a generic top view with the same terminal coordinates.
func drawMechanicalSwitch(_ designation: SwitchDesignation, actuated: Bool, physical: Bool, point: (CGPoint) -> CGPoint,
                          ink: Color, in context: GraphicsContext) {
    func path(_ points: [CGPoint]) -> Path {
        Path { $0.addLines(points.map(point)) }
    }

    let spdt = designation == .spdt
    if physical || spdt {
        let outline = path([CGPoint(x: -3.175, y: -3.81), CGPoint(x: 3.175, y: -3.81),
                            CGPoint(x: 3.175, y: 3.81), CGPoint(x: -3.175, y: 3.81),
                            CGPoint(x: -3.175, y: -3.81)])
        context.fill(outline, with: .color(physical ? Color(white: 0.22) : Color(red: 1, green: 1, blue: 0.76)))
        context.stroke(outline, with: .color(physical ? .gray : ink), lineWidth: 1.2)
    }

    let color = physical ? Color(white: 0.85) : ink
    let left = CGPoint(x: -2.032, y: 0)
    let right = CGPoint(x: 2.032, y: spdt ? -2.54 : 0)
    let lower = CGPoint(x: 2.032, y: 2.54)
    let contacts = spdt ? [left, right, lower] : [left, right]
    for center in contacts {
        let projected = point(center)
        let edge = point(CGPoint(x: center.x + 0.508, y: center.y))
        let radius = hypot(edge.x - projected.x, edge.y - projected.y)
        let ring = Path(ellipseIn: CGRect(x: projected.x - radius, y: projected.y - radius,
                                         width: 2 * radius, height: 2 * radius))
        if physical { context.fill(ring, with: .color(.gray)) }
        context.stroke(ring, with: .color(color), lineWidth: 1.2)
    }

    if spdt {
        let endY = actuated ? 2.286 : -2.286
        let blade = path([CGPoint(x: -1.651, y: 0), CGPoint(x: 1.651, y: endY)])
        context.stroke(blade, with: .color(color), style: StrokeStyle(lineWidth: physical ? 4 : 1.6, lineCap: .round))
    } else if physical {
        let center = point(.zero)
        let edge = point(CGPoint(x: 1.45, y: 0))
        let radius = hypot(edge.x - center.x, edge.y - center.y)
        let cap = Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius,
                                        width: 2 * radius, height: 2 * radius))
        context.fill(cap, with: .color(actuated ? .gray : Color(red: 0.75, green: 0.15, blue: 0.13)))
        context.stroke(cap, with: .color(color), lineWidth: 1.2)
    } else {
        let barY: CGFloat = actuated ? -0.508 : -1.27
        let bar = path([CGPoint(x: -2.54, y: barY), CGPoint(x: 2.54, y: barY)])
        let stem = path([CGPoint(x: 0, y: barY), CGPoint(x: 0, y: barY - 1.778)])
        context.stroke(bar, with: .color(color), lineWidth: 1.6)
        context.stroke(stem, with: .color(color), lineWidth: 1.2)
    }
}

struct SwitchActuator: View {
    let part: WorkbenchPart
    let contact: MechanicalSwitch
    let bench: Workbench
    let select: () -> Void
    let rotate: (Int) -> Void
    let size: CGSize

    var body: some View {
        Button {
            select()
            guard !workbenchShiftPressed, bench.selectedTerminal == nil else { return }
            if contact.designation == .spdt {
                bench.toggleContact(contact)
            }
        } label: {
            Color.clear
                .frame(width: size.width, height: size.height)
                .contentShape(Rectangle())
        }
        .buttonStyle(SwitchPressStyle { pressed in
            guard !pressed || (!workbenchShiftPressed && bench.selectedTerminal == nil) else { return }
            bench.setPressed(pressed, for: contact)
        })
        .accessibilityLabel("\(part.reference ?? part.name) · \(contact.designation.label)")
        .accessibilityValue(contact.designation == .pushButton
            ? (contact.isPressed ? "Closed" : "Open")
            : (contact.selectsThrow3 ? "Throw 3" : "Throw 1"))
        .help(contact.designation == .pushButton ? "Press and hold to close" : "Click to change throws")
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didResignKeyNotification)) { _ in
            bench.setPressed(false, for: contact)
        }
        .onChange(of: bench.selectedTerminal) { _, terminal in
            if terminal != nil { bench.setPressed(false, for: contact) }
        }
        .onDisappear { bench.setPressed(false, for: contact) }
        .contextMenu {
            Menu("Switch Type") {
                ForEach(SwitchDesignation.allCases) { designation in
                    Button {
                        bench.setSwitchDesignation(designation, for: part.id)
                    } label: {
                        if contact.designation == designation {
                            Label(designation.label, systemImage: "checkmark")
                        } else {
                            Text(designation.label)
                        }
                    }
                    .disabled(!bench.canSetSwitchDesignation(designation, for: part.id))
                }
            }
            PartRotationCommands(rotate: rotate)
            Button("Remove Part", role: .destructive) { bench.removePart(part.id) }
        }
    }
}

private struct SwitchPressStyle: ButtonStyle {
    let update: (Bool) -> Void

    func makeBody(configuration: Configuration) -> some View {
        configuration.label.onChange(of: configuration.isPressed) { _, pressed in update(pressed) }
    }
}
