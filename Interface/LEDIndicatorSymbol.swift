import SwiftUI

struct LEDIndicatorSymbol: View {
    enum LampColour: String, CaseIterable, Codable {
        case red = "Red"
        case green = "Green"
        case orange = "Orange"
        case blue = "Blue"
        case yellow = "Yellow"

        var tint: Color {
            switch self {
            case .red: .red
            case .green: .green
            case .orange: .orange
            case .blue: .blue
            case .yellow: .yellow
            }
        }
    }

    let partID: Int
    let bench: Workbench
    let isSelected: Bool
    let select: () -> Void
    let rotate: (Int) -> Void

    private var colour: LampColour { bench.ledColours[partID, default: .green] }

    private var terminal: WorkbenchTerminal {
        WorkbenchTerminal(partID: partID, pinNumber: 1)
    }

    var body: some View {
        let state = bench.readings[terminal] ?? .highImpedance
        let terminalSelected = bench.selectedTerminal == terminal
        let outline = isSelected ? Color.schematicSelectionInk : Color.secondary

        ZStack {
            Path { path in
                path.move(to: CGPoint(x: 14, y: 15))
                path.addLine(to: CGPoint(x: 14, y: 32))
            }
            .stroke(outline, lineWidth: 1.2)
            .allowsHitTesting(false)
            .accessibilityHidden(true)

            Button(action: select) {
                Circle()
                    .fill(state == .high ? colour.tint : Color.secondary.opacity(0.15))
                    .overlay {
                        Circle().strokeBorder(outline, style: StrokeStyle(
                            lineWidth: isSelected ? 2 : 1,
                            dash: state == .undefined ? [2, 2] : []
                        ))
                    }
                    .frame(width: 15, height: 15)
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("LED \(partID)")
            .accessibilityValue("\(colour.rawValue), \(state.description)")
            .help(state.description)
            .contextMenu {
                Picker("Colour", selection: Binding(
                    get: { colour },
                    set: { bench.setLEDColour($0, for: partID) }
                )) {
                    ForEach(LampColour.allCases, id: \.self) { choice in
                        Text(choice.rawValue).tag(choice)
                    }
                }
                .pickerStyle(.menu)
                PartRotationCommands(rotate: rotate)
                Button("Remove Part", role: .destructive) { bench.removePart(partID) }
            }
            .position(x: 14, y: 13)

            Button {
                bench.select(terminal)
            } label: {
                Image(systemName: terminalSelected ? "circle.inset.filled" : "circle")
                    .font(.system(size: 8))
                    .foregroundStyle(terminalSelected ? Color.accentColor : outline)
                    .frame(width: 18, height: 18)
                    .contentShape(Rectangle())
                    .anchorPreference(key: CanvasBounds.self, value: .bounds) { [.terminal(terminal): $0] }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(bench.label(for: terminal))
            .accessibilityValue(state.description)
            .accessibilityAddTraits(terminalSelected ? .isSelected : [])
            .position(x: 14, y: 32)
        }
        .frame(width: 28, height: 42)
    }
}
