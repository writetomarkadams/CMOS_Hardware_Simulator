import SwiftUI

struct PowerRailSymbol: View {
    let partID: Int
    let rail: PowerRail
    let bench: Workbench
    let isSelected: Bool
    let select: () -> Void
    let rotate: (Int) -> Void

    private var terminal: WorkbenchTerminal {
        WorkbenchTerminal(partID: partID, pinNumber: 1)
    }

    var body: some View {
        let isGround = rail == .ground
        let endpointY: CGFloat = isGround ? 8 : 48
        let terminalSelected = bench.selectedTerminal == terminal
        let ink = Color(red: 0.65, green: 0, blue: 0)

        ZStack {
            Button(action: select) {
                ZStack {
                    Path { path in
                        if isGround {
                            path.addLines([CGPoint(x: 30, y: 8), CGPoint(x: 30, y: 21)])
                            path.addLines([CGPoint(x: 20, y: 21), CGPoint(x: 40, y: 21),
                                           CGPoint(x: 30, y: 31), CGPoint(x: 20, y: 21)])
                        } else {
                            path.addLines([CGPoint(x: 30, y: 20), CGPoint(x: 30, y: 48)])
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

            Button {
                bench.select(terminal)
            } label: {
                Image(systemName: terminalSelected ? "circle.inset.filled" : "circle.fill")
                    .font(.system(size: 7))
                    .foregroundStyle(terminalSelected ? Color.accentColor : ink)
                    .frame(width: 16, height: 16)
                    .contentShape(Rectangle())
                    .anchorPreference(key: CanvasBounds.self, value: .bounds) { [.terminal(terminal): $0] }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(rail.rawValue) terminal")
            .accessibilityValue((bench.readings[terminal] ?? rail.level).description)
            .accessibilityAddTraits(terminalSelected ? .isSelected : [])
            .position(x: 30, y: endpointY)
        }
        .frame(width: 60, height: 56)
    }
}
