/// An ordinal within one resolved clock stream. The producer owns the stream
/// and assigns strictly increasing ordinals to causally relevant receiver
/// updates, including relevant updates that resolve to the same symbol.
struct ClockSampleID: Equatable {
    let ordinal: UInt64
}

/// Repeated delivery during settling uses the same ID and resolved level.
/// Unrelated activity produces no sample. A derived update can have a new ID
/// at the same simulation time. IDs are local to a stream and do not wrap.
struct ResolvedClockSample {
    let id: ClockSampleID
    let level: LogicState
}

enum ClockSampleTransition: Hashable {
    case firstSample
    case hold
    case rising
    case falling

    fileprivate init(previous: BinaryClockLevel?, current: BinaryClockLevel) {
        switch (previous, current) {
        case (nil, _): self = .firstSample
        case (.low?, .high): self = .rising
        case (.high?, .low): self = .falling
        default: self = .hold
        }
    }
}

fileprivate enum BinaryClockLevel: Hashable {
    case low
    case high
}

/// Tracks each possible device state together with its previous binary clock.
/// State must have a finite model-defined domain. With N possible device
/// states, an initialized history has at most 2N distinct candidates.
struct CorrelatedClockHistory<State: Hashable> {
    private struct Candidate: Hashable {
        let state: State
        let level: BinaryClockLevel?
    }

    private enum Candidates {
        case empty
        case single(Candidate)
        case multiple(Set<Candidate>)

        mutating func insert(_ candidate: Candidate) {
            switch self {
            case .empty:
                self = .single(candidate)
            case .single(let existing):
                if existing != candidate {
                    self = .multiple([existing, candidate])
                }
            case .multiple(var values):
                // Release the original reference before mutating the Set.
                self = .empty
                values.insert(candidate)
                self = .multiple(values)
            }
        }
    }

    private var candidates: Candidates
    private var lastSample: ResolvedClockSample?

    init(initialState: State) {
        candidates = .single(Candidate(state: initialState, level: nil))
    }

    init<States: Sequence>(initialStates: States) where States.Element == State {
        candidates = .empty
        invalidateClock(resetTo: initialStates)
    }

    /// Replace device state without resampling the previous binary clock.
    mutating func updateStates<Successors: Sequence>(
        applying transition: (State) -> Successors
    ) where Successors.Element == State {
        var next = Candidates.empty
        func update(_ candidate: Candidate) {
            for state in transition(candidate.state) {
                next.insert(Candidate(state: state, level: candidate.level))
            }
        }
        switch candidates {
        case .empty: break
        case .single(let candidate): update(candidate)
        case .multiple(let values):
            for candidate in values { update(candidate) }
        }
        if case .empty = next { preconditionFailure("At least one clock history must remain feasible") }
        candidates = next
    }

    var unanimousState: State? {
        switch candidates {
        case .empty: return nil
        case .single(let candidate): return candidate.state
        case .multiple(let values):
            guard let state = values.first?.state,
                  values.allSatisfy({ $0.state == state }) else { return nil }
            return state
        }
    }

    var candidateCount: Int {
        switch candidates {
        case .empty: return 0
        case .single: return 1
        case .multiple(let values): return values.count
        }
    }

    var possibleStates: Set<State> {
        switch candidates {
        case .empty: return []
        case .single(let candidate): return [candidate.state]
        case .multiple(let values): return Set(values.map(\.state))
        }
    }

    /// Power loss or reset that discards clock history supplies the device's
    /// replacement state. Retain the sample watermark so a repeated settle
    /// of the old event cannot initialize the restored history.
    mutating func invalidateClock(resetTo state: State) {
        candidates = .single(Candidate(state: state, level: nil))
    }

    mutating func invalidateClock<States: Sequence>(resetTo states: States) where States.Element == State {
        candidates = .empty
        for state in states {
            candidates.insert(Candidate(state: state, level: nil))
        }
        if case .empty = candidates { preconditionFailure("At least one initial state must be feasible") }
    }

    /// Consumes a resolved sample and applies a pure device transition to each
    /// feasible history using controls captured at this boundary. An empty
    /// result can discard a branch, provided another branch remains feasible.
    /// A first sample establishes a binary level without a clock edge.
    /// Same-ID repeats and stale deliveries never invoke the transition.
    @discardableResult
    mutating func consume<Successors: Sequence>(
        _ sample: ResolvedClockSample,
        applying transition: (State, ClockSampleTransition) -> Successors
    ) -> Bool where Successors.Element == State {
        if let lastSample {
            if sample.id == lastSample.id {
                precondition(sample.level == lastSample.level, "A clock sample must keep its resolved level")
                return false
            }
            guard sample.id.ordinal > lastSample.id.ordinal else { return false }
        }

        var next = Candidates.empty

        func advance(_ candidate: Candidate, to level: BinaryClockLevel) {
            let event = ClockSampleTransition(previous: candidate.level, current: level)
            for state in transition(candidate.state, event) {
                next.insert(Candidate(state: state, level: level))
            }
        }

        func advance(_ candidate: Candidate) {
            if sample.level != .high { advance(candidate, to: .low) }
            if sample.level != .low { advance(candidate, to: .high) }
        }

        switch candidates {
        case .empty: break
        case .single(let candidate): advance(candidate)
        case .multiple(let values):
            for candidate in values { advance(candidate) }
        }

        if case .empty = next { preconditionFailure("At least one clock history must remain feasible") }
        candidates = next
        lastSample = sample
        return true
    }
}
