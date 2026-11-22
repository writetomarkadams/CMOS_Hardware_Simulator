import SwiftUI

struct PowerRailSymbol: View {
    let partID: Int
    let rail: PowerRail
    let bench: Workbench
    let isSelected: Bool
    let select: () -> Void
    let rotate: (Int) -> Void

    static func endpoint(for rail: PowerRail) -> CGPoint {
        CGPoint(x: 30, y: rail == .ground ? 10 : 50)
    }

    private var terminal: WorkbenchTerminal {
        WorkbenchTerminal(partID: partID, pinNumber: 1)
    }

    var body: some View {
        let isGround = rail == .ground
        let endpoint = Self.endpoint(for: rail)
        let trim: CGFloat = bench.showsOpenPinMarker(terminal) ? 2.5 : 0
        let ink = Color(red: 0.65, green: 0, blue: 0)

        ZStack {
            Button(action: select) {
                ZStack {
                    Path { path in
                        if isGround {
                            path.addLines([CGPoint(x: endpoint.x, y: endpoint.y + trim), CGPoint(x: 30, y: 21)])
                            path.addLines([CGPoint(x: 20, y: 21), CGPoint(x: 40, y: 21),
                                           CGPoint(x: 30, y: 31), CGPoint(x: 20, y: 21)])
                        } else {
                            path.addLines([CGPoint(x: 30, y: 20), CGPoint(x: endpoint.x, y: endpoint.y - trim)])
                            path.addLines([CGPoint(x: 24, y: 27), CGPoint(x: 30, y: 20),
                                           CGPoint(x: 36, y: 27)])
                        }
                    }
                    .stroke(isSelected ? Color.schematicSelectionInk : ink, lineWidth: 1.5)
                    Text(rail.rawValue)
                        .font(.caption.monospaced())
                        .foregroundStyle(isSelected ? Color.schematicSelectionInk : Color(red: 0, green: 0.35, blue: 0.36))
                        .position(x: 30, y: isGround ? 43 : 10)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(rail.rawValue)
            .contextMenu {
                PartRotationCommands(rotate: rotate)
                Button("Remove Part", role: .destructive) { bench.removePart(partID) }
            }

            SchematicPinButton(terminal: terminal, bench: bench)
                .position(endpoint)
        }
        .frame(width: 60, height: 60)
    }
}
