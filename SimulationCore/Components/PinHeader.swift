enum PinHeaderKind: Int, CaseIterable, Codable {
    case two = 2
    case three = 3
    case eight = 8

    var pinNumbers: ClosedRange<Int> { 1...rawValue }
    var schematicSymbol: String { "Conn_01x0\(rawValue)" }
    var name: String { "1×\(rawValue) Pin Header" }
    var footprint: String { "Connector_PinHeader_2.54mm:PinHeader_1x0\(rawValue)_P2.54mm_Vertical" }
}

final class PinHeader: LogicComponent {
    let kind: PinHeaderKind
    let pins: [Int: Pin]

    init(_ kind: PinHeaderKind) {
        self.kind = kind
        pins = Dictionary(uniqueKeysWithValues: kind.pinNumbers.map { number in
            (number, Pin(number: number, name: "Pin \(number)", direction: .input))
        })
    }

    // The header exposes each net at its own contact and supplies no drive.
    func evaluate() {}
}
