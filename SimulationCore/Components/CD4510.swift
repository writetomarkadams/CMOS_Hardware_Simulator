
final class CD4510: LogicComponent {
    
    let pins: [Int: Pin]
    
    private var counter = BCDCountState()
    private let clockDetector = ClockEdgeDetector()
    
    var count: Int {
        counter.value
    }
    
    init() {
        pins = [
            // Parallel Enable
            1: Pin(number: 1, name: "PE", direction: .input),
            
            // BCD outputs
            2: Pin(number: 2, name: "Q4", direction: .output),
            6: Pin(number: 6, name: "Q1", direction: .output),
            11: Pin(number: 11, name: "Q2", direction: .output),
            14: Pin(number: 14, name: "Q3", direction: .output),
            
            // Parallel preset inputs
            3: Pin(number: 3, name: "P4", direction: .input),
            4: Pin(number: 4, name: "P1", direction: .input),
            12: Pin(number: 12, name: "P2", direction: .input),
            13: Pin(number: 13, name: "P3", direction: .input),
            
            // Carry connections
            5: Pin(number: 5, name: "CARRY_IN", direction: .input),
            7: Pin(number: 7, name: "CARRY_OUT", direction: .output),
            
            // Control inputs
            9: Pin(number: 9, name: "RESET", direction: .input),
            10: Pin(number: 10, name: "UP_DOWN", direction: .input),
            15: Pin(number: 15, name: "CLOCK", direction: .input),
            
            // Power
            8: Pin(number: 8, name: "VSS", direction: .power),
            16: Pin(number: 16, name: "VDD", direction: .power)
        ]
    }
    
    func evaluate() {
        
        let clock = pins[15]!.state
        let direction = pins[10]!.state
        let reset = pins[9]!.state
        let carryIn = pins[5]!.state
        let parallelEnable = pins[1]!.state
        
        // Always observe clock transitions.
        let edge = clockDetector.update(clock)
        
        // RESET is asynchronous and has highest priority.
        if reset == .high {
            counter.reset()
        }
        
        // Parallel Enable is asynchronous and active HIGH.
        else if reset == .low && parallelEnable == .high {
            
            let presetPins = [4, 12, 13, 3] // P1, P2, P3, P4
            var presetValue = 0
            var validInputs = true
            
            for (bit, pinNumber) in presetPins.enumerated() {
                switch pins[pinNumber]!.state {
                case .high:
                    presetValue |= (1 << bit)
                case .low:
                    break
                default:
                    validInputs = false
                }
            }
            
            if validInputs {
                counter.load(presetValue)
            }
        }
        
        // Normal counting on rising clock edges.
        else if reset == .low &&
                    parallelEnable == .low &&
                    edge == .rising &&
                    carryIn == .low {
            
            if direction == .high {
                counter.countUp()
            } else if direction == .low {
                counter.countDown()
            }
        }
        
        // Drive BCD outputs.
        let bits = counter.bits
        
        pins[6]!.drive(bits[0])   // Q1
        pins[11]!.drive(bits[1])  // Q2
        pins[14]!.drive(bits[2])  // Q3
        pins[2]!.drive(bits[3])   // Q4

        // Carry Out is active LOW at the terminal count when Carry In is LOW.
        switch (counter.value, direction, carryIn) {
        case (9, .high, .low), (0, .low, .low):
            pins[7]!.drive(.low)
        case (_, _, .high), (9, .low, _), (0, .high, _), (1...8, _, _):
            pins[7]!.drive(.high)
        default:
            pins[7]!.drive(.undefined)
        }
    }
}
