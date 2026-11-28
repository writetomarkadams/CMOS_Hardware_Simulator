
enum PinDirection {
    case input
    case output
    case bidirectional
    case power
    case noConnect
}

// The drivers visible at the winning resolution tier, or potential drivers
// on a floating clock. An explicit publication distinguishes equal symbols.
struct ClockDriveObservation: Equatable {
    let level: LogicState
    let publication: UInt64
}

final class Pin: Identifiable {
    var tracksClockProvenance = false
    var clockDriveObservations: [ObjectIdentifier: ClockDriveObservation] = [:]
    private(set) var clockPublication: UInt64 = 0

    /// Publish an independently identified source event before settling. This
    /// distinguishes equal symbols at separate resolution boundaries. During
    /// component evaluation, use drive() as usual.
    func publishClockDrive(_ level: LogicState) {
        drive(level)
        clockPublication += 1
    }

    let number: Int
    let name: String
    let direction: PinDirection
    let isWeakDriver: Bool
    var drivenSupplyRail: SupplyRail?
    private(set) var supplyRail: SupplyRail?
    private(set) var dcVoltage: Double?

    // The logic level this pin actively drives.
    // HIGH-Z means it is not driving the net.
    var driveState: LogicState = .highImpedance

    // The logic level observed at this pin.
    // Eventually supplied by the connected Net.
    var state: LogicState = .highImpedance

    // The level driven directly on this net, before weak drivers are considered.
    private(set) var strongState: LogicState

    var id: Int { number }

    init(
        number: Int,
        name: String,
        direction: PinDirection,
        state: LogicState = .highImpedance,
        isWeakDriver: Bool = false
    ) {
        self.number = number
        self.name = name
        self.direction = direction
        self.state = state
        self.strongState = state
        self.isWeakDriver = isWeakDriver
    }

    // Update the logic level driven by this pin.
    func drive(_ newState: LogicState) {
        guard direction == .output ||
              direction == .bidirectional ||
              direction == .power else {
            return
        }

        driveState = newState
    }

    // Update the logic level observed at this pin.
    func receive(_ newState: LogicState, strongState: LogicState? = nil, supplyRail: SupplyRail? = nil, dcVoltage: Double? = nil) {
        state = newState
        clockDriveObservations = [:]
        self.supplyRail = supplyRail
        self.dcVoltage = dcVoltage
        self.strongState = strongState ?? newState
    }
}

