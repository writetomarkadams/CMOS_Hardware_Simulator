import SwiftUI

struct LogicSwitchSymbol: View {
    let partID: Int
    let source: WorkbenchSwitch
    let bench: Workbench
    let isSelected: Bool
    let select: () -> Void
    let rotate: (Int) -> Void

    private var terminal: WorkbenchTerminal {
        WorkbenchTerminal(partID: partID, pinNumber: 1)
    }

    var body: some View {
        let selected = bench.selectedTerminal == terminal
        let output = bench.readings[terminal] ?? .highImpedance

        let ink = isSelected ? Color.schematicSelectionInk : Color.primary
        let terminalY: CGFloat = source.showsValue ? 21 : 28

        ZStack(alignment: .topLeading) {
            Path { path in
                if source.showsValue {
                    path.addLines([CGPoint(x: 48, y: terminalY), CGPoint(x: 68, y: terminalY)])
                    return
                }
                path.move(to: CGPoint(x: 4, y: 28))
                path.addLine(to: CGPoint(x: 16, y: 28))
                path.move(to: CGPoint(x: 46, y: 28))
                path.addLine(to: CGPoint(x: 68, y: 28))
            }
            .stroke(ink, lineWidth: 1.5)
            .allowsHitTesting(false)
            .accessibilityHidden(true)

            Button {
                select()
                bench.toggle(source)
            } label: {
                Group {
                    if source.showsValue {
                        Text(source.isOn ? "1" : "0")
                            .font(.system(size: 20, weight: .bold, design: .monospaced))
                            .foregroundStyle(source.isOn ? .white : ink)
                            .frame(width: 32, height: 30)
                            .background(source.isOn ? Color(red: 0.05, green: 0.43, blue: 0.20) : .clear)
                            .border(source.isOn && !isSelected ? .green : ink, width: 1.5)
                    } else {
                        Path { path in
                            path.move(to: CGPoint(x: 6, y: 23))
                            path.addLine(to: CGPoint(x: 36, y: source.isOn ? 23 : 7))
                            for x in [6.0, 36.0] {
                                path.addEllipse(in: CGRect(x: x - 2, y: 21, width: 4, height: 4))
                            }
                        }
                        .stroke(ink, style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
                    }
                }
                .frame(width: 44, height: 32)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(source.showsValue ? "Logic input \(partID)" : "Logic switch \(partID)")
            .accessibilityValue(output.description)
            .help(output.description)
            .contextMenu {
                PartRotationCommands(rotate: rotate)
                Button("Remove Part", role: .destructive) { bench.removePart(partID) }
            }
            .position(x: 32, y: 21)

            Button {
                bench.select(terminal)
            } label: {
                Image(systemName: selected ? "circle.inset.filled" : "circle")
                    .font(.system(size: 8))
                    .foregroundStyle(selected ? Color.accentColor : Color.primary)
                    .frame(width: 18, height: 18)
                    .contentShape(Rectangle())
                    .anchorPreference(key: CanvasBounds.self, value: .bounds) { [.terminal(terminal): $0] }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(bench.label(for: terminal))
            .accessibilityValue(output.description)
            .accessibilityAddTraits(selected ? .isSelected : [])
            .help(output.description)
            .position(x: 68, y: terminalY)
        }
        .frame(width: 80, height: 40)
    }
}
