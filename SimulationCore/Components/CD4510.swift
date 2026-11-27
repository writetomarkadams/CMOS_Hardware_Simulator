
final class CD4510: LogicComponent {
    
    let pins: [Int: Pin]
    
    private var counter = PresettableCounterState(maximum: 9, initialCount: 0)
    
    var count: Int? {
        counter.count
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
    
    func powerDidFail() {
        counter.powerDidFail()
    }

    func evaluate() {
        counter.evaluate(pins)
    }
}
