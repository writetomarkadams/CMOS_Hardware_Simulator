import Observation

enum ScopeProbe: Codable, Hashable {
    case pin(WorkbenchTerminal)
    case wire(Int)
}

enum ScopeValue: Equatable {
    case logic(LogicState)
    case voltage(Double)
}

struct ScopeSample: Equatable {
    let time: Double
    let value: ScopeValue
}

struct ScopeHistory {
    private let capacity: Int
    private var samples: [ScopeSample] = []
    private var head = 0

    init(capacity: Int = 8192) {
        precondition(capacity > 0)
        self.capacity = capacity
    }

    private func sample(at index: Int) -> ScopeSample {
        samples[(head + index) % samples.count]
    }

    var last: ScopeSample? { samples.isEmpty ? nil : sample(at: samples.count - 1) }

    mutating func append(_ sample: ScopeSample) {
        if let last {
            guard sample.time >= last.time else { return }
            if case .logic = sample.value, sample.value == last.value { return }
            if sample == last { return }
        }
        if samples.count < capacity {
            samples.append(sample)
        } else {
            samples[head] = sample
            head = (head + 1) % capacity
        }
    }

    func visible(in window: ClosedRange<Double>) -> [ScopeSample] {
        func partition(after time: Double) -> Int {
            var low = 0
            var high = samples.count
            while low < high {
                let mid = (low + high) / 2
                if sample(at: mid).time <= time { low = mid + 1 } else { high = mid }
            }
            return low
        }
        let start = max(0, partition(after: window.lowerBound.nextDown) - 1)
        // One point past the right edge allows interpolation of sampled voltages.
        let end = min(samples.count, partition(after: window.upperBound) + 1)
        return (start..<end).map { sample(at: $0) }
    }
}

@Observable
final class Oscilloscope {
    static let channelCount = 4
    private(set) var running = true
    private(set) var span = 0.1
    private(set) var revision = 0
    @ObservationIgnored private(set) var time = 0.0
    @ObservationIgnored private var histories = Array(repeating: ScopeHistory(), count: channelCount)

    func setSpan(_ seconds: Double) {
        guard seconds.isFinite, seconds > 0 else { return }
        span = seconds
    }

    func setRunning(_ enabled: Bool) {
        if enabled { clear() }
        running = enabled
    }

    func clear() {
        histories = Array(repeating: ScopeHistory(), count: Self.channelCount)
        revision &+= 1
    }

    func reset(channel: Int) {
        histories[channel] = ScopeHistory()
        revision &+= 1
    }

    func capture(at timestamp: Double, value: (Int) -> ScopeValue?) {
        guard running, timestamp >= time else { return }
        for channel in histories.indices {
            guard let value = value(channel) else { continue }
            histories[channel].append(ScopeSample(time: timestamp, value: value))
        }
        time = timestamp
    }

    var window: ClosedRange<Double> { (time - span)...time }

    func samples(channel: Int, in window: ClosedRange<Double>) -> [ScopeSample] {
        histories[channel].visible(in: window)
    }
}
