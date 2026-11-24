import AppKit
import SwiftUI
import UniformTypeIdentifiers

private extension CGRect {
    var center: CGPoint { CGPoint(x: midX, y: midY) }
}

enum CanvasItem: Hashable {
    case part(Int)
}

struct CanvasBounds: PreferenceKey {
    static let defaultValue: [CanvasItem: Anchor<CGRect>] = [:]

    static func reduce(
        value: inout [CanvasItem: Anchor<CGRect>],
        nextValue: () -> [CanvasItem: Anchor<CGRect>]
    ) {
        value.merge(nextValue(), uniquingKeysWith: { _, next in next })
    }
}

private extension WireColour {
    var stroke: Color {
        switch self {
        case .black: .black
        case .grey: Color(white: 0.46)
        case .brown: Color(red: 0.56, green: 0.32, blue: 0.19)
        case .red: .red
        case .orange: .orange
        case .yellow: Color(red: 1, green: 0.81, blue: 0.14)
        case .green: .green
        case .blue: .blue
        case .violet: .purple
        }
    }
}

struct WorkbenchView: View {
    @Environment(\.colorScheme) private var colourScheme
    @State private var bench = Workbench()
    @State private var scopeWindow = WorkbenchScopeWindow()
    @State private var scopeDocked = false
    @AppStorage("workbenchShowsWireList") private var showsWireList = false
    @AppStorage(WorkbenchNavigationStyle.preferenceKey) private var navigationStyle = WorkbenchNavigationStyle.kiCad
    @State private var showingLibrary = false
    @State private var importFile: CircuitImportFile?

    @State private var editingOscillator: WorkbenchPart?
    @State private var editingResistance: Resistor?
    @State private var editingCapacitance: Capacitor?
    @State private var camera = WorkbenchViewport()
    @State private var circuitBounds: CGRect?
    @State private var viewportSize: CGSize = .zero
    @State private var occupiedBounds: [Int: CGRect] = [:]
    @State private var showingCircuitCheck = false
    @State private var findings: [CircuitFinding] = []
    @State private var selectedFinding: CircuitFinding.ID?
    @State private var selectedParts: Set<Int> = []
    @State private var pointerLocation: CGPoint?
    @State private var placingProbe = false
    @State private var movingProbe: Int?
    @State private var probePointer: CGPoint?
    @State private var probeMessage: String?
    @GestureState private var selectionBox: CGRect?
    @FocusState private var canvasFocused: Bool
    @GestureState private var drag: Workbench.Movement?
    @State private var dragCancelled = false
    @State private var placement: Placement?
    @State private var placementPointer: CGPoint?

    private struct Placement {
        let archive: WorkbenchArchive
        let anchor: CGPoint
        let outlines: [CGRect]
        let routes: [[CGPoint]]
    }

    private struct PartIdentity: Hashable {
        let id: Int
        let component: ObjectIdentifier
    }

    private var workflow: WorkbenchFileWorkflow { .shared }
    private var canClear: Bool { bench.hasCircuit || bench.isDirty || bench.documentURL != nil }

    private let canvasSpace = "WorkbenchCanvas"

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            fileBar
            Divider()

            HStack(spacing: 0) {
                toolStrip
                Divider()
                workbenchArea
                if showingCircuitCheck { circuitCheckPanel } else { wireList }
                Divider()
                instrumentStrip
            }

            if scopeDocked {
                Divider()
                OscilloscopeView(bench: bench, voltageRange: $scopeWindow.voltageRange,
                                 cursors: $scopeWindow.cursors, placementLabel: "Undock", changePlacement: showScope)
                    .frame(height: 240)
            }

            Divider()
            statusBar
        }
        .frame(minWidth: 680, minHeight: 460)
        .onDisappear { scopeWindow.dispose() }
        .task(id: !bench.hasRunningClocks && bench.scope.running && !bench.scopeProbes.isEmpty) {
            guard !bench.hasRunningClocks, bench.scope.running, !bench.scopeProbes.isEmpty else { return }
            while !Task.isCancelled {
                bench.refreshScope()
                do { try await Task.sleep(for: .milliseconds(33)) }
                catch { return }
            }
        }
        .focusedSceneValue(\.workbenchActions, commands)
        .background(WorkbenchWindowBridge(bench: bench, isDirty: bench.isDirty))
        .task(id: bench.hasRunningClocks) {
            guard bench.hasRunningClocks else { return }
            let clock = ContinuousClock()
            while !Task.isCancelled {
                let nextUpdate = clock.now + .milliseconds(16)
                bench.serviceClocks()
                do {
                    try await clock.sleep(until: nextUpdate)
                } catch {
                    return
                }
            }
        }
        .sheet(item: $importFile) { file in
            CircuitImportView(file: file, hasExistingCircuit: canClear, powerMode: bench.powerMode) {
                importCircuit(file, replacing: $0)
            }
        }
        .sheet(isPresented: $showingLibrary) {
            ComponentLibraryView(bench: bench, placeNewPart: placeNewPart)
        }
        .sheet(item: $editingCapacitance) { capacitor in
            CapacitanceEditor(capacitor: capacitor) { value in
                bench.setCapacitance(value, for: capacitor)
            }
        }
        .sheet(item: $editingOscillator) { part in
            if let source = part.component as? CXO_DIP8 {
                ClockFrequencyEditor(frequency: bench.clockFrequency(for: part.id, source: source),
                                     units: [.kilohertz, .megahertz]) {
                    bench.setClockFrequency($0, for: part.id)
                }
            }
        }
        .sheet(item: $editingResistance) { resistor in
            ResistanceEditor(resistor: resistor) { value, unit in
                bench.setResistance(value, unit: unit, for: resistor)
            }
        }
        .onChange(of: bench.circuitRevision) { _, _ in
            if showingCircuitCheck { refreshCircuitCheck() }
        }
        .onChange(of: bench.parts.map(\.id)) { _, ids in
            selectedParts.formIntersection(ids)
            if ids.isEmpty {
                camera = WorkbenchViewport()
                circuitBounds = nil
                occupiedBounds.removeAll()
            }
        }
    }

    private var workbenchArea: some View {
        GeometryReader { viewport in
            let frame = camera.canvasFrame(in: viewport.size, extent: canvasExtent)
            let worldOrigin = frame.origin
            let screenOrigin = camera.screenPoint(at: worldOrigin)
            let pinLocations = displayedPinLocations()
            let movement = dragCancelled ? nil : drag
            canvasBackground
                .overlay(alignment: .topLeading) {
                    canvas(worldOrigin: worldOrigin)
                        .frame(width: frame.width, height: frame.height, alignment: .topLeading)
                        .backgroundPreferenceValue(CanvasBounds.self) { anchors in
                            wireLayer(anchors: anchors, pinLocations: pinLocations, movement: movement,
                                      worldOrigin: worldOrigin)
                        }
                        .overlay { pinMarkers(at: pinLocations, worldOrigin: worldOrigin) }
                        .environment(\.schematicZoom, camera.scale)
                        .coordinateSpace(name: canvasSpace)
                        .scaleEffect(camera.scale, anchor: .topLeading)
                        .offset(x: screenOrigin.x, y: screenOrigin.y)
                        .allowsHitTesting(placement == nil)
                }
                .overlay {
                    if bench.parts.isEmpty {
                        Button("Add Part…", systemImage: "plus") { showingLibrary = true }
                            .buttonStyle(.bordered)
                    }
                }
                .overlay {
                    if let placement { placementLayer(placement) }
                }
                .overlay {
                    if placingProbe || !bench.scopeProbes.isEmpty {
                        probeLayer(pins: pinLocations, movement: movement)
                    }
                }
                .background {
                    WorkbenchNavigation(
                        style: navigationStyle,
                        pan: { camera.pan(x: $0, y: $1) },
                        zoom: { camera.zoom(to: camera.scale * $0, around: $1) },
                        scroll: { mode, x, y, precise, momentum, point in
                            mode.apply(x: x, y: y, precise: precise, momentum: momentum, at: point, to: &camera)
                        },
                        editShortcut: handleEditShortcut
                    )
                }
                .clipped()
                .contentShape(Rectangle())
                .onGeometryChange(for: CGSize.self) { $0.size } action: { viewportSize = $0 }
                .focusable()
                .focused($canvasFocused)
                .focusEffectDisabled()
                .onChange(of: drag == nil) { _, ended in
                    if ended { dragCancelled = false }
                    else { canvasFocused = true }
                }
                .onKeyPress(.escape) {
                    if placement != nil {
                        placement = nil
                    } else if placingProbe {
                        endProbePlacement()
                    } else if drag != nil {
                        dragCancelled = true
                    } else if bench.selectedTerminal != nil {
                        bench.cancelWire()
                    } else if !selectedParts.isEmpty || bench.selectedWireID != nil {
                        selectedParts.removeAll()
                        bench.selectWire(nil)
                    } else {
                        return .ignored
                    }
                    return .handled
                }

        }
    }

    private func canvas(worldOrigin: CGPoint) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach(bench.parts) { part in
                let turns = bench.rotations[part.id, default: 0]
                let geometry = SchematicPartGeometry(part: part, turns: turns, appearance: bench.componentAppearance)
                let position = displayedPosition(of: part.id)
                let center = geometry.canvasOrigin(at: position, imported: part.importedSymbol != nil)
                partCard(part, geometry: geometry)
                    .frame(width: geometry.size.width, height: geometry.size.height, alignment: .topLeading)
                    .id(PartIdentity(id: part.id, component: ObjectIdentifier(part.component)))
                    .simultaneousGesture(partDrag(part.id))
                    .rotationEffect(.degrees(Double(turns * 90)))
                    .offset(x: center.x - geometry.size.width / 2 - worldOrigin.x,
                            y: center.y - geometry.size.height / 2 - worldOrigin.y)
                    .zIndex(drag?.parts.contains(part.id) == true ? 1 : 0)
            }
        }
    }

    private func displayedPosition(of id: Int) -> CGPoint {
        let origin = bench.positions[id] ?? CGPoint(x: 20, y: 20)
        guard !dragCancelled, let drag, drag.parts.contains(id) else { return origin }
        return drag.translate(origin)
    }

    private var visibleWorld: CGRect {
        let origin = camera.worldPoint(at: .zero)
        return CGRect(origin: origin, size: CGSize(width: viewportSize.width / camera.scale,
                                                   height: viewportSize.height / camera.scale))
    }

    private func zoom(by factor: CGFloat) {
        camera.zoom(to: camera.scale * factor, around: CGRect(origin: .zero, size: viewportSize).center)
    }

    private func resetZoom() {
        camera.zoom(to: 1, around: CGRect(origin: .zero, size: viewportSize).center)
    }

    private func fitCircuit() {
        if let circuitBounds { camera.fit(circuitBounds, in: viewportSize) }
    }

    private var fileBar: some View {
        HStack(spacing: 8) {
            Button("Open…", systemImage: "folder") { chooseFile(importing: false) }
            Button(bench.documentURL == nil ? "Save…" : "Save", systemImage: "square.and.arrow.down") { saveCircuit() }
            Button("Import…", systemImage: "square.and.arrow.down.on.square") { chooseFile(importing: true) }
            Spacer()
            Button("Check Circuit", systemImage: "checkmark.circle") {
                showingCircuitCheck.toggle()
                selectedFinding = nil
                if showingCircuitCheck { refreshCircuitCheck() }
            }
            .accessibilityAddTraits(showingCircuitCheck ? .isSelected : [])
        }
        .disabled(commands == nil)
        .controlSize(.small)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
    }

    private var toolStrip: some View {
        VStack(spacing: 4) {
            stripButton("Select", icon: "cursorarrow", active: !bench.wiringEnabled && !placingProbe) {
                setWiringEnabled(false)
            }
            .keyboardShortcut("v", modifiers: [])
            .accessibilityAddTraits(bench.wiringEnabled || placingProbe ? [] : .isSelected)
            stripButton("Wire", icon: "point.topleft.down.to.point.bottomright.curvepath", active: bench.wiringEnabled) {
                setWiringEnabled(true)
            }
            .keyboardShortcut("w", modifiers: [])
            .accessibilityAddTraits(bench.wiringEnabled ? .isSelected : [])
            wireColourMenu
            stripButton("Probe", icon: "eyedropper", active: placingProbe) { beginProbePlacement() }
                .accessibilityAddTraits(placingProbe ? .isSelected : [])
            Divider()
            stripButton("Add Part…", icon: "plus") { showingLibrary = true }
                .keyboardShortcut("a", modifiers: [])
                .disabled(showingLibrary)
            stripButton("Rotate Clockwise", icon: "rotate.right") { rotateSelected(1) }
                .disabled(commands?.canRotate != true)
            Divider()
            Group {
                stripButton("Zoom In", icon: "plus.magnifyingglass") { zoom(by: 1.25) }
                    .disabled(camera.scale >= 4)
                stripButton("Zoom Out", icon: "minus.magnifyingglass") { zoom(by: 0.8) }
                    .disabled(camera.scale <= 0.25)
                stripButton("Fit Circuit", icon: "arrow.up.left.and.arrow.down.right", action: fitCircuit)
            }
            .disabled(bench.parts.isEmpty)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 6)
        .frame(width: 40)
        .background(.bar)
    }

    private var wireColourMenu: some View {
        let selected = bench.wires.first { $0.id == bench.selectedWireID }
        let colour = selected?.colour ?? bench.newWireColour
        let title = selected == nil ? "New Wire Colour" : "Selected Wire Colour"
        return Menu {
            wireColourPicker(title, colour: colour) { choice in
                if let selected {
                    bench.setWireColour(choice, for: selected.id)
                } else {
                    bench.newWireColour = choice
                }
                canvasFocused = true
            }
        } label: {
            Label {
                Text(title)
            } icon: {
                Image(nsImage: wireColourSwatch(colour))
            }
            .labelStyle(.iconOnly)
            .frame(width: 30, height: 30)
            .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .accessibilityLabel(title)
        .accessibilityValue(colour.title)
        .help("\(title): \(colour.title)")
    }

    private func wireColourPicker(_ title: String, colour: WireColour,
                                  onChange: @escaping (WireColour) -> Void) -> some View {
        Picker(title, selection: Binding(get: { colour }, set: onChange)) {
            ForEach(WireColour.allCases, id: \.self) { choice in
                Text(choice.title).tag(choice)
            }
        }
        .pickerStyle(.inline)
    }

    private func wireContextMenu(_ wire: WorkbenchWire) -> some View {
        Group {
            Menu("Wire Colour") {
                wireColourPicker("Wire Colour", colour: wire.colour) { choice in
                    bench.setWireColour(choice, for: wire.id)
                }
            }
            Button("Remove Wire", role: .destructive) { bench.removeWire(wire.id) }
        }
    }

    private func wireColourSwatch(_ colour: WireColour) -> NSImage {
        let fill = NSColor(colour.stroke)
        let border = NSColor.labelColor.withAlphaComponent(0.55)
        return NSImage(size: NSSize(width: 16, height: 12), flipped: false) { bounds in
            let outline = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 2, yRadius: 2)
            fill.setFill()
            outline.fill()
            border.setStroke()
            outline.lineWidth = 1
            outline.stroke()
            return true
        }
    }

    private var instrumentStrip: some View {
        VStack(spacing: 4) {
            stripButton("Wire List", icon: "list.bullet", active: showsWireList) { showsWireList.toggle() }
                .accessibilityAddTraits(showsWireList ? .isSelected : [])
            stripButton("Oscilloscope", icon: "waveform.path", active: scopeDocked, action: toggleScope)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 6)
        .frame(width: 40)
        .background(.bar)
    }

    private func stripButton(_ title: String, icon: String, active: Bool = false,
                             action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .labelStyle(.iconOnly)
                .frame(width: 30, height: 30)
                .contentShape(Rectangle())
                .background(active ? Color.accentColor.opacity(0.18) : .clear, in: .rect(cornerRadius: 5))
        }
        .buttonStyle(.borderless)
        .help(title)
    }

    private func setWiringEnabled(_ enabled: Bool) {
        endProbePlacement()
        if !enabled { bench.cancelWire() }
        bench.wiringEnabled = enabled
        canvasFocused = true
    }

    private var statusBar: some View {
        let status = !bench.isStable ? "Did not settle"
            : bench.clockIsBehind ? "Clock behind"
            : bench.hasRunningClocks ? "Running" : "Ready"
        return HStack(spacing: 10) {
            if placement != nil {
                Text("Click to place copies · Esc to cancel")
            } else if let probeMessage {
                Text(probeMessage).lineLimit(1)
            } else if placingProbe, let channel = movingProbe ?? bench.nextScopeChannel {
                Text("CH\(channel + 1) · Click a wire, junction or pin · Esc to cancel")
                    .lineLimit(1)
            } else if bench.nextScopeChannel == nil && !bench.wiringEnabled {
                Text("Click a probe marker to move it or right-click to remove it")
                    .lineLimit(1)
            } else if let selected = bench.selectedTerminal {
                Text("Wiring \(bench.label(for: selected)) · Click to bend, click a pin or an unambiguous wire segment to finish")
                    .lineLimit(1)
                Button("Cancel", action: bench.cancelWire)
                    .keyboardShortcut(.cancelAction)
                    .controlSize(.mini)
            } else {
                Text(bench.wiringEnabled ? "Click a pin to start wiring" : "Drag empty canvas to select parts")
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if !bench.scopeProbes.isEmpty || placingProbe {
                let count = bench.scopeProbes.count
                let limit = Oscilloscope.channelCount
                Text("Probes \(count)/\(limit)")
                    .monospacedDigit()
                    .foregroundStyle(count == limit ? Color.orange : Color.secondary)
                    .help("Click a probe marker to move it, or right-click to remove it.")
            }
            Button(Double(camera.scale).formatted(.percent.precision(.fractionLength(0))), action: resetZoom)
                .buttonStyle(.borderless)
                .monospacedDigit()
                .accessibilityLabel("Reset zoom to 100 percent")
                .help("Reset zoom to 100%. Pinch to zoom. Middle-drag or Space-drag to pan.")
                .disabled(bench.parts.isEmpty)
            Divider().frame(height: 12)
            Text(status)
                .foregroundStyle(!bench.isStable || bench.clockIsBehind ? Color.orange : Color.primary)
            Text(bench.powerMode.rawValue)
                .foregroundStyle(.secondary)
        }
        .font(.caption)
        .padding(.horizontal, 10)
        .frame(height: 26)
        .background(.bar)
    }

    private var commands: WorkbenchActions? {
        guard !showingLibrary, editingResistance == nil, editingCapacitance == nil, editingOscillator == nil,
              importFile == nil else { return nil }
        return WorkbenchActions(
            open: { chooseFile(importing: false) }, save: { saveCircuit() }, saveAs: { saveCircuit(saveAs: true) },
            importCircuit: { chooseFile(importing: true) }, clear: clearWorkbench,
            undo: { placement = nil; bench.undo() }, redo: { placement = nil; bench.redo() },
            rotate: rotateSelected, oscilloscope: toggleScope,
            wireList: $showsWireList,
            componentAppearance: Binding(get: { bench.componentAppearance }, set: { appearance in
                bench.hoveredTerminal = nil
                bench.setComponentAppearance(appearance)
                if let archive = placement?.archive { beginPlacement(archive) }
            }),
            zoomIn: { zoom(by: 1.25) }, zoomOut: { zoom(by: 0.8) },
            resetZoom: resetZoom, fitCircuit: fitCircuit,
            powerMode: Binding(get: { bench.powerMode }, set: bench.setPowerMode),
            canUndo: bench.canUndo, canRedo: bench.canRedo, canRotate: selectedParts.count == 1,
            hasCircuit: bench.hasCircuit, canClear: canClear, zoom: camera.scale
        )
    }

    private func rotateSelected(_ steps: Int) {
        if selectedParts.count == 1, let id = selectedParts.first {
            rotationAction(for: id)(steps)
        }
    }

    @ViewBuilder
    private var circuitCheckPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Circuit Check").font(.headline)
                Spacer()
                Button("Refresh Check", systemImage: "arrow.clockwise", action: refreshCircuitCheck)
                    .labelStyle(.iconOnly)
                Button("Close Circuit Check", systemImage: "xmark") {
                    showingCircuitCheck = false
                    selectedFinding = nil
                }
                .labelStyle(.iconOnly)
            }
            .padding(12)
            Divider()
            if !bench.isStable {
                Text("Simulation did not settle. Check for feedback loops and conflicting outputs.")
                    .foregroundStyle(.secondary)
                    .padding(12)
            }
            if findings.isEmpty {
                Text(bench.parts.isEmpty ? "Add components to check a circuit." : "No issues found by the built-in checks.")
                    .foregroundStyle(.secondary)
                    .padding(12)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(findings) { finding in
                            Button {
                                selectedFinding = finding.id
                                revealFinding(finding.target)
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(finding.title).font(.subheadline.weight(.semibold))
                                    Text(finding.location).foregroundStyle(.secondary)
                                    Text("Current state · \((bench.currentState(for: finding) ?? finding.state).description)")
                                        .font(.caption.monospaced())
                                    Text(finding.suggestion).font(.callout)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(8)
                                .background(selectedFinding == finding.id ? Color.accentColor.opacity(0.15) : .clear,
                                            in: .rect(cornerRadius: 6))
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityElement(children: .combine)
                            .accessibilityAddTraits(selectedFinding == finding.id ? .isSelected : [])
                        }
                    }
                    .padding(8)
                }
            }
            Spacer(minLength: 0)
        }
        .frame(width: 270)
        .background(.bar)
    }

    private func refreshCircuitCheck() {
        findings = bench.checkCircuit()
        if !findings.contains(where: { $0.id == selectedFinding }) { selectedFinding = nil }
    }

    private func revealFinding(_ target: CircuitFinding.Target) {
        let pins = displayedPinLocations()
        let point: CGPoint?
        switch target {
        case .pin(let terminal):
            point = pins[terminal]
        case .wire(let id):
            guard let wire = bench.wires.first(where: { $0.id == id }) else { return }
            func location(_ terminal: WorkbenchTerminal) -> CGPoint? {
                terminal.isJunction ? bench.junctions[terminal.pinNumber] : pins[terminal]
            }
            guard let first = location(wire.first), let second = location(wire.second) else { return }
            point = wirePath(wire.route(from: first, to: second)).boundingRect.center
        }
        if let point {
            let screen = camera.screenPoint(at: point)
            camera.pan(x: viewportSize.width / 2 - screen.x, y: viewportSize.height / 2 - screen.y)
        }
    }

    @ViewBuilder
    private var wireList: some View {
        let wires = bench.wires.filter { $0.sourceRoute != .alias }
        if showsWireList {
            Divider()
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("Wire List").font(.headline)
                    Spacer()
                    Button("Hide Wire List", systemImage: "sidebar.right") { showsWireList = false }
                        .labelStyle(.iconOnly)
                }
                .padding(12)
                Divider()
                if wires.isEmpty {
                    Text("No wires").foregroundStyle(.secondary).padding(12)
                }
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(wires) { wire in
                            Button {
                                bench.cancelWire()
                                selectWire(wire.id)
                            } label: {
                                let endpoints = "\(bench.label(for: wire.first)) ↔ \(bench.label(for: wire.second))"
                                Text(wire.netName.map { "\($0) · \(endpoints)" } ?? endpoints)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.vertical, 4)
                                    .padding(.horizontal, 6)
                                    .background(bench.selectedWireID == wire.id ? Color.accentColor.opacity(0.18) : .clear,
                                                in: .rect(cornerRadius: 4))
                            }
                            .buttonStyle(.plain)
                            .accessibilityAddTraits(bench.selectedWireID == wire.id ? .isSelected : [])
                            .contextMenu { wireContextMenu(wire) }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                }
            }
            .frame(width: 220)
            .frame(maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private func toggleScope() {
        if scopeDocked {
            scopeDocked = false
        } else {
            showScope()
        }
    }

    private func showScope() {
        scopeDocked = false
        let docked = $scopeDocked
        let controller = scopeWindow
        let owner = NSApp.keyWindow
        controller.show(bench: bench) { [weak controller, weak owner] in
            controller?.close()
            docked.wrappedValue = true
            owner?.makeKeyAndOrderFront(nil)
        }
    }

    private func saveCircuit(saveAs: Bool = false) {
        workflow.perform { workflow.save(bench, saveAs: saveAs) }
    }

    private func clearWorkbench() {
        workflow.perform {
            guard workflow.permitsLeaving(bench) else { return false }
            bench.clear()
            placement = nil
            selectedParts.removeAll()
            occupiedBounds.removeAll()
            camera = WorkbenchViewport()
            return true
        }
    }

    private func chooseFile(importing: Bool) {
        workflow.perform {
            let panel = NSOpenPanel()
            panel.allowedContentTypes = [.data]
            panel.allowsMultipleSelection = false
            guard panel.runModal() == .OK, let url = panel.url else { return false }
            do {
                if importing {
                    let accessing = url.startAccessingSecurityScopedResource()
                    defer { if accessing { url.stopAccessingSecurityScopedResource() } }
                    let text = try String(contentsOf: url, encoding: .utf8)
                    let preview = try CircuitImportPreview.read(text, filenameExtension: url.pathExtension)
                    importFile = CircuitImportFile(name: url.lastPathComponent, preview: preview)
                } else {
                    guard workflow.permitsLeaving(bench) else { return false }
                    let accessing = url.startAccessingSecurityScopedResource()
                    defer { if accessing { url.stopAccessingSecurityScopedResource() } }
                    let archive = try JSONDecoder().decode(WorkbenchArchive.self, from: Data(contentsOf: url))
                    try bench.open(archive, at: url)
                    placement = nil
                    camera = WorkbenchViewport()
                    selectedParts.removeAll()
                    occupiedBounds.removeAll()
                }
                return true
            } catch {
                workflow.showError(error)
                return false
            }
        }
    }

    private func importCircuit(_ file: CircuitImportFile, replacing: Bool) {
        workflow.perform {
            if replacing && !workflow.permitsLeaving(bench) { return false }
            guard let first = bench.importCircuit(file.preview, replacing: replacing) else { return false }
            placement = nil
            selectedParts.removeAll()
            occupiedBounds.removeAll()
            importFile = nil
            if let point = bench.positions[first.id] {
                if first.importedSymbol != nil {
                    let top = bench.parts.filter { $0.id >= first.id }.compactMap { part -> CGFloat? in
                        guard let position = bench.positions[part.id], let drawing = part.importedSymbol else { return nil }
                        let quarterTurn = bench.rotations[part.id, default: 0] % 2 != 0
                        return position.y - (quarterTurn ? drawing.bounds.width : drawing.bounds.height) / 2
                    }.min() ?? point.y
                    camera.reveal(top: top - 24)
                } else {
                    camera.reveal(top: point.y - 20)
                }
            }
            return true
        }
    }

    private let gridSpacing = WorkbenchWire.gridSpacing

    private func snap(_ point: CGPoint) -> CGPoint {
        WorkbenchWire.snap(point)
    }

    private var canvasExtent: CGSize {
        var size = CGSize(width: 1400, height: 900)
        for part in bench.parts {
            let origin = bench.positions[part.id] ?? CGPoint(x: 20, y: 20)
            size.width = max(size.width, origin.x + 300)
            size.height = max(size.height, origin.y + 550)
        }
        let wirePoints = bench.wires.flatMap(\.bends) + bench.pendingBends + Array(bench.junctions.values)
        for bend in wirePoints + bench.schematicMarks.map(\.position) {
            size.width = max(size.width, bend.x + 24)
            size.height = max(size.height, bend.y + 24)
        }
        return size
    }

    private func placeNewPart(_ id: Int) {
        guard viewportSize.width > 0, viewportSize.height > 0, bench.parts.count > 1 else {
            bench.placeNewPart(id, at: CGPoint(x: 20, y: 20))
            return
        }

        // Keep the card's centre on screen, even when the visible canvas is crowded.
        let visible = visibleWorld
        let minX = max(20, visible.minX + 20)
        let minY = max(20, visible.minY + 20)
        let maxX = max(minX, visible.maxX - 270)
        let height = min(290, max(60, visible.height - 32))
        let maxY = max(minY, visible.maxY - height)
        let bounds = bench.parts.compactMap { $0.id == id ? nil : occupiedBounds[$0.id] }
        let candidatesX = Array(stride(from: minX, through: maxX, by: 120)) + [maxX]
        let candidatesY = Array(stride(from: minY, through: maxY, by: 85)) + [maxY]
        var best = CGPoint(x: minX, y: minY)
        var leastOverlap = CGFloat.infinity
        for y in candidatesY {
            for x in candidatesX {
                let footprint = CGRect(x: x + 45, y: y, width: 180, height: height)
                let overlap = bounds.reduce(CGFloat.zero) { sum, rect in
                    let intersection = footprint.intersection(rect.insetBy(dx: -10, dy: -10))
                    return intersection.isNull ? sum : sum + intersection.width * intersection.height
                }
                if overlap < leastOverlap {
                    best = CGPoint(x: x, y: y)
                    leastOverlap = overlap
                }
                if overlap == 0 {
                    bench.placeNewPart(id, at: snap(best))
                    return
                }
            }
        }
        bench.placeNewPart(id, at: snap(best))
    }

    private func partDrag(_ id: Int) -> some Gesture {
        DragGesture(minimumDistance: 6 / camera.scale, coordinateSpace: .named(canvasSpace))
            .updating($drag) { value, state, _ in
                guard bench.selectedTerminal == nil else { return }
                let ids = selectedParts.contains(id) ? selectedParts : [id]
                state = bench.movement(of: ids, by: value.translation)
            }
            .onEnded { value in
                guard !dragCancelled, bench.selectedTerminal == nil else { return }
                let ids = selectedParts.contains(id) ? selectedParts : [id]
                bench.moveParts(bench.movement(of: ids, by: value.translation))
                selectedParts = ids
                bench.selectWire(nil)
                canvasFocused = true
            }
    }

    private let clipboardType = NSPasteboard.PasteboardType("com.cmos4000simulator.workbench-selection")
    private var canCopySelection: Bool {
        !selectedParts.isEmpty && placement == nil && drag == nil && bench.selectedTerminal == nil
    }
    private var canPasteSelection: Bool {
        placement == nil && drag == nil && bench.selectedTerminal == nil
    }

    private func handleEditShortcut(_ key: String) -> Bool {
        guard canvasFocused, !placingProbe, !showingLibrary, editingResistance == nil,
              editingCapacitance == nil, editingOscillator == nil, importFile == nil else { return false }
        switch key {
        case "c":
            guard canCopySelection, let data = try? bench.copyParts(selectedParts).encoded() else { return false }
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setData(data, forType: clipboardType)
        case "v":
            guard canPasteSelection,
                  let data = NSPasteboard.general.data(forType: clipboardType),
                  let archive = try? JSONDecoder().decode(WorkbenchArchive.self, from: data) else { return false }
            beginPlacement(archive)
        case "d":
            guard canCopySelection, let archive = try? bench.copyParts(selectedParts) else { return false }
            beginPlacement(archive)
        case "delete":
            guard canPasteSelection else { return false }
            if bench.selectedWireID != nil {
                bench.removeSelectedWire()
            } else {
                guard !selectedParts.isEmpty else { return false }
                bench.removeParts(selectedParts)
                selectedParts.removeAll()
            }
        default:
            return false
        }
        return true
    }

    private func beginPlacement(_ archive: WorkbenchArchive) {
        guard let circuit = try? archive.makeCircuit(), !circuit.parts.isEmpty else { return }
        endProbePlacement()
        var pinLocations: [WorkbenchTerminal: CGPoint] = [:]
        let outlines = circuit.parts.map { part in
            let position = circuit.positions[part.id] ?? CGPoint(x: 20, y: 20)
            let turns = circuit.rotations[part.id, default: 0]
            let geometry = SchematicPartGeometry(part: part, turns: turns, appearance: bench.componentAppearance)
            let imported = part.importedSymbol != nil
            for pin in geometry.pins.keys {
                pinLocations[WorkbenchTerminal(partID: part.id, pinNumber: pin)] =
                    geometry.location(of: pin, at: position, turns: turns, imported: imported)
            }
            let center = geometry.canvasOrigin(at: position, imported: imported)
            let size = turns.isMultiple(of: 2) ? geometry.size
                : CGSize(width: geometry.size.height, height: geometry.size.width)
            return CGRect(x: center.x - size.width / 2, y: center.y - size.height / 2,
                          width: size.width, height: size.height)
        }
        func location(_ endpoint: WorkbenchTerminal) -> CGPoint? {
            endpoint.isJunction ? archive.junctions[endpoint.pinNumber] : pinLocations[endpoint]
        }
        let routes = circuit.wires.compactMap { wire -> [CGPoint]? in
            guard let first = location(wire.first), let second = location(wire.second),
                  wire.isDrawn(from: first, to: second) else { return nil }
            return wire.route(from: first, to: second)
        }
        let bounds = outlines.reduce(CGRect.null) { $0.union($1) }
        placementPointer = nil
        placement = Placement(archive: archive, anchor: bounds.center, outlines: outlines, routes: routes)
        canvasFocused = true
    }

    private func placementOffset(_ placement: Placement, at point: CGPoint) -> CGPoint {
        let world = camera.worldPoint(at: point)
        return snap(CGPoint(x: world.x - placement.anchor.x, y: world.y - placement.anchor.y))
    }

    private func placementLayer(_ placement: Placement) -> some View {
        Canvas { context, _ in
            let point = placementPointer ?? CGRect(origin: .zero, size: viewportSize).center
            let delta = placementOffset(placement, at: point)
            var world = context
            world.translateBy(x: camera.origin.x, y: camera.origin.y)
            world.scaleBy(x: camera.scale, y: camera.scale)
            world.translateBy(x: delta.x, y: delta.y)
            let colour = Color.accentColor
            for route in placement.routes {
                world.stroke(wirePath(route), with: .color(colour), lineWidth: 1.5)
            }
            for outline in placement.outlines {
                world.fill(Path(outline), with: .color(colour.opacity(0.15)))
                world.stroke(Path(outline), with: .color(colour),
                             style: StrokeStyle(lineWidth: 1.5, dash: [5, 3]))
            }
        }
        .contentShape(Rectangle())
        .onContinuousHover { phase in
            if case .active(let point) = phase { placementPointer = point }
        }
        .gesture(SpatialTapGesture().onEnded { tap in
            let delta = placementOffset(placement, at: tap.location)
            if let ids = try? bench.pasteParts(placement.archive, by: CGSize(width: delta.x, height: delta.y)) {
                selectedParts = ids
            }
            self.placement = nil
            canvasFocused = true
        })
        .accessibilityHidden(true)
    }

    private func displayedPinLocations() -> [WorkbenchTerminal: CGPoint] {
        bench.parts.reduce(into: [:]) { result, part in
            let turns = bench.rotations[part.id, default: 0]
            let layout = SchematicPartGeometry(part: part, turns: turns, appearance: bench.componentAppearance)
            let position = displayedPosition(of: part.id)
            for number in layout.pins.keys {
                result[WorkbenchTerminal(partID: part.id, pinNumber: number)] =
                    layout.location(of: number, at: position, turns: turns, imported: part.importedSymbol != nil)
            }
        }
    }

    private func pinMarkers(at locations: [WorkbenchTerminal: CGPoint], worldOrigin: CGPoint) -> some View {
        let explicitNoConnects = Set(bench.parts.flatMap { part in
            (part.importedSymbol?.noConnectPins ?? []).map { WorkbenchTerminal(partID: part.id, pinNumber: $0) }
        })
        return Canvas { context, _ in
            var context = context
            context.translateBy(x: -worldOrigin.x, y: -worldOrigin.y)
            for (terminal, point) in locations {
                if bench.showsOpenPinMarker(terminal, explicitNoConnect: explicitNoConnects.contains(terminal)) {
                    let ring = CGRect(x: point.x - 2.5, y: point.y - 2.5, width: 5, height: 5)
                    context.stroke(Path(ellipseIn: ring), with: .color(Color(red: 0.65, green: 0, blue: 0)), lineWidth: 1)
                }
                if selectedFinding?.target == .pin(terminal) {
                    let radius = 11 / camera.scale
                    let ring = CGRect(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2)
                    context.fill(Path(ellipseIn: ring), with: .color(.orange.opacity(0.25)))
                    context.stroke(Path(ellipseIn: ring), with: .color(.orange), lineWidth: 2.5 / camera.scale)
                }
                let selected = bench.selectedTerminal == terminal
                if selected || (bench.wiringEnabled && bench.hoveredTerminal == terminal) {
                    let ring = CGRect(x: point.x - 4.5, y: point.y - 4.5, width: 9, height: 9)
                    context.stroke(Path(ellipseIn: ring), with: .color(.accentColor.opacity(selected ? 1 : 0.65)),
                                   lineWidth: 1.2)
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func displayedJunctions(movement: Workbench.Movement?) -> [Int: CGPoint] {
        guard let movement else { return bench.junctions }
        var junctions = bench.junctions
        for id in movement.junctions { junctions[id] = junctions[id].map(movement.translate) }
        return junctions
    }

    private func wireLayer(anchors: [CanvasItem: Anchor<CGRect>], pinLocations: [WorkbenchTerminal: CGPoint],
                           movement: Workbench.Movement?, worldOrigin: CGPoint) -> some View {
        GeometryReader { geometry in
            let junctions = displayedJunctions(movement: movement)
            let location: (WorkbenchTerminal) -> CGPoint? = { endpoint in
                endpoint.isJunction ? junctions[endpoint.pinNumber] : pinLocations[endpoint]
            }
            let locations = pinLocations.merging(Dictionary(uniqueKeysWithValues: junctions.map {
                (WorkbenchTerminal.junction($0.key), $0.value)
            })) { current, _ in current }
            let routes = canvasWires(at: locations, movement: movement)
            let visibleWires = routes.filter { $0.points.count > 1 }.map(\.wire)
            let visibleIDs = Set(visibleWires.map(\.id))
            let pinContacts = bench.wires.filter {
                $0.sourceRoute == .pinAttachment && !visibleIDs.contains($0.id)
            }
            let dots = bench.junctionDots(visible: visibleWires, pinContacts: pinContacts, at: junctions)

            let partBounds = anchors.compactMap { key, anchor -> (Int, CGRect)? in
                guard case .part(let id) = key else { return nil }
                return (id, geometry[anchor].offsetBy(dx: worldOrigin.x, dy: worldOrigin.y))
            }

            let bounds = measuredBounds(parts: partBounds.map(\.1),
                                        routes: routes.map(\.path), marks: bench.schematicMarks)

            ZStack {
                Canvas { context, _ in
                    var context = context
                    context.translateBy(x: -worldOrigin.x, y: -worldOrigin.y)
                    for route in routes {
                        let selected = route.wire.id == bench.selectedWireID
                        if selected {
                            context.stroke(route.path, with: .color(.accentColor.opacity(0.75)),
                                           style: StrokeStyle(lineWidth: max(5, 5 / camera.scale),
                                                              lineCap: .round, lineJoin: .round))
                        }
                        drawWire(route.path, colour: route.wire.colour, in: context)
                    }

                    if case .wire(let id) = selectedFinding?.target,
                       let route = routes.first(where: { $0.wire.id == id }) {
                        context.stroke(route.path, with: .color(.orange),
                                       style: StrokeStyle(lineWidth: 4 / camera.scale, lineCap: .round, lineJoin: .round))
                    }

                    for point in dots {
                        let dot = schematicJunction(at: point)
                        context.fill(dot, with: .color(.primary))
                        context.stroke(dot, with: .color(colourScheme == .dark ? .black : .white), lineWidth: 0.8)
                    }

                    for mark in bench.schematicMarks {
                        switch mark.kind {
                        case .label:
                            if let text = mark.text {
                                context.draw(Text(text).font(.system(size: 10, design: .monospaced)).foregroundStyle(.primary),
                                             at: CGPoint(x: mark.position.x + 2, y: mark.position.y - 2), anchor: .bottomLeading)
                            }
                        case .noConnect:
                            context.stroke(schematicCross(at: mark.position), with: .color(.blue), lineWidth: 1.3)
                        case .junction:
                            break // Junction dots follow the current wire graph.
                        }
                    }

                    if let selected = bench.selectedTerminal, let start = location(selected) {
                        var bends = bench.pendingBends
                        if let hovered = bench.hoveredTerminal, let endpoint = location(hovered) {
                            bends.append(endpoint)
                        } else if let pointerLocation {
                            bends.append(snap(camera.worldPoint(at: pointerLocation)))
                        }
                        let path = wirePath(WorkbenchWire.gridRoute(from: start, through: bends))
                        drawWire(path, colour: bench.newWireColour, in: context, dash: [5, 3])
                    }
                }
                .allowsHitTesting(false)

                ForEach(routes, id: \.wire.id) { route in
                    let hitArea = StrokeStyle(lineWidth: 12 / camera.scale, lineCap: .round, lineJoin: .round)
                    Color.clear
                        .contentShape(route.path.offsetBy(dx: -worldOrigin.x, dy: -worldOrigin.y).strokedPath(hitArea))
                        .gesture(SpatialTapGesture().onEnded { tap in
                            let worldClick = CGPoint(x: tap.location.x + worldOrigin.x, y: tap.location.y + worldOrigin.y)
                            if bench.selectedTerminal == nil {
                                selectWire(route.wire.id)
                            } else {
                                let overlapping = routes.contains { other in
                                    guard other.wire.id != route.wire.id,
                                          other.path.strokedPath(StrokeStyle(lineWidth: 4 / camera.scale)).contains(worldClick)
                                    else { return false }
                                    let shared = [route.wire.first, route.wire.second].filter {
                                        $0 == other.wire.first || $0 == other.wire.second
                                    }
                                    return !shared.contains {
                                        guard let point = location($0) else { return false }
                                        return hypot(point.x - worldClick.x, point.y - worldClick.y) <= 6 / camera.scale
                                    }
                                }
                                if !overlapping {
                                    connect(to: route.wire, points: route.points, near: worldClick)
                                }
                            }
                        })
                        .contextMenu { wireContextMenu(route.wire) }
                }
            }
            .accessibilityHidden(true)
            .onChange(of: Dictionary(uniqueKeysWithValues: partBounds), initial: true) { _, bounds in
                occupiedBounds = bounds
            }
            .onChange(of: bounds, initial: true) { _, bounds in circuitBounds = bounds }
        }
    }


    private func beginProbePlacement(moving channel: Int? = nil) {
        if placingProbe && channel == nil {
            endProbePlacement()
            return
        }
        endProbePlacement()
        guard channel != nil || bench.nextScopeChannel != nil else {
            probeMessage = "All channels occupied · Click a marker to move it or right-click to remove it"
            return
        }
        bench.cancelWire()
        bench.wiringEnabled = false
        placement = nil
        movingProbe = channel
        placingProbe = true
        canvasFocused = true
    }

    private func endProbePlacement() {
        placingProbe = false
        movingProbe = nil
        probePointer = nil
        probeMessage = nil
    }

    private struct CanvasWire {
        let wire: WorkbenchWire
        let points: [CGPoint]
        let path: Path
    }

    private func drawWire(_ path: Path, colour: WireColour, in context: GraphicsContext, dash: [CGFloat] = []) {
        if colour == .yellow || (colour == .black && colourScheme == .dark) {
            let outline: Color = colour == .yellow ? Color(white: 0.35) : Color(white: 0.72)
            context.stroke(path, with: .color(outline), style: StrokeStyle(lineWidth: 2.8, lineJoin: .round, dash: dash))
        }
        context.stroke(path, with: .color(colour.stroke),
                       style: StrokeStyle(lineWidth: 1.5, lineJoin: .round, dash: dash))
    }

    private func canvasWires(at locations: [WorkbenchTerminal: CGPoint],
                             movement: Workbench.Movement?) -> [CanvasWire] {
        let wires = movement.map { bench.wires.map($0.wire) } ?? bench.wires
        return wires.compactMap { wire in
            guard let first = locations[wire.first], let second = locations[wire.second],
                  wire.isDrawn(from: first, to: second) else { return nil }
            let points = wire.route(from: first, to: second)
            return CanvasWire(wire: wire, points: points, path: wirePath(points))
        }
    }

    private func probeLayer(pins: [WorkbenchTerminal: CGPoint], movement: Workbench.Movement?) -> some View {
        let locations = pins.merging(Dictionary(uniqueKeysWithValues: displayedJunctions(movement: movement).map {
            (WorkbenchTerminal.junction($0.key), $0.value)
        })) { current, _ in current }
        let routes = canvasWires(at: locations, movement: movement)
        let target = probePointer.flatMap { probeTarget(at: $0, terminals: locations, routes: routes) }
        let net = target.flatMap { bench.scopeNet(for: $0) }
        let highlighted = net.map { net in routes.filter { bench.circuitNet(at: $0.wire.first) === net } } ?? []
        var markers: [(channel: Int, anchor: CGPoint, center: CGPoint)] = []
        for channel in bench.scopeProbes.keys.sorted() {
            guard let probe = bench.scopeProbes[channel],
                  let point = probeLocation(probe, terminals: locations, routes: routes) else { continue }
            let anchor = camera.screenPoint(at: point)
            var center = CGPoint(x: anchor.x + 10, y: anchor.y - 12)
            while markers.contains(where: { hypot($0.center.x - center.x, $0.center.y - center.y) < 17 }) {
                center.x += 18
            }
            markers.append((channel, anchor, center))
        }
        return ZStack {
            if placingProbe {
                Color.clear
                    .contentShape(Rectangle())
                    .onContinuousHover { phase in
                        if case .active(let point) = phase { probePointer = point }
                        else { probePointer = nil }
                    }
                    .gesture(SpatialTapGesture().onEnded { tap in
                        guard let probe = probeTarget(at: tap.location, terminals: locations, routes: routes),
                              bench.placeScopeProbe(probe, moving: movingProbe) else {
                            probeMessage = "Choose a pin, junction or unambiguous wire segment"
                            return
                        }
                        endProbePlacement()
                    })
                    .accessibilityHidden(true)
            }
            Canvas { context, _ in
                var world = context
                world.translateBy(x: camera.origin.x, y: camera.origin.y)
                world.scaleBy(x: camera.scale, y: camera.scale)
                for route in highlighted {
                    world.stroke(route.path, with: .color(.accentColor),
                                 style: StrokeStyle(lineWidth: 4 / camera.scale, lineCap: .round, lineJoin: .round))
                }
                if let target, let point = probeLocation(target, terminals: locations, routes: routes) {
                    let screen = camera.screenPoint(at: point)
                    let ring = CGRect(x: screen.x - 6, y: screen.y - 6, width: 12, height: 12)
                    context.stroke(Path(ellipseIn: ring), with: .color(.accentColor), lineWidth: 2)
                }
                for marker in markers {
                    var lead = Path()
                    lead.move(to: marker.anchor)
                    lead.addLine(to: marker.center)
                    context.stroke(lead, with: .color(oscilloscopeChannelColours[marker.channel]), lineWidth: 1.5)
                }
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            if !placingProbe && placement == nil {
                ForEach(markers, id: \.channel) { marker in
                    Button { beginProbePlacement(moving: marker.channel) } label: {
                        probeBadge(marker.channel)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Move CH\(marker.channel + 1) probe")
                    .help("Click to move CH\(marker.channel + 1). Right-click to remove.")
                    .contextMenu {
                        Button("Move CH\(marker.channel + 1)") { beginProbePlacement(moving: marker.channel) }
                        Button("Remove CH\(marker.channel + 1)", role: .destructive) {
                            bench.assignScopeProbe(nil, to: marker.channel)
                            endProbePlacement()
                        }
                    }
                    .position(marker.center)
                }
            } else {
                ForEach(markers, id: \.channel) { marker in
                    probeBadge(marker.channel).position(marker.center)
                }
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
        }
    }

    private func probeBadge(_ channel: Int) -> some View {
        Text("\(channel + 1)")
            .font(.system(size: 10, weight: .bold, design: .monospaced))
            .foregroundStyle(.black)
            .frame(width: 16, height: 16)
            .background(oscilloscopeChannelColours[channel], in: .circle)
            .overlay { Circle().strokeBorder(.black.opacity(0.65)) }
    }

    private func probeTarget(at screenPoint: CGPoint, terminals: [WorkbenchTerminal: CGPoint],
                             routes: [CanvasWire]) -> ScopeProbe? {
        let point = camera.worldPoint(at: screenPoint)
        let radius = 6 / camera.scale
        let nearby = terminals.compactMap { terminal, position -> (WorkbenchTerminal, CGFloat)? in
            let distance = hypot(point.x - position.x, point.y - position.y)
            guard distance <= radius, !terminal.isJunction || bench.circuitNet(at: terminal) != nil else { return nil }
            return (terminal, distance)
        }.sorted { $0.1 < $1.1 }
        if let (terminal, distance) = nearby.first {
            let net = bench.circuitNet(at: terminal)
            guard !nearby.dropFirst().contains(where: {
                abs($0.1 - distance) < 0.01 && (net == nil || bench.circuitNet(at: $0.0) !== net)
            }) else { return nil }
            return net == nil ? .pin(terminal) : .netPin(terminal)
        }
        let hits = routes.compactMap { route -> (CanvasWire, RouteProjection)? in
            guard let projection = project(point, onto: route.points), projection.distance <= radius else { return nil }
            return (route, projection)
        }.sorted { $0.1.distance < $1.1.distance }
        guard let (route, hit) = hits.first else { return nil }
        let net = bench.circuitNet(at: route.wire.first)
        guard !hits.dropFirst().contains(where: {
            abs($0.1.distance - hit.distance) < 2 / camera.scale && bench.circuitNet(at: $0.0.wire.first) !== net
        }) else { return nil }
        let prefix = Array(route.points.prefix(hit.segment + 1)) + [hit.point]
        return .wirePoint(id: route.wire.id, fraction: routeLength(prefix) / routeLength(route.points))
    }

    private func probeLocation(_ probe: ScopeProbe, terminals: [WorkbenchTerminal: CGPoint],
                               routes: [CanvasWire]) -> CGPoint? {
        if let terminal = probe.terminal { return terminals[terminal] }
        guard let points = routes.first(where: { $0.wire.id == probe.wireID })?.points else {
            return bench.wires.first(where: { $0.id == probe.wireID }).flatMap { terminals[$0.first] }
        }
        let fraction: Double
        if case .wirePoint(_, let stored) = probe { fraction = stored }
        else { fraction = 0.5 }
        var remaining = routeLength(points) * fraction
        for (start, end) in zip(points, points.dropFirst()) {
            let length = hypot(end.x - start.x, end.y - start.y)
            if length > 0 && remaining <= length {
                return CGPoint(x: start.x + (end.x - start.x) * remaining / length,
                               y: start.y + (end.y - start.y) * remaining / length)
            }
            remaining -= length
        }
        return points.last
    }

    private func routeLength(_ points: [CGPoint]) -> CGFloat {
        zip(points, points.dropFirst()).reduce(0) { $0 + hypot($1.1.x - $1.0.x, $1.1.y - $1.0.y) }
    }

    private func measuredBounds(parts: [CGRect], routes: [Path], marks: [SchematicMark]) -> CGRect? {
        let markBounds = marks.map { mark in
            if let text = mark.text {
                let font = NSFont.monospacedSystemFont(ofSize: 10, weight: .regular)
                let size = (text as NSString).size(withAttributes: [.font: font])
                return CGRect(x: mark.position.x + 2, y: mark.position.y - 2 - size.height,
                              width: size.width, height: size.height)
            }
            return CGRect(x: mark.position.x - 5, y: mark.position.y - 5, width: 10, height: 10)
        }
        let bounds = (parts + routes.map { $0.boundingRect.insetBy(dx: -2, dy: -2) } + markBounds)
            .reduce(CGRect.null) { $0.union($1) }
        return bounds.isNull ? nil : bounds
    }

    private var canvasBackground: some View {
        Canvas { context, size in
            var world = context
            world.translateBy(x: camera.origin.x, y: camera.origin.y)
            world.scaleBy(x: camera.scale, y: camera.scale)
            drawGrid(in: world, viewport: size)

            if let selectionBox {
                let path = Path(selectionBox)
                context.fill(path, with: .color(.accentColor.opacity(0.12)))
                context.stroke(path, with: .color(.accentColor), lineWidth: 1)
            }
        }
        .contentShape(Rectangle())
        .accessibilityHidden(true)
        .onContinuousHover { phase in
            switch phase {
            case .active(let point):
                bench.hoveredTerminal = nil
                if bench.selectedTerminal != nil { pointerLocation = point }
            case .ended:
                pointerLocation = nil
            }
        }
        .onChange(of: bench.selectedTerminal) { _, _ in pointerLocation = nil }
        .gesture(SpatialTapGesture().onEnded { tap in
            if bench.selectedTerminal != nil {
                bench.addBend(at: snap(camera.worldPoint(at: tap.location)))
            } else {
                bench.selectWire(nil)
                selectedParts.removeAll()
                canvasFocused = true
            }
        })
        .simultaneousGesture(
            DragGesture(minimumDistance: 5)
                .updating($selectionBox) { value, box, _ in
                    guard bench.selectedTerminal == nil else { return }
                    box = selectionRectangle(from: value.startLocation, to: value.location)
                }
                .onEnded { value in
                    guard bench.selectedTerminal == nil else { return }
                    let box = selectionRectangle(from: camera.worldPoint(at: value.startLocation),
                                                 to: camera.worldPoint(at: value.location))
                    selectedParts = Set(occupiedBounds.keys.filter { id in
                        occupiedBounds[id].map(box.intersects) ?? false
                    })
                    bench.selectWire(nil)
                    canvasFocused = true
                }
        )
    }

    private func drawGrid(in context: GraphicsContext, viewport: CGSize) {
        var dots = Path()
        let min = camera.worldPoint(at: .zero)
        let max = camera.worldPoint(at: CGPoint(x: viewport.width, y: viewport.height))
        for x in stride(from: (min.x / gridSpacing).rounded(.down) * gridSpacing, through: max.x, by: gridSpacing) {
            for y in stride(from: (min.y / gridSpacing).rounded(.down) * gridSpacing, through: max.y, by: gridSpacing) {
                dots.addEllipse(in: CGRect(x: x - 0.65, y: y - 0.65, width: 1.3, height: 1.3))
            }
        }
        context.fill(dots, with: .color(.secondary.opacity(0.34)))
    }

    private func selectionRectangle(from start: CGPoint, to end: CGPoint) -> CGRect {
        CGRect(x: min(start.x, end.x), y: min(start.y, end.y),
               width: abs(end.x - start.x), height: abs(end.y - start.y))
    }

    private func wirePath(_ points: [CGPoint]) -> Path {
        Path { $0.addLines(points) }
    }

    private typealias RouteProjection = (point: CGPoint, segment: Int, distance: CGFloat)

    private func project(_ click: CGPoint, onto points: [CGPoint]) -> RouteProjection? {
        var closest: RouteProjection?
        for index in points.indices.dropLast() {
            let start = points[index]
            let end = points[index + 1]
            guard start != end else { continue }
            let dx = end.x - start.x
            let dy = end.y - start.y
            let fraction = ((click.x - start.x) * dx + (click.y - start.y) * dy) / (dx * dx + dy * dy)
            let t = min(1, max(0, fraction))
            let projection = CGPoint(x: start.x + dx * t, y: start.y + dy * t)
            let distance = hypot(projection.x - click.x, projection.y - click.y)
            if closest == nil || distance < closest!.distance { closest = (projection, index, distance) }
        }
        return closest
    }

    private func connect(to wire: WorkbenchWire, points: [CGPoint], near click: CGPoint) {
        guard let closest = project(click, onto: points),
              let first = points.first, let last = points.last else { return }
        let a = points[closest.segment]
        let b = points[closest.segment + 1]
        let snapped = snap(closest.point)
        let point: CGPoint
        if a.y == b.y {
            point = CGPoint(x: min(max(snapped.x, min(a.x, b.x)), max(a.x, b.x)), y: a.y)
        } else {
            point = CGPoint(x: a.x, y: min(max(snapped.y, min(a.y, b.y)), max(a.y, b.y)))
        }
        if point == first || hypot(click.x - first.x, click.y - first.y) <= 6 / camera.scale {
            bench.select(wire.first)
        } else if point == last || hypot(click.x - last.x, click.y - last.y) <= 6 / camera.scale {
            bench.select(wire.second)
        } else {
            bench.joinWire(wire.id, at: point,
                           before: Array(points.dropFirst().prefix(closest.segment)),
                           after: Array(points.dropFirst(closest.segment + 1).dropLast()),
                           splitFraction: routeLength(Array(points.prefix(closest.segment + 1)) + [point]) / routeLength(points))
        }
    }

    @ViewBuilder
    private func partCard(_ part: WorkbenchPart, geometry: SchematicPartGeometry) -> some View {
        if let drawing = part.importedSymbol {
            ImportedSymbolView(drawing: drawing, part: part, bench: bench, isSelected: selectedParts.contains(part.id),
                               select: { selectPart(part.id) }, rotate: rotationAction(for: part.id),
                               editResistance: { editingResistance = part.component as? Resistor },
                               editCapacitance: { editingCapacitance = part.component as? Capacitor })
        } else {
            standardPartCard(part, packageLayout: geometry.packageLayout)
        }
    }

    private func standardPartCard(_ part: WorkbenchPart, packageLayout: MultiUnitSchematicLayout?) -> some View {
        let isSelected = selectedParts.contains(part.id)
        let select = { selectPart(part.id) }
        let rotate = rotationAction(for: part.id)

        return Group {
            if bench.componentAppearance == .physicalDIP, let package = DIPPackage(part: part) {
                DIPPackageView(package: package, part: part, bench: bench, isSelected: isSelected,
                               select: select, rotate: rotate)
            } else if let packageLayout {
                ZStack(alignment: .topLeading) {
                    ForEach(packageLayout.units) { unit in
                        SchematicSymbolView(symbol: unit.symbol, part: unit.part, bench: bench,
                                            isSelected: isSelected, select: select, rotate: rotate)
                            .offset(x: unit.origin.x, y: unit.origin.y)
                    }
                }
                .frame(width: packageLayout.size.width, height: packageLayout.size.height, alignment: .topLeading)
            } else if let symbol = part.librarySymbol(for: bench.componentAppearance) {
                SchematicSymbolView(symbol: symbol, part: part, bench: bench, isSelected: isSelected, select: select,
                                    rotate: rotate,
                                    editResistance: (part.component as? Resistor).map { resistor in { editingResistance = resistor } },
                                    editCapacitance: (part.component as? Capacitor).map { capacitor in { editingCapacitance = capacitor } },
                                    editFrequency: part.component is CXO_DIP8 ? { editingOscillator = part } : nil)
            } else if let source = part.component as? WorkbenchSwitch {
                LogicSwitchSymbol(partID: part.id, source: source, bench: bench, isSelected: isSelected, select: select, rotate: rotate)
            } else if let power = part.component as? WorkbenchPower {
                PowerRailSymbol(partID: part.id, rail: power.rail, bench: bench,
                                isSelected: isSelected, select: select, rotate: rotate)
            } else if let clock = part.component as? WorkbenchClock {
                ClockSourceSymbol(part: part, source: clock, bench: bench, isSelected: isSelected, select: select, rotate: rotate)
            } else if part.component is WorkbenchLED {
                LEDIndicatorSymbol(partID: part.id, bench: bench, isSelected: isSelected, select: select, rotate: rotate)
            }
        }
        .overlay(alignment: .topTrailing) {
            if let warning = bench.powerStates[part.id]?.warning ?? bench.timingIssues[part.id] {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .help(warning)
                    .accessibilityLabel(warning)
            }
        }
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .transformAnchorPreference(key: CanvasBounds.self, value: .bounds) { bounds, anchor in
            bounds[.part(part.id)] = anchor
        }
    }

    private func selectWire(_ id: Int) {
        selectedParts.removeAll()
        bench.selectWire(id)
        canvasFocused = true
    }

    private func selectPart(_ id: Int, extending: Bool = workbenchShiftPressed) {
        if extending {
            if selectedParts.remove(id) == nil { selectedParts.insert(id) }
        } else {
            selectedParts = [id]
        }
        bench.selectWire(nil)
        canvasFocused = true
    }

    private func rotationAction(for id: Int) -> (Int) -> Void {
        { steps in
            selectPart(id, extending: false)
            bench.rotatePart(id, by: steps)
        }
    }


}

struct PartRotationCommands: View {
    let rotate: (Int) -> Void

    var body: some View {
        Button("Rotate 90° Clockwise") { rotate(1) }
        Button("Rotate 90° Counterclockwise") { rotate(-1) }
        Divider()
    }
}
