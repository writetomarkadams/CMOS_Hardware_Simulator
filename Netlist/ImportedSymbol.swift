import Foundation

/// Embedded geometry retained in the workbench archive, in local Y-down millimetres.
struct ImportedSymbol: Codable {
    static let scale: CGFloat = 6

    struct Graphic: Codable {
        enum Kind: String, Codable { case line, circle, arc }
        let kind: Kind
        let points: [CGPoint]
        let fill: String
    }

    struct Pin: Codable, Identifiable {
        let id: Int
        let name: String
        let style: String
        let position: CGPoint
        let end: CGPoint
    }

    struct Field: Codable {
        let key: String
        let offset: CGPoint
        let angle: Double
        let size: CGFloat
        let justify: String?
    }

    let fields: [Field]?
    let graphics: [Graphic]
    let pins: [Pin]
    let value: String
    var mirror: String?
    var noConnectPins: [Int] = []
    // Local model offsets for newly imported pins, before mirror and rotation.
    // Older archives retain their original artwork scale.
    var gridPinOffsets: [Int: CGPoint]?
    var drawingScale: CGFloat { gridPinOffsets == nil ? Self.scale : SchematicSymbolGeometry.scale }

    func localReflection(_ offset: CGPoint, turns: Int) -> CGPoint {
        let odd = turns % 2 != 0
        let flipX = mirror == (odd ? "x" : "y")
        let flipY = mirror == (odd ? "y" : "x")
        return CGPoint(x: flipX ? -offset.x : offset.x, y: flipY ? -offset.y : offset.y)
    }

    func pinOffset(_ pin: Pin, turns: Int) -> CGPoint {
        let offset = gridPinOffsets?[pin.id] ?? WorkbenchWire.snap(CGPoint(
            x: pin.position.x * drawingScale, y: pin.position.y * drawingScale
        ))
        return localReflection(offset, turns: turns)
    }

    init(elements: [KiCadExpression], value: String, fields: [Field]) {
        self.value = value
        self.fields = fields
        graphics = elements.compactMap { node in
            let fill = node.child("fill")?.child("type")?[1] ?? "none"
            switch node[0] {
            case "rectangle":
                guard let a = node.child("start")?.point, let b = node.child("end")?.point else { return nil }
                return Graphic(kind: .line, points: [a, CGPoint(x: a.x, y: b.y), b, CGPoint(x: b.x, y: a.y), a], fill: fill)
            case "polyline":
                guard let points = node.child("pts")?.children.compactMap(\.point), points.count > 1 else { return nil }
                return Graphic(kind: .line, points: points, fill: fill)
            case "arc":
                guard let a = node.child("start")?.point, let m = node.child("mid")?.point, let b = node.child("end")?.point else { return nil }
                return Graphic(kind: .arc, points: [a, m, b], fill: fill)
            case "circle":
                guard let center = node.child("center")?.point, let radius = node.child("radius")?[1].flatMap(Double.init),
                      radius > 0 else { return nil }
                return Graphic(kind: .circle, points: [CGPoint(x: center.x - radius, y: center.y - radius),
                                                        CGPoint(x: center.x + radius, y: center.y + radius)], fill: fill)
            default: return nil
            }
        }
        var numbers: Set<Int> = []
        pins = elements.compactMap { node in
            guard node[0] == "pin", let number = node.child("number")?[1].flatMap(Int.init),
                  let at = node.child("at"), let point = at.point,
                  let angle = at[3].flatMap(Double.init), angle.isFinite, angle.truncatingRemainder(dividingBy: 90) == 0,
                  let length = node.child("length")?[1].flatMap(Double.init), length >= 0,
                  numbers.insert(number).inserted else { return nil }
            let direction = (Int(angle.truncatingRemainder(dividingBy: 360) / 90) + 4) % 4
            let offset = [CGPoint(x: length, y: 0), CGPoint(x: 0, y: -length),
                          CGPoint(x: -length, y: 0), CGPoint(x: 0, y: length)][direction]
            let name = node.child("name")?[1] ?? ""
            return Pin(id: number, name: name == "~" ? "" : name, style: node[2] ?? "line", position: point,
                       end: CGPoint(x: point.x + offset.x, y: point.y + offset.y))
        }
    }

    var isValid: Bool {
        func valid(_ point: CGPoint) -> Bool { abs(point.x) < 2_000 && abs(point.y) < 2_000 }
        return (gridPinOffsets ?? [:]).allSatisfy { pins.map(\.id).contains($0.key) &&
            abs($0.value.x) < 20_000 && abs($0.value.y) < 20_000 && WorkbenchWire.snap($0.value) == $0.value } &&
            (mirror == nil || mirror == "x" || mirror == "y") &&
            Set(pins.map(\.id)).count == pins.count &&
            pins.allSatisfy { valid($0.position) && valid($0.end) } &&
            (fields ?? []).allSatisfy { valid($0.offset) && $0.angle.isFinite && $0.size > 0 && $0.size < 100 } &&
            graphics.allSatisfy { graphic in
                let count = graphic.points.count
                return graphic.points.allSatisfy(valid) &&
                    (graphic.kind == .arc ? count == 3 : graphic.kind == .circle ? count == 2 : count >= 2)
            }
    }

    var bounds: CGRect {
        let points = graphics.flatMap(\.points) + pins.flatMap { [$0.position, $0.end] }
        let halfWidth = (points.map { abs($0.x) }.max() ?? 0) * drawingScale + 20
        let halfHeight = (points.map { abs($0.y) }.max() ?? 0) * drawingScale + 20
        return CGRect(x: -halfWidth, y: -halfHeight, width: halfWidth * 2, height: halfHeight * 2)
    }
}
