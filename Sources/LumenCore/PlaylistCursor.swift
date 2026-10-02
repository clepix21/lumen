import Foundation

/// Walks through a playlist: next/previous with wrap-around, optional shuffle
/// (a new random order on every pass), and removal of videos while playing.
public struct PlaylistCursor: Equatable, Sendable {
    public private(set) var order: [UUID]
    public private(set) var position: Int
    private let shuffle: Bool
    private var generator: SplitMix64

    public init(videoIDs: [UUID], shuffle: Bool, seed: UInt64) {
        self.shuffle = shuffle
        generator = SplitMix64(seed: seed)
        order = videoIDs
        position = 0
        if shuffle {
            order.shuffle(using: &generator)
        }
    }

    public var current: UUID? {
        order.indices.contains(position) ? order[position] : nil
    }

    public var count: Int { order.count }

    public mutating func next() {
        guard !order.isEmpty else { return }
        if position + 1 < order.count {
            position += 1
        } else {
            position = 0
            if shuffle {
                order.shuffle(using: &generator)
            }
        }
    }

    public mutating func previous() {
        guard !order.isEmpty else { return }
        position = position == 0 ? order.count - 1 : position - 1
    }

    /// Removes a video; if it was the current one, the following video becomes current.
    public mutating func remove(_ id: UUID) {
        guard let index = order.firstIndex(of: id) else { return }
        order.remove(at: index)
        if index < position {
            position -= 1
        }
        if position >= order.count {
            position = 0
        }
    }
}

/// Small deterministic generator so shuffles are reproducible in tests.
struct SplitMix64: RandomNumberGenerator, Equatable, Sendable {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
