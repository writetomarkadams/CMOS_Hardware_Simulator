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
    @State private var showingLibrary = false
    @State private var openingFile = false
    @State private var savingFile = false
    @State private var exportArchive: WorkbenchArchive?
    @State private var fileError: String?
    @State private var editingResistance: Resistor?
    @State private var canvasOffset: CGPoint = .zero
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
    private let viewportSpace = "WorkbenchViewport"

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Button("Add Part…", systemImage: "plus") { showingLibrary = true }
                    .keyboardShortcut("a", modifiers: [])
                    .help("Open the component library (A)")
                    .disabled(showingLibrary)
                Button("Rotate", systemImage: "rotate.right") {
                    if selectedParts.count == 1, let id = selectedParts.first {
                        rotationAction(for: id)(1)
                    }
                }
                .keyboardShortcut("r", modifiers: .command)
                .help("Rotate the selected component 90° clockwise (⌘R)")
                .disabled(selectedParts.count != 1 || showingLibrary || editingResistance != nil)

                Button("Undo", systemImage: "arrow.uturn.backward") { bench.undo() }
                    .keyboardShortcut("z", modifiers: .command)
                    .disabled(!bench.canUndo || showingLibrary || editingResistance != nil)
                Button("Redo", systemImage: "arrow.uturn.forward") { bench.redo() }
                    .keyboardShortcut("z", modifiers: [.command, .shift])
                    .disabled(!bench.canRedo || showingLibrary || editingResistance != nil)

                Picker("Power", selection: Binding(
                    get: { bench.powerMode }, set: { bench.setPowerMode($0) }
                )) {
                    ForEach(PowerMode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .fixedSize()
                .help("Automatic assumes a 5 V supply. Explicit requires wired supply rails.")
                Spacer()
                Button("Open…", systemImage: "folder") { openingFile = true }
                    .labelStyle(.iconOnly)
                    .help("Open Workbench File (⌘O)")
                    .keyboardShortcut("o", modifiers: .command)
                Button("Save…", systemImage: "square.and.arrow.down", action: saveCircuit)
                    .labelStyle(.iconOnly)
                    .help("Save Workbench File (⌘S)")
                    .keyboardShortcut("s", modifiers: .command)
                Button("Clear Workbench") {
                    bench.clear()
                    selectedParts.removeAll()
                }
                .disabled(bench.parts.isEmpty)
            }
            .padding()

            Divider()

            if bench.parts.isEmpty {
                ContentUnavailableView(
                    "Empty Workbench",
                    systemImage: "cpu",
                    description: Text("Add a chip or logic switch to begin.")
                )
                .frame(maxHeight: .infinity)
            } else {
                HStack {
                    if let selected = bench.selectedTerminal {
                        Text("Connecting \(bench.label(for: selected)). Click the canvas to bend, or a pin or wire to finish.")
                        Button("Cancel", action: bench.cancelWire)
                    } else {
                        Text("Click a pin to start a wire. Drag empty canvas to select components.")
                    }
                    Spacer()
                    if !bench.isStable {
                        Label("Circuit did not settle", systemImage: "exclamationmark.triangle")
                    } else if bench.clockIsBehind {
                        Label("Simulation is running slower than the clock setting", systemImage: "timer")
                    }
                }
                .font(.callout)
                .frame(height: 24)
                .padding()

                GeometryReader { viewport in
                    ScrollView([.horizontal, .vertical]) {
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
                        .frame(width: max(viewport.size.width, canvasExtent.width),
                               height: max(viewport.size.height, canvasExtent.height),
                               alignment: .topLeading)
                        .coordinateSpace(name: canvasSpace)
                        .onGeometryChange(for: CGPoint.self) { geometry in
                            geometry.frame(in: .named(viewportSpace)).origin
                        } action: { origin in
                            canvasOffset = CGPoint(x: max(0, -origin.x), y: max(0, -origin.y))
                        }
                        .backgroundPreferenceValue(CanvasBounds.self) { anchors in
                            wireLayer(anchors: anchors)
                        }
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
                    .coordinateSpace(name: viewportSpace)
                    .onGeometryChange(for: CGSize.self) { $0.size } action: { viewportSize = $0 }
                }
            }

            if !bench.wires.isEmpty {
                Divider()
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(bench.wires) { wire in
                            HStack {
                                Button {
                                    bench.cancelWire()
                                    selectWire(wire.id)
                                } label: {
                                    Text("\(bench.label(for: wire.first)) ↔ \(bench.label(for: wire.second))")
                                }
                                .buttonStyle(.plain)
                                .accessibilityAddTraits(bench.selectedWireID == wire.id ? .isSelected : [])
                                .contextMenu {
                                    Button("Remove Wire", role: .destructive) { bench.removeWire(wire.id) }
                                }
                                Spacer()
                            }
                        }
                    }
                    .padding(12)
                }
                .frame(maxHeight: 120)
            }
        }
        .frame(minWidth: 680, minHeight: 460)
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
        .fileImporter(isPresented: $openingFile, allowedContentTypes: [.json], onCompletion: openCircuit)
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
        .sheet(item: $editingResistance) { resistor in
            ResistanceEditor(resistor: resistor) { value, unit in
                bench.setResistance(value, unit: unit, for: resistor)
            }
        }
        .onChange(of: bench.parts.map(\.id)) { _, ids in
            selectedParts.formIntersection(ids)
            if ids.isEmpty {
                canvasOffset = .zero
                occupiedBounds.removeAll()
            }
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

    private func openCircuit(_ result: Result<URL, Error>) {
        do {
            let url = try result.get()
            let accessing = url.startAccessingSecurityScopedResource()
            defer { if accessing { url.stopAccessingSecurityScopedResource() } }
            let archive = try JSONDecoder().decode(WorkbenchArchive.self, from: Data(contentsOf: url))
            try bench.open(archive)
            selectedParts.removeAll()
        } catch {
            fileError = error.localizedDescription
        }
    }

    private let gridSpacing: CGFloat = 10

    private func snap(_ point: CGPoint) -> CGPoint {
        CGPoint(x: (point.x / gridSpacing).rounded() * gridSpacing,
                y: (point.y / gridSpacing).rounded() * gridSpacing)
    }

    private var canvasExtent: CGSize {
        var size = CGSize(width: 1400, height: 900)
        for part in bench.parts {
            let origin = bench.positions[part.id] ?? CGPoint(x: 20, y: 20)
            size.width = max(size.width, origin.x + 300)
            size.height = max(size.height, origin.y + 550)
        }
        for bend in bench.wires.flatMap(\.bends) + bench.pendingBends + Array(bench.junctions.values) {
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
        let minX = canvasOffset.x + 20
        let minY = canvasOffset.y + 20
        let maxX = max(minX, canvasOffset.x + viewportSize.width - 270)
        let height = min(290, max(60, viewportSize.height - 32))
        let maxY = max(minY, canvasOffset.y + viewportSize.height - height)
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
        DragGesture(minimumDistance: 6, coordinateSpace: .named(canvasSpace))
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
                guard let first = location(wire.first), let second = location(wire.second) else { return nil }
                let points = wirePoints(start: first, bends: wire.bends, end: second)
                return (wire, points, wirePath(points))
            }
            let branches = Dictionary(grouping: bench.wires.flatMap { [$0.first, $0.second] }.filter(\.isJunction),
                                      by: \.pinNumber)

            let partBounds = anchors.compactMap { key, anchor -> (Int, CGRect)? in
                guard case .part(let id) = key else { return nil }
                return (id, geometry[anchor])
            }

            ZStack {
                Rectangle()
                    .fill(.clear)
                    .contentShape(Rectangle())
                    .onContinuousHover { phase in
                        switch phase {
                        case .active(let location):
                            if bench.selectedTerminal != nil {
                                pointerLocation = location
                            }
                        case .ended:
                            pointerLocation = nil
                        }
                    }
                    .onChange(of: bench.selectedTerminal) { _, _ in
                        pointerLocation = nil
                    }
                    .gesture(SpatialTapGesture().onEnded { tap in
                        if bench.selectedTerminal != nil {
                            bench.addBend(at: snap(tap.location))
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
                                let box = selectionRectangle(from: value.startLocation, to: value.location)
                                selectedParts = Set(partBounds.compactMap { id, bounds in
                                    box.intersects(bounds) ? id : nil
                                })
                                bench.selectWire(nil)
                                canvasFocused = true
                            }
                    )

                Canvas { context, size in
                    drawGrid(in: context, size: size)
                    if let selectionBox {
                        let path = Path(selectionBox)
                        context.fill(path, with: .color(.accentColor.opacity(0.12)))
                        context.stroke(path, with: .color(.accentColor), lineWidth: 1)
                    }
                    for route in routes {
                        let selected = route.wire.id == bench.selectedWireID
                        context.stroke(route.path, with: .color(selected ? .accentColor : .green),
                                       lineWidth: selected ? 3 : 1.5)
                    }

                    for (id, point) in bench.junctions where branches[id, default: []].count >= 3 {
                        context.fill(Path(ellipseIn: CGRect(x: point.x - 3.5, y: point.y - 3.5, width: 7, height: 7)),
                                     with: .color(.green))
                    }

                    if let selected = bench.selectedTerminal, let start = location(selected) {
                        var bends = bench.pendingBends
                        if let pointerLocation {
                            bends.append(snap(pointerLocation))
                        }
                        let path = wirePath(wirePoints(start: start, bends: bends))
                        context.stroke(path, with: .color(.green),
                                       style: StrokeStyle(lineWidth: 1.5, dash: [5, 3]))
                        let marker = CGRect(x: start.x - 6, y: start.y - 6, width: 12, height: 12)
                        context.stroke(Path(ellipseIn: marker), with: .color(.green), lineWidth: 1.5)
                    }
                }
                .allowsHitTesting(false)

                ForEach(routes, id: \.wire.id) { route in
                    let hitArea = StrokeStyle(lineWidth: 12, lineCap: .round, lineJoin: .round)
                    Color.clear
                        .contentShape(route.path.strokedPath(hitArea))
                        .gesture(SpatialTapGesture().onEnded { tap in
                            if bench.selectedTerminal == nil {
                                selectWire(route.wire.id)
                            } else {
                                connect(to: route.wire, points: route.points, near: tap.location)
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
        }
    }

    private func drawGrid(in context: GraphicsContext, size: CGSize) {
        var dots = Path()
        let minX = max(0, canvasOffset.x - gridSpacing)
        let minY = max(0, canvasOffset.y - gridSpacing)
        let maxX = min(size.width, canvasOffset.x + viewportSize.width + gridSpacing)
        let maxY = min(size.height, canvasOffset.y + viewportSize.height + gridSpacing)
        for x in stride(from: (minX / gridSpacing).rounded(.down) * gridSpacing, through: maxX, by: gridSpacing) {
            for y in stride(from: (minY / gridSpacing).rounded(.down) * gridSpacing, through: maxY, by: gridSpacing) {
                dots.addEllipse(in: CGRect(x: x - 0.65, y: y - 0.65, width: 1.3, height: 1.3))
            }
        }
        context.fill(dots, with: .color(.secondary.opacity(0.34)))
    }

    private func selectionRectangle(from start: CGPoint, to end: CGPoint) -> CGRect {
        CGRect(x: min(start.x, end.x), y: min(start.y, end.y),
               width: abs(end.x - start.x), height: abs(end.y - start.y))
    }

    private func wirePoints(start: CGPoint, bends: [CGPoint], end: CGPoint? = nil) -> [CGPoint] {
        var points = [start]
        var previous = start
        for bend in bends {
            previous = orthogonalPoint(from: previous, toward: bend)
            points.append(previous)
        }
        if let end {
            points.append(orthogonalPoint(from: previous, toward: end))
            points.append(end)
        }
        return points
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
            let horizontal = start.y == end.y
            let projection = horizontal
                ? CGPoint(x: min(max(click.x, min(start.x, end.x)), max(start.x, end.x)), y: start.y)
                : CGPoint(x: start.x, y: min(max(click.y, min(start.y, end.y)), max(start.y, end.y)))
            let distance = hypot(projection.x - click.x, projection.y - click.y)
            if closest == nil || distance < closest!.distance { closest = (projection, index, distance) }
        }
        guard let closest, let first = points.first, let last = points.last else { return }
        let a = points[closest.segment]
        let b = points[closest.segment + 1]
        let snapped = snap(closest.point)
        let point = a.y == b.y
            ? CGPoint(x: min(max(snapped.x, min(a.x, b.x)), max(a.x, b.x)), y: a.y)
            : CGPoint(x: a.x, y: min(max(snapped.y, min(a.y, b.y)), max(a.y, b.y)))
        if point == first || hypot(click.x - first.x, click.y - first.y) <= 6 {
            bench.select(wire.first)
        } else if point == last || hypot(click.x - last.x, click.y - last.y) <= 6 {
            bench.select(wire.second)
        } else {
            bench.joinWire(wire.id, at: point,
                           before: Array(points[1...closest.segment + 1].dropLast()),
                           after: Array(points.dropFirst(closest.segment + 1).dropLast()))
        }
    }

    private func orthogonalPoint(from start: CGPoint, toward target: CGPoint) -> CGPoint {
        if abs(target.x - start.x) >= abs(target.y - start.y) {
            return CGPoint(x: target.x, y: start.y)
        }
        return CGPoint(x: start.x, y: target.y)
    }

    private func partCard(_ part: WorkbenchPart) -> some View {
        let isSelected = selectedParts.contains(part.id)
        let select = { selectPart(part.id) }
        let rotate = rotationAction(for: part.id)

        return VStack(alignment: .leading, spacing: 10) {
            if let placement = part.unitPlacement,
               let symbol = KiCadSymbol.chipUnits[placement.kind]?[placement.unit.id] {
                SchematicSymbolView(symbol: symbol, part: part, bench: bench, isSelected: isSelected, select: select, rotate: rotate)
            } else if let kind = CounterChip.kind(of: part.component), let symbol = KiCadSymbol.additionalCounters[kind] {
                SchematicSymbolView(symbol: symbol, part: part, bench: bench, isSelected: isSelected, select: select, rotate: rotate)
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
            if let warning = bench.powerStates[part.id]?.warning {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .help(warning + " — connect VDD to +5V and VSS to GND.")
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
