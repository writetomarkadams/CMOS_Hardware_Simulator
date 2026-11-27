import SwiftUI

struct TO92Package {
    let size = CGSize(width: 80, height: 80)
    let body = CGRect(x: 6, y: 27, width: 68, height: 52)
    let leads: [Pin]
    let endpoints: [Int: CGPoint]

    init?(part: WorkbenchPart) {
        guard let transistor = part.component as? Transistor,
              transistor.definition.package == .to92 else { return nil }
        leads = transistor.definition.leads.map { transistor.pin($0) }
        let grid = WorkbenchWire.gridSpacing
        // Keep the existing offsets from the rotation pivot for saved wire routes.
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        endpoints = Dictionary(uniqueKeysWithValues: leads.enumerated().map { index, lead in
            (lead.number, CGPoint(x: center.x + CGFloat(2 * (index - 1)) * grid,
                                y: center.y + 3 * grid))
        })
    }

    func drawHousing(in context: GraphicsContext, isSelected: Bool) {
        let face = body
        let shoulder = face.minY + 34
        let housing = Path { path in
            path.move(to: CGPoint(x: face.minX + 5, y: face.maxY))
            path.addQuadCurve(to: CGPoint(x: face.minX, y: face.maxY - 12),
                              control: CGPoint(x: face.minX, y: face.maxY - 3))
            path.addLine(to: CGPoint(x: face.minX, y: shoulder))
            path.addCurve(to: CGPoint(x: face.midX, y: face.minY),
                          control1: CGPoint(x: face.minX, y: shoulder - 19),
                          control2: CGPoint(x: face.midX - 19, y: face.minY))
            path.addCurve(to: CGPoint(x: face.maxX, y: shoulder),
                          control1: CGPoint(x: face.midX + 19, y: face.minY),
                          control2: CGPoint(x: face.maxX, y: shoulder - 19))
            path.addLine(to: CGPoint(x: face.maxX, y: face.maxY - 12))
            path.addQuadCurve(to: CGPoint(x: face.maxX - 5, y: face.maxY),
                              control: CGPoint(x: face.maxX, y: face.maxY - 3))
            path.closeSubpath()
        }
        context.stroke(housing, with: .color(isSelected ? .cyan : .black),
                       style: StrokeStyle(lineWidth: 3, lineJoin: .round))
        context.stroke(housing, with: .color(.black),
                       style: StrokeStyle(lineWidth: 1.25, lineJoin: .round))
    }
}

struct TO92PackageView: View {
    let package: TO92Package
    let part: WorkbenchPart
    let transistor: Transistor
    let bench: Workbench
    let select: () -> Void
    let rotate: (Int) -> Void
    let editProperties: () -> Void

    var body: some View {
        let face = package.body
        ZStack(alignment: .topLeading) {
            Canvas { context, _ in
                context.draw(Text(transistor.designation.rawValue)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Color.black), at: CGPoint(x: face.midX, y: face.minY + 18))
                for lead in package.leads {
                    let end = package.endpoints[lead.number]!
                    context.draw(Text(lead.name).font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Color.black), at: CGPoint(x: end.x, y: end.y - 12))
                    let pad = CGRect(x: end.x - 4.5, y: end.y - 4.5, width: 9, height: 9)
                    context.fill(Path(ellipseIn: pad), with: .color(Color(red: 0.86, green: 0.08, blue: 0.05)))
                    context.fill(Path(ellipseIn: pad.insetBy(dx: 2, dy: 2)), with: .color(.white))
                }
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)

            Color.clear
                .frame(width: face.width, height: face.height)
                .contentShape(Rectangle())
                .onTapGesture(perform: select)
                .contextMenu {
                    PartRotationCommands(rotate: rotate)
                    Button("Properties…", action: editProperties)
                    Button("Remove Part", role: .destructive) { bench.removePart(part.id) }
                }
                .position(x: face.midX, y: face.midY)
                .accessibilityLabel(part.label)

            ForEach(package.leads) { lead in
                SchematicPinButton(terminal: WorkbenchTerminal(partID: part.id, pinNumber: lead.number), bench: bench)
                    .position(package.endpoints[lead.number]!)
            }
        }
        .frame(width: package.size.width, height: package.size.height)
    }
}

struct TransistorProperties: View {
    let partID: Int
    let bench: Workbench
    @Environment(\.dismiss) private var dismiss
    @State private var designation: TransistorDesignation

    init(partID: Int, bench: Workbench, designation: TransistorDesignation) {
        self.partID = partID
        self.bench = bench
        _designation = State(initialValue: designation)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Transistor Properties").font(.headline)
            Picker("Designation", selection: $designation) {
                ForEach(TransistorDesignation.allCases) { option in
                    Text(option.rawValue).tag(option)
                        .disabled(!bench.canSetTransistorDesignation(option, for: partID))
                }
            }
            if designation == .bc547B {
                Text("onsemi BC547BG · Ideal switching and limited DC approximation")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if designation == .twoN3906 {
                Text("onsemi 2N3906 · Ideal digital high-side switching only")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if TransistorDesignation.allCases.contains(where: { !bench.canSetTransistorDesignation($0, for: partID) }) {
                Text("Some designations are unavailable because they would change the existing terminal layout.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Apply") {
                    bench.setTransistorDesignation(designation, for: partID)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!bench.canSetTransistorDesignation(designation, for: partID))
            }
        }
        .padding(20)
        .frame(width: 320)
    }
}
