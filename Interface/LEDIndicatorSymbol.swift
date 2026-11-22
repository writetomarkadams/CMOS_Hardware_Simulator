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

    static let endpoint = CGPoint(x: 20, y: 30)

    private var terminal: WorkbenchTerminal {
        WorkbenchTerminal(partID: partID, pinNumber: 1)
    }

    var body: some View {
        let state = bench.readings[terminal] ?? .highImpedance
        let endpoint = Self.endpoint
        let outline = isSelected ? Color.schematicSelectionInk : Color.secondary

        ZStack {
            Path { path in
                path.move(to: CGPoint(x: endpoint.x, y: 15))
                path.addLine(to: CGPoint(x: endpoint.x, y: endpoint.y - (bench.showsOpenPinMarker(terminal) ? 2.5 : 0)))
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
            .position(x: endpoint.x, y: 13)

            SchematicPinButton(terminal: terminal, bench: bench)
                .position(endpoint)
        }
        .frame(width: 40, height: 60)
    }
}
