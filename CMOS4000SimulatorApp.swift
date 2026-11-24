import SwiftUI

@main
struct CMOS4000SimulatorApp: App {
    @NSApplicationDelegateAdaptor(WorkbenchAppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup("Circuit Workbench", id: "workbench") {
            WorkbenchView()
        }
        .defaultSize(width: 900, height: 700)
        .commands { WorkbenchCommands() }

        Settings {
            WorkbenchNavigationSettings()
        }
    }
}

private struct WorkbenchNavigationSettings: View {
    @AppStorage(WorkbenchNavigationStyle.preferenceKey) private var style = WorkbenchNavigationStyle.kiCad

    var body: some View {
        Form {
            Picker("Workbench navigation", selection: $style) {
                ForEach(WorkbenchNavigationStyle.allCases, id: \.self) { style in
                    Text(style.rawValue).tag(style)
                }
            }
            Text(style == .kiCad
                 ? "Scroll vertically to zoom and horizontally to pan."
                 : "Scroll in any direction to pan. Command-scroll to zoom.")
                .foregroundStyle(.secondary)
            Text("Pinch to zoom. Middle-drag or hold Space and drag to pan.")
                .foregroundStyle(.secondary)
        }
        .padding(20)
        .frame(width: 440)
    }
}

struct WorkbenchActions {
    let open: () -> Void
    let save: () -> Void
    let saveAs: () -> Void
    let importCircuit: () -> Void
    let clear: () -> Void
    let undo: () -> Void
    let redo: () -> Void
    let rotate: (Int) -> Void
    let oscilloscope: () -> Void
    let wireList: Binding<Bool>
    let componentAppearance: Binding<ComponentAppearance>
    let zoomIn: () -> Void
    let zoomOut: () -> Void
    let resetZoom: () -> Void
    let fitCircuit: () -> Void
    let powerMode: Binding<PowerMode>
    let canUndo: Bool
    let canRedo: Bool
    let canRotate: Bool
    let hasCircuit: Bool
    let canClear: Bool
    let zoom: CGFloat
}

private struct WorkbenchActionsKey: FocusedValueKey {
    typealias Value = WorkbenchActions
}

extension FocusedValues {
    var workbenchActions: WorkbenchActions? {
        get { self[WorkbenchActionsKey.self] }
        set { self[WorkbenchActionsKey.self] = newValue }
    }
}

struct WorkbenchCommands: Commands {
    @FocusedValue(\.workbenchActions) private var actions

    var body: some Commands {
        CommandGroup(after: .newItem) {
            Button("Open…") { actions?.open() }
                .keyboardShortcut("o")
                .disabled(actions == nil)
            Button("Save") { actions?.save() }
                .keyboardShortcut("s")
                .disabled(actions == nil)
            Button("Save As…") { actions?.saveAs() }
                .keyboardShortcut("s", modifiers: [.command, .shift])
                .disabled(actions == nil)
            Button("Import Circuit…") { actions?.importCircuit() }
                .disabled(actions == nil)
            Divider()
            Button("Clear Workbench…") { actions?.clear() }
                .disabled(actions?.canClear != true)
        }
        CommandGroup(replacing: .undoRedo) {
            Button("Undo") { actions?.undo() }
                .keyboardShortcut("z")
                .disabled(actions?.canUndo != true)
            Button("Redo") { actions?.redo() }
                .keyboardShortcut("z", modifiers: [.command, .shift])
                .disabled(actions?.canRedo != true)
            Divider()
            Button("Rotate 90° Clockwise") { actions?.rotate(1) }
                .keyboardShortcut("r")
                .disabled(actions?.canRotate != true)
            Button("Rotate 90° Counterclockwise") { actions?.rotate(-1) }
                .keyboardShortcut("r", modifiers: [.command, .shift])
                .disabled(actions?.canRotate != true)
        }
        CommandGroup(after: .toolbar) {
            Button("Oscilloscope") { actions?.oscilloscope() }
                .disabled(actions == nil)
            if let actions {
                Toggle("Wire List", isOn: actions.wireList)
                Picker("Component Appearance", selection: actions.componentAppearance) {
                    ForEach(ComponentAppearance.allCases, id: \.self) { appearance in
                        Text(appearance.rawValue).tag(appearance)
                    }
                }
                .pickerStyle(.menu)
            } else {
                Button("Wire List") {}.disabled(true)
                Button("Component Appearance") {}.disabled(true)
            }
            Divider()
            Button("Zoom In") { actions?.zoomIn() }
                .keyboardShortcut("=")
                .disabled(actions.map { !$0.hasCircuit || $0.zoom >= 4 } ?? true)
            Button("Zoom Out") { actions?.zoomOut() }
                .keyboardShortcut("-")
                .disabled(actions.map { !$0.hasCircuit || $0.zoom <= 0.25 } ?? true)
            Button("Reset Zoom to 100%") { actions?.resetZoom() }
                .keyboardShortcut("0")
                .disabled(actions?.hasCircuit != true)
            Button("Fit Circuit") { actions?.fitCircuit() }
                .keyboardShortcut("9")
                .disabled(actions?.hasCircuit != true)
        }
        CommandMenu("Simulation") {
            if let actions {
                Picker("Power Mode", selection: actions.powerMode) {
                    ForEach(PowerMode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.inline)
            } else {
                Button("Power Mode") {}.disabled(true)
            }
        }
    }
}
