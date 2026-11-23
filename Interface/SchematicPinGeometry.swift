import SwiftUI

/// Model units per KiCad millimetre for library symbols. One grid step is 50 mil.
struct SchematicSymbolGeometry {
    static let scale = WorkbenchWire.gridSpacing / 1.27

    let bounds: CGRect
    let padding: CGFloat
    let size: CGSize

    init(symbol: KiCadSymbol, part: WorkbenchPart) {
        // Keep the MAN74A placement and rotation pivot shared with its physical face.
        let layoutSymbol = part.component is MAN74A ? KiCadSymbol.man74a : symbol
        bounds = layoutSymbol.terminals.reduce(layoutSymbol.body) { rect, pin in
            rect.union(CGRect(origin: pin.position, size: .zero))
        }
        padding = symbol.polygon.isEmpty && !(part.component is Diode1N4148 || part.component is LED3mm) ? 20 : 30
        let labelWidth: CGFloat = symbol.isCircular || part.component is Resistor || part.component is Capacitor ? 85 : 0
        size = CGSize(width: Self.pivotAlignedSize(bounds.width * Self.scale + 2 * padding + labelWidth),
                      height: Self.pivotAlignedSize(bounds.height * Self.scale + 2 * padding))
    }

    static func pivotAlignedSize(_ length: CGFloat) -> CGFloat {
        let step = 2 * WorkbenchWire.gridSpacing
        return ceil((length - 0.000001) / step) * step
    }

    func point(_ local: CGPoint) -> CGPoint {
        // Use a grid-aligned translation so KiCad's 50 mil lattice keeps its phase.
        let origin = WorkbenchWire.snap(CGPoint(x: bounds.minX * Self.scale, y: bounds.minY * Self.scale))
        return CGPoint(x: local.x * Self.scale - origin.x + padding,
                       y: local.y * Self.scale - origin.y + padding)
    }

    func endpoint(_ pin: KiCadSymbol.Terminal) -> CGPoint {
        WorkbenchWire.snap(point(pin.position))
    }
}

/// One schematic placement with multiple symbols sharing the package's terminal IDs.
struct MultiUnitSchematicLayout {
    struct Unit: Identifiable {
        let part: WorkbenchPart
        let symbol: KiCadSymbol
        let origin: CGPoint

        var id: Int { part.unitPlacement!.unit.id }
    }

    let units: [Unit]
    let size: CGSize
    let pins: [Int: CGPoint]

    init(part: WorkbenchPart, kind: MultiUnitChip) {
        let unitParts = kind.allUnits.map { unit in
            let placement = ChipUnitPlacement(kind: kind, packageID: part.chipNumber ?? part.id, unit: unit)
            let unitPart = WorkbenchPart(id: part.id, name: part.name, component: part.component,
                                         unitPlacement: placement, chipNumber: part.chipNumber,
                                         designation: part.referenceBase)
            let symbol = unitPart.librarySymbol!
            return (part: unitPart, symbol: symbol, size: SchematicSymbolGeometry(symbol: symbol, part: unitPart).size)
        }
        let gateSizes = unitParts.prefix(kind.units.count).map(\.size)
        let gateWidth = gateSizes.map(\.width).max()!
        let gateHeight = gateSizes.map(\.height).max()!
        let powerSize = unitParts.last!.size
        let powerY = CGFloat((kind.units.count + 1) / 2) * gateHeight
        size = CGSize(width: 2 * gateWidth, height: powerY + powerSize.height)
        units = unitParts.enumerated().map { index, unit in
            let origin = index == kind.units.count
                ? CGPoint(x: gateWidth - powerSize.width / 2, y: powerY)
                : CGPoint(x: CGFloat(index % 2) * gateWidth, y: CGFloat(index / 2) * gateHeight)
            return Unit(part: unit.part, symbol: unit.symbol, origin: origin)
        }
        pins = Dictionary(uniqueKeysWithValues: units.flatMap { unit in
            let geometry = SchematicSymbolGeometry(symbol: unit.symbol, part: unit.part)
            return unit.symbol.terminals.map { pin in
                let endpoint = geometry.endpoint(pin)
                return (pin.id, CGPoint(x: endpoint.x + unit.origin.x, y: endpoint.y + unit.origin.y))
            }
        })
    }
}

struct SchematicPartGeometry {
    let size: CGSize
    let pins: [Int: CGPoint]

    let packageLayout: MultiUnitSchematicLayout?

    private let originHeight: CGFloat

    init(part: WorkbenchPart, turns: Int, appearance: ComponentAppearance = .schematic) {
        // Keep the original placement pivot for existing CD4070 circuits and DIP artwork.
        let packageKind: MultiUnitChip?
        switch part.component {
        case is CD4011: packageKind = .nand
        case is CD4027: packageKind = .jk
        case let counter as DualCounter where counter.kind == .bcd: packageKind = .dualBCD
        case is CD4070: packageKind = .xor
        case is CD4081: packageKind = .and
        case is CD40106: packageKind = .inverter
        default: packageKind = nil
        }
        let wholePackage = part.unitPlacement == nil && part.importedSymbol == nil ? packageKind : nil
        let packageOriginHeight = wholePackage == .xor
            ? part.librarySymbol.map { SchematicSymbolGeometry(symbol: $0, part: part).size.height }
            : nil
        if appearance == .schematic, let wholePackage {
            packageLayout = MultiUnitSchematicLayout(part: part, kind: wholePackage)
        } else {
            packageLayout = nil
        }
        if appearance == .physicalDIP, let package = DIPPackage(part: part) {
            size = package.size
            pins = package.endpoints
            originHeight = packageOriginHeight ?? SchematicPartGeometry(part: part, turns: turns).size.height
            return
        }
        if let drawing = part.importedSymbol {
            size = drawing.bounds.size
            originHeight = size.height
            pins = drawing.pins.reduce(into: [:]) { result, pin in
                guard part.pins[pin.id] != nil else { return }
                result[pin.id] = drawing.pinOffset(pin, turns: turns)
            }
            return
        }
        if let packageLayout {
            size = packageLayout.size
            pins = packageLayout.pins
            originHeight = packageOriginHeight ?? size.height
            return
        }
        if let symbol = part.librarySymbol(for: appearance) {
            let geometry = SchematicSymbolGeometry(symbol: symbol, part: part)
            size = geometry.size
            pins = Dictionary(uniqueKeysWithValues: symbol.terminals.map { ($0.id, geometry.endpoint($0)) })
        } else {
            let pin: CGPoint
            switch part.component {
            case let source as WorkbenchSwitch:
                size = CGSize(width: 80, height: 40)
                pin = LogicSwitchSymbol.endpoint(showsValue: source.showsValue)
            case let power as WorkbenchPower:
                size = CGSize(width: 60, height: 60)
                pin = PowerRailSymbol.endpoint(for: power.rail)
            case is WorkbenchClock:
                size = CGSize(width: 100, height: 60)
                pin = ClockSourceSymbol.endpoint
            case is WorkbenchLED:
                size = CGSize(width: 40, height: 60)
                pin = LEDIndicatorSymbol.endpoint
            default:
                preconditionFailure("Missing schematic geometry for \(part.name)")
            }
            pins = [1: pin]
        }
        originHeight = size.height
    }

    func canvasOrigin(at position: CGPoint, imported: Bool) -> CGPoint {
        let origin = WorkbenchWire.snap(position)
        if imported { return origin }
        return CGPoint(x: origin.x + 140, y: origin.y + 20 + originHeight / 2)
    }

    func location(of number: Int, at position: CGPoint, turns: Int, imported: Bool) -> CGPoint? {
        guard var offset = pins[number] else { return nil }
        let origin = canvasOrigin(at: position, imported: imported)
        if !imported {
            offset = CGPoint(x: offset.x - size.width / 2, y: offset.y - size.height / 2)
        }
        offset = offset.schematicRotated(turns)
        return CGPoint(x: origin.x + offset.x, y: origin.y + offset.y)
    }
}

extension CGPoint {
    func schematicRotated(_ turns: Int) -> CGPoint {
        switch (turns % 4 + 4) % 4 {
        case 1: CGPoint(x: -y, y: x)
        case 2: CGPoint(x: -x, y: -y)
        case 3: CGPoint(x: y, y: -x)
        default: self
        }
    }
}

extension WorkbenchPart {
    func librarySymbol(for appearance: ComponentAppearance) -> KiCadSymbol? {
        if appearance == .schematic && component is MAN74A { return .man74aSchematic }
        return librarySymbol
    }

    var librarySymbol: KiCadSymbol? {
        let symbol: KiCadSymbol?
        switch component {
        case let header as PinHeader: symbol = KiCadSymbol.pinHeaders[header.kind]
        case let device as AnalogSwitch: symbol = KiCadSymbol.analogSwitches[device.kind]
        case is NE555: symbol = KiCadSymbol.ne555
        case is CD4510: symbol = KiCadSymbol.counter
        case is CD4060: symbol = KiCadSymbol.counter4060
        case let driver as SevenSegmentDriver: symbol = KiCadSymbol.displayDrivers[driver.kind]
        case is MAN72A: symbol = KiCadSymbol.man72a
        case is MAN74A: symbol = KiCadSymbol.man74a
        case is NPN2N3904: symbol = KiCadSymbol.npn2N3904
        case let capacitor as Capacitor: symbol = KiCadSymbol.capacitors[capacitor.kind]
        case is Resistor: symbol = KiCadSymbol.smallResistor
        case is LED3mm: symbol = KiCadSymbol.led3mm
        case is Diode1N4148: symbol = KiCadSymbol.diode1N4148
        case is CXO_DIP8: symbol = KiCadSymbol.oscillatorDIP8
        case is WorkbenchClock, is WorkbenchLED, is WorkbenchSwitch, is WorkbenchPower: return nil
        default:
            if let placement = unitPlacement {
                symbol = KiCadSymbol.chipUnits[placement.kind]?[placement.unit.id]
            } else {
                symbol = CounterChip.kind(of: component).flatMap { KiCadSymbol.additionalCounters[$0] }
            }
        }
        return symbol ?? KiCadSymbol.fallback(pins: pins.values.sorted { $0.number < $1.number })
    }
}

extension EnvironmentValues {
    @Entry var schematicZoom: CGFloat = 1
}

struct SchematicPinButton: View {
    let terminal: WorkbenchTerminal
    let bench: Workbench
    var spacing: CGFloat = 20

    @Environment(\.schematicZoom) private var zoom

    static func hitSize(zoom: CGFloat, spacing: CGFloat) -> CGFloat {
        min(spacing, 16 / zoom)
    }

    var body: some View {
        let selected = bench.selectedTerminal == terminal
        let state = bench.readings[terminal] ?? .highImpedance
        let connected = bench.isTerminalConnected(terminal)
        let target = Self.hitSize(zoom: zoom, spacing: spacing)
        Button {
            bench.select(terminal)
        } label: {
            Color.clear
                .frame(width: target, height: target)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .allowsHitTesting(bench.wiringEnabled)
        .onHover { inside in
            if inside && bench.wiringEnabled {
                bench.hoveredTerminal = terminal
            } else if bench.hoveredTerminal == terminal {
                bench.hoveredTerminal = nil
            }
        }
        .onDisappear {
            if bench.hoveredTerminal == terminal { bench.hoveredTerminal = nil }
        }
        .accessibilityLabel(bench.label(for: terminal))
        .accessibilityValue(state.description)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .help("\(bench.label(for: terminal)) · \(state.description)\(connected ? " · Connected" : "")")
    }
}

func schematicPinSpacing(at point: CGPoint, among points: [CGPoint]) -> CGFloat {
    points.lazy.filter { $0 != point }
        .map { max(abs($0.x - point.x), abs($0.y - point.y)) }
        .reduce(20, min)
}

/// The first segment leaves the terminal along the pin axis. Any small
/// source-artwork adjustment stays close to the symbol.
func schematicPinLead(from endpoint: CGPoint, toward original: CGPoint, trim: CGFloat, inward: CGVector) -> [CGPoint] {
    let start = CGPoint(x: endpoint.x + inward.dx * trim, y: endpoint.y + inward.dy * trim)
    let axis = inward.dx != 0 ? CGPoint(x: start.x, y: original.y) : CGPoint(x: original.x, y: start.y)
    return [start, axis]
}
