import AppKit
import SwiftUI
import UniformTypeIdentifiers

private extension CGRect {
    var center: CGPoint { CGPoint(x: midX, y: midY) }
}

enum CanvasItem: Hashable {
    case part(Int)
    case terminal(WorkbenchTerminal)
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

struct WorkbenchView: View {
    @State private var bench = Workbench()
    @State private var scopeWindow = WorkbenchScopeWindow()
    @State private var scopeDocked = false
    @AppStorage("workbenchShowsWireList") private var showsWireList = false
    @State private var showingLibrary = false
    @State private var openingFile = false
    @State private var openingImport = false
    @State private var importFile: CircuitImportFile?

    @State private var confirmingClear = false
    @State private var savingFile = false
    @State private var exportArchive: WorkbenchArchive?
    @State private var fileError: String?
    @State private var editingResistance: Resistor?
    @State private var editingCapacitance: Capacitor?
    @State private var camera = WorkbenchViewport()
    @State private var circuitBounds: CGRect?
    @State private var viewportSize: CGSize = .zero
    @State private var occupiedBounds: [Int: CGRect] = [:]
    @State private var selectedParts: Set<Int> = []
    @State private var pointerLocation: CGPoint?
    @GestureState private var selectionBox: CGRect?
    @FocusState private var canvasFocused: Bool
    @GestureState private var drag: PartDrag?

    private struct PartIdentity: Hashable {
        let id: Int
        let component: ObjectIdentifier
    }

    private struct PartDrag {
        let id: Int
        let translation: CGSize
    }

    private let canvasSpace = "WorkbenchCanvas"

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            fileBar
            Divider()

            HStack(spacing: 0) {
                toolStrip
                Divider()
                workbenchArea
                wireList
                Divider()
                instrumentStrip
            }

            if scopeDocked {
                Divider()
                OscilloscopeView(bench: bench, voltageRange: $scopeWindow.voltageRange,
                                 placementLabel: "Undock", changePlacement: showScope)
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
        .confirmationDialog("Clear the workbench?", isPresented: $confirmingClear) {
            Button("Clear Workbench", role: .destructive) {
                bench.clear()
                selectedParts.removeAll()
            }
        }
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
        .fileImporter(isPresented: $openingFile, allowedContentTypes: [.data], onCompletion: openCircuit)
        .sheet(item: $importFile) { file in
            CircuitImportView(file: file, hasExistingCircuit: !bench.parts.isEmpty, powerMode: bench.powerMode) { replacing in
                if let first = bench.importCircuit(file.preview, replacing: replacing) {
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
                }
            }
        }
        .fileExporter(isPresented: $savingFile, document: exportArchive,
                      contentType: .json, defaultFilename: "Circuit.json") { result in
            if case .failure(let error) = result { fileError = error.localizedDescription }
        }
        .alert("Workbench File", isPresented: Binding(
            get: { fileError != nil },
            set: { if !$0 { fileError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(fileError ?? "")
        }
        .sheet(isPresented: $showingLibrary) {
            ComponentLibraryView(bench: bench, placeNewPart: placeNewPart)
        }
        .sheet(item: $editingCapacitance) { capacitor in
            CapacitanceEditor(capacitor: capacitor) { value in
                bench.setCapacitance(value, for: capacitor)
            }
        }
        .sheet(item: $editingResistance) { resistor in
            ResistanceEditor(resistor: resistor) { value, unit in
                bench.setResistance(value, unit: unit, for: resistor)
            }
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
            let visibleCorner = camera.worldPoint(at: CGPoint(x: viewport.size.width, y: viewport.size.height))
            let extent = canvasExtent
            canvasBackground
                .overlay(alignment: .topLeading) {
                    canvas
                        .frame(width: max(visibleCorner.x, extent.width),
                               height: max(visibleCorner.y, extent.height), alignment: .topLeading)
                        .backgroundPreferenceValue(CanvasBounds.self) { anchors in
                            wireLayer(anchors: anchors)
                        }
                        .coordinateSpace(name: canvasSpace)
                        .scaleEffect(camera.scale, anchor: .topLeading)
                        .offset(x: camera.origin.x, y: camera.origin.y)
                }
                .overlay {
                    if bench.parts.isEmpty {
                        Button("Add Part…", systemImage: "plus") { showingLibrary = true }
                            .buttonStyle(.bordered)
                    }
                }
                .background {
                    WorkbenchNavigation(
                        pan: { camera.pan(x: $0, y: $1) },
                        zoom: { camera.zoom(to: camera.scale * $0, around: $1) }
                    )
                }
                .clipped()
                .contentShape(Rectangle())
                .onGeometryChange(for: CGSize.self) { $0.size } action: { viewportSize = $0 }
                .focusable()
                .focused($canvasFocused)
                .focusEffectDisabled()
                .onKeyPress(keys: [.delete, .deleteForward], phases: .down) { _ in
                    guard bench.selectedTerminal == nil else { return .ignored }
                    if bench.selectedWireID != nil {
                        bench.removeSelectedWire()
                        return .handled
                    }
                    guard !selectedParts.isEmpty else { return .ignored }
                    bench.removeParts(selectedParts)
                    selectedParts.removeAll()
                    return .handled
                }
        }
    }

    private var canvas: some View {
        ZStack(alignment: .topLeading) {
            ForEach(bench.parts) { part in
                let origin = bench.positions[part.id] ?? CGPoint(x: 20, y: 20)
                let translation = drag?.id == part.id ? drag?.translation ?? .zero : .zero
                let position = movedPosition(from: origin, by: translation)
                partCard(part)
                    .id(PartIdentity(id: part.id, component: ObjectIdentifier(part.component)))
                    .simultaneousGesture(partDrag(part.id, origin: origin))
                    .offset(x: position.x, y: position.y)
                    .zIndex(drag?.id == part.id ? 1 : 0)
            }
        }
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
            Button("Save…", systemImage: "square.and.arrow.down", action: saveCircuit)
            Button("Import…", systemImage: "square.and.arrow.down.on.square") { chooseFile(importing: true) }
            Spacer()
        }
        .disabled(commands == nil)
        .controlSize(.small)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
    }

    private var toolStrip: some View {
        VStack(spacing: 4) {
            stripButton("Select", icon: "cursorarrow", active: !bench.wiringEnabled) {
                setWiringEnabled(false)
            }
            .keyboardShortcut("v", modifiers: [])
            .accessibilityAddTraits(bench.wiringEnabled ? [] : .isSelected)
            stripButton("Wire", icon: "point.topleft.down.to.point.bottomright.curvepath", active: bench.wiringEnabled) {
                setWiringEnabled(true)
            }
            .keyboardShortcut("w", modifiers: [])
            .accessibilityAddTraits(bench.wiringEnabled ? .isSelected : [])
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
        if !enabled { bench.cancelWire() }
        bench.wiringEnabled = enabled
        canvasFocused = true
    }

    private var statusBar: some View {
        let status = !bench.isStable ? "Did not settle"
            : bench.clockIsBehind ? "Clock behind"
            : bench.hasRunningClocks ? "Running" : "Ready"
        return HStack(spacing: 10) {
            if let selected = bench.selectedTerminal {
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
            Button(Double(camera.scale).formatted(.percent.precision(.fractionLength(0))), action: resetZoom)
                .buttonStyle(.borderless)
                .monospacedDigit()
                .accessibilityLabel("Reset zoom to 100 percent")
                .help("Reset zoom to 100%. Pinch or ⌘-scroll to zoom, or scroll to pan.")
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
        guard !showingLibrary, editingResistance == nil, editingCapacitance == nil,
              !openingFile, !savingFile, importFile == nil, !confirmingClear else { return nil }
        return WorkbenchActions(
            open: { chooseFile(importing: false) }, save: saveCircuit,
            importCircuit: { chooseFile(importing: true) }, clear: { confirmingClear = true },
            undo: bench.undo, redo: bench.redo, rotate: rotateSelected, oscilloscope: toggleScope,
            wireList: $showsWireList,
            zoomIn: { zoom(by: 1.25) }, zoomOut: { zoom(by: 0.8) },
            resetZoom: resetZoom, fitCircuit: fitCircuit,
            powerMode: Binding(get: { bench.powerMode }, set: bench.setPowerMode),
            canUndo: bench.canUndo, canRedo: bench.canRedo, canRotate: selectedParts.count == 1,
            hasCircuit: !bench.parts.isEmpty, zoom: camera.scale
        )
    }

    private func rotateSelected(_ steps: Int) {
        if selectedParts.count == 1, let id = selectedParts.first {
            rotationAction(for: id)(steps)
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
                            .contextMenu {
                                Button("Remove Wire", role: .destructive) { bench.removeWire(wire.id) }
                            }
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

    private func saveCircuit() {
        do {
            exportArchive = try WorkbenchArchive(bench: bench)
            savingFile = true
        } catch {
            fileError = error.localizedDescription
        }
    }

    private func chooseFile(importing: Bool) {
        openingImport = importing
        openingFile = true
    }

    private func openCircuit(_ result: Result<URL, Error>) {
        do {
            let url = try result.get()
            let accessing = url.startAccessingSecurityScopedResource()
            defer { if accessing { url.stopAccessingSecurityScopedResource() } }
            if openingImport {
                let text = try String(contentsOf: url, encoding: .utf8)
                let preview = try CircuitImportPreview.read(text, filenameExtension: url.pathExtension)
                importFile = CircuitImportFile(name: url.lastPathComponent, preview: preview)
                return
            }
            let archive = try JSONDecoder().decode(WorkbenchArchive.self, from: Data(contentsOf: url))
            try bench.open(archive)
            camera = WorkbenchViewport()
            selectedParts.removeAll()
        } catch {
            fileError = error.localizedDescription
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

    private func movedPosition(from origin: CGPoint, by translation: CGSize) -> CGPoint {
        guard translation != .zero else { return origin }
        return snap(CGPoint(x: max(0, origin.x + translation.width),
                            y: max(0, origin.y + translation.height)))
    }

    private func partDrag(_ id: Int, origin: CGPoint) -> some Gesture {
        DragGesture(minimumDistance: 6 / camera.scale, coordinateSpace: .named(canvasSpace))
            .updating($drag) { value, state, _ in
                state = PartDrag(id: id, translation: value.translation)
            }
            .onEnded { value in
                bench.movePart(id, from: origin, to: movedPosition(from: origin, by: value.translation))
                selectPart(id)
            }
    }

    private func wireLayer(anchors: [CanvasItem: Anchor<CGRect>]) -> some View {
        GeometryReader { geometry in
            let location: (WorkbenchTerminal) -> CGPoint? = { endpoint in
                if endpoint.isJunction { return bench.junctions[endpoint.pinNumber] }
                return anchors[.terminal(endpoint)].map { geometry[$0].center }
            }
            let routes = bench.wires.compactMap { wire -> (wire: WorkbenchWire, points: [CGPoint], path: Path)? in
                guard let first = location(wire.first), let second = location(wire.second),
                      wire.isDrawn(from: first, to: second) else { return nil }
                let points = wire.route(from: first, to: second)
                return (wire, points, wirePath(points))
            }
            let visibleWires = routes.filter { $0.points.count > 1 }.map(\.wire)
            let visibleIDs = Set(visibleWires.map(\.id))
            let pinContacts = bench.wires.filter {
                $0.sourceRoute == .pinAttachment && !visibleIDs.contains($0.id)
            }
            let dots = bench.junctionDots(visible: visibleWires, pinContacts: pinContacts)

            let partBounds = anchors.compactMap { key, anchor -> (Int, CGRect)? in
                guard case .part(let id) = key else { return nil }
                return (id, geometry[anchor])
            }

            let bounds = measuredBounds(parts: partBounds.map(\.1),
                                        routes: routes.map(\.path), marks: bench.schematicMarks)

            ZStack {
                Canvas { context, _ in
                    for route in routes {
                        let selected = route.wire.id == bench.selectedWireID
                        context.stroke(route.path, with: .color(selected ? .accentColor : .green),
                                       lineWidth: selected ? 3 : 1.5)
                    }

                    for point in dots {
                        context.fill(schematicJunction(at: point), with: .color(.green))
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
                        if let pointerLocation {
                            bends.append(snap(canvasPoint(at: pointerLocation)))
                        }
                        let path = wirePath(WorkbenchWire.gridRoute(from: start, through: bends))
                        context.stroke(path, with: .color(.green),
                                       style: StrokeStyle(lineWidth: 1.5, dash: [5, 3]))
                        let marker = CGRect(x: start.x - 6, y: start.y - 6, width: 12, height: 12)
                        context.stroke(Path(ellipseIn: marker), with: .color(.green), lineWidth: 1.5)
                    }
                }
                .allowsHitTesting(false)

                ForEach(routes, id: \.wire.id) { route in
                    let hitArea = StrokeStyle(lineWidth: 12 / camera.scale, lineCap: .round, lineJoin: .round)
                    Color.clear
                        .contentShape(route.path.strokedPath(hitArea))
                        .gesture(SpatialTapGesture().onEnded { tap in
                            if bench.selectedTerminal == nil {
                                selectWire(route.wire.id)
                            } else {
                                let overlapping = routes.contains { other in
                                    guard other.wire.id != route.wire.id,
                                          other.path.strokedPath(StrokeStyle(lineWidth: 4 / camera.scale)).contains(tap.location)
                                    else { return false }
                                    let shared = [route.wire.first, route.wire.second].filter {
                                        $0 == other.wire.first || $0 == other.wire.second
                                    }
                                    return !shared.contains {
                                        guard let point = location($0) else { return false }
                                        return hypot(point.x - tap.location.x, point.y - tap.location.y) <= 6 / camera.scale
                                    }
                                }
                                if !overlapping {
                                    connect(to: route.wire, points: route.points, near: tap.location)
                                }
                            }
                        })
                        .contextMenu {
                            Button("Remove Wire", role: .destructive) { bench.removeWire(route.wire.id) }
                        }
                }
            }
            .accessibilityHidden(true)
            .onChange(of: Dictionary(uniqueKeysWithValues: partBounds), initial: true) { _, bounds in
                occupiedBounds = bounds
            }
            .onChange(of: bounds, initial: true) { _, bounds in circuitBounds = bounds }
        }
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
                if bench.selectedTerminal != nil { pointerLocation = point }
            case .ended:
                pointerLocation = nil
            }
        }
        .onChange(of: bench.selectedTerminal) { _, _ in pointerLocation = nil }
        .gesture(SpatialTapGesture().onEnded { tap in
            if bench.selectedTerminal != nil {
                bench.addBend(at: snap(canvasPoint(at: tap.location)))
            } else {
                bench.selectWire(nil)
                selectedParts.removeAll()
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

    private func canvasPoint(at point: CGPoint) -> CGPoint {
        let world = camera.worldPoint(at: point)
        return CGPoint(x: max(0, world.x), y: max(0, world.y))
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

    private func connect(to wire: WorkbenchWire, points: [CGPoint], near click: CGPoint) {
        var closest: (point: CGPoint, segment: Int, distance: CGFloat)?
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
        guard let closest, let first = points.first, let last = points.last else { return }
        let a = points[closest.segment]
        let b = points[closest.segment + 1]
        let snapped = snap(closest.point)
        let point: CGPoint
        if wire.sourceRoute == .straight {
            point = closest.point
        } else if a.y == b.y {
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
                           after: Array(points.dropFirst(closest.segment + 1).dropLast()))
        }
    }

    @ViewBuilder
    private func partCard(_ part: WorkbenchPart) -> some View {
        if let drawing = part.importedSymbol {
            ImportedSymbolView(drawing: drawing, part: part, bench: bench, isSelected: selectedParts.contains(part.id),
                               select: { selectPart(part.id) }, rotate: rotationAction(for: part.id),
                               editResistance: { editingResistance = part.component as? Resistor },
                               editCapacitance: { editingCapacitance = part.component as? Capacitor })
        } else {
            standardPartCard(part)
        }
    }

    private func standardPartCard(_ part: WorkbenchPart) -> some View {
        let isSelected = selectedParts.contains(part.id)
        let select = { selectPart(part.id) }
        let rotate = rotationAction(for: part.id)

        return VStack(alignment: .leading, spacing: 10) {
            if let placement = part.unitPlacement,
               let symbol = KiCadSymbol.chipUnits[placement.kind]?[placement.unit.id] {
                SchematicSymbolView(symbol: symbol, part: part, bench: bench, isSelected: isSelected, select: select, rotate: rotate)
            } else if let header = part.component as? PinHeader, let symbol = KiCadSymbol.pinHeaders[header.kind] {
                SchematicSymbolView(symbol: symbol, part: part, bench: bench, isSelected: isSelected, select: select, rotate: rotate)
            } else if let kind = CounterChip.kind(of: part.component), let symbol = KiCadSymbol.additionalCounters[kind] {
                SchematicSymbolView(symbol: symbol, part: part, bench: bench, isSelected: isSelected, select: select, rotate: rotate)
            } else if let device = part.component as? AnalogSwitch, let symbol = KiCadSymbol.analogSwitches[device.kind] {
                SchematicSymbolView(symbol: symbol, part: part, bench: bench, isSelected: isSelected, select: select, rotate: rotate)
            } else if part.component is NE555, let symbol = KiCadSymbol.ne555 {
                SchematicSymbolView(symbol: symbol, part: part, bench: bench, isSelected: isSelected, select: select, rotate: rotate)
                    .help("NE555: digital inputs or standard RC astable/monostable wiring. CONT may be open or bypassed to GND.")
            } else if part.component is CD4510, let symbol = KiCadSymbol.counter {
                SchematicSymbolView(symbol: symbol, part: part, bench: bench, isSelected: isSelected, select: select, rotate: rotate)
            } else if part.component is CD4060, let symbol = KiCadSymbol.counter4060 {
                SchematicSymbolView(symbol: symbol, part: part, bench: bench, isSelected: isSelected, select: select, rotate: rotate)
            } else if let driver = part.component as? SevenSegmentDriver, let symbol = KiCadSymbol.displayDrivers[driver.kind] {
                SchematicSymbolView(symbol: symbol, part: part, bench: bench, isSelected: isSelected, select: select, rotate: rotate)
            } else if part.component is MAN72A, let symbol = KiCadSymbol.man72a {
                SchematicSymbolView(symbol: symbol, part: part, bench: bench, isSelected: isSelected, select: select, rotate: rotate)
            } else if part.component is MAN74A, let symbol = KiCadSymbol.man74a {
                SchematicSymbolView(symbol: symbol, part: part, bench: bench, isSelected: isSelected, select: select, rotate: rotate)
            } else if part.component is NPN2N3904, let symbol = KiCadSymbol.npn2N3904 {
                SchematicSymbolView(symbol: symbol, part: part, bench: bench, isSelected: isSelected, select: select, rotate: rotate)
            } else if let capacitor = part.component as? Capacitor, let symbol = KiCadSymbol.capacitors[capacitor.kind] {
                SchematicSymbolView(symbol: symbol, part: part, bench: bench, isSelected: isSelected, select: select, rotate: rotate, editCapacitance: { editingCapacitance = capacitor })
            } else if let resistor = part.component as? Resistor, let symbol = KiCadSymbol.smallResistor {
                SchematicSymbolView(symbol: symbol, part: part, bench: bench,
                                    isSelected: isSelected, select: select, rotate: rotate, editResistance: { editingResistance = resistor })
            } else if part.component is Diode1N4148, let symbol = KiCadSymbol.diode1N4148 {
                SchematicSymbolView(symbol: symbol, part: part, bench: bench, isSelected: isSelected, select: select, rotate: rotate)
            } else if let source = part.component as? WorkbenchSwitch {
                LogicSwitchSymbol(partID: part.id, source: source, bench: bench, isSelected: isSelected, select: select, rotate: rotate)
            } else if let power = part.component as? WorkbenchPower {
                PowerRailSymbol(partID: part.id, rail: power.rail, bench: bench,
                                isSelected: isSelected, select: select, rotate: rotate)
            } else if let clock = part.component as? WorkbenchClock {
                ClockSourceSymbol(part: part, source: clock, bench: bench, isSelected: isSelected, select: select, rotate: rotate)
            } else if part.component is WorkbenchLED {
                LEDIndicatorSymbol(partID: part.id, bench: bench, isSelected: isSelected, select: select, rotate: rotate)
            } else {
                partHeading(part)
                    .font(.headline)
                    .foregroundStyle(isSelected ? Color.schematicSelectionInk : Color.primary)
                    .contentShape(Rectangle())
                    .onTapGesture(perform: select)
                    .contextMenu {
                        PartRotationCommands(rotate: rotate)
                        if let capacitor = part.component as? Capacitor {
                            Button("Set Capacitance…") { editingCapacitance = capacitor }
                        }
                        if let resistor = part.component as? Resistor {
                            Button("Set Resistance…") { editingResistance = resistor }
                        }
                        Button("Remove Part", role: .destructive) { bench.removePart(part.id) }
                    }

                ForEach(part.pins.values.sorted(by: { $0.number < $1.number })) { pin in
                    let terminal = WorkbenchTerminal(partID: part.id, pinNumber: pin.number)
                    pinRow(pin, terminal: terminal)
                }
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
        .padding(4)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .transformAnchorPreference(key: CanvasBounds.self, value: .bounds) { bounds, anchor in
            bounds[.part(part.id)] = anchor
        }
        .rotationEffect(.degrees(Double(bench.rotations[part.id, default: 0] * 90)))
        .padding(12)
        .frame(width: 270)
    }

    private func selectWire(_ id: Int) {
        selectedParts.removeAll()
        bench.selectWire(id)
        canvasFocused = true
    }

    private func selectPart(_ id: Int) {
        selectedParts = [id]
        bench.selectWire(nil)
        canvasFocused = true
    }

    private func rotationAction(for id: Int) -> (Int) -> Void {
        { steps in
            selectPart(id)
            bench.rotatePart(id, by: steps)
        }
    }

    @ViewBuilder
    private func partHeading(_ part: WorkbenchPart) -> some View {
        switch part.component {
        case is WorkbenchPullUp:
            Label(part.label, systemImage: "arrow.up")
        default:
            Label(part.label, systemImage: "cpu")
        }
    }

    private func pinRow(_ pin: Pin, terminal: WorkbenchTerminal) -> some View {
        let state = bench.readings[terminal] ?? .highImpedance
        let selected = bench.selectedTerminal == terminal

        return HStack(spacing: 6) {
            Button {
                bench.select(terminal)
            } label: {
                Image(systemName: selected ? "circle.inset.filled" : "circle")
                    .frame(width: 20, height: 18)
                    .anchorPreference(key: CanvasBounds.self, value: .bounds) { [.terminal(terminal): $0] }
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.accentColor)
            .accessibilityLabel(bench.label(for: terminal))
            .accessibilityAddTraits(selected ? .isSelected : [])

            Text("\(pin.number)")
                .font(.caption.monospacedDigit())
                .frame(width: 18, alignment: .trailing)
            Text(pin.name)
                .font(.caption)
            Spacer()
            Text(state.description)
                .font(.caption2.monospaced())
                .foregroundStyle(.secondary)
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
