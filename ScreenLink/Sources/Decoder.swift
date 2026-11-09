import Foundation

struct LightSample { let time: Double; let value: Double }
struct Packet { let bytes: [UInt8]; let checksumOK: Bool; let duration: Double }

// Shared wire format: 16 sync bits, 8-bit byte count, UTF-8 bytes, XOR checksum.
final class Decoder {
    static let sync = [1,1,0,1,0,0,1,1,1,0,0,0,1,0,1,0]
    let symbol: Double
    var samples: [LightSample] = []
    var candidate: Double?
    private var timingRefined = false
    var nextSearch = 0.0
    var onPacket: ((Packet) -> Void)?
    init(symbol: Double) { self.symbol = symbol }
    func energy(_ points: [LightSample], start: Double, frequency: Double) -> Double {
        guard points.count >= 6 else { return 0 }
        let mean = points.reduce(0) { $0 + $1.value } / Double(points.count)
        var c = 0.0, s = 0.0
        for p in points {
            let phase = 2 * Double.pi * frequency * (p.time - start)
            c += (p.value - mean) * cos(phase)
            s += (p.value - mean) * sin(phase)
        }
        return (c*c + s*s) / Double(points.count * points.count)
    }
    func evidence(_ start: Double) -> (bit: Int, confidence: Double)? {
        let points = samples.filter { $0.time >= start + symbol * 0.04 && $0.time < start + symbol * 0.96 }
        guard points.count >= 6, let first = points.first, let last = points.last,
              last.time - first.time > symbol * 0.65 else { return nil }
        let e0 = energy(points, start: start, frequency: 2 / symbol)
        let e1 = energy(points, start: start, frequency: 3 / symbol)
        guard max(e0, e1) > 0.000001 else { return nil }
        return (e1 > e0 ? 1 : 0, abs(e1-e0) / (e1+e0))
    }
    func bit(_ start: Double) -> Int? { evidence(start)?.bit }

    private func syncScore(_ start: Double) -> Double {
        var score = 0.0
        for i in 0..<16 {
            guard let result = evidence(start + Double(i)*symbol), result.bit == Self.sync[i] else { return -1 }
            score += result.confidence
        }
        return score
    }
    func byte(_ start: Double) -> UInt8? {
        var v: UInt8 = 0
        for i in 0..<8 {
            guard let b = bit(start + Double(i) * symbol) else { return nil }
            v = (v << 1) | UInt8(b)
        }
        return v
    }
    func append(_ sample: LightSample) {
        if samples.isEmpty { nextSearch = sample.time }
        samples.append(sample)
        let now = sample.time
        if candidate == nil, now >= nextSearch + 16 * symbol {
            // Search in small steps so clock phase is recovered from the optical signal.
            while nextSearch + 16 * symbol <= now {
                let start = nextSearch
                nextSearch += min(symbol / 16, 1 / 60.0)
                let decoded = (0..<16).map { bit(start + Double($0) * symbol) }
                if zip(decoded, Self.sync).allSatisfy({ $0.0 == $0.1 }) {
                    candidate = start
                    timingRefined = false
                    break
                }
            }
        }
        // A broad range of offsets can produce the same sync bits. Wait for
        // the full neighborhood and choose its strongest frequency separation.
        // Timing is chosen using sync only, never the message or checksum.
        if let initial = candidate, !timingRefined, now >= initial + 17 * symbol {
            var best = initial, bestScore = syncScore(initial)
            for step in -16...48 {
                let start = initial + Double(step) * symbol / 64
                let score = syncScore(start)
                if score > bestScore { best = start; bestScore = score }
            }
            candidate = best
            timingRefined = true
        }
        if let start = candidate, timingRefined, now >= start + 24 * symbol {
            guard let count = byte(start + 16 * symbol), count > 0, count <= 128 else {
                candidate = nil; return
            }
            let end = start + Double(32 + Int(count) * 8) * symbol
            if now >= end {
                var bytes: [UInt8] = []
                for i in 0..<Int(count) {
                    guard let b = byte(start + Double(24 + i*8) * symbol) else {
                        candidate = nil; nextSearch = end; return
                    }
                    bytes.append(b)
                }
                let check = byte(start + Double(24 + Int(count)*8) * symbol)
                onPacket?(Packet(bytes: bytes, checksumOK: check == bytes.reduce(UInt8(0), ^), duration: end-start))
                candidate = nil; nextSearch = end
            }
        }
        let keepFrom = candidate ?? nextSearch
        if samples.count > 500 { samples.removeAll { $0.time < keepFrom - symbol } }
    }
}
