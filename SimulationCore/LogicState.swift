enum LogicState: Equatable, CustomStringConvertible {
    case low
    case high
    case highImpedance
    case undefined

    var description: String {
        switch self {
        case .low:           return "LOW"
        case .high:          return "HIGH"
        case .highImpedance: return "HIGH-Z"
        case .undefined:     return "UNDEFINED"
        }
    }
}

extension LogicState {
    var inverted: LogicState {
        switch self {
        case .low: .high
        case .high: .low
        case .highImpedance, .undefined: .undefined
        }
    }
}
